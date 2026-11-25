#+build linux:android
#+private package
#+vet explicit-allocators
package karl2d

import "base:runtime"
import "log"
import "core:strings"
import "core:sys/android"
import app_glue "core:sys/android/native_app_glue"
import java "vendor:android/java"

PLATFORM_ANDROID :: Platform_Interface {
	init = android_init,
	shutdown = android_shutdown,
	get_window_render_glue = android_get_window_render_glue,
	get_events = android_get_events,
	before_present = android_before_present,
	set_window_title = android_set_window_title,
	set_window_position = android_set_window_position,
	get_window_position = android_get_window_position,
	set_screen_size = android_set_screen_size,
	get_screen_width = android_get_screen_width,
	get_screen_height = android_get_screen_height,
	get_window_scale = android_get_window_scale,
	set_window_mode = android_set_window_mode,
	get_window_mode = android_get_window_mode,
	set_window_icon = android_set_window_icon,
	get_monitors = android_get_monitors,
	get_window_monitor = android_get_window_monitor,
	set_window_monitor = android_set_window_monitor,

	set_cursor_hidden = android_set_cursor_hidden,
	is_cursor_hidden = android_is_cursor_hidden,
	set_mouse_locked = android_set_mouse_locked,
	is_mouse_locked = android_is_mouse_locked,
	create_custom_cursor = android_create_custom_cursor,
	set_cursor = android_set_cursor,
	destroy_custom_cursor = android_destroy_custom_cursor,

	is_gamepad_active = android_is_gamepad_active,
	get_gamepad_axis = android_get_gamepad_axis,
	set_gamepad_vibration = android_set_gamepad_vibration,

	open_url = android_open_url,
}

ANDROID_MONITOR_ID :: Monitor_Id(1)

Android_State :: struct {
	using _: Platform_State,
	allocator: runtime.Allocator,
	app: ^app_glue.android_app,
	window_render_glue: ^Window_Render_Glue,
	events: [dynamic]Event,
	width: int,
	height: int,
	scale: f32,
	mouse_buttons: android.AMotionEventButtons,
}

android_init :: proc(
	s: ^Android_State,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s.allocator = allocator
	s.events = make([dynamic]Event, allocator)
	s.app = app_glue.app()
	s.app.userData = s
	s.app.onAppCmd = android_on_app_cmd
	s.app.onInputEvent = android_on_input_event

	for s.app.window == nil && s.app.destroyRequested == 0 {
		android_process_app_events(s, true)
	}

	log.ensure(s.app.window != nil, "The Android activity was destroyed before it got a window")

	s.width = int(android.ANativeWindow_getWidth(s.app.window))
	s.height = int(android.ANativeWindow_getHeight(s.app.window))
	s.scale = android_get_scale(s.app)

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = create_android_gl_glue(s.app.window, allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Android and render backend '" + RENDER_BACKEND_NAME + "'")
	}

	android_hide_system_bars(s)
}

android_shutdown :: proc(s: ^Android_State) {
	s.app.userData = nil
	s.app.onAppCmd = nil
	s.app.onInputEvent = nil
	delete(s.events)
}

android_get_window_render_glue :: proc(s: ^Android_State) -> ^Window_Render_Glue {
	return s.window_render_glue
}

android_process_app_events :: proc(s: ^Android_State, block: bool) {
	for {
		source: ^app_glue.android_poll_source
		poll_res := android.ALooper_pollOnce(block ? -1 : 0, nil, nil, (^rawptr)(&source))

		if poll_res >= 0 && source != nil {
			source.process(s.app, source)
		}

		if block || poll_res < 0 {
			return
		}
	}
}

android_get_scale :: proc(app: ^app_glue.android_app) -> f32 {
	if app.config == nil {
		return 1
	}

	density := android.AConfiguration_getDensity(app.config)

	if density <= 0 || density >= android.ACONFIGURATION_DENSITY_ANY {
		return 1
	}

	return f32(density) / 160
}

android_on_app_cmd :: proc(app: ^app_glue.android_app, cmd: i32) {
	s := (^Android_State)(app.userData)

	switch cmd {
	case app_glue.APP_CMD_INIT_WINDOW:
		when RENDER_BACKEND_NAME == "gl" {
			if s.window_render_glue != nil {
				android_gl_glue_set_window((^Android_GL_Glue)(s.window_render_glue), app.window)
			}
		}

	case app_glue.APP_CMD_TERM_WINDOW:
		when RENDER_BACKEND_NAME == "gl" {
			if s.window_render_glue != nil {
				android_gl_glue_set_window((^Android_GL_Glue)(s.window_render_glue), nil)
			}
		}

	case app_glue.APP_CMD_GAINED_FOCUS:
		append(&s.events, Event_Window_Focused {})
		android_hide_system_bars(s)

	case app_glue.APP_CMD_LOST_FOCUS:
		append(&s.events, Event_Window_Unfocused {})
	}
}

android_on_input_event :: proc(app: ^app_glue.android_app, event: ^android.AInputEvent) -> i32 {
	s := (^Android_State)(app.userData)

	#partial switch android.AInputEvent_getType(event) {
	case .KEY:
		key_code := android.AKeyEvent_getKeyCode(event)

		if key_code < min(android.AKeyCode) || key_code > max(android.AKeyCode) {
			return 0
		}

		key := ANDROID_KEY_MAP[key_code]

		if key == .None {
			return 0
		}

		#partial switch android.AKeyEvent_getAction(event) {
		case .DOWN:
			if android.AKeyEvent_getRepeatCount(event) > 0 {
				append(&s.events, Event_Key_Repeat { key = key })
			} else {
				append(&s.events, Event_Key_Went_Down { key = key })
			}

		case .UP:
			append(&s.events, Event_Key_Went_Up { key = key })
		}

		return 1

	case .MOTION:
		source := android.AInputEvent_getSource(event)
		packed_action := android.AMotionEvent_getAction(event)

		if .MOUSE in source {
			#partial switch packed_action.action {
			case .SCROLL:
				wheel := android.AMotionEvent_getAxisValue(event, .VSCROLL, 0)
				wheel_horizontal := android.AMotionEvent_getAxisValue(event, .HSCROLL, 0)

				if wheel != 0 {
					append(&s.events, Event_Mouse_Wheel { delta = wheel })
				}

				if wheel_horizontal != 0 {
					append(&s.events, Event_Mouse_Wheel_Horizontal { delta = wheel_horizontal })
				}

			case:
				append(&s.events, Event_Mouse_Move {
					position = {
						android.AMotionEvent_getX(event, 0),
						android.AMotionEvent_getY(event, 0),
					},
				})
			}

			buttons := android.AMotionEvent_getButtonState(event)

			for b in ANDROID_MOUSE_BUTTONS {
				is_down := b.android_button in buttons
				was_down := b.android_button in s.mouse_buttons

				if is_down && !was_down {
					append(&s.events, Event_Mouse_Button_Went_Down { button = b.button })
				}

				if !is_down && was_down {
					append(&s.events, Event_Mouse_Button_Went_Up { button = b.button })
				}
			}

			s.mouse_buttons = buttons
			return 1
		}

		if .TOUCHSCREEN not_in source && .STYLUS not_in source {
			return 0
		}

		#partial switch packed_action.action {
		case .DOWN, .POINTER_DOWN:
			pointer_idx := uint(packed_action.pointer_index)

			append(&s.events, Event_Touch_Went_Down {
				id = Touch_Id(android.AMotionEvent_getPointerId(event, pointer_idx)),
				position = {
					android.AMotionEvent_getX(event, pointer_idx),
					android.AMotionEvent_getY(event, pointer_idx),
				},
			})

		case .MOVE:
			for pointer_idx in 0..<uint(android.AMotionEvent_getPointerCount(event)) {
				append(&s.events, Event_Touch_Moved {
					id = Touch_Id(android.AMotionEvent_getPointerId(event, pointer_idx)),
					position = {
						android.AMotionEvent_getX(event, pointer_idx),
						android.AMotionEvent_getY(event, pointer_idx),
					},
				})
			}

		case .UP, .POINTER_UP:
			pointer_idx := uint(packed_action.pointer_index)

			append(&s.events, Event_Touch_Went_Up {
				id = Touch_Id(android.AMotionEvent_getPointerId(event, pointer_idx)),
				position = {
					android.AMotionEvent_getX(event, pointer_idx),
					android.AMotionEvent_getY(event, pointer_idx),
				},
			})

		case .CANCEL:
			for pointer_idx in 0..<uint(android.AMotionEvent_getPointerCount(event)) {
				append(&s.events, Event_Touch_Cancelled {
					id = Touch_Id(android.AMotionEvent_getPointerId(event, pointer_idx)),
				})
			}
		}

		return 1
	}

	return 0
}

android_before_present :: proc(s: ^Android_State) {
}

android_get_events :: proc(s: ^Android_State, events: ^[dynamic]Event) {
	android_process_app_events(s, false)

	for s.app.destroyRequested == 0 &&
	    (s.app.window == nil || s.app.activityState != app_glue.APP_CMD_RESUME) {
		android_process_app_events(s, true)
	}

	if s.app.destroyRequested != 0 {
		append(&s.events, Event_Close_Window_Requested {})
	}

	if s.app.window != nil {
		width := int(android.ANativeWindow_getWidth(s.app.window))
		height := int(android.ANativeWindow_getHeight(s.app.window))
		scale := android_get_scale(s.app)

		if scale != s.scale {
			append(&s.events, Event_Window_Scale_Changed {
				scale = scale,
				screen_width = width,
				screen_height = height,
			})
		} else if width != s.width || height != s.height {
			append(&s.events, Event_Screen_Resize { width = width, height = height })
		}

		s.width = width
		s.height = height
		s.scale = scale
	}

	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

android_set_window_title :: proc(s: ^Android_State, title: string) {
}

android_set_window_position :: proc(s: ^Android_State, x: int, y: int) {
}

android_get_window_position :: proc(s: ^Android_State) -> Vec2 {
	return {}
}

android_set_screen_size :: proc(s: ^Android_State, w, h: int) {
}

android_get_screen_width :: proc(s: ^Android_State) -> int {
	return s.width
}

android_get_screen_height :: proc(s: ^Android_State) -> int {
	return s.height
}

android_get_window_scale :: proc(s: ^Android_State) -> f32 {
	return s.scale
}

android_set_window_mode :: proc(s: ^Android_State, window_mode: Window_Mode) {
}

android_get_window_mode :: proc(s: ^Android_State) -> Window_Mode {
	return .Borderless_Fullscreen
}

android_set_window_icon :: proc(s: ^Android_State, image: Image) -> bool {
	return false
}

android_get_monitors :: proc(_: ^Android_State, allocator: runtime.Allocator) -> []Monitor_Info {
	app := app_glue.app()
	monitors := make([]Monitor_Info, 1, allocator)

	monitors[0] = {
		id = ANDROID_MONITOR_ID,
		name = strings.clone("Android Screen", allocator),
		scale = android_get_scale(app),
		primary = true,
	}

	if app.window != nil {
		monitors[0].size = {
			int(android.ANativeWindow_getWidth(app.window)),
			int(android.ANativeWindow_getHeight(app.window)),
		}

		dots_per_mm := monitors[0].scale * 160 / 25.4

		monitors[0].physical_size = {
			int(f32(monitors[0].size.x) / dots_per_mm),
			int(f32(monitors[0].size.y) / dots_per_mm),
		}
	}

	return monitors
}

android_get_window_monitor :: proc(s: ^Android_State) -> Monitor_Id {
	return ANDROID_MONITOR_ID
}

android_set_window_monitor :: proc(s: ^Android_State, monitor: Monitor_Id) {
}

android_set_cursor_hidden :: proc(s: ^Android_State, hidden: bool) {
}

android_is_cursor_hidden :: proc(s: ^Android_State) -> bool {
	return false
}

android_set_mouse_locked :: proc(s: ^Android_State, locked: bool) {
}

android_is_mouse_locked :: proc(s: ^Android_State) -> bool {
	return false
}

android_create_custom_cursor :: proc(
	s: ^Android_State,
	image: Image,
	hotspot: [2]int,
) -> (
	Custom_Cursor,
	bool,
) {
	return {}, false
}

android_set_cursor :: proc(s: ^Android_State, cursor: Cursor) {
}

android_destroy_custom_cursor :: proc(s: ^Android_State, custom_cursor: Custom_Cursor) {
}

android_is_gamepad_active :: proc(s: ^Android_State, gamepad: int) -> bool {
	return false
}

android_get_gamepad_axis :: proc(s: ^Android_State, gamepad: int, axis: Gamepad_Axis) -> f32 {
	return 0
}

android_set_gamepad_vibration :: proc(s: ^Android_State, gamepad: int, left: f32, right: f32) {
}

android_open_url :: proc(s: ^Android_State, url: string) -> bool {
	if s.app.activity == nil {
		return false
	}

	start_view_activity :: proc(
		activity: ^java.Activity,
		url: string,
	) -> (
		exception: ^java.Throwable,
	) {
		url_string := java.string_from(url, frame_allocator) or_return
		uri := java.Uri_parse(url_string) or_return
		action := java.string_from(java.Intent_ACTION_VIEW, frame_allocator) or_return
		intent := java.Intent_new(action, uri) or_return
		return java.Activity_startActivity(activity, intent)
	}

	java.push_local_frame()
	exception := start_view_activity((^java.Activity)(s.app.activity.clazz), url)

	if exception != nil {
		message := java.exception_message(exception, frame_allocator)
		log.errorf("Failed opening URL %v: %v", url, message)
	}

	java.pop_local_frame()
	return exception == nil
}

android_hide_system_bars :: proc(s: ^Android_State) {
	if s.app.activity == nil {
		return
	}

	hide_on_ui_thread :: proc(
		data: rawptr,
		method: ^java.Method,
		args: ^java.Array(java.Object),
	) -> (
		result: ^java.Object,
		exception: ^java.Throwable,
	) {
		window := java.Activity_getWindow((^java.Activity)(data)) or_return
		view := java.Window_getDecorView(window) or_return

		java.View_setSystemUiVisibility(view, {
			.FULLSCREEN,
			.HIDE_NAVIGATION,
			.IMMERSIVE_STICKY,
			.LAYOUT_FULLSCREEN,
			.LAYOUT_HIDE_NAVIGATION,
			.LAYOUT_STABLE,
		}) or_return

		return
	}

	run_on_ui_thread :: proc(activity: ^java.Activity) -> (exception: ^java.Throwable) {
		runnable_class := java.find_class("java/lang/Runnable") or_return
		runnable := java.proxy_new({ runnable_class }, hide_on_ui_thread, activity) or_return
		return java.Activity_runOnUiThread(activity, (^java.Runnable)(runnable))
	}

	java.push_local_frame()
	exception := run_on_ui_thread((^java.Activity)(s.app.activity.clazz))

	if exception != nil {
		message := java.exception_message(exception, frame_allocator)
		log.errorf("Failed hiding the Android system bars: %v", message)
	}

	java.pop_local_frame()
}

Android_Mouse_Button :: struct {
	android_button: android.AMotionEventButton,
	button: Mouse_Button,
}

@(rodata)
ANDROID_MOUSE_BUTTONS := [?]Android_Mouse_Button {
	{ .PRIMARY, .Left },
	{ .SECONDARY, .Right },
	{ .TERTIARY, .Middle },
}

@(rodata)
ANDROID_KEY_MAP := #partial [android.AKeyCode]Keyboard_Key {
	.NUM0 = .N0,
	.NUM1 = .N1,
	.NUM2 = .N2,
	.NUM3 = .N3,
	.NUM4 = .N4,
	.NUM5 = .N5,
	.NUM6 = .N6,
	.NUM7 = .N7,
	.NUM8 = .N8,
	.NUM9 = .N9,

	.A = .A,
	.B = .B,
	.C = .C,
	.D = .D,
	.E = .E,
	.F = .F,
	.G = .G,
	.H = .H,
	.I = .I,
	.J = .J,
	.K = .K,
	.L = .L,
	.M = .M,
	.N = .N,
	.O = .O,
	.P = .P,
	.Q = .Q,
	.R = .R,
	.S = .S,
	.T = .T,
	.U = .U,
	.V = .V,
	.W = .W,
	.X = .X,
	.Y = .Y,
	.Z = .Z,

	.APOSTROPHE    = .Apostrophe,
	.COMMA         = .Comma,
	.MINUS         = .Minus,
	.PERIOD        = .Period,
	.SLASH         = .Slash,
	.SEMICOLON     = .Semicolon,
	.EQUALS        = .Equal,
	.LEFT_BRACKET  = .Left_Bracket,
	.BACKSLASH     = .Backslash,
	.RIGHT_BRACKET = .Right_Bracket,
	.GRAVE         = .Backtick,

	.SPACE       = .Space,
	.ESCAPE      = .Escape,
	.ENTER       = .Enter,
	.TAB         = .Tab,
	.DEL         = .Backspace,
	.INSERT      = .Insert,
	.FORWARD_DEL = .Delete,
	.DPAD_RIGHT  = .Right,
	.DPAD_LEFT   = .Left,
	.DPAD_DOWN   = .Down,
	.DPAD_UP     = .Up,
	.PAGE_UP     = .Page_Up,
	.PAGE_DOWN   = .Page_Down,
	.MOVE_HOME   = .Home,
	.MOVE_END    = .End,
	.CAPS_LOCK   = .Caps_Lock,
	.SCROLL_LOCK = .Scroll_Lock,
	.NUM_LOCK    = .Num_Lock,
	.SYSRQ       = .Print_Screen,
	.BREAK       = .Pause,

	.F1  = .F1,
	.F2  = .F2,
	.F3  = .F3,
	.F4  = .F4,
	.F5  = .F5,
	.F6  = .F6,
	.F7  = .F7,
	.F8  = .F8,
	.F9  = .F9,
	.F10 = .F10,
	.F11 = .F11,
	.F12 = .F12,

	.SHIFT_LEFT  = .Left_Shift,
	.CTRL_LEFT   = .Left_Control,
	.ALT_LEFT    = .Left_Alt,
	.META_LEFT   = .Left_Super,
	.SHIFT_RIGHT = .Right_Shift,
	.CTRL_RIGHT  = .Right_Control,
	.ALT_RIGHT   = .Right_Alt,
	.META_RIGHT  = .Right_Super,
	.MENU        = .Menu,

	.NUMPAD_0        = .NP_0,
	.NUMPAD_1        = .NP_1,
	.NUMPAD_2        = .NP_2,
	.NUMPAD_3        = .NP_3,
	.NUMPAD_4        = .NP_4,
	.NUMPAD_5        = .NP_5,
	.NUMPAD_6        = .NP_6,
	.NUMPAD_7        = .NP_7,
	.NUMPAD_8        = .NP_8,
	.NUMPAD_9        = .NP_9,
	.NUMPAD_DOT      = .NP_Decimal,
	.NUMPAD_DIVIDE   = .NP_Divide,
	.NUMPAD_MULTIPLY = .NP_Multiply,
	.NUMPAD_SUBTRACT = .NP_Subtract,
	.NUMPAD_ADD      = .NP_Add,
	.NUMPAD_ENTER    = .NP_Enter,
	.NUMPAD_EQUALS   = .NP_Equal,
}
