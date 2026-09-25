// Wayland Client-Side Decorations (WLCSD).
//
// This file implements window decorations: A frame with buttons and a titlebar. It's used on
// Linux + Wayland when there are no server-side decorations. If you use for example KDE then the
// Wayland server draws the frame for you. But under GNOME this does not happen. The we instead
// implement so-called client-side decorations (CSD): The application draws the frame.
//
// This frame drawing is not done using Karl2D itself. Rather, it is done using Wayland surfaces.
// stb_truetype is used for drawing the title. We don't use Karl2D itself to draw the frame because
// it creates a weird circular dependency. 

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
	// The surface holds the pixels and the subsurface controls how it is parented into the window.
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

	rect: WLCSD_Rect,
}

wlcsd_buffer_listener := wl.Buffer_Listener {
	// When the compositor is done with a buffer, we get notified. We unset the busy flag for that
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
// Non-resizable windows will not have a Maximize button.
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

	scanout_blocker: ^wl.Surface,
	scanout_blocker_subsurface: ^wl.Subsurface,
	scanout_blocker_image: WL_Shared_Memory_Image,

	pointer_part: Maybe(WLCSD_Part_Type),

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

	// If true, then `wlcsd_paint` will repaint the window. Otherwise it will do nothing.
	dirty: bool,

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

	// We use the Karl2D default font for the title.
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

	csd.scanout_blocker = wl.compositor_create_surface(compositor)
	csd.scanout_blocker_subsurface = wl.subcompositor_get_subsurface(
		subcompositor,
		csd.scanout_blocker,
		surface,
	)

	blocker_region := wl.compositor_create_region(compositor)
	wl.surface_set_input_region(csd.scanout_blocker, blocker_region)
	wl.region_destroy(blocker_region)

	blocker_image, blocker_image_ok := wl_create_shared_memory_image("karl2d-scanout-blocker", 1, 1)

	if blocker_image_ok {
		blocker_image.pixels[0] = 0
		csd.scanout_blocker_image = blocker_image
	} else {
		log.error("Failed creating the scanout blocker buffer. The window frame may not show.")
	}

	wlcsd_mark_dirty(csd)
	return csd
}

wlcsd_set_window_size :: proc(csd: ^WLCSD_State, window_width: int, window_height: int) {
	csd.window_width = window_width
	csd.window_height = window_height
}

wlcsd_set_window_mode :: proc(csd: ^WLCSD_State, window_mode: Window_Mode) {
	csd.window_mode = window_mode
}

// Marks all the parts of the frame as dirty so they get redrawn the next frame.
wlcsd_mark_dirty :: proc(csd: ^WLCSD_State) {
	csd.dirty = true
}

wlcsd_set_toplevel_state :: proc(csd: ^WLCSD_State, active: bool, maximized: bool) {
	changed := active != csd.active || maximized != csd.maximized

	csd.active = active
	csd.maximized = maximized

	if changed {
		wlcsd_mark_dirty(csd)
	}
}

// Repaints the frame if it has been marked as dirty.
wlcsd_paint :: proc(csd: ^WLCSD_State, scale: f32) {
	if !csd.dirty {
		return
	}

	csd.dirty = false

	if csd.window_mode == .Borderless_Fullscreen {
		for part in WLCSD_Part_Type {
			d := &csd.parts[part]
			wl.surface_attach(d.surface, nil, 0, 0)
			wl.surface_commit(d.surface)
		}

		wl.surface_attach(csd.scanout_blocker, nil, 0, 0)
		wl.surface_commit(csd.scanout_blocker)

		wl.xdg_surface_set_window_geometry(
			csd.xdg_surface,
			0,
			0,
			i32(csd.window_width),
			i32(csd.window_height),
		)

		return
	}

	w := csd.window_width
	h := csd.window_height

	pixel_size := 1/scale

	// The rectangle of the window, excluding the shadow, but with the titlebar included.
	window_rect := WLCSD_Rect {
		x = 0,
		y = -WLCSD_TITLEBAR_HEIGHT,
		width = w,
		height = h + WLCSD_TITLEBAR_HEIGHT,
	}

	for part in WLCSD_Part_Type {
		d := &csd.parts[part]

		// How far a part reaches past the window, which is as far as the shadow goes.
		OUT :: WLCSD_SHADOW_REACH
		
		switch part {
		case .Titlebar:
			d.rect = {-OUT, -WLCSD_TITLEBAR_HEIGHT - OUT, w + OUT*2, WLCSD_TITLEBAR_HEIGHT + OUT}

		case .Left:
			d.rect = {-OUT, 0, OUT, h}

		case .Right:
			d.rect = {w, 0, OUT, h}

		case .Bottom:
			d.rect = {-OUT, h, w + OUT*2, OUT}
		}

		// The buffer holds physical pixels and a viewport maps it back to the logical size.
		buffer_width := max(1, int(math.round(f32(d.rect.width) * scale)))
		buffer_height := max(1, int(math.round(f32(d.rect.height) * scale)))

		current := -1

		for i in 0..<len(d.buffers) {
			if !d.buffers_busy[i] {
				current = i
				break
			}
		}

		if current == -1 {
			log.debug("Every window decoration buffer is still in use. Skipping a repaint.")
			csd.dirty = true
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
				csd.dirty = true
				continue
			}

			wl.add_listener(image.buffer, &wlcsd_buffer_listener, d)
		}

		d.current_buffer = current
		pixels := d.buffers[current].pixels
		shadow := csd.active ? WLCSD_SHADOW_FOCUSED : WLCSD_SHADOW_UNFOCUSED

		// Draw the shadow
		for y in 0..<buffer_height {
			for x in 0..<buffer_width {
				px := f32(d.rect.x) + (f32(x) + 0.5)*pixel_size
				py := f32(d.rect.y) + (f32(y) + 0.5)*pixel_size
				at := y*buffer_width + x

				// How far this pixel is from the window, which is all the shadow depends on.
				dx := max(f32(window_rect.x) - px, 0, px - f32(window_rect.x + window_rect.width))
				dy := max(f32(window_rect.y) - py, 0, py - f32(window_rect.y + window_rect.height))
				distance := math.sqrt(dx*dx + dy*dy)
				alpha := f32(0)

				if distance < WLCSD_SHADOW_REACH {
					faded := shadow.a*math.exp(-shadow.b*distance) + shadow.c
					alpha = clamp(faded, 0, 1)
				}

				pixels[at] = u32(alpha*255) << 24
			}
		}

		if part == .Titlebar {
			wlcsd_paint_title(csd, d, scale)
		}

		input_area_left := -WLCSD_RESIZE_MARGIN
		input_area_top := -WLCSD_TITLEBAR_HEIGHT - WLCSD_RESIZE_MARGIN
		input_area_right := csd.window_width + WLCSD_RESIZE_MARGIN
		input_area_bottom := csd.window_height + WLCSD_RESIZE_MARGIN

		x0 := max(d.rect.x, input_area_left) - d.rect.x
		y0 := max(d.rect.y, input_area_top) - d.rect.y
		x1 := min(d.rect.x + d.rect.width, input_area_right) - d.rect.x
		y1 := min(d.rect.y + d.rect.height, input_area_bottom) - d.rect.y

		region := wl.compositor_create_region(csd.compositor)

		if x1 > x0 && y1 > y0 {
			wl.region_add(region, i32(x0), i32(y0), i32(x1 - x0), i32(y1 - y0))
		}

		wl.surface_set_input_region(d.surface, region)
		wl.region_destroy(region)
		wl.subsurface_set_position(d.subsurface, i32(d.rect.x), i32(d.rect.y))
		wl.wp_viewport_set_destination(d.viewport, i32(max(1, d.rect.width)), i32(max(1, d.rect.height)))
		wl.surface_attach(d.surface, d.buffers[current].buffer, 0, 0)
		wl.surface_damage_buffer(d.surface, 0, 0, i32(buffer_width), i32(buffer_height))
		wl.surface_commit(d.surface)
		d.buffers_busy[current] = true
	}

	// This fixes a bug with KWin where the frame is hidden unless some surface overlaps the canvas.
	// So we draw a 1x1 transparent pixel over it.
	if csd.scanout_blocker_image.buffer != nil {
		wl.surface_attach(csd.scanout_blocker, csd.scanout_blocker_image.buffer, 0, 0)
		wl.surface_damage_buffer(csd.scanout_blocker, 0, 0, 1, 1)
		wl.surface_commit(csd.scanout_blocker)
	}

	// Makes sure the titlebar takes its size when maximized and when resizing the window.
	wl.xdg_surface_set_window_geometry(
		csd.xdg_surface,
		0,
		-WLCSD_TITLEBAR_HEIGHT,
		i32(csd.window_width),
		i32(csd.window_height + WLCSD_TITLEBAR_HEIGHT),
	)
}

wlcsd_set_title :: proc(csd: ^WLCSD_State, title: string) {
	if csd.title == title {
		return
	}

	delete(csd.title, csd.allocator)
	csd.title = strings.clone(title, csd.allocator)
	csd.dirty = true
}

// CSD make a copy of the image, so you don't have to keep it alive.
wlcsd_set_icon :: proc(csd: ^WLCSD_State, image: Image) {
	pixels := make([]Color, len(image.pixels), csd.allocator)
	copy(pixels, image.pixels)
	delete(csd.icon.pixels, csd.allocator)

	csd.icon = {
		pixels = pixels,
		width = image.width,
		height = image.height,
	}

	csd.dirty = true
}

// Paints the title background, its button, the title text and the icon.
wlcsd_paint_title :: proc(csd: ^WLCSD_State, d: ^WLCSD_Part, scale: f32) {
	buf := d.buffers[d.current_buffer]
	pixel_size := 1/scale
	text_color := wlcsd_text_color(csd)

	titlebar_rect := WLCSD_Rect {
		x = 0,
		y = -WLCSD_TITLEBAR_HEIGHT,
		width = csd.window_width,
		height = WLCSD_TITLEBAR_HEIGHT,
	}

	// BACKGROUND

	for y in 0..<buf.height {
		for x in 0..<buf.width {
			px := f32(d.rect.x) + (f32(x) + 0.5)*pixel_size
			py := f32(d.rect.y) + (f32(y) + 0.5)*pixel_size

			if wlcsd_point_in_rect(titlebar_rect, px, py) {
				buf.pixels[y*buf.width + x] = csd.theme.fill
			}
		}
	}

	// BUTTONS

	button_idx: int
	glyph_size := int(math.round(WLCSD_BUTTON_ICON_SIZE * scale))
	glyph_stroke := max(1, int(math.round(WLCSD_BUTTON_STROKE * scale)))

	for button in WLCSD_Button {
		if button == .Maximize && csd.window_mode != .Windowed_Resizable {
			continue
		}

		rect := wlcsd_button_rect(csd, button_idx)
		button_idx += 1

		pixel_rect := WLCSD_Rect {
			x = int(math.round(f32(rect.x - d.rect.x) * scale)),
			y = int(math.round(f32(rect.y - d.rect.y) * scale)),
			width = int(math.round(f32(rect.width) * scale)),
			height = int(math.round(f32(rect.height) * scale)),
		}

		right := pixel_rect.x + pixel_rect.width
		bottom := pixel_rect.y + pixel_rect.height

		if pixel_rect.x < 0 || pixel_rect.y < 0 {
			continue
		}

		if right > buf.width || bottom > buf.height {
			continue
		}

		background := csd.theme.fill

		if csd.pointer_button == button {
			background = csd.theme.hover
			wlcsd_fill_rect(buf, pixel_rect, background)
		}

		glyph := WLCSD_Rect {
			x = pixel_rect.x + (pixel_rect.width - glyph_size)/2,
			y = pixel_rect.y + (pixel_rect.height - glyph_size)/2,
			width = glyph_size,
			height = glyph_size,
		}

		switch button {
		case .Close:
			for y in glyph.y..<glyph.y + glyph.height {
				for x in glyph.x..<glyph.x + glyph.width {
					i := x - glyph.x
					j := y - glyph.y

					if abs(i - j) < glyph_stroke || abs(i + j - (glyph.width - 1)) < glyph_stroke {
						buf.pixels[y*buf.width + x] = text_color
					}
				}
			}

		case .Maximize:
			square := WLCSD_Rect {
				x = glyph.x + glyph_stroke,
				y = glyph.y + glyph_stroke,
				width = glyph.width - glyph_stroke*2,
				height = glyph.height - glyph_stroke*2,
			}

			if csd.maximized {
				back := WLCSD_Rect {
					x = square.x + square.width/4,
					y = square.y,
					width = square.width*3/4,
					height = square.height*3/4,
				}

				square.y += square.height/4
				square.width = square.width*3/4
				square.height = square.height*3/4
				wlcsd_outline_rect(buf, back, glyph_stroke, text_color)
				wlcsd_fill_rect(buf, square, background)
			}

			wlcsd_outline_rect(buf, square, glyph_stroke, text_color)

		case .Minimize:
			line := WLCSD_Rect {
				x = glyph.x,
				y = glyph.y + glyph.height - glyph_stroke,
				width = glyph.width,
				height = glyph_stroke,
			}

			wlcsd_fill_rect(buf, line, text_color)
		}
	}

	// ICON AND TITLE TEXT

	if !csd.font_ok || csd.title == "" {
		return
	}

	font := &csd.font
	font_scale_factor := stbtt.ScaleForPixelHeight(font, WLCSD_TITLE_FONT_SIZE * scale)

	left_most_button_rect := wlcsd_button_rect(csd, button_idx - 1)
	title_margin := int(math.round(WLCSD_TITLE_HORIZONTAL_MARGIN * scale))
	title_area_left := int(math.round(f32(-d.rect.x) * scale)) + title_margin
	title_area_right := int(math.round(f32(left_most_button_rect.x - d.rect.x) * scale)) -
		title_margin

	if title_area_right <= title_area_left {
		return
	}

	title_width := 0

	for r in csd.title {
		advance, left_bearing: i32
		stbtt.GetCodepointHMetrics(font, r, &advance, &left_bearing)
		title_width += int(math.round(f32(advance) * font_scale_factor))
	}

	icon_size := 0
	icon_space := 0

	if len(csd.icon.pixels) > 0 {
		icon_size = int(math.round(WLCSD_ICON_SIZE * scale))
		icon_space = icon_size + int(math.round(WLCSD_ICON_HORIZONTAL_MARGIN * scale))
	}

	// Centered on the full window width.
	title_center_x := int(math.round(f32(csd.window_width - d.rect.x*2) * scale))/2
	title_pen_x := max(title_area_left + icon_space, title_center_x - title_width/2)
	titlebar_top := int(math.round(f32(-WLCSD_TITLEBAR_HEIGHT - d.rect.y) * scale))
	titlebar_height := int(math.round(WLCSD_TITLEBAR_HEIGHT * scale))

	if icon_size > 0 {
		icon := csd.icon
		icon_x := title_pen_x - icon_space
		icon_y := titlebar_top + (titlebar_height - icon_size)/2
		draw_width := icon_size
		draw_height := icon_size

		if icon.width > icon.height {
			draw_height = max(1, icon_size*icon.height/icon.width)
		} else if icon.height > icon.width {
			draw_width = max(1, icon_size*icon.width/icon.height)
		}

		// Center the image within the box
		box_x := icon_x + (icon_size - draw_width)/2
		box_y := icon_y + (icon_size - draw_height)/2

		for y in 0..<draw_height {
			for x in 0..<draw_width {
				to_x := box_x + x
				to_y := box_y + y

				if to_x < title_area_left || to_x >= title_area_right || to_y < 0 || to_y >= buf.height {
					continue
				}

				from_x := x*icon.width/draw_width
				from_y := y*icon.height/draw_height
				col := icon.pixels[from_y*icon.width + from_x]
				icon_color := 0xff000000 | u32(col.r) << 16 | u32(col.g) << 8 | u32(col.b)
				at := to_y*buf.width + to_x
				buf.pixels[at] = wlcsd_blend(buf.pixels[at], icon_color, f32(col.a)/255)
			}
		}
	}

	cap_x0, cap_y0, cap_x1, cap_y1: i32
	stbtt.GetCodepointBox(font, 'H', &cap_x0, &cap_y0, &cap_x1, &cap_y1)
	cap_height := f32(cap_y1) * font_scale_factor
	title_baseline_y := titlebar_top + int(math.round((f32(titlebar_height) + cap_height)/2))

	for r in csd.title {
		advance, left_bearing: i32
		stbtt.GetCodepointHMetrics(font, r, &advance, &left_bearing)

		glyph_width, glyph_height, glyph_x, glyph_y: i32
		coverage := stbtt.GetCodepointBitmap(
			font,
			0,
			font_scale_factor,
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

				x := title_pen_x + int(glyph_x) + i%int(glyph_width)
				y := title_baseline_y + int(glyph_y) + i/int(glyph_width)

				if x < title_area_left || x >= title_area_right || y < 0 || y >= buf.height {
					continue
				}

				at := y*buf.width + x
				buf.pixels[at] = wlcsd_blend(buf.pixels[at], text_color, f32(alpha)/255)
			}

			stbtt.FreeBitmap(coverage, nil)
		}

		title_pen_x += int(math.round(f32(advance) * font_scale_factor))

		if title_pen_x >= title_area_right {
			break
		}
	}
}

wlcsd_text_color :: proc(csd: ^WLCSD_State) -> u32 {
	if csd.active {
		return csd.theme.text
	}

	return wlcsd_blend(csd.theme.fill, csd.theme.text, 0.45)
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

wlcsd_fill_rect :: proc(buf: WL_Shared_Memory_Image, rect: WLCSD_Rect, color: u32) {
	for y in rect.y..<rect.y + rect.height {
		for x in rect.x..<rect.x + rect.width {
			buf.pixels[y*buf.width + x] = color
		}
	}
}

wlcsd_outline_rect :: proc(buf: WL_Shared_Memory_Image, rect: WLCSD_Rect, stroke: int, color: u32) {
	wlcsd_fill_rect(buf, {rect.x, rect.y, rect.width, stroke}, color)
	wlcsd_fill_rect(buf, {rect.x, rect.y + rect.height - stroke, rect.width, stroke}, color)
	wlcsd_fill_rect(buf, {rect.x, rect.y, stroke, rect.height}, color)
	wlcsd_fill_rect(buf, {rect.x + rect.width - stroke, rect.y, stroke, rect.height}, color)
}

wlcsd_point_in_rect :: proc(rect: WLCSD_Rect, x: f32, y: f32) -> bool {
	return (
		x >= f32(rect.x) &&
		x <  f32(rect.x + rect.width) &&
		y >= f32(rect.y) &&
		y <  f32(rect.y + rect.height)
	)
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

		for slot in d.buffers {
			wl_destroy_shared_memory_image(slot)
		}
	}

	if csd.scanout_blocker != nil {
		wl.subsurface_destroy(csd.scanout_blocker_subsurface)
		wl.surface_destroy(csd.scanout_blocker)
		wl_destroy_shared_memory_image(csd.scanout_blocker_image)
	}

	delete(csd.title, csd.allocator)
	delete(csd.icon.pixels, csd.allocator)
}

// Use dbus to ask which theme to use. If we fail to ask it, then we get light theme.
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

	call := dbus.message_new_method_call(
		"org.freedesktop.portal.Desktop",
		"/org/freedesktop/portal/desktop",
		"org.freedesktop.portal.Settings",
		"Read",
	)

	namespace := cstring("org.freedesktop.appearance")
	key := cstring("color-scheme")
	arguments: dbus.Message_Iter
	dbus.message_iter_init_append(call, &arguments)
	dbus.message_iter_append_basic(&arguments, dbus.TYPE_STRING, &namespace)
	dbus.message_iter_append_basic(&arguments, dbus.TYPE_STRING, &key)

	// A portal that has to be started first takes a moment, but a game must not hang on its way to
	// a window because something on the desktop is unwell.
	PORTAL_TIMEOUT_MS :: 500

	reply := dbus.connection_send_with_reply_and_block(connection, call, PORTAL_TIMEOUT_MS, nil)
	dbus.message_unref(call)
	dbus.connection_close(connection)
	dbus.connection_unref(connection)

	if reply == nil {
		return WLCSD_THEME_LIGHT
	}

	scheme: u32
	outer, inner, value: dbus.Message_Iter

	if dbus.message_iter_init(reply, &outer) != 0 {
		if dbus.message_iter_get_arg_type(&outer) == dbus.TYPE_VARIANT {
			dbus.message_iter_recurse(&outer, &inner)

			if dbus.message_iter_get_arg_type(&inner) == dbus.TYPE_VARIANT {
				dbus.message_iter_recurse(&inner, &value)

				if dbus.message_iter_get_arg_type(&value) == dbus.TYPE_UINT32 {
					dbus.message_iter_get_basic(&value, &scheme)
				}
			}
		}
	}

	dbus.message_unref(reply)
	return scheme == 1 ? WLCSD_THEME_DARK : WLCSD_THEME_LIGHT
}

wlcsd_pointer_over_frame :: proc(csd: ^WLCSD_State) -> bool {
	return csd.pointer_part != nil
}

wlcsd_set_pointer_surface :: proc(csd: ^WLCSD_State, pointer_surface: ^wl.Surface) {
	csd.pointer_part = nil

	if pointer_surface == nil {
		csd.pressed_button = nil

		if csd.pointer_button != nil {
			csd.pointer_button = nil
			csd.dirty = true
		}

		return
	}

	for part in WLCSD_Part_Type {
		if csd.parts[part].surface == pointer_surface {
			csd.pointer_part = part
		}
	}
}

// Figures out what parts of the frame that are under the pointer.
wlcsd_pointer_moved :: proc(csd: ^WLCSD_State, local_x: f32, local_y: f32) {
	part, part_ok := csd.pointer_part.?
	
	if !part_ok {
		return
	}

	d := csd.parts[part]

	// Where the pointer is with the game canvas at the origin, which is what the window's own
	// edges are measured against.
	x := f32(d.rect.x) + local_x
	y := f32(d.rect.y) + local_y

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

			if wlcsd_point_in_rect(rect, x, y) {
				hovered = button
				break
			}
		}
	}

	if hovered != csd.pointer_button {
		csd.pointer_button = hovered
		csd.dirty = true
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
	pointer_part, pointer_part_ok := csd.pointer_part.?

	if !pointer_part_ok {
		return
	}

	// The right button asks the compositor for the window menu, which is the one thing on the
	// frame that Karl2D does not draw itself.
	if button == wl.BTN_RIGHT && state == wl.POINTER_BUTTON_STATE_PRESSED {
		d := csd.parts[pointer_part]

		// The position is measured from the corner of the window geometry, which is the top left of
		// the titlebar.
		wl.xdg_toplevel_show_window_menu(
			csd.toplevel,
			csd.seat,
			serial,
			i32(f32(d.rect.x) + local_x),
			i32(f32(d.rect.y + WLCSD_TITLEBAR_HEIGHT) + local_y),
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

	if double_click && resizable && csd.pointer_part == .Titlebar {
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

	pointer_part, pointer_part_ok := csd.pointer_part.?

	if !pointer_part_ok {
		return {}
	}

	d := csd.parts[pointer_part]
	x := f32(d.rect.x) + local_x
	y := f32(d.rect.y) + local_y

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
