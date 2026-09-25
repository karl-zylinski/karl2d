// Wayland Client-Side Decorations (WLCSD).
//
// This file implements window decorations: A frame with buttons and a titlebar. It's used on
// Linux + Wayland when there are no server-side decorations. If you use for example KDE then the
// Wayland server draws the frame for you. But under GNOME this does not happen. The we instead
// implement so-called client-side decorations (CSD): The application draws the frame.

#+build linux
#+private package
package karl2d

import "core:math"
import "core:strings"
import "base:runtime"
import stbtt "vendor:stb/truetype"

import "log"
import "platform_bindings/linux/dbus"
import wl "platform_bindings/linux/wayland"

// These measurements are in "logical pixels". They are automatically scaled.
WLCSD_TITLEBAR_HEIGHT :: 32
WLCSD_SHADOW_REACH :: 43

// How dark the shadow is at a given distance from the window: `a*exp(-b*distance) + c`.
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

// How far outside the window the pointer can still grab an edge to resize.
WLCSD_RESIZE_MARGIN :: 12

WLCSD_BUTTON_WIDTH :: 32
WLCSD_BUTTON_ICON_SIZE :: 12
WLCSD_BUTTON_STROKE :: 1.2
WLCSD_BUTTON_INSET :: 4

WLCSD_TITLE_FONT_SIZE :: 15
WLCSD_TITLE_HORIZONTAL_MARGIN :: 8

WLCSD_ICON_SIZE :: 16
WLCSD_ICON_HORIZONTAL_MARGIN :: 6

// The colors to paint with. Fill is the background. Text is the text color. Hover if the color that
// you see when you hover the titlebar buttons.
WLCSD_Theme :: struct {
	fill: u32,
	text: u32,
	hover: u32,
}

WLCSD_THEME_DARK :: WLCSD_Theme {
	fill = 0xff2e2e2e,
	text = 0xffdadada,
	hover = 0xff474747,
}

WLCSD_THEME_LIGHT :: WLCSD_Theme {
	fill = 0xfff6f6f6,
	text = 0xff303030,
	hover = 0xffe0e0e0,
}

// A part of the window frame, such as the titlebar or one of the sides.
WLCSD_Part :: struct {
	surface: ^wl.Surface,
	subsurface: ^wl.Subsurface,

	// Scales the buffer down from physical to logical pixels.
	viewport: ^wl.WP_Viewport,

	// A part of the frame may still be read by compositor when we want to paint a new one. Having
	// three seems to be enough for making sure that there's always one that isn't currently being
	// read.
	buffers: [3]WL_Shared_Memory_Image,
	buffers_busy: [3]bool,

	// Index into `buffers` of the currently used buffer.
	current_buffer: int,

	x: int,
	y: int,
	width: int,
	height: int,
}

wlcsd_buffer_listener := wl.Buffer_Listener {
	// When the compositor is done with a buffer, we get notifed. We unset the busy flag for that
	// buffer, so we can reuse it.
	release = proc "c" (data: rawptr, buffer: ^wl.Buffer) {
		d := (^WLCSD_Part)(data)

		for i in 0..<len(d.buffers) {
			if d.buffers[i].buffer == buffer {
				d.buffers_busy[i] = false
			}
		}
	},
}

WLCSD_Part_Type :: enum {
	Titlebar,
	Left,
	Right,
	Bottom,
}

// The buttons in the titlebar, laid out from the right edge of the window inwards, in this order.
WLCSD_Button :: enum {
	Close,
	Maximize,
	Minimize,
}

WLCSD_Edge :: enum {
	Top,
	Bottom,
	Left,
	Right,
}

WLCSD_Rect :: struct {
	x: int,
	y: int,
	width: int,
	height: int,
}

// The main state of the client-side deocrations. WL_State has one of these.
WLCSD_State :: struct {
	allocator: runtime.Allocator,
	surface: ^wl.Surface,
	xdg_surface: ^wl.XDG_Surface,
	seat: ^wl.Seat,
	compositor: ^wl.Compositor,
	toplevel: ^wl.XDG_Toplevel,

	parts: [WLCSD_Part_Type]WLCSD_Part,
	theme: WLCSD_Theme,

	pointer_surface: ^wl.Surface,

	// The button under the pointer, which is the one that lights up, and the one the button went
	// down on. A button only acts if the pointer is still on it when the button comes back up.
	pointer_button: Maybe(WLCSD_Button),
	pressed_button: Maybe(WLCSD_Button),

	// The window title. Used when re-painting the titlebar.
	title: string,

	// The window icon, drawn next to the title.
	icon: Image,

	// Used for rendering the title.
	font: stbtt.fontinfo,
	font_ok: bool,

	// Parts that need to be re-painted because some state changed during the frame.
	needs_paint: bit_set[WLCSD_Part_Type],

	// For detecting double click on titlebar.
	last_press_time: u32,
	last_press_x: f32,
	last_press_y: f32,

	active: bool,
	maximized: bool,

	window_width: int,
	window_height: int,
	window_mode: Window_Mode,
}

wlcsd_set_window_size :: proc(csd: ^WLCSD_State, window_width: int, window_height: int) {
	csd.window_width = window_width
	csd.window_height = window_height
}

wlcsd_set_window_mode :: proc(csd: ^WLCSD_State, window_mode: Window_Mode) {
	csd.window_mode = window_mode
}

// Sets up the client-side decorations. Creates the four parts that make up the frame.
wlcsd_init :: proc(
	surface: ^wl.Surface,
	xdg_surface: ^wl.XDG_Surface,
	viewporter: ^wl.WP_Viewporter,
	seat: ^wl.Seat,
	compositor: ^wl.Compositor,
	subcompositor: ^wl.Subcompositor,
	toplevel: ^wl.XDG_Toplevel,
	window_width: int,
	window_height: int,
	window_mode: Window_Mode,
	allocator: runtime.Allocator,
	loc := #caller_location
) -> ^WLCSD_State {
	if surface == nil {
		log.error("surface is nil. The window gets no frame.", location = loc)
		return nil
	}

	if xdg_surface == nil {
		log.error("xdg_surface is nil. The window gets no frame.", location = loc)
		return nil
	}

	if viewporter == nil {
		log.error("viewporter is nil. The window gets no frame.", location = loc)
		return nil
	}

	if seat == nil {
		log.error("seat is nil. The window gets no frame.", location = loc)
		return nil
	}

	if compositor == nil {
		log.error("compositor is nil. The window gets no frame.", location = loc)
		return nil
	}

	if subcompositor == nil {
		log.error("subcompositor is nil. The window gets no frame.", location = loc)
		return nil
	}

	if toplevel == nil {
		log.error("toplevel is nil. The window gets no frame.", location = loc)
		return nil
	}

	csd := new(WLCSD_State, allocator, loc)
	csd.surface = surface
	csd.xdg_surface = xdg_surface
	csd.seat = seat
	csd.compositor = compositor
	csd.allocator = allocator
	csd.toplevel = toplevel
	csd.window_width = window_width
	csd.window_height = window_height
	csd.window_mode = window_mode

	csd.theme = wlcsd_pick_theme()

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
		d.surface = wl.compositor_create_surface(compositor)
		d.subsurface = wl.subcompositor_get_subsurface(subcompositor, d.surface, surface)
		d.viewport = wl.wp_viewporter_get_viewport(viewporter, d.surface)
	}

	wlcsd_needs_repaint_all(csd)
	return csd
}

// Says that the whole frame has to be laid out and painted again, which is what a resize or a scale
// change means. Nothing is drawn here; `wlcsd_paint` does that once, before the next game frame.
wlcsd_needs_repaint_all :: proc(csd: ^WLCSD_State) {
	csd.needs_paint = {.Titlebar, .Left, .Right, .Bottom}
}

wlcsd_set_toplevel_state :: proc(csd: ^WLCSD_State, active: bool, maximized: bool) {
	changed := active != csd.active || maximized != csd.maximized

	csd.active = active
	csd.maximized = maximized

	if changed {
		wlcsd_needs_repaint_all(csd)
	}
}

// Paints whatever has changed and puts it where it belongs. Called once per game frame, just
// before the game draws its own, so that everything the frame commits is picked up by the same
// commit that shows the game's next frame.
wlcsd_paint :: proc(
	csd: ^WLCSD_State,
	scale: f32,
) {
	if csd.needs_paint == {} {
		return
	}

	parts := csd.needs_paint
	csd.needs_paint = {}

	if csd.window_mode == .Borderless_Fullscreen {
		for part in WLCSD_Part_Type {
			d := &csd.parts[part]
			wl.surface_attach(d.surface, nil, 0, 0)
			wl.surface_commit(d.surface)
		}

		wl.xdg_surface_set_window_geometry(
			csd.xdg_surface,
			0,
			0,
			i32(csd.window_width),
			i32(csd.window_height),
		)

		return
	}

	for part in parts {
		w := csd.window_width
		h := csd.window_height
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
		buffer_width := max(1, int(math.round(f32(d.width) * scale)))
		buffer_height := max(1, int(math.round(f32(d.height) * scale)))

		current := -1

		for i in 0..<len(d.buffers) {
			if !d.buffers_busy[i] {
				current = i
				break
			}
		}

		if current == -1 {
			// Every slot is still on the compositor's hands. It lets go of them as soon as it shows
			// something else, so this means it is several frames behind and the frame can wait one
			// more.
			log.debug("Every window decoration buffer is still in use. Skipping a repaint.")
			csd.needs_paint += {part}
			continue
		}

		if d.buffers[current].width != buffer_width || d.buffers[current].height != buffer_height {
			wl_destroy_shared_memory_image(d.buffers[current])

			image, image_ok := wl_create_shared_memory_image(
				"karl2d-decoration",
				buffer_width,
				buffer_height,
			)

			d.buffers[current] = image

			if !image_ok {
				csd.needs_paint += {part}
				continue
			}

			wl.add_listener(image.buffer, &wlcsd_buffer_listener, d)
		}

		d.current_buffer = current
		pixels := d.buffers[current].pixels

		// Where the window is inside this part, in the part's own physical pixels. The titlebar is
		// the only piece of the window that lands in a decoration surface at all; everything else
		// in every part is shadow.
		left := int(math.round(f32(-d.x) * scale))
		top := int(math.round(f32(-WLCSD_TITLEBAR_HEIGHT - d.y) * scale))
		right := int(math.round(f32(w - d.x) * scale))
		bottom := int(math.round(f32(h - d.y) * scale))

		shadow := csd.active ? WLCSD_SHADOW_FOCUSED : WLCSD_SHADOW_UNFOCUSED
		shadow_reach := WLCSD_SHADOW_REACH * scale

		for y in 0..<buffer_height {
			for x in 0..<buffer_width {
				if x >= left && x < right && y >= top && y < bottom {
					pixels[y*buffer_width + x] = csd.theme.fill
					continue
				}

				// How far this pixel is from the window, which is all the shadow depends on. The
				// distance is put back into logical pixels because that is what the curve was
				// fitted against, and the shadow is black, so premultiplying leaves nothing but the
				// alpha.
				dx := f32(max(left - x, 0, x - right + 1))
				dy := f32(max(top - y, 0, y - bottom + 1))
				distance := math.sqrt(dx*dx + dy*dy)
				alpha := f32(0)

				if distance < shadow_reach {
					faded := shadow.a*math.exp(-shadow.b*distance/scale) + shadow.c
					alpha = clamp(faded, 0, 1)
				}

				pixels[y*buffer_width + x] = u32(alpha*255) << 24
			}
		}

		if part == .Titlebar {
			wlcsd_paint_title(csd, d, scale)
			button_idx: int

			for button in WLCSD_Button {
				if button == .Maximize && csd.window_mode != .Windowed_Resizable {
					continue
				}

				rect := wlcsd_button_rect(csd, button_idx)
				button_idx += 1

				// The button's corner in the titlebar's own physical pixels.
				x0 := int(math.round(f32(rect.x - d.x) * scale))
				y0 := int(math.round(f32(rect.y - d.y) * scale))
				x1 := min(
					buffer_width,
					int(math.round(f32(rect.x + rect.width - d.x) * scale)),
				)

				y1 := min(
					buffer_height,
					int(math.round(f32(rect.y + rect.height - d.y) * scale)),
				)

				if x0 >= x1 || y0 >= y1 {
					continue
				}

				background := csd.theme.fill

				if csd.pointer_button == button {
					background = csd.theme.hover
				}

				center_x := f32(x0 + x1)/2
				center_y := f32(y0 + y1)/2
				reach := WLCSD_BUTTON_ICON_SIZE/2 * scale
				half_stroke := WLCSD_BUTTON_STROKE/2 * scale
				color := wlcsd_text_color(csd)

				for y in y0..<y1 {
					for x in x0..<x1 {
						// Every glyph is drawn from how far the pixel is from the lines that make
						// it up. Turning that distance into coverage costs nothing and keeps the
						// drawing from looking like a staircase at any scale.
						dx := f32(x) - center_x + 0.5
						dy := f32(y) - center_y + 0.5
						to_line := max(f32)

						switch button {
						case .Close:
							if abs(dx) <= reach && abs(dy) <= reach {
								// The 0.7071 turns a distance along an axis into the distance to a
								// line at 45 degrees, which is what the two strokes of an X are.
								to_line = min(abs(dx - dy), abs(dx + dy)) * 0.70710678
							}

						case .Maximize:
							if !csd.maximized {
								to_line = wlcsd_square_distance(dx, dy, reach*0.8)
								break
							}

							// Once the window is maximized the button undoes that, and says so as
							// two windows laid over one another: one at the front, and one behind
							// it up and to the right showing only the corner the front one does not
							// cover.
							window := reach*0.62
							shift := window*0.45
							to_line = wlcsd_square_distance(dx + shift, dy - shift, window)
							front_reach := window + half_stroke + 0.5
							covered := max(abs(dx + shift), abs(dy - shift)) <= front_reach

							if !covered {
								to_line = min(
									to_line,
									wlcsd_square_distance(dx - shift, dy + shift, window),
								)
							}

						case .Minimize:
							// A line along the bottom of where the other glyphs are.
							if abs(dx) <= reach*0.8 {
								to_line = abs(dy - reach*0.6)
							}
						}

						coverage := clamp(half_stroke + 0.5 - to_line, 0, 1)
						pixels[y*buffer_width + x] = wlcsd_blend(background, color, coverage)
					}
				}
			}
		}

		band_left := -WLCSD_RESIZE_MARGIN
		band_top := -WLCSD_TITLEBAR_HEIGHT - WLCSD_RESIZE_MARGIN
		band_right := csd.window_width + WLCSD_RESIZE_MARGIN
		band_bottom := csd.window_height + WLCSD_RESIZE_MARGIN

		// Clip the band to this part and put it in the part's own coordinates.
		x0 := max(d.x, band_left) - d.x
		y0 := max(d.y, band_top) - d.y
		x1 := min(d.x + d.width, band_right) - d.x
		y1 := min(d.y + d.height, band_bottom) - d.y

		region := wl.compositor_create_region(csd.compositor)

		if x1 > x0 && y1 > y0 {
			wl.region_add(region, i32(x0), i32(y0), i32(x1 - x0), i32(y1 - y0))
		}

		wl.surface_set_input_region(d.surface, region)
		wl.region_destroy(region)
		wl.subsurface_set_position(d.subsurface, i32(d.x), i32(d.y))
		wl.wp_viewport_set_destination(d.viewport, i32(max(1, d.width)), i32(max(1, d.height)))
		wl.surface_attach(d.surface, d.buffers[current].buffer, 0, 0)
		wl.surface_damage_buffer(d.surface, 0, 0, i32(buffer_width), i32(buffer_height))
		wl.surface_commit(d.surface)
		d.buffers_busy[current] = true
	}

	// The window is the game canvas with the titlebar on top, and neither the shadow nor the grip
	// around it. Without this the compositor would treat the canvas alone as the window, and a
	// maximized window would hang off the screen by the height of the titlebar.
	wl.xdg_surface_set_window_geometry(
		csd.xdg_surface,
		0,
		-WLCSD_TITLEBAR_HEIGHT,
		i32(csd.window_width),
		i32(csd.window_height + WLCSD_TITLEBAR_HEIGHT),
	)
}

// Takes the title to draw. The compositor is told separately, since it wants one for its window
// list whether or not it draws any of this.
wlcsd_set_title :: proc(csd: ^WLCSD_State, title: string) {
	// Games that put their frame rate in the title set it every frame, and repainting the titlebar
	// for a title that has not changed would be that much work for nothing.
	if csd.title == title {
		return
	}

	delete(csd.title, csd.allocator)
	csd.title = strings.clone(title, csd.allocator)
	csd.needs_paint += {.Titlebar}
}

// Takes the icon to draw in front of the title. The image belongs to whoever passed it in and may
// be gone by the next repaint, so the frame keeps a copy of the pixels.
wlcsd_set_icon :: proc(csd: ^WLCSD_State, image: Image) {
	pixels := make([]Color, len(image.pixels), csd.allocator)
	copy(pixels, image.pixels)
	delete(csd.icon.pixels, csd.allocator)

	csd.icon = {
		pixels = pixels,
		width = image.width,
		height = image.height,
	}

	csd.needs_paint += {.Titlebar}
}

// Draws the window title across the middle of the titlebar, with the window icon in front of it,
// in the space the buttons leave. The glyphs are rasterized straight out of the font Karl2D
// already embeds, one at a time, which is little enough work for something that only happens when
// the title, the size, the focus or the button under the pointer changes.
wlcsd_paint_title :: proc(
	csd: ^WLCSD_State,
	d: ^WLCSD_Part,
	scale: f32,
) {
	if !csd.font_ok || csd.title == "" {
		return
	}

	font := &csd.font
	buf := d.buffers[d.current_buffer]
	scale_factor := stbtt.ScaleForPixelHeight(font, WLCSD_TITLE_FONT_SIZE * scale)

	last_button_idx := csd.window_mode == .Windowed_Resizable ? 2 : 1
	left_most_button_rect := wlcsd_button_rect(csd, last_button_idx)
	horizontal_margin := int(math.round(WLCSD_TITLE_HORIZONTAL_MARGIN * scale))
	left := int(math.round(f32(-d.x) * scale)) + horizontal_margin
	right := int(math.round(f32(left_most_button_rect.x - d.x) * scale)) - horizontal_margin

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
		icon_size = int(math.round(WLCSD_ICON_SIZE * scale))
		icon_room = icon_size + int(math.round(WLCSD_ICON_HORIZONTAL_MARGIN * scale))
	}

	// Centered on the window itself rather than on the room beside the buttons, so that it sits
	// where the eye looks for it. A title too long for that room runs into the buttons and is cut
	// off there instead.
	center := int(math.round(f32(csd.window_width - d.x*2) * scale))/2
	pen := max(left + icon_room, center - width/2)
	top := int(math.round(f32(-WLCSD_TITLEBAR_HEIGHT - d.y) * scale))
	bar_height := int(math.round(WLCSD_TITLEBAR_HEIGHT * scale))

	if icon_size > 0 {
		icon := csd.icon
		icon_x := pen - icon_room
		icon_y := top + (bar_height - icon_size)/2
		draw_width := icon_size
		draw_height := icon_size

		if icon.width > icon.height {
			draw_height = max(1, icon_size*icon.height/icon.width)
		} else if icon.height > icon.width {
			draw_width = max(1, icon_size*icon.width/icon.height)
		}

		// A picture that does not fill the box sits in the middle of it.
		box_x := icon_x + (icon_size - draw_width)/2
		box_y := icon_y + (icon_size - draw_height)/2

		for y in 0..<draw_height {
			for x in 0..<draw_width {
				to_x := box_x + x
				to_y := box_y + y

				if to_x < left || to_x >= right || to_y < 0 || to_y >= buf.height {
					continue
				}

				// The source pixels this one covers. Averaging them is the whole of the scaling,
				// and the color is weighted by alpha so that transparent pixels do not wash the
				// edges out.
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
				at := to_y*buf.width + to_x
				icon_color := 0xff000000 | r << 16 | g << 8 | b
				buf.pixels[at] = wlcsd_blend(buf.pixels[at], icon_color, alpha)
			}
		}
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
			for i in 0..<int(glyph_width*glyph_height) {
				alpha := coverage[i]

				if alpha == 0 {
					continue
				}

				x := pen + int(glyph_x) + i%int(glyph_width)
				y := baseline + int(glyph_y) + i/int(glyph_width)

				if x < left || x >= right || y < 0 || y >= buf.height {
					continue
				}

				at := y*buf.width + x
				buf.pixels[at] = wlcsd_blend(buf.pixels[at], color, f32(alpha)/255)
			}

			stbtt.FreeBitmap(coverage, nil)
		}

		pen += int(math.round(f32(advance) * scale_factor))

		if pen >= right {
			break
		}
	}
}

// What the title and the button glyphs are drawn in. Dimmed towards the titlebar itself while the
// window is not the one being typed into, the way every other window on the desktop dims.
wlcsd_text_color :: proc(csd: ^WLCSD_State) -> u32 {
	if csd.active {
		return csd.theme.text
	}

	return wlcsd_blend(csd.theme.fill, csd.theme.text, 0.45)
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

wlcsd_button_rect :: proc(
	csd: ^WLCSD_State,
	index_from_right: int,
) -> WLCSD_Rect {
	return {
		x = csd.window_width - (index_from_right + 1)*WLCSD_BUTTON_WIDTH + WLCSD_BUTTON_INSET,
		y = -WLCSD_TITLEBAR_HEIGHT + WLCSD_BUTTON_INSET,
		width = WLCSD_BUTTON_WIDTH - WLCSD_BUTTON_INSET*2,
		height = WLCSD_TITLEBAR_HEIGHT - WLCSD_BUTTON_INSET*2,
	}
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
		for slot in d.buffers {
			wl_destroy_shared_memory_image(slot)
		}

		d^ = {}
	}

	delete(csd.title, csd.allocator)
	csd.title = ""
	delete(csd.icon.pixels, csd.allocator)
	csd.icon = {}
}

// Picks the frame colors from what the desktop is set up for, by asking the desktop portal over
// D-Bus. That is the one place every desktop answers the question: GNOME, KDE, GTK, Qt and SDL all
// read the preference from here. A machine with no portal gets the light scheme, the same as one
// whose desktop has no preference.
//
// This is read once, while the window is being made. A player who switches their desktop between
// dark and light while the game runs keeps the frame they started with.
wlcsd_pick_theme :: proc() -> WLCSD_Theme {
	if missing, load_ok := dbus.load(); !load_ok {
		log.debugf("Using light window decorations. Could not load %v.", missing)
		return WLCSD_THEME_LIGHT
	}

	connection := dbus.bus_get_private(.Session, nil)

	if connection == nil {
		log.debug("Using light window decorations. Could not connect to the session bus.")
		return WLCSD_THEME_LIGHT
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
		return WLCSD_THEME_LIGHT
	}

	// 1 asks for dark, 2 asks for light and 0 is a desktop with no opinion. No opinion means light
	// in practice: GNOME sets the preference to dark when its dark style is picked and back to
	// nothing when its light one is, so anything but an explicit 1 belongs in the light scheme.
	return scheme == 1 ? WLCSD_THEME_DARK : WLCSD_THEME_LIGHT
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
	return csd.pointer_surface != nil && csd.pointer_surface != csd.surface
}

wlcsd_set_pointer_surface :: proc(csd: ^WLCSD_State, pointer_surface: ^wl.Surface) {
	csd.pointer_surface = pointer_surface
}

// Figures out what parts of the frame that are under the pointer.
wlcsd_pointer_moved :: proc(csd: ^WLCSD_State, local_x: f32, local_y: f32) {
	part := wlcsd_pointer_part(csd)
	d := csd.parts[part]

	// Where the pointer is with the game canvas at the origin, which is what the window's own
	// edges are measured against.
	x := f32(d.x) + local_x
	y := f32(d.y) + local_y

	edges := wlcsd_resize_edges(csd, local_x, local_y)
	hovered: Maybe(WLCSD_Button)

	if edges == {} && part == .Titlebar {
		button_idx: int
		for button in WLCSD_Button {
			if csd.window_mode != .Windowed_Resizable && button == .Maximize {
				continue
			}

			rect := wlcsd_button_rect(csd, button_idx)
			button_idx += 1
			inside_x := x >= f32(rect.x) && x < f32(rect.x + rect.width)
			inside_y := y >= f32(rect.y) && y < f32(rect.y + rect.height)

			if inside_x && inside_y {
				hovered = button
				break
			}
		}
	}

	if hovered != csd.pointer_button {
		csd.pointer_button = hovered
		csd.needs_paint += {.Titlebar}
	}
}

// The pointer left the frame, so nothing on it is under the pointer any more.
wlcsd_pointer_left :: proc(csd: ^WLCSD_State) {
	csd.pressed_button = nil

	if csd.pointer_button != nil {
		csd.pointer_button = nil
		csd.needs_paint += {.Titlebar}
	}
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
) -> (
	_button_pressed_type: WLCSD_Button,
	_button_pressed: bool,
) {
	// The right button asks the compositor for the window menu, which is the one thing on the
	// frame that Karl2D does not draw itself.
	if button == wl.BTN_RIGHT && state == wl.POINTER_BUTTON_STATE_PRESSED {
		d := csd.parts[wlcsd_pointer_part(csd)]

		// The position is measured from the corner of the window geometry, which is the top left of
		// the titlebar.
		wl.xdg_toplevel_show_window_menu(
			csd.toplevel,
			csd.seat,
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
		pressed, pressed_ok := csd.pressed_button.?
		csd.pressed_button = nil

		if pressed_ok && pressed == csd.pointer_button {
			return pressed, true
		}

		return
	}

	if csd.pointer_button != nil {
		csd.pressed_button = csd.pointer_button
		return
	}

	edges := wlcsd_resize_edges(csd, local_x, local_y)

	if edges != {} {
		xdg_edge: u32

		if .Top in edges {
			xdg_edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP
		}

		if .Bottom in edges {
			xdg_edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM
		}

		if .Left in edges {
			xdg_edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_LEFT
		}

		if .Right in edges {
			xdg_edge |= wl.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT
		}

		wl.xdg_toplevel_resize(csd.toplevel, csd.seat, serial, xdg_edge)
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
	double_click := quick && near_x && near_y
	csd.last_press_time = time
	csd.last_press_x = local_x
	csd.last_press_y = local_y

	resizable := csd.window_mode == .Windowed_Resizable

	if double_click && resizable && wlcsd_pointer_part(csd) == .Titlebar {
		// Forget the press, so that a third one is not the start of another double click.
		csd.last_press_time = 0

		return .Maximize, true
	}

	wl.xdg_toplevel_move(csd.toplevel, csd.seat, serial)
	return
}

wlcsd_resize_edges :: proc(csd: ^WLCSD_State, local_x: f32, local_y: f32) -> bit_set[WLCSD_Edge] {
	// Only a window the game lets the player resize has edges to grab. A fixed size one, and a
	// fullscreen one, can only be moved.
	if csd.window_mode != .Windowed_Resizable {
		return {}
	}

	d := csd.parts[wlcsd_pointer_part(csd)]
	x := f32(d.x) + local_x
	y := f32(d.y) + local_y

	// The grip reaches from the margin outside the window to the same distance inside it, so a
	// corner is that much square.
	grip :: f32(WLCSD_RESIZE_MARGIN)
	edges: bit_set[WLCSD_Edge]

	if y < f32(-WLCSD_TITLEBAR_HEIGHT) + grip {
		edges += {.Top}
	} else if y >= f32(csd.window_height) - grip {
		edges += {.Bottom}
	}

	if x < grip {
		edges += {.Left}
	} else if x >= f32(csd.window_width) - grip {
		edges += {.Right}
	}

	return edges
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
wlcsd_cursor :: proc(csd: ^WLCSD_State, local_x: f32, local_y: f32) -> Standard_Cursor {
	switch wlcsd_resize_edges(csd, local_x, local_y) {
	case {.Top}, {.Bottom}:
		return .Resize_NS

	case {.Left}, {.Right}:
		return .Resize_EW

	case {.Top, .Left}, {.Bottom, .Right}:
		return .Resize_NWSE

	case {.Top, .Right}, {.Bottom, .Left}:
		return .Resize_NESW
	}

	return .Default
}
