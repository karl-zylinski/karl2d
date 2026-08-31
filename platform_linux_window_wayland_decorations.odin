#+build linux
package karl2d

// The window frame Karl2D draws for itself, on Wayland compositors that draw none. GNOME is the
// one that matters: it has no zxdg_decoration_manager_v1 and expects every window to come with its
// own titlebar and borders.
//
// The frame is four subsurfaces of the surface the game renders into, with shared memory buffers
// filled on the CPU. Keeping it out of the game's own surface is what lets every render backend
// carry on knowing nothing about any of this, and it means the compositor moves the frame along
// with the window for free.
//
// `platform_linux_window_wayland.odin` owns the window and the input; it calls in here to make the
// frame, to lay it out again after a resize, and to hand over the pointer events that landed on
// it. Nothing in here talks to the compositor about anything but the frame.

import "core:c"
import "core:math"
import "core:strings"
import "core:sys/linux"
import stbtt "vendor:stb/truetype"

import "log"
import "platform_bindings/linux/dbus"
import wl "platform_bindings/linux/wayland"

// The frame Karl2D draws where the compositor draws none, in logical pixels. There is no border
// around the game canvas: it runs right to the window's edge on the three sides that have no
// titlebar, and what sets the window apart from the desktop is the shadow it casts.
DECORATION_TITLEBAR_HEIGHT :: 32

// How far the shadow spreads from the window, in logical pixels.
DECORATION_SHADOW_REACH :: 43

// How dark the shadow is at a given distance from the window: `a*exp(-b*distance) + c`, distance
// in logical pixels. Adwaita's shadow is a stack of CSS box shadows, which is nothing a CPU
// rasterizer wants to reproduce, so these are the curve sctk-adwaita fitted to a screenshot of a
// real Adwaita window and draws its own Wayland decorations with. Straight black, and the same in
// both color schemes, which is how GNOME does it.
WL_Decoration_Shadow :: struct {
	a: f32,
	b: f32,
	c: f32,
}

DECORATION_SHADOW_FOCUSED :: WL_Decoration_Shadow {
	a = 0.2065055,
	b = 0.10461753,
	c = -0.0005424462,
}

DECORATION_SHADOW_UNFOCUSED :: WL_Decoration_Shadow {
	a = 0.16829729,
	b = 0.2042998,
	c = 0.0017697986,
}

// How far outside the window the pointer can still grab an edge to resize. Well inside the shadow,
// and the only part of the shadow that takes pointer events at all: the rest lets clicks through
// to whatever is behind the window. GTK uses the same twelve pixels.
DECORATION_RESIZE_MARGIN :: 12

// A titlebar button, and how much room it takes, in logical pixels. `glyph` is the box the drawing
// inside it fits in, `stroke` how wide the lines of that drawing are, and `inset` how far the
// button keeps away from the edges of its share of the titlebar, so that the lit background under
// the pointer does not run into the next button along.
DECORATION_BUTTON_WIDTH :: 32
DECORATION_BUTTON_GLYPH :: 12
DECORATION_BUTTON_STROKE :: 1.2
DECORATION_BUTTON_INSET :: 4

// How tall the title is drawn, in logical pixels, and how much room is left either side of it
// before it is left out entirely.
DECORATION_TITLE_SIZE :: 15
DECORATION_TITLE_PADDING :: 8

// What the frame is painted with. The fill covers the titlebar, `text` draws the title and the
// button glyphs, and `hover` lights up the button under the pointer. Premultiplied ARGB, the
// format the decoration buffers are in.
WL_Decoration_Colors :: struct {
	fill: u32,
	text: u32,
	hover: u32,
}

DECORATION_COLORS_DARK :: WL_Decoration_Colors {
	fill = 0xff2e2e2e,
	text = 0xffdadada,
	hover = 0xff474747,
}

DECORATION_COLORS_LIGHT :: WL_Decoration_Colors {
	fill = 0xfff6f6f6,
	text = 0xff303030,
	hover = 0xffe0e0e0,
}

// One part of the window frame Karl2D draws for itself. Each is a subsurface of the surface the
// game renders into, with a shared memory buffer that we fill on the CPU.
WL_Decoration :: struct {
	surface: ^wl.Surface,
	subsurface: ^wl.Subsurface,

	// Scales the buffer down from physical to logical pixels, like the one a cursor has.
	viewport: ^wl.WP_Viewport,

	// A part paints into one buffer while the compositor may still be reading the one before it, so
	// it keeps a few. Two are enough in practice; the third is headroom.
	buffers: [3]WL_Decoration_Buffer,

	// The buffer being painted into right now, and its size in physical pixels.
	pixels: [^]u32,
	buffer_width: int,
	buffer_height: int,

	// Where the part sits and how big it is, in logical pixels relative to the game canvas.
	x: int,
	y: int,
	width: int,
	height: int,
}

// One shared memory buffer belonging to a part. `busy` is true from the moment it is attached
// until the compositor says it has finished reading it. Destroying a buffer before that leaves the
// surface with undefined contents, which on screen is the frame vanishing for a frame.
WL_Decoration_Buffer :: struct {
	buffer: ^wl.Buffer,
	pixels: [^]u32,
	data_size: int,
	width: int,
	height: int,
	busy: bool,
}

// The compositor has finished reading a buffer, so it can be painted into or thrown away again.
decoration_buffer_listener := wl.Buffer_Listener {
	release = proc "c" (data: rawptr, buffer: ^wl.Buffer) {
		(^WL_Decoration_Buffer)(data).busy = false
	},
}

WL_Decoration_Part :: enum {
	Titlebar,
	Left,
	Right,
	Bottom,
}

// The buttons in the titlebar, laid out from the right edge of the window inwards in this order.
WL_Decoration_Button :: enum {
	None,
	Close,
	Maximize,
	Minimize,
}

// A rectangle in logical pixels with the game canvas at the origin, which is how the frame
// measures everything it draws.
WL_Decoration_Rect :: struct {
	x: int,
	y: int,
	width: int,
	height: int,
}

// Everything the frame keeps track of. `WL_State` holds one of these, so that the state of the
// window and the state of the frame around it stay apart.
WL_Decorations :: struct {
	// The window the frame is drawn around, handed over by `wldeco_init`. Everything in this file
	// reaches the compositor through it, so that none of it goes looking for the Wayland backend's
	// own state on its own. `WL_State` is allocated once and never moves, and this points back into
	// the same allocation it lives in.
	win: ^WL_State,

	parts: [WL_Decoration_Part]WL_Decoration,
	colors: WL_Decoration_Colors,

	// The window edge under the pointer, as an `xdg_toplevel` resize edge. Zero where the frame
	// moves the window rather than resizing it, and stale whenever the pointer is not on the frame
	// at all, which `wldeco_has_pointer` is what answers.
	pointer_edge: u32,

	// The button under the pointer, which is the one that lights up, and the one the button went
	// down on. A button only acts if the pointer is still on it when the button comes back up.
	pointer_button: WL_Decoration_Button,
	pressed_button: WL_Decoration_Button,

	// The window title, kept because the titlebar has to be repainted with it whenever anything
	// else about the titlebar changes. Owned by the frame, in the allocator Karl2D was given.
	title: string,

	// The embedded font, parsed once. It points into `DEFAULT_FONT_DATA`, which is baked into the
	// program and outlives everything.
	font: stbtt.fontinfo,
	font_ok: bool,

	// When and where the last press on the titlebar was, to catch the second one of a double
	// click. The time is the compositor's, in milliseconds.
	last_press_time: u32,
	last_press_x: f32,
	last_press_y: f32,
}

// Creates the four surfaces that make up the window frame. They are subsurfaces of the surface the
// game renders into, so the compositor keeps them glued to it and no render backend has to know
// that they exist. `win` is the window they go around, and the frame holds on to it.
//
// They are left synchronized, which is how a subsurface starts: everything the frame commits waits
// for the game's next frame and lands with it in one go. Anything else tears the window in half
// while it resizes, since a subsurface's position always waits for the parent whatever its buffer
// does.
wldeco_init :: proc(deco: ^WL_Decorations, win: ^WL_State) {
	deco.win = win

	if win.subcompositor == nil {
		log.error("Wayland compositor has no wl_subcompositor. The window gets no frame.")
		return
	}

	deco.colors = wldeco_desktop_colors()

	// The title is drawn with the font Karl2D embeds for the game to use. Parsing it is just
	// reading the table offsets out of the file, and the file is baked into the program.
	offset := stbtt.GetFontOffsetForIndex(raw_data(DEFAULT_FONT_DATA), 0)
	deco.font_ok = bool(stbtt.InitFont(
		&deco.font,
		raw_data(DEFAULT_FONT_DATA),
		offset,
	))

	if !deco.font_ok {
		log.error("Failed reading the built in font. The window title will not be drawn.")
	}

	for part in WL_Decoration_Part {
		d := &deco.parts[part]
		d.surface = wl.compositor_create_surface(win.compositor)
		d.subsurface = wl.subcompositor_get_subsurface(win.subcompositor, d.surface, win.surface)
		d.viewport = wl.wp_viewporter_get_viewport(win.viewporter, d.surface)
	}

	wldeco_layout(deco)
}

// Puts every part of the frame where it belongs for the current window size and repaints it. The
// compositor leaves the parts where they were put, so this runs on every resize and scale change.
wldeco_layout :: proc(deco: ^WL_Decorations) {
	if deco.parts[.Titlebar].surface == nil {
		return
	}

	// In fullscreen the window is the canvas and nothing else, so the parts come off the screen
	// entirely. Attaching no buffer to a surface is how Wayland says that.
	if !wldeco_shown(deco) {
		for part in WL_Decoration_Part {
			d := &deco.parts[part]
			wl.surface_attach(d.surface, nil, 0, 0)
			wl.surface_commit(d.surface)
		}

		wl.xdg_surface_set_window_geometry(
			deco.win.xdg_surface,
			0,
			0,
			i32(deco.win.last_configure_width),
			i32(deco.win.last_configure_height),
		)

		return
	}

	for part in WL_Decoration_Part {
		wldeco_paint(deco, part)
	}

	// The window is the game canvas with the titlebar on top, and neither the shadow nor the grip
	// around it. Without this the compositor would treat the canvas alone as the window, and a
	// maximized window would hang off the screen by the height of the titlebar.
	wl.xdg_surface_set_window_geometry(
		deco.win.xdg_surface,
		0,
		-DECORATION_TITLEBAR_HEIGHT,
		i32(deco.win.last_configure_width),
		i32(deco.win.last_configure_height + DECORATION_TITLEBAR_HEIGHT),
	)
}

// Whether the frame is on screen. It is not in fullscreen: that mode is for the game covering the
// screen, and a compositor sizes a fullscreen window to exactly the output with no room for a
// titlebar above it.
wldeco_shown :: proc(deco: ^WL_Decorations) -> bool {
	if deco.parts[.Titlebar].surface == nil {
		return false
	}

	return deco.win.window_mode != .Borderless_Fullscreen
}

// Repaints the titlebar alone, for the things that change while the window stays the same size:
// the title, whether the window has focus, and which button the pointer is on.
wldeco_repaint_titlebar :: proc(deco: ^WL_Decorations) {
	if !wldeco_shown(deco) || deco.parts[.Titlebar].surface == nil {
		return
	}

	wldeco_paint(deco, .Titlebar)
}

// Takes the title to draw. The compositor is told separately, since it wants one for its window
// list whether or not it draws any of this.
wldeco_set_title :: proc(deco: ^WL_Decorations, title: string) {
	// Games that put their frame rate in the title set it every frame, and repainting the titlebar
	// for a title that has not changed would be that much work for nothing.
	if deco.title == title {
		return
	}

	delete(deco.title, deco.win.allocator)
	deco.title = strings.clone(title, deco.win.allocator)
	wldeco_repaint_titlebar(deco)
}

// Works out where one part of the frame sits for the current window size, paints it and puts it
// there. Positions are in logical pixels relative to the game canvas, so the titlebar has a
// negative y since it hangs above the canvas, and every part reaches a shadow's width further out
// again.
wldeco_paint :: proc(deco: ^WL_Decorations, part: WL_Decoration_Part) {
	w := deco.win.last_configure_width
	h := deco.win.last_configure_height
	d := &deco.parts[part]

	// How far a part reaches past the window, which is as far as the shadow goes.
	out :: DECORATION_SHADOW_REACH

	switch part {
	case .Titlebar:
		d.x = -out
		d.y = -DECORATION_TITLEBAR_HEIGHT - out
		d.width = w + out*2
		d.height = DECORATION_TITLEBAR_HEIGHT + out

	case .Left:
		d.x = -out
		d.y = 0
		d.width = out
		d.height = h

	case .Right:
		d.x = w
		d.y = 0
		d.width = out
		d.height = h

	case .Bottom:
		d.x = -out
		d.y = h
		d.width = w + out*2
		d.height = out
	}

	// The buffer holds physical pixels and a viewport maps it back to the logical size, the way
	// cursor images are handled.
	buffer_width := max(1, int(math.round(f32(d.width) * deco.win.scale)))
	buffer_height := max(1, int(math.round(f32(d.height) * deco.win.scale)))

	slot := wldeco_take_buffer(deco, d, buffer_width, buffer_height)

	if slot == nil {
		return
	}

	d.pixels = slot.pixels
	d.buffer_width = buffer_width
	d.buffer_height = buffer_height

	// Where the window is inside this part, in the part's own physical pixels. The titlebar is the
	// only piece of the window that lands in a decoration surface at all; everything else in every
	// part is shadow.
	left := int(math.round(f32(-d.x) * deco.win.scale))
	top := int(math.round(f32(-DECORATION_TITLEBAR_HEIGHT - d.y) * deco.win.scale))
	right := int(math.round(f32(w - d.x) * deco.win.scale))
	bottom := int(math.round(f32(h - d.y) * deco.win.scale))

	shadow := deco.win.active ? DECORATION_SHADOW_FOCUSED : DECORATION_SHADOW_UNFOCUSED
	reach := DECORATION_SHADOW_REACH * deco.win.scale

	for y in 0..<buffer_height {
		for x in 0..<buffer_width {
			if x >= left && x < right && y >= top && y < bottom {
				d.pixels[y*buffer_width + x] = deco.colors.fill
				continue
			}

			// How far this pixel is from the window, which is all the shadow depends on. The
			// distance is put back into logical pixels because that is what the curve was fitted
			// against, and the shadow is black, so premultiplying leaves nothing but the alpha.
			dx := f32(max(left - x, 0, x - right + 1))
			dy := f32(max(top - y, 0, y - bottom + 1))
			distance := math.sqrt(dx*dx + dy*dy)
			alpha := f32(0)

			if distance < reach {
				faded := shadow.a*math.exp(-shadow.b*distance/deco.win.scale) + shadow.c
				alpha = clamp(faded, 0, 1)
			}

			d.pixels[y*buffer_width + x] = u32(alpha*255) << 24
		}
	}

	if part == .Titlebar {
		wldeco_paint_title(deco, d)

		for button in WL_Decoration_Button {
			if button != .None {
				wldeco_paint_button(deco, d, button)
			}
		}
	}

	wldeco_set_input_region(deco, d)
	wl.subsurface_set_position(d.subsurface, i32(d.x), i32(d.y))
	wl.wp_viewport_set_destination(d.viewport, i32(max(1, d.width)), i32(max(1, d.height)))
	wl.surface_attach(d.surface, slot.buffer, 0, 0)
	wl.surface_damage_buffer(d.surface, 0, 0, i32(buffer_width), i32(buffer_height))
	wl.surface_commit(d.surface)
	slot.busy = true
}

// Finds a buffer of this size that the compositor is not reading, making one if none of the part's
// slots holds it already. Handing back the buffer that is on screen would mean painting over what
// the compositor is showing, and freeing it would leave the surface with nothing at all.
wldeco_take_buffer :: proc(
	deco: ^WL_Decorations,
	d: ^WL_Decoration,
	width: int,
	height: int,
) -> ^WL_Decoration_Buffer {
	for &slot in d.buffers {
		if !slot.busy && slot.buffer != nil && slot.width == width && slot.height == height {
			return &slot
		}
	}

	for &slot in d.buffers {
		if !slot.busy {
			wldeco_make_buffer(deco, &slot, width, height)
			return slot.buffer != nil ? &slot : nil
		}
	}

	// Every slot is still on the compositor's hands. It lets go of them as soon as it shows
	// something else, so this means it is several frames behind and the frame can wait one more.
	log.debug("Every window decoration buffer is still in use. Skipping a repaint.")
	return nil
}

// Says which pixels of a part take pointer events: the window itself and a band around it wide
// enough to grab for resizing. Without this the shadow would swallow every click that landed on it,
// and a window has a lot of shadow around it.
wldeco_set_input_region :: proc(deco: ^WL_Decorations, d: ^WL_Decoration) {
	band_left := -DECORATION_RESIZE_MARGIN
	band_top := -DECORATION_TITLEBAR_HEIGHT - DECORATION_RESIZE_MARGIN
	band_right := deco.win.last_configure_width + DECORATION_RESIZE_MARGIN
	band_bottom := deco.win.last_configure_height + DECORATION_RESIZE_MARGIN

	// The band, clipped to this part and put in the part's own coordinates.
	x0 := max(d.x, band_left) - d.x
	y0 := max(d.y, band_top) - d.y
	x1 := min(d.x + d.width, band_right) - d.x
	y1 := min(d.y + d.height, band_bottom) - d.y

	region := wl.compositor_create_region(deco.win.compositor)

	if x1 > x0 && y1 > y0 {
		wl.region_add(region, i32(x0), i32(y0), i32(x1 - x0), i32(y1 - y0))
	}

	wl.surface_set_input_region(d.surface, region)
	wl.region_destroy(region)
}

// Draws the window title across the middle of the titlebar, in the space the buttons leave. The
// glyphs are rasterized straight out of the font Karl2D already embeds, one at a time, which is
// little enough work for something that only happens when the title, the size, the focus or the
// button under the pointer changes.
wldeco_paint_title :: proc(deco: ^WL_Decorations, d: ^WL_Decoration) {
	if !deco.font_ok || deco.title == "" {
		return
	}

	font := &deco.font
	scale_factor := stbtt.ScaleForPixelHeight(font, DECORATION_TITLE_SIZE * deco.win.scale)

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(font, &ascent, &descent, &line_gap)

	// Everything below is in the titlebar's own physical pixels. `left` and `right` are as far as
	// the title may reach: the window's left edge on one side and the first button on the other.
	buttons := wldeco_button_rect(deco, max(WL_Decoration_Button))
	padding := int(math.round(DECORATION_TITLE_PADDING * deco.win.scale))
	left := int(math.round(f32(-d.x) * deco.win.scale)) + padding
	right := int(math.round(f32(buttons.x - d.x) * deco.win.scale)) - padding

	if right <= left {
		return
	}

	width := 0

	for r in deco.title {
		advance, left_bearing: i32
		stbtt.GetCodepointHMetrics(font, r, &advance, &left_bearing)
		width += int(math.round(f32(advance) * scale_factor))
	}

	// Centered on the window itself rather than on the room beside the buttons, so that it sits
	// where the eye looks for it. A title too long for that room runs into the buttons and is cut
	// off there instead.
	center := int(math.round(f32(deco.win.last_configure_width - d.x*2) * deco.win.scale))/2
	pen := max(left, center - width/2)
	top := int(math.round(f32(-DECORATION_TITLEBAR_HEIGHT - d.y) * deco.win.scale))
	bar_height := int(math.round(DECORATION_TITLEBAR_HEIGHT * deco.win.scale))
	text_height := f32(ascent - descent) * scale_factor
	baseline := top + int((f32(bar_height) - text_height)/2 + f32(ascent)*scale_factor)
	color := wldeco_text_color(deco)

	for r in deco.title {
		advance, left_bearing: i32
		stbtt.GetCodepointHMetrics(font, r, &advance, &left_bearing)

		glyph_width, glyph_height, glyph_x, glyph_y: i32
		coverage := stbtt.GetCodepointBitmap(
			font,
			0,
			scale_factor,
			r,
			&glyph_width,
			&glyph_height,
			&glyph_x,
			&glyph_y,
		)

		if coverage != nil {
			wldeco_blit_glyph(
				d,
				coverage[:glyph_width*glyph_height],
				int(glyph_width),
				pen + int(glyph_x),
				baseline + int(glyph_y),
				left,
				right,
				color,
			)

			stbtt.FreeBitmap(coverage, nil)
		}

		pen += int(math.round(f32(advance) * scale_factor))

		if pen >= right {
			break
		}
	}
}

// Blends one rasterized glyph into the titlebar buffer. `coverage` is stbtt's 8 bit alpha, and
// `clip_left` and `clip_right` keep the title out of the buttons and off the window's edge.
wldeco_blit_glyph :: proc(
	d: ^WL_Decoration,
	coverage: []u8,
	glyph_width: int,
	at_x: int,
	at_y: int,
	clip_left: int,
	clip_right: int,
	color: u32,
) {
	for i in 0..<len(coverage) {
		alpha := coverage[i]

		if alpha == 0 {
			continue
		}

		x := at_x + i%glyph_width
		y := at_y + i/glyph_width

		if x < clip_left || x >= clip_right || y < 0 || y >= d.buffer_height {
			continue
		}

		at := y*d.buffer_width + x
		d.pixels[at] = wldeco_blend(d.pixels[at], color, f32(alpha)/255)
	}
}

// What the title and the button glyphs are drawn in. Dimmed towards the titlebar itself while the
// window is not the one being typed into, the way every other window on the desktop dims.
wldeco_text_color :: proc(deco: ^WL_Decorations) -> u32 {
	if deco.win.active {
		return deco.colors.text
	}

	return wldeco_blend(deco.colors.fill, deco.colors.text, 0.45)
}

// Draws one button into the titlebar buffer: a lit background while the pointer is on it, and the
// glyph that says what it does. `d` is the titlebar, whose buffer the button is painted into.
wldeco_paint_button :: proc(
	deco: ^WL_Decorations,
	d: ^WL_Decoration,
	button: WL_Decoration_Button,
) {
	rect := wldeco_button_rect(deco, button)

	// The button's corner in the titlebar's own physical pixels.
	x0 := int(math.round(f32(rect.x - d.x) * deco.win.scale))
	y0 := int(math.round(f32(rect.y - d.y) * deco.win.scale))
	x1 := min(d.buffer_width, int(math.round(f32(rect.x + rect.width - d.x) * deco.win.scale)))
	y1 := min(d.buffer_height, int(math.round(f32(rect.y + rect.height - d.y) * deco.win.scale)))

	if x0 >= x1 || y0 >= y1 {
		return
	}

	background := deco.colors.fill

	if deco.pointer_button == button {
		background = deco.colors.hover
	}

	center_x := f32(x0 + x1)/2
	center_y := f32(y0 + y1)/2
	reach := DECORATION_BUTTON_GLYPH/2 * deco.win.scale
	half_stroke := DECORATION_BUTTON_STROKE/2 * deco.win.scale
	color := wldeco_text_color(deco)

	for y in y0..<y1 {
		for x in x0..<x1 {
			// Every glyph is drawn from how far the pixel is from the lines that make it up.
			// Turning that distance into coverage costs nothing and keeps the drawing from
			// looking like a staircase at any scale.
			dx := f32(x) - center_x + 0.5
			dy := f32(y) - center_y + 0.5
			to_line := max(f32)

			switch button {
			case .None:

			case .Close:
				if abs(dx) <= reach && abs(dy) <= reach {
					// The 0.7071 turns a distance along an axis into the distance to a line at 45
					// degrees, which is what the two strokes of an X are.
					to_line = min(abs(dx - dy), abs(dx + dy)) * 0.70710678
				}

			case .Maximize:
				if !deco.win.maximized {
					to_line = wldeco_square_distance(dx, dy, reach*0.8)
					break
				}

				// Once the window is maximized the button undoes that, and says so as two windows
				// laid over one another: one at the front, and one behind it up and to the right
				// showing only the corner the front one does not cover.
				window := reach*0.62
				shift := window*0.45
				to_line = wldeco_square_distance(dx + shift, dy - shift, window)
				covered := max(abs(dx + shift), abs(dy - shift)) <= window + half_stroke + 0.5

				if !covered {
					to_line = min(to_line, wldeco_square_distance(dx - shift, dy + shift, window))
				}

			case .Minimize:
				// A line along the bottom of where the other glyphs are.
				if abs(dx) <= reach*0.8 {
					to_line = abs(dy - reach*0.6)
				}
			}

			coverage := clamp(half_stroke + 0.5 - to_line, 0, 1)
			d.pixels[y*d.buffer_width + x] = wldeco_blend(background, color, coverage)
		}
	}
}

// How far a point is from the outline of a square of half width `reach` centered on the origin, so
// that a square comes out of the same coverage code as the diagonal strokes of the X.
wldeco_square_distance :: proc(dx: f32, dy: f32, reach: f32) -> f32 {
	return abs(max(abs(dx), abs(dy)) - reach)
}

// Mixes two opaque colors, `amount` being how much of `over` shows.
wldeco_blend :: proc(under: u32, over: u32, amount: f32) -> u32 {
	if amount <= 0 {
		return under
	}

	if amount >= 1 {
		return over
	}

	from_r := f32((under >> 16) & 0xff)
	from_g := f32((under >> 8) & 0xff)
	from_b := f32(under & 0xff)
	to_r := f32((over >> 16) & 0xff)
	to_g := f32((over >> 8) & 0xff)
	to_b := f32(over & 0xff)

	r := u32(from_r + (to_r - from_r)*amount)
	g := u32(from_g + (to_g - from_g)*amount)
	b := u32(from_b + (to_b - from_b)*amount)
	return 0xff000000 | r << 16 | g << 8 | b
}

// Where a titlebar button sits, both for drawing it and for deciding whether the pointer is on it.
// They are laid out from the right edge of the window inwards, in the order of the enum, each in a
// slot of its own with a little room left around it.
wldeco_button_rect :: proc(
	deco: ^WL_Decorations,
	button: WL_Decoration_Button,
) -> WL_Decoration_Rect {
	slot := int(button) - 1

	return {
		x = deco.win.last_configure_width - (slot + 1)*DECORATION_BUTTON_WIDTH + DECORATION_BUTTON_INSET,
		y = -DECORATION_TITLEBAR_HEIGHT + DECORATION_BUTTON_INSET,
		width = DECORATION_BUTTON_WIDTH - DECORATION_BUTTON_INSET*2,
		height = DECORATION_TITLEBAR_HEIGHT - DECORATION_BUTTON_INSET*2,
	}
}

// Fills one of a part's slots with a fresh shared memory buffer. Whatever the slot held is thrown
// away first, which is safe because a slot is only ever passed here once the compositor has said
// it has finished reading it.
wldeco_make_buffer :: proc(
	deco: ^WL_Decorations,
	slot: ^WL_Decoration_Buffer,
	width: int,
	height: int,
) {
	if slot.buffer != nil {
		wl.buffer_destroy(slot.buffer)
		linux.munmap(slot.pixels, uint(slot.data_size))
		slot^ = {}
	}

	stride := width * 4
	size := stride * height

	fd, fd_err := linux.memfd_create("karl2d-decoration", {})
	if fd_err != .NONE {
		log.errorf("Failed making a window decoration: memfd failed with %v", fd_err)
		return
	}

	// The compositor dups the fd in shm_create_pool, so we don't have to keep ours around.
	defer linux.close(fd)

	if trunc_err := linux.ftruncate(fd, i64(size)); trunc_err != .NONE {
		log.errorf("Failed making a window decoration: ftruncate failed with %v", trunc_err)
		return
	}

	data, mmap_err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.SHARED}, fd, 0)
	if mmap_err != .NONE {
		log.errorf("Failed making a window decoration: mmap failed with %v", mmap_err)
		return
	}

	pool := wl.shm_create_pool(deco.win.shm, c.int32_t(fd), c.int32_t(size))

	slot.buffer = wl.shm_pool_create_buffer(
		pool, 0,
		c.int32_t(width), c.int32_t(height), c.int32_t(stride),
		wl.SHM_FORMAT_ARGB8888,
	)

	// The pool can go away immediately: the mapping stays alive until every buffer made from it
	// has been destroyed.
	wl.shm_pool_destroy(pool)

	slot.pixels = ([^]u32)(data)
	slot.data_size = size
	slot.width = width
	slot.height = height
	wl.add_listener(slot.buffer, &decoration_buffer_listener, slot)
}

wldeco_destroy :: proc(deco: ^WL_Decorations) {
	for part in WL_Decoration_Part {
		d := &deco.parts[part]

		if d.surface == nil {
			continue
		}

		wl.wp_viewport_destroy(d.viewport)
		wl.subsurface_destroy(d.subsurface)
		wl.surface_destroy(d.surface)

		// The surfaces are gone, so the compositor is reading none of these whatever they say.
		for &slot in d.buffers {
			if slot.buffer != nil {
				wl.buffer_destroy(slot.buffer)
				linux.munmap(slot.pixels, uint(slot.data_size))
			}
		}

		d^ = {}
	}

	delete(deco.title, deco.win.allocator)
	deco.title = ""
}

// Picks the frame colors from what the desktop is set up for, by asking the desktop portal over
// D-Bus. That is the one place every desktop answers the question: GNOME, KDE, GTK, Qt and SDL all
// read the preference from here. A machine with no portal gets the light scheme, the same as one
// whose desktop has no preference.
//
// This is read once, while the window is being made. A player who switches their desktop between
// dark and light while the game runs keeps the frame they started with.
wldeco_desktop_colors :: proc() -> WL_Decoration_Colors {
	if missing, load_ok := dbus.load(); !load_ok {
		log.debugf("Using light window decorations. Could not load %v.", missing)
		return DECORATION_COLORS_LIGHT
	}

	connection := dbus.bus_get_private(.Session, nil)

	if connection == nil {
		log.debug("Using light window decorations. Could not connect to the session bus.")
		return DECORATION_COLORS_LIGHT
	}

	// Otherwise libdbus ends the game itself when the bus goes away.
	dbus.connection_set_exit_on_disconnect(connection, 0)

	scheme, result := wldeco_read_portal_setting(connection, "ReadOne")

	// `ReadOne` arrived in xdg-desktop-portal 1.17. An older portal has only `Read`, which is the
	// same question asked of a portal that answers it with one variant too many.
	if result == .No_Such_Method {
		scheme, result = wldeco_read_portal_setting(connection, "Read")
	}

	dbus.connection_close(connection)
	dbus.connection_unref(connection)

	if result != .Value {
		return DECORATION_COLORS_LIGHT
	}

	// 1 asks for dark, 2 asks for light and 0 is a desktop with no opinion. No opinion means light
	// in practice: GNOME sets the preference to dark when its dark style is picked and back to
	// nothing when its light one is, so anything but an explicit 1 belongs in the light scheme.
	return scheme == 1 ? DECORATION_COLORS_DARK : DECORATION_COLORS_LIGHT
}

WL_Portal_Result :: enum {
	Value,
	No_Such_Method,
	Failed,
}

// Asks the desktop portal for the color scheme with one of its two reading methods. Both take the
// setting's namespace and key and answer with the value inside one or more variants, which is what
// the unwrapping at the end is for.
wldeco_read_portal_setting :: proc(
	connection: dbus.Connection,
	method: cstring,
) -> (
	color_scheme: u32,
	result: WL_Portal_Result,
) {
	call := dbus.message_new_method_call(
		"org.freedesktop.portal.Desktop",
		"/org/freedesktop/portal/desktop",
		"org.freedesktop.portal.Settings",
		method,
	)

	if call == nil {
		return 0, .Failed
	}

	namespace := cstring("org.freedesktop.appearance")
	key := cstring("color-scheme")
	arguments: dbus.Message_Iter
	dbus.message_iter_init_append(call, &arguments)
	dbus.message_iter_append_basic(&arguments, dbus.TYPE_STRING, &namespace)
	dbus.message_iter_append_basic(&arguments, dbus.TYPE_STRING, &key)

	// A portal that has to be started first takes a moment, but a game must not hang on its way to
	// a window because something on the desktop is unwell.
	PORTAL_TIMEOUT_MS :: 500

	error: dbus.Error
	dbus.error_init(&error)
	reply := dbus.connection_send_with_reply_and_block(connection, call, PORTAL_TIMEOUT_MS, &error)
	dbus.message_unref(call)

	if reply == nil {
		// An old portal answers this way, and is the one failure worth trying something else after.
		missing := error.name == dbus.ERROR_UNKNOWN_METHOD

		log.debugf(
			"Desktop portal %v did not answer with a color scheme. Error: %v",
			method,
			error.name,
		)

		dbus.error_free(&error)
		return 0, missing ? .No_Such_Method : .Failed
	}

	dbus.error_free(&error)

	// Unwrap variants until the number falls out. Two levels is as deep as either method goes.
	outer: dbus.Message_Iter
	inner: dbus.Message_Iter
	value := &outer

	if dbus.message_iter_init(reply, &outer) == 0 {
		dbus.message_unref(reply)
		return 0, .Failed
	}

	if dbus.message_iter_get_arg_type(value) == dbus.TYPE_VARIANT {
		dbus.message_iter_recurse(&outer, &inner)
		value = &inner
	}

	unwrapped: dbus.Message_Iter

	if dbus.message_iter_get_arg_type(value) == dbus.TYPE_VARIANT {
		dbus.message_iter_recurse(value, &unwrapped)
		value = &unwrapped
	}

	if dbus.message_iter_get_arg_type(value) != dbus.TYPE_UINT32 {
		dbus.message_unref(reply)
		return 0, .Failed
	}

	scheme: u32
	dbus.message_iter_get_basic(value, &scheme)
	dbus.message_unref(reply)
	return scheme, .Value
}

// True while the pointer is over one of the surfaces that make up the frame Karl2D draws. Pointer
// events name the surface they happened on, which is what tells a click on the titlebar apart from
// a click in the game. The game hears about neither the clicks nor the movement.
wldeco_has_pointer :: proc(deco: ^WL_Decorations) -> bool {
	return deco.win.pointer_surface != nil && deco.win.pointer_surface != deco.win.surface
}

// Follows the pointer across the frame and works out what is under it: the edge it can resize from
// and the button it is on. Returns true when the cursor has to be set again.
//
// Nothing at all happens while the pointer sits still, and a button lighting up repaints the
// titlebar and nothing else. Repainting the whole frame on every motion event is exactly the
// mistake that dropped a libdecor window from 90 frames a second to one.
wldeco_pointer_moved :: proc(deco: ^WL_Decorations, local_x: f32, local_y: f32) -> bool {
	edge := wldeco_resize_edge(deco, local_x, local_y)
	button := wldeco_button_at(deco, local_x, local_y, edge)

	if button != deco.pointer_button {
		deco.pointer_button = button
		wldeco_repaint_titlebar(deco)
	}

	if edge == deco.pointer_edge {
		return false
	}

	deco.pointer_edge = edge
	return true
}

// The pointer left the frame, so nothing on it is under the pointer any more.
wldeco_pointer_left :: proc(deco: ^WL_Decorations) {
	deco.pressed_button = .None

	if deco.pointer_button != .None {
		deco.pointer_button = .None
		wldeco_repaint_titlebar(deco)
	}

	deco.pointer_edge = wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE
}

// Acts on a mouse button that changed state over the frame. Pressing near an edge starts a resize
// and pressing anywhere else that is not a titlebar button starts a move; the compositor runs both
// itself, grabbing the pointer until the button comes back up, so there is nothing here to follow
// along with. A titlebar button waits for the release, and only acts if the pointer is still on it,
// so that pressing one and sliding off changes nothing.
wldeco_pointer_button :: proc(
	deco: ^WL_Decorations,
	button: u32,
	state: u32,
	time: u32,
	serial: u32,
	local_x: f32,
	local_y: f32,
) {
	// The right button asks the compositor for the window menu, which is the one thing on the
	// frame that Karl2D does not draw itself.
	if button == wl.POINTER_BTN_RIGHT && state == wl.POINTER_BUTTON_STATE_PRESSED {
		d := deco.parts[wldeco_pointer_part(deco)]

		// The position is measured from the corner of the window geometry, which is the top left of
		// the titlebar.
		wl.xdg_toplevel_show_window_menu(
			deco.win.toplevel,
			deco.win.seat,
			serial,
			i32(f32(d.x) + local_x),
			i32(f32(d.y + DECORATION_TITLEBAR_HEIGHT) + local_y),
		)

		return
	}

	if button != wl.POINTER_BTN_LEFT {
		return
	}

	if state != wl.POINTER_BUTTON_STATE_PRESSED {
		acted := deco.pressed_button
		deco.pressed_button = .None

		if acted != .None && acted == deco.pointer_button {
			wldeco_button_acted(deco, acted)
		}

		return
	}

	if deco.pointer_button != .None {
		deco.pressed_button = deco.pointer_button
		return
	}

	if deco.pointer_edge != wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE {
		wl.xdg_toplevel_resize(deco.win.toplevel, deco.win.seat, serial, deco.pointer_edge)
		return
	}

	// Two presses close together in the same spot on the titlebar maximize the window, the way
	// they do on every desktop. The compositor's clock is what times them.
	DOUBLE_CLICK_MS :: 400
	DOUBLE_CLICK_SLOP :: 6

	quick := time - deco.last_press_time < DOUBLE_CLICK_MS
	near_x := abs(local_x - deco.last_press_x) < DOUBLE_CLICK_SLOP
	near_y := abs(local_y - deco.last_press_y) < DOUBLE_CLICK_SLOP
	deco.last_press_time = time
	deco.last_press_x = local_x
	deco.last_press_y = local_y

	if quick && near_x && near_y && wldeco_pointer_part(deco) == .Titlebar {
		// So that a third press is not the start of another double click.
		deco.last_press_time = 0
		wldeco_toggle_maximized(deco)
		return
	}

	wl.xdg_toplevel_move(deco.win.toplevel, deco.win.seat, serial)
}

// What a titlebar button does when it is clicked.
wldeco_button_acted :: proc(deco: ^WL_Decorations, button: WL_Decoration_Button) {
	switch button {
	case .None:

	case .Close:
		// The same event the compositor's own close button would have sent. What happens next is
		// the game's business: Karl2D does not close the window by itself.
		append(&deco.win.events, Event_Close_Window_Requested{})

	case .Maximize:
		wldeco_toggle_maximized(deco)

	case .Minimize:
		wl.xdg_toplevel_set_minimized(deco.win.toplevel)
	}
}

// Fills the screen with the window, or gives it back the size it had. The compositor answers with
// a configure, which is where the new size and the new state come from.
wldeco_toggle_maximized :: proc(deco: ^WL_Decorations) {
	if deco.win.maximized {
		wl.xdg_toplevel_unset_maximized(deco.win.toplevel)
		return
	}

	wl.xdg_toplevel_set_maximized(deco.win.toplevel)
}

// Which titlebar button is under the pointer, if any. `edge` is the resize edge there, since a
// grip near the corner of the window resizes rather than pressing the button beneath it.
wldeco_button_at :: proc(
	deco: ^WL_Decorations,
	local_x: f32,
	local_y: f32,
	edge: u32,
) -> WL_Decoration_Button {
	if edge != wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE || wldeco_pointer_part(deco) != .Titlebar {
		return .None
	}

	d := deco.parts[.Titlebar]
	x := f32(d.x) + local_x
	y := f32(d.y) + local_y

	for button in WL_Decoration_Button {
		if button == .None {
			continue
		}

		rect := wldeco_button_rect(deco, button)
		inside_x := x >= f32(rect.x) && x < f32(rect.x + rect.width)
		inside_y := y >= f32(rect.y) && y < f32(rect.y + rect.height)

		if inside_x && inside_y {
			return button
		}
	}

	return .None
}

// Which window edge the pointer is over, as an `xdg_toplevel` resize edge. Zero means it is on the
// frame but not near an edge, which is where dragging moves the window instead. The position is
// surface-local and in logical pixels, as pointer events give it.
wldeco_resize_edge :: proc(deco: ^WL_Decorations, local_x: f32, local_y: f32) -> u32 {
	// Only a window the game lets the player resize has edges to grab. A fixed size one, and a
	// fullscreen one, can only be moved.
	if deco.win.window_mode != .Windowed_Resizable {
		return wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE
	}

	d := deco.parts[wldeco_pointer_part(deco)]

	// Where the pointer is with the game canvas at the origin, which is what the window's own
	// edges are measured against.
	x := f32(d.x) + local_x
	y := f32(d.y) + local_y

	// The grip reaches from the margin outside the window to the same distance inside it, so a
	// corner is that much square.
	grip :: f32(DECORATION_RESIZE_MARGIN)
	edge: u32

	if y < f32(-DECORATION_TITLEBAR_HEIGHT) + grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP
	} else if y >= f32(deco.win.last_configure_height) - grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM
	}

	if x < grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_LEFT
	} else if x >= f32(deco.win.last_configure_width) - grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT
	}

	return edge
}

// Which part of the frame the pointer is on. Only meaningful while `wldeco_has_pointer` is true.
wldeco_pointer_part :: proc(deco: ^WL_Decorations) -> WL_Decoration_Part {
	for part in WL_Decoration_Part {
		if deco.parts[part].surface == deco.win.pointer_surface {
			return part
		}
	}

	return .Titlebar
}

// The cursor the frame wants under the pointer: the matching double arrow along the edges that
// resize the window, and the ordinary arrow everywhere else. The game's own cursor stays on the
// game's own canvas.
wldeco_cursor :: proc(deco: ^WL_Decorations) -> Standard_Cursor {
	switch deco.pointer_edge {
	case wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP, wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM:
		return .Resize_NS

	case wl.XDG_TOPLEVEL_RESIZE_EDGE_LEFT, wl.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT:
		return .Resize_EW

	case wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT, wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT:
		return .Resize_NWSE

	case wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT, wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT:
		return .Resize_NESW
	}

	return .Default
}

// The game canvas that fits inside a window of this size. The compositor sizes the whole window,
// frame included, while the rest of Karl2D is about the canvas, so every size that arrives in a
// configure comes through here first.
//
// An axis of zero means the compositor is leaving that one to us and stays zero.
wldeco_canvas_size :: proc(
	deco: ^WL_Decorations,
	window_width: int,
	window_height: int,
) -> (
	canvas_width: int,
	canvas_height: int,
) {
	if !wldeco_shown(deco) {
		return window_width, window_height
	}

	height := window_height

	if height != 0 {
		height = max(1, height - DECORATION_TITLEBAR_HEIGHT)
	}

	return window_width, height
}

// The window that a canvas of this size needs, which is the other direction: sizes Karl2D tells
// the compositor about, like the limits on a window the game keeps at a fixed size, are the
// window's and not the canvas's.
wldeco_window_size :: proc(
	deco: ^WL_Decorations,
	canvas_width: int,
	canvas_height: int,
) -> (
	window_width: int,
	window_height: int,
) {
	if !wldeco_shown(deco) {
		return canvas_width, canvas_height
	}

	return canvas_width, canvas_height + DECORATION_TITLEBAR_HEIGHT
}
