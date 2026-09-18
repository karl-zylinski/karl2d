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
import "base:runtime"
import stbtt "vendor:stb/truetype"

import "log"
import "platform_bindings/linux/dbus"
import wl "platform_bindings/linux/wayland"

// The frame Karl2D draws where the compositor draws none, in logical pixels. There is no border
// around the game canvas: it runs right to the window's edge on the three sides that have no
// titlebar, and what sets the window apart from the desktop is the shadow it casts.
WLCSD_TITLEBAR_HEIGHT :: 32

// How far the shadow spreads from the window, in logical pixels.
WLCSD_SHADOW_REACH :: 43

// How dark the shadow is at a given distance from the window: `a*exp(-b*distance) + c`, distance
// in logical pixels. Adwaita's shadow is a stack of CSS box shadows, which is nothing a CPU
// rasterizer wants to reproduce, so these are the curve sctk-adwaita fitted to a screenshot of a
// real Adwaita window and draws its own Wayland decorations with. Straight black, and the same in
// both color schemes, which is how GNOME does it.
WLCSD_Shadow :: struct {
	a: f32,
	b: f32,
	c: f32,
}

WLCSD_SHADOW_FOCUSED :: WLCSD_Shadow {
	a = 0.2065055,
	b = 0.10461753,
	c = -0.0005424462,
}

WLCSD_SHADOW_UNFOCUSED :: WLCSD_Shadow {
	a = 0.16829729,
	b = 0.2042998,
	c = 0.0017697986,
}

// How far outside the window the pointer can still grab an edge to resize. Well inside the shadow,
// and the only part of the shadow that takes pointer events at all: the rest lets clicks through
// to whatever is behind the window. GTK uses the same twelve pixels.
WLCSD_RESIZE_MARGIN :: 12

// A titlebar button, and how much room it takes, in logical pixels. `glyph` is the box the drawing
// inside it fits in, `stroke` how wide the lines of that drawing are, and `inset` how far the
// button keeps away from the edges of its share of the titlebar, so that the lit background under
// the pointer does not run into the next button along.
WLCSD_BUTTON_WIDTH :: 32
WLCSD_BUTTON_GLYPH :: 12
WLCSD_BUTTON_STROKE :: 1.2
WLCSD_BUTTON_INSET :: 4

// How tall the title is drawn, in logical pixels, and how much room is left either side of it
// before it is left out entirely.
WLCSD_TITLE_SIZE :: 15
WLCSD_TITLE_PADDING :: 8

// The window icon, in logical pixels: the box it is drawn in and the gap it keeps to the title it
// sits in front of. Sixteen pixels is the size a desktop draws a window icon at.
WLCSD_ICON_SIZE :: 16
WLCSD_ICON_GAP :: 6

// What the frame is painted with. The fill covers the titlebar, `text` draws the title and the
// button glyphs, and `hover` lights up the button under the pointer. Premultiplied ARGB, the
// format the decoration buffers are in.
WLCSD_Colors :: struct {
	fill: u32,
	text: u32,
	hover: u32,
}

WLCSD_COLORS_DARK :: WLCSD_Colors {
	fill = 0xff2e2e2e,
	text = 0xffdadada,
	hover = 0xff474747,
}

WLCSD_COLORS_LIGHT :: WLCSD_Colors {
	fill = 0xfff6f6f6,
	text = 0xff303030,
	hover = 0xffe0e0e0,
}

// One part of the window frame Karl2D draws for itself. Each is a subsurface of the surface the
// game renders into, with a shared memory buffer that we fill on the CPU.
WLCSD_Part :: struct {
	surface: ^wl.Surface,
	subsurface: ^wl.Subsurface,

	// Scales the buffer down from physical to logical pixels, like the one a cursor has.
	viewport: ^wl.WP_Viewport,

	// A part paints into one buffer while the compositor may still be reading the one before it, so
	// it keeps a few. Two are enough in practice; the third is headroom.
	buffers: [3]WLCSD_Buffer,

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
WLCSD_Buffer :: struct {
	buffer: ^wl.Buffer,
	pixels: [^]u32,
	data_size: int,
	width: int,
	height: int,
	busy: bool,
}

// The compositor has finished reading a buffer, so it can be painted into or thrown away again.
wlcsd_buffer_listener := wl.Buffer_Listener {
	release = proc "c" (data: rawptr, buffer: ^wl.Buffer) {
		(^WLCSD_Buffer)(data).busy = false
	},
}

WLCSD_Part_Type :: enum {
	Titlebar,
	Left,
	Right,
	Bottom,
}

// The buttons in the titlebar, laid out from the right edge of the window inwards in this order.
WLCSD_Button :: enum {
	None,
	Close,
	Maximize,
	Minimize,
}

// A rectangle in logical pixels with the game canvas at the origin, which is how the frame
// measures everything it draws.
WLCSD_Rect :: struct {
	x: int,
	y: int,
	width: int,
	height: int,
}

// Everything the frame keeps track of. `WL_State` holds one of these, so that the state of the
// window and the state of the frame around it stay apart.
WLCSD_State :: struct {
	// The window the frame is drawn around, handed over by `wlcsd_init`. Everything in this file
	// reaches the compositor through it, so that none of it goes looking for the Wayland backend's
	// own state on its own. `WL_State` is allocated once and never moves, and this points back into
	// the same allocation it lives in.
	win: ^WL_State,

	parts: [WLCSD_Part_Type]WLCSD_Part,
	colors: WLCSD_Colors,

	pointer_surface: ^wl.Surface,

	// The window edge under the pointer, as an `xdg_toplevel` resize edge. Zero where the frame
	// moves the window rather than resizing it, and stale whenever the pointer is not on the frame
	// at all, which `wlcsd_has_pointer` is what answers.
	pointer_edge: u32,

	// The button under the pointer, which is the one that lights up, and the one the button went
	// down on. A button only acts if the pointer is still on it when the button comes back up.
	pointer_button: WLCSD_Button,
	pressed_button: WLCSD_Button,

	// The window title, kept because the titlebar has to be repainted with it whenever anything
	// else about the titlebar changes. Owned by the frame, in the allocator Karl2D was given.
	title: string,

	// The window icon, drawn in front of the title. Empty until `set_window_icon` runs, which
	// `init` does for every game. A copy in the allocator Karl2D was given, at the size it came in
	// at, scaled down to the titlebar every time that is painted.
	icon: Image,

	// The embedded font, parsed once. It points into `DEFAULT_FONT_DATA`, which is baked into the
	// program and outlives everything.
	font: stbtt.fontinfo,
	font_ok: bool,

	// The parts that have changed since the last game frame. The frame is painted at most once per
	// frame however much happens in between, because a subsurface committed twice before its
	// parent catches up throws the first buffer away without the compositor ever having read it,
	// and so without ever saying it is done with it.
	needs_paint: bit_set[WLCSD_Part_Type],

	// When and where the last press on the titlebar was, to catch the second one of a double
	// click. The time is the compositor's, in milliseconds.
	last_press_time: u32,
	last_press_x: f32,
	last_press_y: f32,

	active: bool,
	maximized: bool,
}

// Creates the four surfaces that make up the window frame. They are subsurfaces of the surface the
// game renders into, so the compositor keeps them glued to it and no render backend has to know
// that they exist. `win` is the window they go around, and the frame holds on to it.
//
// They are left synchronized, which is how a subsurface starts: everything the frame commits waits
// for the game's next frame and lands with it in one go. Anything else tears the window in half
// while it resizes, since a subsurface's position always waits for the parent whatever its buffer
// does.
wlcsd_init :: proc(
	win: ^WL_State,
	allocator: runtime.Allocator,
	loc := #caller_location
) -> ^WLCSD_State {
	csd := new(WLCSD_State, allocator, loc)
	csd.win = win

	if win.subcompositor == nil {
		log.error("Wayland compositor has no wl_subcompositor. The window gets no frame.")
		free(csd, allocator)
		return nil
	}

	csd.colors = wlcsd_desktop_colors()

	// The title is drawn with the font Karl2D embeds for the game to use. Parsing it is just
	// reading the table offsets out of the file, and the file is baked into the program.
	offset := stbtt.GetFontOffsetForIndex(raw_data(DEFAULT_FONT_DATA), 0)
	csd.font_ok = bool(stbtt.InitFont(
		&csd.font,
		raw_data(DEFAULT_FONT_DATA),
		offset,
	))

	if !csd.font_ok {
		log.error("Failed reading the built in font. The window title will not be drawn.")
	}

	for part in WLCSD_Part_Type {
		d := &csd.parts[part]
		d.surface = wl.compositor_create_surface(win.compositor)
		d.subsurface = wl.subcompositor_get_subsurface(win.subcompositor, d.surface, win.surface)
		d.viewport = wl.wp_viewporter_get_viewport(win.viewporter, d.surface)
	}

	wlcsd_repaint_all(csd)
	return csd
}

// Says that the whole frame has to be laid out and painted again, which is what a resize or a scale
// change means. Nothing is drawn here; `wlcsd_flush` does that once, before the next game frame.
wlcsd_repaint_all :: proc(csd: ^WLCSD_State) {
	csd.needs_paint = {.Titlebar, .Left, .Right, .Bottom}
}

// Says that the titlebar alone has to be painted again, for the things that change while the
// window stays the same size: the title, whether the window has focus, and which button the
// pointer is on.
wlcsd_repaint_titlebar :: proc(csd: ^WLCSD_State) {
	csd.needs_paint += {.Titlebar}
}

wlcsd_set_toplevel_state :: proc(csd: ^WLCSD_State, active: bool, maximized: bool) {
	changed := active != csd.active || maximized != csd.maximized

	csd.active = active
	csd.maximized = maximized

	if changed {
		wlcsd_repaint_all(csd)
	}
}

// Paints whatever has changed and puts it where it belongs. Called once per game frame, just
// before the game draws its own, so that everything the frame commits is picked up by the same
// commit that shows the game's next frame.
wlcsd_flush :: proc(csd: ^WLCSD_State) {
	if csd.needs_paint == {} || csd.parts[.Titlebar].surface == nil {
		return
	}

	parts := csd.needs_paint
	csd.needs_paint = {}

	// In fullscreen the window is the canvas and nothing else, so the parts come off the screen
	// entirely. Attaching no buffer to a surface is how Wayland says that.
	if !wlcsd_shown(csd) {
		for part in WLCSD_Part_Type {
			d := &csd.parts[part]
			wl.surface_attach(d.surface, nil, 0, 0)
			wl.surface_commit(d.surface)
		}

		wl.xdg_surface_set_window_geometry(
			csd.win.xdg_surface,
			0,
			0,
			i32(csd.win.last_configure_width),
			i32(csd.win.last_configure_height),
		)

		return
	}

	for part in parts {
		wlcsd_paint(csd, part)
	}

	// The window is the game canvas with the titlebar on top, and neither the shadow nor the grip
	// around it. Without this the compositor would treat the canvas alone as the window, and a
	// maximized window would hang off the screen by the height of the titlebar.
	wl.xdg_surface_set_window_geometry(
		csd.win.xdg_surface,
		0,
		-WLCSD_TITLEBAR_HEIGHT,
		i32(csd.win.last_configure_width),
		i32(csd.win.last_configure_height + WLCSD_TITLEBAR_HEIGHT),
	)
}

// Whether the frame is on screen. It is not in fullscreen: that mode is for the game covering the
// screen, and a compositor sizes a fullscreen window to exactly the output with no room for a
// titlebar above it.
wlcsd_shown :: proc(csd: ^WLCSD_State) -> bool {
	if csd.parts[.Titlebar].surface == nil {
		return false
	}

	return csd.win.window_mode != .Borderless_Fullscreen
}

// Takes the title to draw. The compositor is told separately, since it wants one for its window
// list whether or not it draws any of this.
wlcsd_set_title :: proc(csd: ^WLCSD_State, title: string) {
	// Games that put their frame rate in the title set it every frame, and repainting the titlebar
	// for a title that has not changed would be that much work for nothing.
	if csd.title == title {
		return
	}

	delete(csd.title, csd.win.allocator)
	csd.title = strings.clone(title, csd.win.allocator)
	wlcsd_repaint_titlebar(csd)
}

// Takes the icon to draw in front of the title. The image belongs to whoever passed it in and may
// be gone by the next repaint, so the frame keeps a copy of the pixels.
wlcsd_set_icon :: proc(csd: ^WLCSD_State, image: Image) {
	pixels := make([]Color, len(image.pixels), csd.win.allocator)
	copy(pixels, image.pixels)
	delete(csd.icon.pixels, csd.win.allocator)

	csd.icon = {
		pixels = pixels,
		width = image.width,
		height = image.height,
	}

	wlcsd_repaint_titlebar(csd)
}

// Works out where one part of the frame sits for the current window size, paints it and puts it
// there. Positions are in logical pixels relative to the game canvas, so the titlebar has a
// negative y since it hangs above the canvas, and every part reaches a shadow's width further out
// again.
wlcsd_paint :: proc(csd: ^WLCSD_State, part: WLCSD_Part_Type) {
	w := csd.win.last_configure_width
	h := csd.win.last_configure_height
	d := &csd.parts[part]

	// How far a part reaches past the window, which is as far as the shadow goes.
	out :: WLCSD_SHADOW_REACH

	switch part {
	case .Titlebar:
		d.x = -out
		d.y = -WLCSD_TITLEBAR_HEIGHT - out
		d.width = w + out*2
		d.height = WLCSD_TITLEBAR_HEIGHT + out

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
	buffer_width := max(1, int(math.round(f32(d.width) * csd.win.scale)))
	buffer_height := max(1, int(math.round(f32(d.height) * csd.win.scale)))

	slot := wlcsd_take_buffer(csd, d, buffer_width, buffer_height)

	if slot == nil {
		return
	}

	d.pixels = slot.pixels
	d.buffer_width = buffer_width
	d.buffer_height = buffer_height

	// Where the window is inside this part, in the part's own physical pixels. The titlebar is the
	// only piece of the window that lands in a decoration surface at all; everything else in every
	// part is shadow.
	left := int(math.round(f32(-d.x) * csd.win.scale))
	top := int(math.round(f32(-WLCSD_TITLEBAR_HEIGHT - d.y) * csd.win.scale))
	right := int(math.round(f32(w - d.x) * csd.win.scale))
	bottom := int(math.round(f32(h - d.y) * csd.win.scale))

	shadow := csd.active ? WLCSD_SHADOW_FOCUSED : WLCSD_SHADOW_UNFOCUSED
	reach := WLCSD_SHADOW_REACH * csd.win.scale

	for y in 0..<buffer_height {
		for x in 0..<buffer_width {
			if x >= left && x < right && y >= top && y < bottom {
				d.pixels[y*buffer_width + x] = csd.colors.fill
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
				faded := shadow.a*math.exp(-shadow.b*distance/csd.win.scale) + shadow.c
				alpha = clamp(faded, 0, 1)
			}

			d.pixels[y*buffer_width + x] = u32(alpha*255) << 24
		}
	}

	if part == .Titlebar {
		wlcsd_paint_title(csd, d)

		for button in WLCSD_Button {
			if wlcsd_button_shown(csd, button) {
				wlcsd_paint_button(csd, d, button)
			}
		}
	}

	wlcsd_set_input_region(csd, d)
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
wlcsd_take_buffer :: proc(
	csd: ^WLCSD_State,
	d: ^WLCSD_Part,
	width: int,
	height: int,
) -> ^WLCSD_Buffer {
	for &slot in d.buffers {
		if !slot.busy && slot.buffer != nil && slot.width == width && slot.height == height {
			return &slot
		}
	}

	for &slot in d.buffers {
		if !slot.busy {
			wlcsd_make_buffer(csd, &slot, width, height)
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
wlcsd_set_input_region :: proc(csd: ^WLCSD_State, d: ^WLCSD_Part) {
	band_left := -WLCSD_RESIZE_MARGIN
	band_top := -WLCSD_TITLEBAR_HEIGHT - WLCSD_RESIZE_MARGIN
	band_right := csd.win.last_configure_width + WLCSD_RESIZE_MARGIN
	band_bottom := csd.win.last_configure_height + WLCSD_RESIZE_MARGIN

	// Clip the band to this part and put it in the part's own coordinates.
	x0 := max(d.x, band_left) - d.x
	y0 := max(d.y, band_top) - d.y
	x1 := min(d.x + d.width, band_right) - d.x
	y1 := min(d.y + d.height, band_bottom) - d.y

	region := wl.compositor_create_region(csd.win.compositor)

	if x1 > x0 && y1 > y0 {
		wl.region_add(region, i32(x0), i32(y0), i32(x1 - x0), i32(y1 - y0))
	}

	wl.surface_set_input_region(d.surface, region)
	wl.region_destroy(region)
}

// Draws the window title across the middle of the titlebar, with the window icon in front of it,
// in the space the buttons leave. The glyphs are rasterized straight out of the font Karl2D
// already embeds, one at a time, which is little enough work for something that only happens when
// the title, the size, the focus or the button under the pointer changes.
wlcsd_paint_title :: proc(csd: ^WLCSD_State, d: ^WLCSD_Part) {
	if !csd.font_ok || csd.title == "" {
		return
	}

	font := &csd.font
	scale_factor := stbtt.ScaleForPixelHeight(font, WLCSD_TITLE_SIZE * csd.win.scale)

	// Everything below is in the titlebar's own physical pixels. `left` and `right` are as far as
	// the title may reach: the window's left edge on one side and the first button on the other.
	buttons := wlcsd_button_rect(csd, max(WLCSD_Button))
	padding := int(math.round(WLCSD_TITLE_PADDING * csd.win.scale))
	left := int(math.round(f32(-d.x) * csd.win.scale)) + padding
	right := int(math.round(f32(buttons.x - d.x) * csd.win.scale)) - padding

	if right <= left {
		return
	}

	width := 0

	for r in csd.title {
		advance, left_bearing: i32
		stbtt.GetCodepointHMetrics(font, r, &advance, &left_bearing)
		width += int(math.round(f32(advance) * scale_factor))
	}

	// The icon stays in front of the title wherever that ends up, so the room it takes comes off
	// the left of the space the text has.
	icon_size := 0
	icon_room := 0

	if len(csd.icon.pixels) > 0 {
		icon_size = int(math.round(WLCSD_ICON_SIZE * csd.win.scale))
		icon_room = icon_size + int(math.round(WLCSD_ICON_GAP * csd.win.scale))
	}

	// Centered on the window itself rather than on the room beside the buttons, so that it sits
	// where the eye looks for it. A title too long for that room runs into the buttons and is cut
	// off there instead.
	center := int(math.round(f32(csd.win.last_configure_width - d.x*2) * csd.win.scale))/2
	pen := max(left + icon_room, center - width/2)
	top := int(math.round(f32(-WLCSD_TITLEBAR_HEIGHT - d.y) * csd.win.scale))
	bar_height := int(math.round(WLCSD_TITLEBAR_HEIGHT * csd.win.scale))

	if icon_size > 0 {
		wlcsd_paint_icon(
			csd,
			d,
			pen - icon_room,
			top + (bar_height - icon_size)/2,
			icon_size,
			left,
			right,
		)
	}

	// The text is centered on the band the capital letters fill, which is what the eye reads as
	// the middle of it. Centering on the font's ascent and descent instead sets it too high, since
	// those leave room for accents and for descenders that a title rarely has. The capital H is
	// what that band is measured from.
	cap_x0, cap_y0, cap_x1, cap_y1: i32
	stbtt.GetCodepointBox(font, 'H', &cap_x0, &cap_y0, &cap_x1, &cap_y1)
	cap_height := f32(cap_y1) * scale_factor
	baseline := top + int(math.round((f32(bar_height) + cap_height)/2))
	color := wlcsd_text_color(csd)

	for r in csd.title {
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
			wlcsd_blit_glyph(
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
wlcsd_blit_glyph :: proc(
	d: ^WLCSD_Part,
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
		d.pixels[at] = wlcsd_blend(d.pixels[at], color, f32(alpha)/255)
	}
}

// Draws the window icon into the titlebar buffer, inside a box `size` physical pixels a side at
// `at_x`, `at_y`, keeping the proportions the image came in with. Every pixel of it is the average
// of the source pixels it covers, which is what keeps an icon far larger than the box, and the
// 256x256 one Karl2D ships is, from coming out ragged. `clip_left` and `clip_right` keep it out of
// the buttons and off the window's edge, the same as the title.
wlcsd_paint_icon :: proc(
	csd: ^WLCSD_State,
	d: ^WLCSD_Part,
	at_x: int,
	at_y: int,
	size: int,
	clip_left: int,
	clip_right: int,
) {
	icon := csd.icon
	draw_width := size
	draw_height := size

	if icon.width > icon.height {
		draw_height = max(1, size*icon.height/icon.width)
	} else if icon.height > icon.width {
		draw_width = max(1, size*icon.width/icon.height)
	}

	// A picture that does not fill the box sits in the middle of it.
	box_x := at_x + (size - draw_width)/2
	box_y := at_y + (size - draw_height)/2

	for y in 0..<draw_height {
		for x in 0..<draw_width {
			to_x := box_x + x
			to_y := box_y + y

			if to_x < clip_left || to_x >= clip_right || to_y < 0 || to_y >= d.buffer_height {
				continue
			}

			// The source pixels this one covers. Averaging them is the whole of the scaling, and
			// the color is weighted by alpha so that transparent pixels do not wash the edges out.
			from_x0 := x*icon.width/draw_width
			from_x1 := max(from_x0 + 1, (x + 1)*icon.width/draw_width)
			from_y0 := y*icon.height/draw_height
			from_y1 := max(from_y0 + 1, (y + 1)*icon.height/draw_height)
			total_a := 0
			total_r := 0
			total_g := 0
			total_b := 0

			for from_y in from_y0..<from_y1 {
				for from_x in from_x0..<from_x1 {
					col := icon.pixels[from_y*icon.width + from_x]
					a := int(col.a)
					total_a += a
					total_r += int(col.r)*a
					total_g += int(col.g)*a
					total_b += int(col.b)*a
				}
			}

			if total_a == 0 {
				continue
			}

			sampled := (from_x1 - from_x0)*(from_y1 - from_y0)
			r := u32(total_r/total_a)
			g := u32(total_g/total_a)
			b := u32(total_b/total_a)
			alpha := f32(total_a)/f32(sampled*255)
			at := to_y*d.buffer_width + to_x
			d.pixels[at] = wlcsd_blend(d.pixels[at], 0xff000000 | r << 16 | g << 8 | b, alpha)
		}
	}
}

// What the title and the button glyphs are drawn in. Dimmed towards the titlebar itself while the
// window is not the one being typed into, the way every other window on the desktop dims.
wlcsd_text_color :: proc(csd: ^WLCSD_State) -> u32 {
	if csd.active {
		return csd.colors.text
	}

	return wlcsd_blend(csd.colors.fill, csd.colors.text, 0.45)
}

// Draws one button into the titlebar buffer: a lit background while the pointer is on it, and the
// glyph that says what it does. `d` is the titlebar, whose buffer the button is painted into.
wlcsd_paint_button :: proc(
	csd: ^WLCSD_State,
	d: ^WLCSD_Part,
	button: WLCSD_Button,
) {
	rect := wlcsd_button_rect(csd, button)

	// The button's corner in the titlebar's own physical pixels.
	x0 := int(math.round(f32(rect.x - d.x) * csd.win.scale))
	y0 := int(math.round(f32(rect.y - d.y) * csd.win.scale))
	x1 := min(d.buffer_width, int(math.round(f32(rect.x + rect.width - d.x) * csd.win.scale)))
	y1 := min(d.buffer_height, int(math.round(f32(rect.y + rect.height - d.y) * csd.win.scale)))

	if x0 >= x1 || y0 >= y1 {
		return
	}

	background := csd.colors.fill

	if csd.pointer_button == button {
		background = csd.colors.hover
	}

	center_x := f32(x0 + x1)/2
	center_y := f32(y0 + y1)/2
	reach := WLCSD_BUTTON_GLYPH/2 * csd.win.scale
	half_stroke := WLCSD_BUTTON_STROKE/2 * csd.win.scale
	color := wlcsd_text_color(csd)

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
				if !csd.maximized {
					to_line = wlcsd_square_distance(dx, dy, reach*0.8)
					break
				}

				// Once the window is maximized the button undoes that, and says so as two windows
				// laid over one another: one at the front, and one behind it up and to the right
				// showing only the corner the front one does not cover.
				window := reach*0.62
				shift := window*0.45
				to_line = wlcsd_square_distance(dx + shift, dy - shift, window)
				covered := max(abs(dx + shift), abs(dy - shift)) <= window + half_stroke + 0.5

				if !covered {
					to_line = min(to_line, wlcsd_square_distance(dx - shift, dy + shift, window))
				}

			case .Minimize:
				// A line along the bottom of where the other glyphs are.
				if abs(dx) <= reach*0.8 {
					to_line = abs(dy - reach*0.6)
				}
			}

			coverage := clamp(half_stroke + 0.5 - to_line, 0, 1)
			d.pixels[y*d.buffer_width + x] = wlcsd_blend(background, color, coverage)
		}
	}
}

// How far a point is from the outline of a square of half width `reach` centered on the origin, so
// that a square comes out of the same coverage code as the diagonal strokes of the X.
wlcsd_square_distance :: proc(dx: f32, dy: f32, reach: f32) -> f32 {
	return abs(max(abs(dx), abs(dy)) - reach)
}

// Mixes two opaque colors, `amount` being how much of `over` shows.
wlcsd_blend :: proc(under: u32, over: u32, amount: f32) -> u32 {
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

// Whether a button is in the titlebar at all. A window the game keeps at a fixed size cannot be
// maximized, and a compositor handed `set_maximized` for one moves it into the corner of the
// screen at the size it already had, so such a window does not get the button.
wlcsd_button_shown :: proc(csd: ^WLCSD_State, button: WLCSD_Button) -> bool {
	if button == .None {
		return false
	}

	if button == .Maximize {
		return csd.win.window_mode == .Windowed_Resizable
	}

	return true
}

// Where a titlebar button sits, both for drawing it and for deciding whether the pointer is on it.
// They are laid out from the right edge of the window inwards, in the order of the enum, each in a
// slot of its own with a little room left around it. A button that is not shown takes up no slot,
// so the ones inside it move out towards the edge.
wlcsd_button_rect :: proc(
	csd: ^WLCSD_State,
	button: WLCSD_Button,
) -> WLCSD_Rect {
	slot := 0

	for b in WLCSD_Button {
		if b == button {
			break
		}

		if wlcsd_button_shown(csd, b) {
			slot += 1
		}
	}

	return {
		x = csd.win.last_configure_width - (slot + 1)*WLCSD_BUTTON_WIDTH + WLCSD_BUTTON_INSET,
		y = -WLCSD_TITLEBAR_HEIGHT + WLCSD_BUTTON_INSET,
		width = WLCSD_BUTTON_WIDTH - WLCSD_BUTTON_INSET*2,
		height = WLCSD_TITLEBAR_HEIGHT - WLCSD_BUTTON_INSET*2,
	}
}

// Fills one of a part's slots with a fresh shared memory buffer. Whatever the slot held is thrown
// away first, which is safe because a slot is only ever passed here once the compositor has said
// it has finished reading it.
wlcsd_make_buffer :: proc(
	csd: ^WLCSD_State,
	slot: ^WLCSD_Buffer,
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

	pool := wl.shm_create_pool(csd.win.shm, c.int32_t(fd), c.int32_t(size))

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
	wl.add_listener(slot.buffer, &wlcsd_buffer_listener, slot)
}

wlcsd_destroy :: proc(csd: ^WLCSD_State) {
	for part in WLCSD_Part_Type {
		d := &csd.parts[part]

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

	delete(csd.title, csd.win.allocator)
	csd.title = ""
	delete(csd.icon.pixels, csd.win.allocator)
	csd.icon = {}
}

// Picks the frame colors from what the desktop is set up for, by asking the desktop portal over
// D-Bus. That is the one place every desktop answers the question: GNOME, KDE, GTK, Qt and SDL all
// read the preference from here. A machine with no portal gets the light scheme, the same as one
// whose desktop has no preference.
//
// This is read once, while the window is being made. A player who switches their desktop between
// dark and light while the game runs keeps the frame they started with.
wlcsd_desktop_colors :: proc() -> WLCSD_Colors {
	if missing, load_ok := dbus.load(); !load_ok {
		log.debugf("Using light window decorations. Could not load %v.", missing)
		return WLCSD_COLORS_LIGHT
	}

	connection := dbus.bus_get_private(.Session, nil)

	if connection == nil {
		log.debug("Using light window decorations. Could not connect to the session bus.")
		return WLCSD_COLORS_LIGHT
	}

	// Tell libdbus to leave the process alone when the bus goes away. It ends the game itself
	// otherwise.
	dbus.connection_set_exit_on_disconnect(connection, 0)

	scheme, result := wlcsd_read_portal_setting(connection, "ReadOne")

	// `ReadOne` arrived in xdg-desktop-portal 1.17. An older portal has only `Read`, which is the
	// same question asked of a portal that answers it with one variant too many.
	if result == .No_Such_Method {
		scheme, result = wlcsd_read_portal_setting(connection, "Read")
	}

	dbus.connection_close(connection)
	dbus.connection_unref(connection)

	if result != .Value {
		return WLCSD_COLORS_LIGHT
	}

	// 1 asks for dark, 2 asks for light and 0 is a desktop with no opinion. No opinion means light
	// in practice: GNOME sets the preference to dark when its dark style is picked and back to
	// nothing when its light one is, so anything but an explicit 1 belongs in the light scheme.
	return scheme == 1 ? WLCSD_COLORS_DARK : WLCSD_COLORS_LIGHT
}

WL_Portal_Result :: enum {
	Value,
	No_Such_Method,
	Failed,
}

// Asks the desktop portal for the color scheme with one of its two reading methods. Both take the
// setting's namespace and key and answer with the value inside one or more variants, which is what
// the unwrapping at the end is for.
wlcsd_read_portal_setting :: proc(
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

wlcsd_pointer_over_frame :: proc(csd: ^WLCSD_State) -> bool {
	return csd.pointer_surface != nil && csd.pointer_surface != csd.win.surface
}

wlcsd_set_pointer_surface :: proc(csd: ^WLCSD_State, pointer_surface: ^wl.Surface) {
	csd.pointer_surface = pointer_surface
}

// Follows the pointer across the frame and works out what is under it: the edge it can resize from
// and the button it is on. Returns true when the cursor has to be set again.
//
// Nothing at all happens while the pointer sits still, and a button lighting up repaints the
// titlebar and nothing else. Repainting the whole frame on every motion event is exactly the
// mistake that dropped a libdecor window from 90 frames a second to one.
wlcsd_pointer_moved :: proc(csd: ^WLCSD_State, local_x: f32, local_y: f32) -> bool {
	edge := wlcsd_resize_edge(csd, local_x, local_y)
	button := wlcsd_button_at(csd, local_x, local_y, edge)

	if button != csd.pointer_button {
		csd.pointer_button = button
		wlcsd_repaint_titlebar(csd)
	}

	if edge == csd.pointer_edge {
		return false
	}

	csd.pointer_edge = edge
	return true
}

// The pointer left the frame, so nothing on it is under the pointer any more.
wlcsd_pointer_left :: proc(csd: ^WLCSD_State) {
	csd.pressed_button = .None

	if csd.pointer_button != .None {
		csd.pointer_button = .None
		wlcsd_repaint_titlebar(csd)
	}

	csd.pointer_edge = wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE
}

// Acts on a mouse button that changed state over the frame. Pressing near an edge starts a resize
// and pressing anywhere else that is not a titlebar button starts a move; the compositor runs both
// itself, grabbing the pointer until the button comes back up, so there is nothing here to follow
// along with. A titlebar button waits for the release, and only acts if the pointer is still on it,
// so that pressing one and sliding off changes nothing.
wlcsd_pointer_button :: proc(
	csd: ^WLCSD_State,
	button: u32,
	state: u32,
	time: u32,
	serial: u32,
	local_x: f32,
	local_y: f32,
) {
	// The right button asks the compositor for the window menu, which is the one thing on the
	// frame that Karl2D does not draw itself.
	if button == wl.BTN_RIGHT && state == wl.POINTER_BUTTON_STATE_PRESSED {
		d := csd.parts[wlcsd_pointer_part(csd)]

		// The position is measured from the corner of the window geometry, which is the top left of
		// the titlebar.
		wl.xdg_toplevel_show_window_menu(
			csd.win.toplevel,
			csd.win.seat,
			serial,
			i32(f32(d.x) + local_x),
			i32(f32(d.y + WLCSD_TITLEBAR_HEIGHT) + local_y),
		)

		return
	}

	if button != wl.BTN_LEFT {
		return
	}

	if state != wl.POINTER_BUTTON_STATE_PRESSED {
		acted := csd.pressed_button
		csd.pressed_button = .None

		if acted != .None && acted == csd.pointer_button {
			wlcsd_button_acted(csd, acted)
		}

		return
	}

	if csd.pointer_button != .None {
		csd.pressed_button = csd.pointer_button
		return
	}

	if csd.pointer_edge != wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE {
		wl.xdg_toplevel_resize(csd.win.toplevel, csd.win.seat, serial, csd.pointer_edge)
		return
	}

	// Two presses close together in the same spot on the titlebar maximize the window, the way
	// they do on every desktop, as long as it is a window that can be maximized at all. The
	// compositor's clock is what times them.
	DOUBLE_CLICK_MS :: 400
	DOUBLE_CLICK_SLOP :: 6

	quick := time - csd.last_press_time < DOUBLE_CLICK_MS
	near_x := abs(local_x - csd.last_press_x) < DOUBLE_CLICK_SLOP
	near_y := abs(local_y - csd.last_press_y) < DOUBLE_CLICK_SLOP
	csd.last_press_time = time
	csd.last_press_x = local_x
	csd.last_press_y = local_y

	resizable := csd.win.window_mode == .Windowed_Resizable

	if quick && near_x && near_y && resizable && wlcsd_pointer_part(csd) == .Titlebar {
		// Forget the press, so that a third one is not the start of another double click.
		csd.last_press_time = 0
		wlcsd_toggle_maximized(csd)
		return
	}

	wl.xdg_toplevel_move(csd.win.toplevel, csd.win.seat, serial)
}

// What a titlebar button does when it is clicked.
wlcsd_button_acted :: proc(csd: ^WLCSD_State, button: WLCSD_Button) {
	switch button {
	case .None:

	case .Close:
		// The same event the compositor's own close button would have sent. What happens next is
		// the game's business: Karl2D does not close the window by itself.
		append(&csd.win.events, Event_Close_Window_Requested{})

	case .Maximize:
		wlcsd_toggle_maximized(csd)

	case .Minimize:
		wl.xdg_toplevel_set_minimized(csd.win.toplevel)
	}
}

// Fills the screen with the window, or gives it back the size it had. The compositor answers with
// a configure, which is where the new size and the new state come from.
wlcsd_toggle_maximized :: proc(csd: ^WLCSD_State) {
	if csd.maximized {
		wl.xdg_toplevel_unset_maximized(csd.win.toplevel)
		return
	}

	wl.xdg_toplevel_set_maximized(csd.win.toplevel)
}

// Which titlebar button is under the pointer, if any. `edge` is the resize edge there, since a
// grip near the corner of the window resizes rather than pressing the button beneath it.
wlcsd_button_at :: proc(
	csd: ^WLCSD_State,
	local_x: f32,
	local_y: f32,
	edge: u32,
) -> WLCSD_Button {
	if edge != wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE || wlcsd_pointer_part(csd) != .Titlebar {
		return .None
	}

	d := csd.parts[.Titlebar]
	x := f32(d.x) + local_x
	y := f32(d.y) + local_y

	for button in WLCSD_Button {
		if !wlcsd_button_shown(csd, button) {
			continue
		}

		rect := wlcsd_button_rect(csd, button)
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
wlcsd_resize_edge :: proc(csd: ^WLCSD_State, local_x: f32, local_y: f32) -> u32 {
	// Only a window the game lets the player resize has edges to grab. A fixed size one, and a
	// fullscreen one, can only be moved.
	if csd.win.window_mode != .Windowed_Resizable {
		return wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE
	}

	d := csd.parts[wlcsd_pointer_part(csd)]

	// Where the pointer is with the game canvas at the origin, which is what the window's own
	// edges are measured against.
	x := f32(d.x) + local_x
	y := f32(d.y) + local_y

	// The grip reaches from the margin outside the window to the same distance inside it, so a
	// corner is that much square.
	grip :: f32(WLCSD_RESIZE_MARGIN)
	edge: u32

	if y < f32(-WLCSD_TITLEBAR_HEIGHT) + grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP
	} else if y >= f32(csd.win.last_configure_height) - grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM
	}

	if x < grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_LEFT
	} else if x >= f32(csd.win.last_configure_width) - grip {
		edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT
	}

	return edge
}

// Which part of the frame the pointer is on. Only meaningful while `wlcsd_has_pointer` is true.
wlcsd_pointer_part :: proc(csd: ^WLCSD_State) -> WLCSD_Part_Type {
	for part in WLCSD_Part_Type {
		if csd.parts[part].surface == csd.pointer_surface {
			return part
		}
	}

	return .Titlebar
}

// The cursor the frame wants under the pointer: the matching double arrow along the edges that
// resize the window, and the ordinary arrow everywhere else. The game's own cursor stays on the
// game's own canvas.
wlcsd_cursor :: proc(csd: ^WLCSD_State) -> Standard_Cursor {
	switch csd.pointer_edge {
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
wlcsd_canvas_size :: proc(
	csd: ^WLCSD_State,
	window_width: int,
	window_height: int,
) -> (
	canvas_width: int,
	canvas_height: int,
) {
	if !wlcsd_shown(csd) {
		return window_width, window_height
	}

	if window_height != 0 {
		return window_width, max(1, window_height - WLCSD_TITLEBAR_HEIGHT)
	}

	return window_width, window_height
}

// The window that a canvas of this size needs, which is the other direction: sizes Karl2D tells
// the compositor about, like the limits on a window the game keeps at a fixed size, are the
// window's and not the canvas's.
wlcsd_window_size :: proc(
	csd: ^WLCSD_State,
	canvas_width: int,
	canvas_height: int,
) -> (
	window_width: int,
	window_height: int,
) {
	if !wlcsd_shown(csd) {
		return canvas_width, canvas_height
	}

	return canvas_width, canvas_height + WLCSD_TITLEBAR_HEIGHT
}
