#+build linux
#+private file

package karl2d

import "core:strings"
@(private="package")
WINDOW_INTERFACE_WAYLAND :: Window_Interface {
	state_size = wayland_state_size,
	init = wayland_init,
	shutdown = wayland_shutdown,
	window_handle = wayland_window_handle,
	process_events = wayland_process_events,
	get_events = wayland_get_events,
	get_width = wayland_get_width,
	get_height = wayland_get_height,
	clear_events = wayland_clear_events,
	set_position = wayland_set_position,
	set_size = wayland_set_size,
	get_window_scale = wayland_get_window_scale,
	set_window_mode = wayland_set_window_mode,
	is_gamepad_active = wayland_is_gamepad_active,
	get_gamepad_axis = wayland_get_gamepad_axis,
	set_gamepad_vibration = wayland_set_gamepad_vibration,
	set_internal_state = wayland_set_internal_state,
}

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:c"
import wl "linux/wayland"
import egl "vendor:egl"

_ :: log
_ :: fmt

wayland_state_size :: proc() -> int {
	return size_of(Wayland_State)
}

wayland_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^Wayland_State)(window_state)
	s.allocator = allocator
	s.windowed_width = window_width
	s.windowed_height = window_height

	s.width = window_width
	s.height = window_height

    // We need to instantiate this so we can register the top level toplevel_listener
    // It will be there that we deal with resizing
	s.window_handle = Window_Handle_Linux_Wayland {
        ready = false,
	}

	display := wl.display_connect(nil)
	s.display = display

	// Get registry, add a global listener and get things started
	// Do a roundtrip in order to get registry info and populate the wayland part of state
	registry := wl.wl_display_get_registry(display)
	wl.wl_registry_add_listener(registry, &registry_listener, s)
	wl.display_roundtrip(display)

    // Create the surface
	surface := wl.wl_compositor_create_surface(s.compositor)
    if surface == nil {
        panic("Error creating wl_surface")
    }
    s.surface = surface

    // Register the listener to respond to pings
    // Without this the compositor will consider the window/client dead and 
    // try to kill it as an unresponsive application
	wl.xdg_wm_base_add_listener(s.xdg_base, &wm_base_listener, nil)

    // Create a XDG surface (i.e a Window...) and set the role top
    // "top-level" and add the listeners
	xdg_surface := wl.xdg_wm_base_get_xdg_surface(s.xdg_base, surface)
	toplevel := wl.xdg_surface_get_toplevel(xdg_surface)
	wl.xdg_toplevel_add_listener(toplevel, &toplevel_listener, nil)
	wl.xdg_surface_add_listener(xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(toplevel, strings.clone_to_cstring(window_title))
	wl.wl_surface_commit(surface)
	wl.display_dispatch(s.display)

    // Get a valid EGL configuration based on some attribute guidelines
    // Create a context based on a "chosen" configuration
    EGL_CONTEXT_FLAGS_KHR :: 0x30FC
    EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR :: 0x00000001

    major, minor, n: i32
    egl_config: egl.Config
    config_attribs: []i32 = {
        egl.SURFACE_TYPE, egl.WINDOW_BIT,
        egl.RED_SIZE, 8,
        egl.GREEN_SIZE, 8,
        egl.BLUE_SIZE, 8,
        egl.ALPHA_SIZE, 0, // Disable surface alpha for now
        egl.DEPTH_SIZE, 24, // Request 24-bit depth buffer
        egl.RENDERABLE_TYPE, egl.OPENGL_BIT,
        egl.NONE,
    }
    context_flags_bitfield: i32 = EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR

    context_attribs: []i32 = {
        egl.CONTEXT_CLIENT_VERSION, 3,
        EGL_CONTEXT_FLAGS_KHR, context_flags_bitfield,
        egl.NONE,
    }
    egl_display := egl.GetDisplay(egl.NativeDisplayType(display))
    if egl_display == egl.NO_DISPLAY {
        panic("Failed to create EGL display")
    }
    if !egl.Initialize(egl_display, &major, &minor) {
        panic("Can't initialise egl display")
    }
    if !egl.ChooseConfig(egl_display, raw_data(config_attribs), &egl_config, 1, &n) {
        panic("Failed to find/choose EGL config")
    }
    // This call must be here before CreateContext
    egl.BindAPI(egl.OPENGL_API)

    fmt.println("Creating Context")
    egl_context := egl.CreateContext(
        egl_display,
        egl_config,
        egl.NO_CONTEXT,
        raw_data(context_attribs),
    )
    if egl_context == egl.NO_CONTEXT {
        panic("Failed creating EGL context")
    }
    fmt.println("Done creating Context")
	egl_window := wl.egl_window_create(surface, i32(s.windowed_width), i32(s.windowed_height))
	egl_surface := egl.CreateWindowSurface(
		egl_display,
		egl_config,
		egl.NativeWindowType(egl_window),
		nil,
	)
	if egl_surface == egl.NO_SURFACE {
	    panic("Error creating window surface")
	}

	wl_callback := wl.wl_surface_frame(surface)
	wl.wl_callback_add_listener(wl_callback, &frame_callback, nil)

    whl := &s.window_handle.(Window_Handle_Linux_Wayland) 
    whl.redraw = true
    whl.display = display
    whl.surface = surface
    whl.egl_display = egl_display
    whl.egl_config = egl_config
    whl.egl_surface = egl_surface
    whl.egl_window = egl_window
    whl.egl_context = egl_context

	wayland_set_window_mode(init_options.window_mode)
}

wayland_shutdown :: proc() {
	// X.DestroyWindow(s.display, s.window)
}

wayland_window_handle :: proc() -> Window_Handle {
	return Window_Handle(&s.window_handle)
}

wayland_process_events :: proc() {
}

@rodata
KEY_FROM_XKEYCODE := [255]Keyboard_Key {
	8 = .Space,
	9 = .Escape,
	10 = .N1,
	11 = .N2,
	12 = .N3,
	13 = .N4,
	14 = .N5,
	15 = .N6,
	16 = .N7,
	17 = .N8,
	18 = .N9,
	19 = .N0,
	20 = .Minus,
	21 = .Equal,
	22 = .Backspace,
	23 = .Tab,
	24 = .Q,
	25 = .W,
	26 = .E,
	27 = .R,
	28 = .T,
	29 = .Y,
	30 = .U,
	31 = .I,
	32 = .O,
	33 = .P,
	34 = .Left_Bracket,
	35 = .Right_Bracket,
	36 = .Enter,
	37 = .Left_Control,
	38 = .A,
	39 = .S,
	40 = .D,
	41 = .F,
	42 = .G,
	43 = .H,
	44 = .J,
	45 = .K,
	46 = .L,
	47 = .Semicolon,
	48 = .Apostrophe,
	49 = .Backtick,
	50 = .Left_Shift,
	51 = .Backslash,
	52 = .Z,
	53 = .X,
	54 = .C,
	55 = .V,
	56 = .B,
	57 = .N,
	58 = .M,
	59 = .Comma,
	60 = .Period,
	61 = .Slash,
	62 = .Right_Shift,
	63 = .NP_Multiply,
	64 = .Left_Alt,
	65 = .Space,
	66 = .Caps_Lock,
	67 = .F1,
	68 = .F2,
	69 = .F3,
	70 = .F4,
	71 = .F5,
	72 = .F6,
	73 = .F7,
	74 = .F8,
	75 = .F9,
	76 = .F10,
	77 = .Num_Lock,
	78 = .Scroll_Lock,
	82 = .NP_Subtract,
	86 = .NP_Add,
	95 = .F11,
	96 = .F12,
	104 = .NP_Enter,
	105 = .Right_Control,
	106 = .NP_Divide,
	107 = .Print_Screen,
	108 = .Right_Alt,
	110 = .Home,
	111 = .Up,
	112 = .Page_Up,
	113 = .Left,
	114 = .Right,
	115 = .End,
	116 = .Down,
	117 = .Page_Down,
	118 = .Insert,
	119 = .Delete,
	125 = .NP_Equal,
	127 = .Pause,
	129 = .NP_Decimal,
	133 = .Left_Super,
	134 = .Right_Super,
	135 = .Menu,
}

key_from_xkeycode :: proc(kc: u32) -> Keyboard_Key {
	if kc >= 255 {
		return .None
	}

	return KEY_FROM_XKEYCODE[u8(kc)]
}

wayland_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

wayland_get_width :: proc() -> int {
	return s.width
}

wayland_get_height :: proc() -> int {
	return s.height
}

wayland_clear_events :: proc() {
	runtime.clear(&s.events)
}

wayland_set_position :: proc(x: int, y: int) {
}

wayland_set_size :: proc(w, h: int) {
}

wayland_get_window_scale :: proc() -> f32 {
	return 1
}

enter_borderless_fullscreen :: proc() {
}

leave_borderless_fullscreen :: proc() {
}

wayland_set_window_mode :: proc(window_mode: Window_Mode) {
}

wayland_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return false
}

wayland_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return 0
}

wayland_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
}

wayland_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Wayland_State)(state)
}

Wayland_State :: struct {
	allocator: runtime.Allocator,
	width: int,
	height: int,
	windowed_width: int,
	windowed_height: int,
	events: [dynamic]Window_Event,
	display: ^wl.wl_display,
	compositor: ^wl.wl_compositor,
	xdg_base: ^wl.xdg_wm_base,
	seat: ^wl.wl_seat,
    surface: ^wl.wl_surface,
	window_handle: Window_Handle_Linux,
	window_mode: Window_Mode,
}

s: ^Wayland_State

@(private="package")
Window_Handle_Linux_Wayland :: struct {
    ready: bool,
    redraw: bool,
	display: ^wl.wl_display,
    surface: ^wl.wl_surface,
    egl_display: egl.Display,
    egl_window: ^wl.egl_window,
    egl_surface: egl.Surface,
    egl_config: egl.Config,
    egl_context: egl.Context,
	// window: X.Window,
	// screen: i32,
}

registry_listener := wl.wl_registry_listener {
	global        = global,
	global_remove = global_remove,
}

display_listener := wl.wl_display_listener{}


global :: proc "c" (
	data: rawptr,
	registry: ^wl.wl_registry,
	name: c.uint32_t,
	interface: cstring,
	version: c.uint32_t,
) {
	context = runtime.default_context()
	if interface == wl.wl_compositor_interface.name {
        state: ^Wayland_State = cast(^Wayland_State)data
		state.compositor = cast(^wl.wl_compositor)(wl.wl_registry_bind(
				registry,
				name,
				&wl.wl_compositor_interface,
				version,
			))
	}

	if interface == wl.xdg_wm_base_interface.name {
		state: ^Wayland_State = cast(^Wayland_State)data
		state.xdg_base = cast(^wl.xdg_wm_base)(wl.wl_registry_bind(
				registry,
				name,
				&wl.xdg_wm_base_interface,
				version,
			))
	}
	if interface == wl.wl_seat_interface.name {
		state: ^Wayland_State = cast(^Wayland_State)data
		state.seat = cast(^wl.wl_seat)(wl.wl_registry_bind(
				registry,
				name,
				&wl.wl_seat_interface,
				version,
			))
	}
}

global_remove :: proc "c" (data: rawptr, registry: ^wl.wl_registry, name: c.uint32_t) {
}

done :: proc "c" (data: rawptr, wl_callback: ^wl.wl_callback, callback_data: c.uint32_t) {
	context = runtime.default_context()
    // fmt.println("done")
    wh := s.window_handle.(Window_Handle_Linux_Wayland)
    wh.redraw = true
    s.window_handle = wh

	wl.wl_callback_destroy(wl_callback)
}

window_listener := wl.xdg_surface_listener {
	configure = proc "c" (data: rawptr, surface: ^wl.xdg_surface, serial: c.uint32_t) {
		context = runtime.default_context()
		fmt.println("window configure")

		wl.xdg_surface_ack_configure(surface, serial)
		wl.wl_surface_damage(s.surface, 0, 0, i32(s.windowed_width), i32(s.windowed_height))
		wl.wl_surface_commit(s.surface)
	},
}

toplevel_listener := wl.xdg_toplevel_listener {
	configure = proc "c" (
		data: rawptr,
		xdg_toplevel: ^wl.xdg_toplevel,
		width: c.int32_t,
		height: c.int32_t,
		states: ^wl.wl_array,
	) {
		context = runtime.default_context()
		fmt.println("Top level configure", width, height, states)

        sw := i32(s.windowed_width)
        sh := i32(s.windowed_height)
        whl := s.window_handle.(Window_Handle_Linux_Wayland)
		if (sw != width || sh != height) && (sw > 0 && sh > 0) && (whl.ready) {
	        wl.egl_window_resize(whl.egl_window, c.int(width), c.int(height), 0, 0)
            s.windowed_width = int(width)
            s.windowed_height = int(height)
            s.width = int(width)
            s.height = int(height)
            /// SHOULD EMIT A VALID WINDOW EVENT
			// append(
			// 	&cc.platform_state.input.events,
			// 	WindowResize{new_width = width, new_height = height},
			// )
		}
        whl.ready = true
	},
	close = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel) {},
	configure_bounds = proc "c" (
		data: rawptr,
		xdg_toplevel: ^wl.xdg_toplevel,
		width: c.int32_t,
		height: c.int32_t,
	) {
		context = runtime.default_context()
		fmt.println("Top level configure bounds", width, height)

	},
	wm_capabilities = proc "c" (
		data: rawptr,
		xdg_toplevel: ^wl.xdg_toplevel,
		capabilities: ^wl.wl_array,
	) {},
}

wm_base_listener := wl.xdg_wm_base_listener {
	ping = proc "c" (data: rawptr, xdg_wm_base: ^wl.xdg_wm_base, serial: c.uint32_t) {
		wl.xdg_wm_base_pong(xdg_wm_base, serial)
	},
}

@(private="package")
frame_callback := wl.wl_callback_listener {
	done = done,
}
