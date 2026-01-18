#+build darwin
#+private file

package karl2d

import NS "core:sys/darwin/Foundation"
import ce "darwin/cocoa_extras"
import gc "darwin/gamecontroller"
import "base:runtime"

@(private="package")
PLATFORM_MAC :: Platform_Interface {
	state_size = mac_state_size,
	init = mac_init,
	shutdown = mac_shutdown,
	get_window_render_glue = mac_get_window_render_glue,
	get_events = mac_get_events,
	get_width = mac_get_width,
	get_height = mac_get_height,
	set_position = mac_set_position,
	set_size = mac_set_size,
	get_window_scale = mac_get_window_scale,
	set_window_mode = mac_set_window_mode,

	is_gamepad_active = mac_is_gamepad_active,
	get_gamepad_axis = mac_get_gamepad_axis,
	set_gamepad_vibration = mac_set_gamepad_vibration,

	set_internal_state = mac_set_internal_state,
}

HAPTICS_SHARPNESS_LEFT  :: 0.1
HAPTICS_SHARPNESS_RIGHT :: 0.9

Mac_State :: struct {
	allocator:        runtime.Allocator,
	app:              ^NS.Application,
	window:           ^NS.Window,
	window_mode:      Window_Mode,

	width:            int,
	height:           int,
	windowed_rect:    NS.Rect,
	events:           [dynamic]Event,

	window_render_glue: Window_Render_Glue,

	gamepads:           [MAX_GAMEPADS]Gamepad,
}

Gamepad :: struct {
	controller:               ^gc.Controller,
	extended_gamepad:         ^gc.ExtendedGamepad,
	button_inputs:            [Gamepad_Button]^gc.ControllerButtonInput,
	button_was_pressed:       [Gamepad_Button]bool,
}

when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
	Gamepad_Haptics :: struct {
		haptic_engine_left_right: [2]^gc.HapticEngine,
		haptic_player_left_right: [2]^gc.HapticPatternPlayer,
		old_intensity_left_right: [2]f32,
	}

	gamepad_haptics: [MAX_GAMEPADS]Gamepad_Haptics
}

s: ^Mac_State

mac_state_size :: proc() -> int {
	return size_of(Mac_State)
}

mac_init :: proc(
	window_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	assert(window_state != nil)
	s = (^Mac_State)(window_state)
	s.allocator = allocator
	s.events = make([dynamic]Event, allocator)
	s.width = screen_width
	s.height = screen_height

	// Initialize NSApplication
	s.app = NS.Application_sharedApplication()
	s.app->setActivationPolicy(.Regular)

	NS.scoped_autoreleasepool()

	// Menu bar, needed for manually quitting
	menu_bar := NS.Menu_alloc()->init()
	s.app->setMainMenu(menu_bar)
	app_menu_item := menu_bar->addItemWithTitle(NS.AT(""), nil, NS.AT(""))

	app_menu := NS.Menu_alloc()->init()
	app_menu->addItemWithTitle(NS.AT("Quit"), NS.sel_registerName(cstring("terminate:")), NS.AT("q"))
	app_menu_item->setSubmenu(app_menu)
	s.app->setAppleMenu(app_menu)

	// Create the window
	rect := NS.Rect {
		origin = {0, 0},
		size = {NS.Float(screen_width), NS.Float(screen_height)},
	}
	s.window = NS.Window_alloc()

	style := NS.WindowStyleMaskTitled | NS.WindowStyleMaskClosable | NS.WindowStyleMaskMiniaturizable
	s.window = s.window->initWithContentRect(rect, style, .Buffered, false)
	s.windowed_rect = rect

	title_str := NS.String_alloc()->initWithOdinString(window_title)
	s.window->setTitle(title_str)

	s.window->center()
	s.window->setAcceptsMouseMovedEvents(true)
	s.window->makeKeyAndOrderFront(nil)

	mac_set_window_mode(init_options.window_mode)

	// Activate the application
	s.app->activateIgnoringOtherApps(true)
	s.app->finishLaunching()

	// Add already connected controllers
	poll_for_new_controllers()

	// Setup listeners for connected/disconnected controllers
	notificationCenter := NS.NotificationCenter_defaultCenter()

	notificationCenter->addObserverForName(
		gc.DidConnectNotification, nil, nil,
		NS.Block_createGlobalWithParam(s, proc "c" (s: rawptr, n: ^NS.Notification) {
			context = runtime.default_context()

			poll_for_new_controllers()
		}),
	)
	notificationCenter->addObserverForName(
		gc.DidDisconnectNotification, nil, nil,
		NS.Block_createGlobalWithParam(s, proc "c" (s: rawptr, n: ^NS.Notification) {
			context = runtime.default_context()

			controller := (^gc.Controller)(n->object())
			remove_controller(controller)
		}),
	)


	// Setup delegates for events not handled in mac_process_events
	window_delegates := NS.window_delegate_register_and_alloc(
		NS.WindowDelegateTemplate{
			windowDidResize = proc(_: ^NS.Notification) {
				content_rect := s.window->contentLayoutRect()
				new_width := int(content_rect.size.width)
				new_height := int(content_rect.size.height)

				if new_width != s.width || new_height != s.height {
					s.width = new_width
					s.height = new_height
					if s.window_mode != .Borderless_Fullscreen {
						s.windowed_rect = content_rect
					}
					append(&s.events, Event_Resize{
						width = new_width,
						height = new_height,
					})
				}
			},

			windowShouldClose = proc(_: ^NS.Window) -> bool {
				append(&s.events, Event_Close_Window_Requested{})
				return true
			},

			// Focus and unfocus events
			windowDidBecomeKey = proc(_: ^NS.Notification) {
				append(&s.events, Event_Window_Focused{})
			},

			windowDidResignKey = proc(_: ^NS.Notification) {
				append(&s.events, Event_Window_Unfocused{})
			},
		},
		"Karl2DWindowDelegate",
		context,
	)

	s.window->setDelegate(window_delegates)

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_mac_gl_glue(s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Mac platform and render backend '" + RENDER_BACKEND_NAME + "'")
	}
}

mac_shutdown :: proc() {
	if s.window != nil {
		s.window->close()
	}
	delete(s.events)
}

mac_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.window_render_glue
}

mac_get_events :: proc(events: ^[dynamic]Event) {
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
					append(&s.events, Event_Key_Went_Down{key = key})
				}
			}

		case .KeyUp:
			key := key_from_macos_keycode(event->keyCode())
			if key != .None {
				append(&s.events, Event_Key_Went_Up{key = key})
			}

		case .LeftMouseDown:
			append(&s.events, Event_Mouse_Button_Went_Down{button = .Left})

		case .LeftMouseUp:
			append(&s.events, Event_Mouse_Button_Went_Up{button = .Left})

		case .RightMouseDown:
			append(&s.events, Event_Mouse_Button_Went_Down{button = .Right})

		case .RightMouseUp:
			append(&s.events, Event_Mouse_Button_Went_Up{button = .Right})

		case .OtherMouseDown:
			append(&s.events, Event_Mouse_Button_Went_Down{button = .Middle})

		case .OtherMouseUp:
			append(&s.events, Event_Mouse_Button_Went_Up{button = .Middle})

		case .MouseMoved, .LeftMouseDragged, .RightMouseDragged, .OtherMouseDragged:
			// Convert to view coordinates (flip Y - macOS origin is bottom-left)
			loc := event->locationInWindow()
			// Flip Y coordinate
			y := NS.Float(s.height) - loc.y
			append(&s.events, Event_Mouse_Move{
				position = {f32(loc.x), f32(y)},
			})

		case .ScrollWheel:
			delta := event->scrollingDeltaY()
			// Normalize: trackpad gives precise deltas, mouse wheel gives line deltas
			if event->hasPreciseScrollingDeltas() {
				append(&s.events, Event_Mouse_Wheel{delta = f32(delta) / 10.0})
			} else {
				append(&s.events, Event_Mouse_Wheel{delta = f32(delta)})
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

	// Poll gamepad buttons and generate events
	for &gamepad, gamepad_index in s.gamepads {
		if gamepad.controller == nil do continue

		for button in Gamepad_Button {
			is_pressed := gamepad.button_inputs[button]->isPressed()
			was_pressed := gamepad.button_was_pressed[button]
			if is_pressed && !was_pressed {
				append(&s.events, Event_Gamepad_Button_Went_Down{gamepad_index, button})
			} else if !is_pressed && was_pressed {
				append(&s.events, Event_Gamepad_Button_Went_Up{gamepad_index, button})
			}
			gamepad.button_was_pressed[button] = is_pressed
		}
	}

	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

mac_get_width :: proc() -> int {
	return s.width
}

mac_get_height :: proc() -> int {
	return s.height
}

mac_set_position :: proc(x: int, y: int) {
	// macOS uses bottom-left origin for screen coordinates
	origin := NS.Point{NS.Float(x), NS.Float(y)}
	s.window->setFrameOrigin(origin)
}

mac_set_size :: proc(w, h: int) {
	frame := NS.Window_frame(s.window)
	// Keep the top-left corner in place when resizing
	new_y := frame.origin.y + frame.size.height - NS.Float(h)
	new_frame := NS.Rect{
		origin = {frame.origin.x, new_y},
		size = {NS.Float(w), NS.Float(h)},
	}
	s.window->setFrame(new_frame, true)
}

mac_get_window_scale :: proc() -> f32 {
	return f32(s.window->backingScaleFactor())
}

mac_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}
	return s.gamepads[gamepad].controller != nil
}

mac_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if !mac_is_gamepad_active(gamepad) {
		return 0
	}

	egp := s.gamepads[gamepad].extended_gamepad

	switch axis {
	case .Left_Stick_X:  return egp->leftThumbstick()->xAxis()->value()
	case .Left_Stick_Y:  return -egp->leftThumbstick()->yAxis()->value() // Invert Y to match XInput
	case .Right_Stick_X: return egp->rightThumbstick()->xAxis()->value()
	case .Right_Stick_Y: return -egp->rightThumbstick()->yAxis()->value()
	case .Left_Trigger:  return egp->leftTrigger()->value()
	case .Right_Trigger: return egp->rightTrigger()->value()
	}

	return 0
}

mac_set_gamepad_vibration :: proc(gamepad_index: int, left: f32, right: f32) {
	when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
		if !mac_is_gamepad_active(gamepad_index) do return
		gamepad := &s.gamepads[gamepad_index]
		haptics := &gamepad_haptics[gamepad_index]

		// early stop so we shutoff player even if delta isn't past the threshold
		if left < 0.01 {
			stop_haptic_player(&haptics.haptic_player_left_right[0])
		}
		if right < 0.01 {
			stop_haptic_player(&haptics.haptic_player_left_right[1])
		}

		// activation threshold, so we don't thrash needlessly (we can tweak this)
		d_intensity_left  := abs(haptics.old_intensity_left_right[0] - left)
		d_intensity_right := abs(haptics.old_intensity_left_right[1] - right)
		if abs(d_intensity_left) < .10 && abs(d_intensity_right) < .10 {
			return
		}

		haptics.old_intensity_left_right = {left, right}

		// prep for new player
		for &player in haptics.haptic_player_left_right {
			stop_haptic_player(&player)
		}

		// Lazy-init haptic engine
		left_initted := init_haptic_engine(
			&haptics.haptic_engine_left_right[0],
			gc.LeftHandle,
			gamepad,
		)
		right_initted := init_haptic_engine(
			&haptics.haptic_engine_left_right[1],
			gc.RightHandle,
			gamepad,
		)

		if !left_initted && !right_initted do return

		create_haptic_player(0, left, haptics)
		create_haptic_player(1, right, haptics)
	}
}

mac_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Mac_State)(state)
}

mac_set_window_mode :: proc(window_mode: Window_Mode) {
	if window_mode == s.window_mode {
		return
	}

	old_mode := s.window_mode
	s.window_mode = window_mode
	style := NS.WindowStyleMaskTitled | NS.WindowStyleMaskClosable | NS.WindowStyleMaskMiniaturizable

	switch window_mode {
	case .Windowed_Resizable:
		style |= NS.WindowStyleMaskResizable
		fallthrough

	case .Windowed:
		s.window->setStyleMask(style)
		if old_mode == .Borderless_Fullscreen {
			s.window->setLevel(.Normal)
			s.window->setFrame(s.windowed_rect, true)
			ce.Application_setPresentationOptions(s.app, {})
		}

	case .Borderless_Fullscreen:
		s.windowed_rect = s.window->frame()
		s.window->setStyleMask({})
		screen_frame := NS.Screen_mainScreen()->frame()
		s.window->setFrame(screen_frame, true)
		s.window->setLevel(.Normal)
		ce.Application_setPresentationOptions(s.app, {.HideMenuBar, .HideDock})

		// same as frame() b/c no decorations, but semantically more correct
		content_rect := s.window->contentLayoutRect()
		s.width = int(content_rect.width)
		s.height = int(content_rect.height)
	}
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

//--------------------//
// CONTROLLER SUPPORT //
//--------------------//

poll_for_new_controllers :: proc() {
	controllers := gc.Controller_controllers()
	controller_count := controllers != nil ? int(controllers->count()) : 0

	// Simple algorithm:
	// - Remove the controllers that aren't connected anymore (defensive).
	// - If we have MAX_GAMEPADS registered, and they're still connected, don't add new controllers.
	// - Connect new controllers.

	remove_no_longer_connected_controllers(controllers, controller_count)

	connected_count := 0
	for gamepad in s.gamepads {
		if gamepad.controller != nil {
			connected_count += 1
		}
	}
	if connected_count >= MAX_GAMEPADS do return

	for i in 0..<controller_count {
		controller := controllers->object(NS.UInteger(i))
		if controller == nil do continue

		extended_gamepad := controller->extendedGamepad()
		if extended_gamepad == nil do continue

		if controller_is_registered(controller) do continue

		available_slot := 0
		for gamepad, gamepad_index in s.gamepads {
			if gamepad.controller == nil {
				available_slot = gamepad_index
				break
			}
		}
		
		s.gamepads[available_slot].controller = controller
		s.gamepads[available_slot].extended_gamepad = extended_gamepad
		s.gamepads[available_slot].button_inputs = make_button_inputs(extended_gamepad)
	}
}

remove_no_longer_connected_controllers :: proc(controllers: ^gc.ControllerArray, count: int) {
	found: [MAX_GAMEPADS]bool

	for i in 0..<count {
		controller := controllers->object(NS.UInteger(i))
		if controller == nil do continue

		for gamepad, gamepad_index in s.gamepads {
			if gamepad.controller == controller {
				found[gamepad_index] = true
			}
		}
	}

	for gamepad, gamepad_index in s.gamepads {
		if gamepad.controller != nil && !found[gamepad_index] {
			remove_controller(gamepad.controller)
		}
	}
}

controller_is_registered :: proc(controller: ^gc.Controller) -> bool {
	for gamepad in s.gamepads {
		if gamepad.controller == controller {
			return true
		}
	}
	return false
}

remove_controller :: proc(controller: ^gc.Controller) {
	for &gamepad, gamepad_index in s.gamepads {
		if gamepad.controller == controller {
			// haptic support is only available in 11.0.0
			when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
				for &engine in gamepad_haptics[gamepad_index].haptic_engine_left_right {
					if engine != nil {
						engine->stopWithCompletionHandler(nil)
						engine->release()
					}
				}
				for &player in gamepad_haptics[gamepad_index].haptic_player_left_right {
					stop_haptic_player(&player)
				}
				gamepad_haptics[gamepad_index] = {}
			}
			
			// no need to release controller, extended_gamepad, or button_inputs;
			// the gamecontroller framework owns the these
			gamepad = {}
			return
		}
	}
}

// Store pointers to the buttons (these won't change until the controller changes,
// and then we'll make a new one)
make_button_inputs :: proc(egp: ^gc.ExtendedGamepad) -> [Gamepad_Button]^gc.ControllerButtonInput {
	return {
		.Right_Face_Down    = egp->buttonA(),
		.Right_Face_Right   = egp->buttonB(),
		.Right_Face_Left    = egp->buttonX(),
		.Right_Face_Up      = egp->buttonY(),
		.Left_Shoulder      = egp->leftShoulder(),
		.Right_Shoulder     = egp->rightShoulder(),
		.Left_Trigger       = egp->leftTrigger(),
		.Right_Trigger      = egp->rightTrigger(),
		.Middle_Face_Right  = egp->buttonMenu(),
		.Middle_Face_Middle = nil,
		.Middle_Face_Left   = egp->buttonOptions(),
		.Left_Stick_Press   = egp->leftThumbstickButton(),
		.Right_Stick_Press  = egp->rightThumbstickButton(),
		.Left_Face_Up       = egp->dpad()->up(),
		.Left_Face_Down     = egp->dpad()->down(),
		.Left_Face_Left     = egp->dpad()->left(),
		.Left_Face_Right    = egp->dpad()->right(),
	}
}

when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
	stop_haptic_player :: proc(player: ^^gc.HapticPatternPlayer) {
		if player^ == nil do return

		player^->stopAtTime(gc.TimeImmediate, nil)
		player^->release()
		player^ = nil
	}

	init_haptic_engine :: proc(
		engine: ^^gc.HapticEngine,
		locality: gc.HapticsLocality,
		gamepad: ^Gamepad,
	) -> bool {
		if engine^ != nil do return true

		haptics := gamepad.controller->haptics()
		if haptics == nil do return false

		engine^ = haptics->createEngineWithLocality(locality)
		success := engine^ != nil && engine^->startAndReturnError(nil)

		return success
	}

	create_haptic_player :: proc(left_right: int, intensity: f32, haptics: ^Gamepad_Haptics) {
		pattern: ^gc.HapticPattern

		{
			NS.scoped_autoreleasepool()

			sharpness : f32 = left_right == 0 ? HAPTICS_SHARPNESS_LEFT : HAPTICS_SHARPNESS_RIGHT

			sharpness_param := gc.HapticEventParameter_alloc()->
				initWithParameterID(gc.HapticSharpness, sharpness)
			intensity_param := gc.HapticEventParameter_alloc()->
				initWithParameterID(gc.HapticIntensity, intensity)
			params := [2]^NS.Object{intensity_param, sharpness_param}
			params_array := NS.Array_alloc()->initWithObjects(raw_data(&params), 2)

			event := gc.HapticEvent_alloc()->initWithEventType(
				gc.HapticContinuous,
				params_array,
				0,
				gc.HapticDurationInfinite,
			)
			events := [1]^NS.Object{event}
			events_array := NS.Array_alloc()->initWithObjects(raw_data(&events), 1)

			pattern = gc.HapticPattern_alloc()->initWithEvents(events_array, nil, nil)
			if pattern == nil do return
		}

		haptics.haptic_player_left_right[left_right] = haptics.haptic_engine_left_right[left_right]->
			createPlayerWithPattern(pattern, nil)
		if haptics.haptic_player_left_right[left_right] != nil {
			haptics.haptic_player_left_right[left_right]->startAtTime(gc.TimeImmediate, nil)
		}

	}
}
