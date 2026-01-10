#+build darwin
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_COCOA :: Window_Interface {
	state_size = cocoa_state_size,
	init = cocoa_init,
	shutdown = cocoa_shutdown,
	window_handle = cocoa_window_handle,
	process_events = cocoa_process_events,
	get_events = cocoa_get_events,
	get_width = cocoa_get_width,
	get_height = cocoa_get_height,
	clear_events = cocoa_clear_events,
	set_position = cocoa_set_position,
	set_size = cocoa_set_size,
	get_window_scale = cocoa_get_window_scale,
	set_window_mode = cocoa_set_window_mode,

	is_gamepad_active = cocoa_is_gamepad_active,
	get_gamepad_axis = cocoa_get_gamepad_axis,
	set_gamepad_vibration = cocoa_set_gamepad_vibration,

	set_internal_state = cocoa_set_internal_state,
}

import NS "core:sys/darwin/Foundation"
import nsgl "darwin/nsgl"
import "base:runtime"

cocoa_state_size :: proc() -> int {
	return size_of(Cocoa_State)
}

cocoa_init :: proc(
	window_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	assert(window_state != nil)
	s = (^Cocoa_State)(window_state)
	s.allocator = allocator
	s.events = make([dynamic]Window_Event, allocator)
	s.windowed_width = screen_width
	s.windowed_height = screen_height
	s.width = screen_width
	s.height = screen_height
	s.custom_context = context
	s.window_mode = init_options.window_mode

	// Initialize NSApplication
	s.app = NS.Application_sharedApplication()
	s.app->setActivationPolicy(.Regular)

	NS.scoped_autoreleasepool()

	menu_bar := NS.Menu_alloc()->init()
	s.app->setMainMenu(menu_bar)
	app_menu_item := menu_bar->addItemWithTitle(NS.AT(""), nil, NS.AT(""))
	app_menu := NS.Menu_alloc()->init()
	fullscreen_item := app_menu->addItemWithTitle(NS.AT("Enter Full Screen"), NS.sel_registerName(cstring("toggleFullScreen:")), NS.AT("f"))

	// Change keyboard shortcut for fullscreen to Ctrl-Cmd-F
	new_mask := NS.EventModifierFlagControl | NS.EventModifierFlagCommand
	fullscreen_item->setKeyEquivalentModifierMask(new_mask)

	app_menu->addItemWithTitle(NS.AT("Quit"), NS.sel_registerName(cstring("terminate:")), NS.AT("q"))
	app_menu_item->setSubmenu(app_menu)
	s.app->setAppleMenu(app_menu)

	// Activate the application
	s.app->activateIgnoringOtherApps(true)
	s.app->finishLaunching()


	// Create window style based on mode
	style := NS.WindowStyleMaskTitled | NS.WindowStyleMaskClosable | NS.WindowStyleMaskMiniaturizable
	if init_options.window_mode == .Windowed_Resizable {
		style |= NS.WindowStyleMaskResizable
	}

	// Create the window
	rect := NS.Rect {
		origin = {0, 0},
		size = {NS.Float(screen_width), NS.Float(screen_height)},
	}
	s.window = NS.Window_alloc()
	s.window = s.window->initWithContentRect(rect, style, .Buffered, false)

	// Set window title
	title_str := NS.String_alloc()->initWithOdinString(window_title)
	s.window->setTitle(title_str)

	// Get the content view for rendering
	s.view = s.window->contentView()

	// Center and show window
	s.window->center()
	s.window->setAcceptsMouseMovedEvents(true)
	s.window->makeKeyAndOrderFront(nil)

	// Setup window handle struct
	s.window_handle.window = s.window
	s.window_handle.view = s.view
}

cocoa_shutdown :: proc() {
	if s.window != nil {
		s.window->close()
	}
	delete(s.events)
}

cocoa_window_handle :: proc() -> Window_Handle {
	return Window_Handle(&s.window_handle)
}

cocoa_process_events :: proc() {
	// Poll for events without blocking
	for {
		event := s.app->nextEventMatchingMask(
			NS.EventMaskAny,
			nil,  // nil date = don't wait
			NS.DefaultRunLoopMode,
			true, // dequeue
		)

		if event == nil {
			break
		}

		event_type := event->type()

		#partial switch event_type {
		case .KeyDown:
			if !event->isARepeat() {
				key := key_from_macos_keycode(event->keyCode())
				if key != .None {
					append(&s.events, Window_Event_Key_Went_Down{key = key})
				}
			}

		case .KeyUp:
			key := key_from_macos_keycode(event->keyCode())
			if key != .None {
				append(&s.events, Window_Event_Key_Went_Up{key = key})
			}

		case .LeftMouseDown:
			append(&s.events, Window_Event_Mouse_Button_Went_Down{button = .Left})

		case .LeftMouseUp:
			append(&s.events, Window_Event_Mouse_Button_Went_Up{button = .Left})

		case .RightMouseDown:
			append(&s.events, Window_Event_Mouse_Button_Went_Down{button = .Right})

		case .RightMouseUp:
			append(&s.events, Window_Event_Mouse_Button_Went_Up{button = .Right})

		case .OtherMouseDown:
			append(&s.events, Window_Event_Mouse_Button_Went_Down{button = .Middle})

		case .OtherMouseUp:
			append(&s.events, Window_Event_Mouse_Button_Went_Up{button = .Middle})

		case .MouseMoved, .LeftMouseDragged, .RightMouseDragged, .OtherMouseDragged:
			// Convert to view coordinates (flip Y - macOS origin is bottom-left)
			loc := event->locationInWindow()
			// Flip Y coordinate
			y := NS.Float(s.height) - loc.y
			append(&s.events, Window_Event_Mouse_Move{
				position = {f32(loc.x), f32(y)},
			})

		case .ScrollWheel:
			delta := event->scrollingDeltaY()
			// Normalize: trackpad gives precise deltas, mouse wheel gives line deltas
			if event->hasPreciseScrollingDeltas() {
				append(&s.events, Window_Event_Mouse_Wheel{delta = f32(delta) / 10.0})
			} else {
				append(&s.events, Window_Event_Mouse_Wheel{delta = f32(delta)})
			}
		}

		// Forward events to application for default handling
		// For now let's just forward if Command or Control is held (for menu shortcuts like Cmd+Q)
		// Otherwise regular key presses will cause system beeps while playing
		is_key_event := event_type == .KeyDown || event_type == .KeyUp
		if is_key_event {
			mods := event->modifierFlags()
			has_cmd_or_ctrl := mods & {.Command, .Control} != {}
			if has_cmd_or_ctrl {
				s.app->sendEvent(event)
			}
		} else {
			s.app->sendEvent(event)
		}
	}

	// Check for window resize
	// TODO: not sure if this is where we should be updating
	content_rect := s.window->contentLayoutRect()
	new_width := int(content_rect.size.width)
	new_height := int(content_rect.size.height)

	if new_width != s.width || new_height != s.height {
		s.width = new_width
		s.height = new_height
		if s.window_mode != .Borderless_Fullscreen {
			s.windowed_width = new_width
			s.windowed_height = new_height
		}
		append(&s.events, Window_Event_Resize{
			width = new_width,
			height = new_height,
		})

		if s.window_handle.opengl_context != nil {
			s.window_handle.opengl_context->update()
		}
	}

	// Check for window close request
	// (This is a simple check - a more robust solution would use a window delegate)
	if s.window != nil && !s.window->keyWindow() {
		// Window lost focus - send unfocused event if not already sent
		// For now we'll skip this - would need to track focus state
	}
}

cocoa_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

cocoa_get_width :: proc() -> int {
	return s.width
}

cocoa_get_height :: proc() -> int {
	return s.height
}

cocoa_clear_events :: proc() {
	runtime.clear(&s.events)
}

cocoa_set_position :: proc(x: int, y: int) {
	// macOS uses bottom-left origin for screen coordinates
	origin := NS.Point{NS.Float(x), NS.Float(y)}
	s.window->setFrameOrigin(origin)
}

cocoa_set_size :: proc(w, h: int) {
	frame := NS.Window_frame(s.window)
	// Keep the top-left corner in place when resizing
	new_y := frame.origin.y + frame.size.height - NS.Float(h)
	new_frame := NS.Rect{
		origin = {frame.origin.x, new_y},
		size = {NS.Float(w), NS.Float(h)},
	}
	s.window->setFrame(new_frame, true)
}

cocoa_get_window_scale :: proc() -> f32 {
	return f32(s.window->backingScaleFactor())
}

cocoa_is_gamepad_active :: proc(gamepad: int) -> bool {
	// Gamepad not implemented for macOS yet
	return false
}

cocoa_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	return 0
}

cocoa_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {}

cocoa_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Cocoa_State)(state)
}

Cocoa_State :: struct {
	allocator:        runtime.Allocator,
	custom_context:   runtime.Context,
	app:              ^NS.Application,
	window:           ^NS.Window,
	view:             ^NS.View,
	window_mode:      Window_Mode,

	width:            int,
	height:           int,
	windowed_width:   int,
	windowed_height:  int,
	events:           [dynamic]Window_Event,

	window_handle:    Window_Handle_Darwin,
}

cocoa_set_window_mode :: proc(window_mode: Window_Mode) {
	if window_mode == s.window_mode {
		return
	}

	old_mode := s.window_mode
	s.window_mode = window_mode

	switch window_mode {
	case .Windowed:
		if old_mode == .Borderless_Fullscreen {
			s.window->toggleFullScreen(nil)
		}
		style := NS.WindowStyleMaskTitled | NS.WindowStyleMaskClosable | NS.WindowStyleMaskMiniaturizable
		s.window->setStyleMask(style)

	case .Windowed_Resizable:
		if old_mode == .Borderless_Fullscreen {
			s.window->toggleFullScreen(nil)
		}
		style := NS.WindowStyleMaskTitled | NS.WindowStyleMaskClosable | NS.WindowStyleMaskMiniaturizable | NS.WindowStyleMaskResizable
		s.window->setStyleMask(style)

	case .Borderless_Fullscreen:
		s.window->toggleFullScreen(nil)
	}
}

s: ^Cocoa_State

@(private="package")
Window_Handle_Darwin :: struct {
	window:         ^NS.Window,
	view:           ^NS.View,
	opengl_context: ^nsgl.OpenGLContext,
}

// Key code mapping from macOS virtual key codes to Keyboard_Key
key_from_macos_keycode :: proc(keycode: u16) -> Keyboard_Key {
	// macOS uses Carbon virtual key codes (kVK)
	#partial switch NS.kVK(keycode) {
	case .ANSI_A: return .A
	case .ANSI_S: return .S
	case .ANSI_D: return .D
	case .ANSI_F: return .F
	case .ANSI_H: return .H
	case .ANSI_G: return .G
	case .ANSI_Z: return .Z
	case .ANSI_X: return .X
	case .ANSI_C: return .C
	case .ANSI_V: return .V
	case .ANSI_B: return .B
	case .ANSI_Q: return .Q
	case .ANSI_W: return .W
	case .ANSI_E: return .E
	case .ANSI_R: return .R
	case .ANSI_Y: return .Y
	case .ANSI_T: return .T
	case .ANSI_O: return .O
	case .ANSI_U: return .U
	case .ANSI_I: return .I
	case .ANSI_P: return .P
	case .ANSI_L: return .L
	case .ANSI_J: return .J
	case .ANSI_K: return .K
	case .ANSI_N: return .N
	case .ANSI_M: return .M

	case .ANSI_1: return .N1
	case .ANSI_2: return .N2
	case .ANSI_3: return .N3
	case .ANSI_4: return .N4
	case .ANSI_5: return .N5
	case .ANSI_6: return .N6
	case .ANSI_7: return .N7
	case .ANSI_8: return .N8
	case .ANSI_9: return .N9
	case .ANSI_0: return .N0

	case .Return:      return .Enter
	case .Tab:         return .Tab
	case .Space:       return .Space
	case .Delete:      return .Backspace  // macOS "Delete" is backspace
	case .Escape:      return .Escape
	case .ForwardDelete: return .Delete

	case .LeftArrow:   return .Left
	case .RightArrow:  return .Right
	case .DownArrow:   return .Down
	case .UpArrow:     return .Up

	case .Home:        return .Home
	case .End:         return .End
	case .PageUp:      return .Page_Up
	case .PageDown:    return .Page_Down

	case .F1:          return .F1
	case .F2:          return .F2
	case .F3:          return .F3
	case .F4:          return .F4
	case .F5:          return .F5
	case .F6:          return .F6
	case .F7:          return .F7
	case .F8:          return .F8
	case .F9:          return .F9
	case .F10:         return .F10
	case .F11:         return .F11
	case .F12:         return .F12

	case .Shift:       return .Left_Shift
	case .RightShift:  return .Right_Shift
	case .Control:     return .Left_Control
	case .RightControl: return .Right_Control
	case .Option:      return .Left_Alt
	case .RightOption: return .Right_Alt
	case .Command:     return .Left_Super
	case .RightCommand: return .Right_Super
	case .CapsLock:    return .Caps_Lock

	case .ANSI_Minus:         return .Minus
	case .ANSI_Equal:         return .Equal
	case .ANSI_LeftBracket:   return .Left_Bracket
	case .ANSI_RightBracket:  return .Right_Bracket
	case .ANSI_Backslash:     return .Backslash
	case .ANSI_Semicolon:     return .Semicolon
	case .ANSI_Quote:         return .Apostrophe
	case .ANSI_Comma:         return .Comma
	case .ANSI_Period:        return .Period
	case .ANSI_Slash:         return .Slash
	case .ANSI_Grave:         return .Backtick

	case: return .None
	}
}
