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
import "core:sys/linux"

import "log"
import "platform_bindings/linux/dbus"
import wl "platform_bindings/linux/wayland"

// The frame Karl2D draws around the game canvas where the compositor draws none, in logical
// pixels. The border is the thin line along the three sides that have no titlebar.
DECORATION_TITLEBAR_HEIGHT :: 32
DECORATION_BORDER :: 1

// What the frame is painted with. The fill covers the titlebar and the outline runs around the
// outside of the whole window, which is all the thin sides are. Premultiplied ARGB, the format the
// decoration buffers are in.
WL_Decoration_Colors :: struct {
	fill: u32,
	outline: u32,
}

DECORATION_COLORS_DARK :: WL_Decoration_Colors {
	fill = 0xff2e2e2e,
	outline = 0xff4a4a4a,
}

DECORATION_COLORS_LIGHT :: WL_Decoration_Colors {
	fill = 0xffe8e8e8,
	outline = 0xffb4b4b4,
}




// One part of the window frame Karl2D draws for itself. Each is a subsurface of the surface the
// game renders into, with a shared memory buffer that we fill on the CPU.
WL_Decoration :: struct {
	surface: ^wl.Surface,
	subsurface: ^wl.Subsurface,

	// Scales the buffer down from physical to logical pixels, like the one a cursor has.
	viewport: ^wl.WP_Viewport,

	// The compositor may read the buffer at any point while it is attached, so both it and the
	// mapping stay alive until the part is resized or the window goes away.
	buffer: ^wl.Buffer,
	pixels: [^]u32,
	data_size: int,

	// Size of the buffer, in physical pixels.
	buffer_width: int,
	buffer_height: int,

	// Where the part sits and how big it is, in logical pixels relative to the game canvas.
	x: int,
	y: int,
	width: int,
	height: int,
}

WL_Decoration_Part :: enum {
	Titlebar,
	Left,
	Right,
	Bottom,
}

// Creates the four surfaces that make up the window frame. They are subsurfaces of the surface the
// game renders into, so the compositor keeps them glued to it and no render backend has to know
// that they exist.
wl_create_decorations :: proc() {
	if s.subcompositor == nil {
		return
	}

	s.decoration_colors = wl_desktop_decoration_colors()

	for part in WL_Decoration_Part {
		d := &s.decorations[part]
		d.surface = wl.compositor_create_surface(s.compositor)
		d.subsurface = wl.subcompositor_get_subsurface(s.subcompositor, d.surface, s.surface)
		d.viewport = wl.wp_viewporter_get_viewport(s.viewporter, d.surface)

		// A subsurface starts out synchronized, which would tie repainting the frame to the game
		// drawing its next frame.
		wl.subsurface_set_desync(d.subsurface)
	}

	wl_layout_decorations()
}

// Puts every part of the frame where it belongs for the current window size and repaints it. The
// compositor leaves the parts where they were put, so this runs on every resize and scale change.
wl_layout_decorations :: proc() {
	if s.decorations[.Titlebar].surface == nil {
		return
	}

	for part in WL_Decoration_Part {
		wl_paint_decoration(part)
	}

	// The window is the game canvas plus everything drawn around it. Without this the compositor
	// would treat the canvas alone as the window, and a maximized window would hang off the screen
	// by the height of the titlebar.
	wl.xdg_surface_set_window_geometry(
		s.xdg_surface,
		-DECORATION_BORDER,
		-DECORATION_TITLEBAR_HEIGHT,
		i32(s.last_configure_width + DECORATION_BORDER*2),
		i32(s.last_configure_height + DECORATION_TITLEBAR_HEIGHT + DECORATION_BORDER),
	)
}

// Works out where one part of the frame sits for the current window size, fills it with a single
// color and puts it there. Positions are in logical pixels relative to the game canvas, which
// means the titlebar has a negative y since it hangs above the canvas.
wl_paint_decoration :: proc(part: WL_Decoration_Part) {
	w := s.last_configure_width
	h := s.last_configure_height
	d := &s.decorations[part]

	switch part {
	case .Titlebar:
		d.x = -DECORATION_BORDER
		d.y = -DECORATION_TITLEBAR_HEIGHT
		d.width = w + DECORATION_BORDER*2
		d.height = DECORATION_TITLEBAR_HEIGHT

	case .Left:
		d.x = -DECORATION_BORDER
		d.y = 0
		d.width = DECORATION_BORDER
		d.height = h

	case .Right:
		d.x = w
		d.y = 0
		d.width = DECORATION_BORDER
		d.height = h

	case .Bottom:
		d.x = -DECORATION_BORDER
		d.y = h
		d.width = w + DECORATION_BORDER*2
		d.height = DECORATION_BORDER
	}

	// The buffer holds physical pixels and a viewport maps it back to the logical size, the way
	// cursor images are handled. That keeps a one pixel border one pixel at any scale.
	buffer_width := max(1, int(math.round(f32(d.width) * s.scale)))
	buffer_height := max(1, int(math.round(f32(d.height) * s.scale)))

	if buffer_width != d.buffer_width || buffer_height != d.buffer_height {
		wl_make_decoration_buffer(d, buffer_width, buffer_height)
	}

	if d.buffer == nil {
		return
	}

	// The three thin sides are outline all the way through. The titlebar is filled, with the
	// outline along the top and down the two sides, where it meets the desktop rather than the
	// game canvas.
	for i in 0..<buffer_width*buffer_height {
		d.pixels[i] = part == .Titlebar ? s.decoration_colors.fill : s.decoration_colors.outline
	}

	if part == .Titlebar {
		thickness := max(1, int(math.round(DECORATION_BORDER * s.scale)))

		for y in 0..<buffer_height {
			for x in 0..<buffer_width {
				if y < thickness || x < thickness || x >= buffer_width - thickness {
					d.pixels[y*buffer_width + x] = s.decoration_colors.outline
				}
			}
		}
	}

	wl.subsurface_set_position(d.subsurface, i32(d.x), i32(d.y))
	wl.wp_viewport_set_destination(d.viewport, i32(max(1, d.width)), i32(max(1, d.height)))
	wl.surface_attach(d.surface, d.buffer, 0, 0)
	wl.surface_damage_buffer(d.surface, 0, 0, i32(buffer_width), i32(buffer_height))
	wl.surface_commit(d.surface)
}

// Makes a fresh shared memory buffer for one part of the frame, throwing away the one it had. The
// compositor keeps its own mapping of the memory for as long as it needs the pixels, so unmapping
// ours here is safe even if the old buffer is still on screen.
wl_make_decoration_buffer :: proc(d: ^WL_Decoration, width: int, height: int) {
	if d.buffer != nil {
		wl.buffer_destroy(d.buffer)
		linux.munmap(d.pixels, uint(d.data_size))
		d.buffer = nil
		d.pixels = nil
		d.buffer_width = 0
		d.buffer_height = 0
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

	pool := wl.shm_create_pool(s.shm, c.int32_t(fd), c.int32_t(size))

	d.buffer = wl.shm_pool_create_buffer(
		pool, 0,
		c.int32_t(width), c.int32_t(height), c.int32_t(stride),
		wl.SHM_FORMAT_ARGB8888,
	)

	// The pool can go away immediately: the mapping stays alive until every buffer made from it
	// has been destroyed.
	wl.shm_pool_destroy(pool)

	d.pixels = ([^]u32)(data)
	d.data_size = size
	d.buffer_width = width
	d.buffer_height = height
}

wl_destroy_decorations :: proc() {
	for part in WL_Decoration_Part {
		d := &s.decorations[part]

		if d.surface == nil {
			continue
		}

		wl.wp_viewport_destroy(d.viewport)
		wl.subsurface_destroy(d.subsurface)
		wl.surface_destroy(d.surface)

		if d.buffer != nil {
			wl.buffer_destroy(d.buffer)
			linux.munmap(d.pixels, uint(d.data_size))
		}

		d^ = {}
	}
}

// Picks the frame colors from what the desktop is set up for, by asking the desktop portal over
// D-Bus. That is the one place every desktop answers the question: GNOME, KDE, GTK, Qt and SDL all
// read the preference from here. A machine with no portal, or one with no preference, gets the
// dark scheme.
//
// This is read once, while the window is being made. A player who switches their desktop between
// dark and light while the game runs keeps the frame they started with.
wl_desktop_decoration_colors :: proc() -> WL_Decoration_Colors {
	if missing, load_ok := dbus.load(); !load_ok {
		log.debugf("Using dark window decorations. Could not load %v.", missing)
		return DECORATION_COLORS_DARK
	}

	connection := dbus.bus_get_private(.Session, nil)

	if connection == nil {
		log.debug("Using dark window decorations. Could not connect to the session bus.")
		return DECORATION_COLORS_DARK
	}

	// Otherwise libdbus ends the game itself when the bus goes away.
	dbus.connection_set_exit_on_disconnect(connection, 0)

	scheme, result := wl_read_portal_setting(connection, "ReadOne")

	// `ReadOne` arrived in xdg-desktop-portal 1.17. An older portal has only `Read`, which is the
	// same question asked of a portal that answers it with one variant too many.
	if result == .No_Such_Method {
		scheme, result = wl_read_portal_setting(connection, "Read")
	}

	dbus.connection_close(connection)
	dbus.connection_unref(connection)

	if result != .Value {
		return DECORATION_COLORS_DARK
	}

	// 0 means the desktop has no preference, 1 dark and 2 light.
	return scheme == 2 ? DECORATION_COLORS_LIGHT : DECORATION_COLORS_DARK
}

WL_Portal_Result :: enum {
	Value,
	No_Such_Method,
	Failed,
}

// Asks the desktop portal for the color scheme with one of its two reading methods. Both take the
// setting's namespace and key and answer with the value inside one or more variants, which is what
// the unwrapping at the end is for.
wl_read_portal_setting :: proc(
	connection: dbus.Connection,
	method: cstring,
) -> (
	u32,
	WL_Portal_Result,
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
wl_pointer_on_decoration :: proc() -> bool {
	return s.pointer_surface != nil && s.pointer_surface != s.surface
}

// How much wider and taller the window is than the game canvas inside it. Zero unless Karl2D draws
// the decorations, since the ones a compositor draws sit outside the window entirely.
wl_decoration_extra_width :: proc() -> int {
	return s.custom_decorations ? DECORATION_BORDER*2 : 0
}

wl_decoration_extra_height :: proc() -> int {
	return s.custom_decorations ? DECORATION_TITLEBAR_HEIGHT + DECORATION_BORDER : 0
}
