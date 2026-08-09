#+build darwin
#+vet explicit-allocators
#+private file

package karl2d

import NS "core:sys/darwin/Foundation"
import CF "core:sys/darwin/CoreFoundation"
import ce "platform_bindings/mac/cocoa_extras"
import gc "platform_bindings/mac/gamecontroller"
import "core:os"
import "base:intrinsics"
import "base:runtime"
import "core:time"
import "core:slice"
import hm "core:container/handle_map"
import "log"

@(private="package")
PLATFORM_MAC :: Platform_Interface {
	state_size = mac_state_size,
	init = mac_init,
	shutdown = mac_shutdown,
	get_window_render_glue = mac_get_window_render_glue,
	get_events = mac_get_events,
	set_window_title = mac_set_window_title,
	set_screen_size = mac_set_screen_size,
	get_screen_width = mac_get_screen_width,
	get_screen_height = mac_get_screen_height,
	set_window_position = mac_set_window_position,
	get_window_scale = mac_get_window_scale,
	set_window_mode = mac_set_window_mode,

	set_cursor_hidden = mac_set_cursor_hidden,
	is_cursor_hidden = mac_is_cursor_hidden,
	set_cursor_locked = mac_set_cursor_locked,
	is_cursor_locked = mac_is_cursor_locked,
	create_custom_cursor = mac_create_custom_cursor,
	set_cursor = mac_set_cursor,
	destroy_custom_cursor = mac_destroy_custom_cursor,

	is_gamepad_active = mac_is_gamepad_active,
	get_gamepad_axis = mac_get_gamepad_axis,
	set_gamepad_vibration = mac_set_gamepad_vibration,
	open_url = mac_open_url,

	set_internal_state = mac_set_internal_state,
}

HAPTICS_SHARPNESS_LEFT  :: 0.1
HAPTICS_SHARPNESS_RIGHT :: 0.9

Mac_State :: struct {
	odin_ctx:         runtime.Context,
	allocator:        runtime.Allocator,
	app:              ^NS.Application,
	window:           ^NS.Window,
	window_mode:      Window_Mode,

	// Cursor visibility (the user's intent). The OS cursor is only actually hidden while
	// the cursor is inside the content area of a key window — see `apply_cursor_state`.
	cursor_hidden:       bool,
	cursor_hidden_by_us: bool,
	cursor_tracker:      NS.id,

	custom_cursors: hm.Dynamic_Handle_Map(Mac_Cursor, Custom_Cursor),

	// The cursor most recently passed to mac_set_cursor. The zero value is Cursor_Shape.Default.
	current_cursor: Cursor,

	cursor_locked: bool,
	mouse_ignore_next_move: bool,

	screen_width:     int,
	screen_height:    int,
	windowed_rect:    NS.Rect,
	events:           [dynamic]Event,

	// for emitting mouse up events after a live resize
	left_mouse_held:  bool,

	window_render_glue: Window_Render_Glue,

	gamepads:           [MAX_GAMEPADS]Gamepad,
	gc_connect_blk:     ^NS.Block,
	gc_disconnect_blk:  ^NS.Block,
}

Mac_Cursor :: struct {
	handle: Custom_Cursor,
	cursor: ^NS.Cursor,

	// Hotspot in physical pixels, as Karl2D takes it. See `mac_build_cursor`.
	hotspot: [2]int,
	built_for_scale: f32,

	// Size in physical pixels.
	width: int,
	height: int,

	// NSBitmapImageRep does not copy the pixel planes it is handed, so a copy of the pixels must
	// stay alive for as long as the cursor does. It is also what the cursor is rebuilt from when
	// the scale changes. The caller's Image is not ours to hold on to.
	pixels: []Color,
}

Gamepad :: struct {
	controller:               ^gc.Controller,
	extended_gamepad:         ^gc.ExtendedGamepad,
	button_inputs:            [Gamepad_Button]^gc.ControllerButtonInput,
	button_was_pressed:       [Gamepad_Button]bool,
	haptic_engine_left_right: [2]^gc.HapticEngine,
	haptic_player_left_right: [2]^gc.HapticPatternPlayer,
	old_intensity_left_right: [2]f32,
}

s: ^Mac_State

mac_state_size :: proc() -> int {
	return size_of(Mac_State)
}

mac_init :: proc(
	platform_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	assert(platform_state != nil)
	s = (^Mac_State)(platform_state)
	s.odin_ctx = context
	s.allocator = allocator
	s.events = make([dynamic]Event, allocator)
	hm.dynamic_init(&s.custom_cursors, allocator)

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

	scale := f32(s.window->backingScaleFactor())
	s.screen_width = int(f32(screen_width) * scale)
	s.screen_height = int(f32(screen_height) * scale)

	mac_set_window_mode(init_options.window_mode)

	// Activate the application
	s.app->activateIgnoringOtherApps(true)
	s.app->finishLaunching()

	// Add already connected controllers
	poll_for_new_controllers()

	// Setup listeners for connected/disconnected controllers
	notificationCenter := NS.NotificationCenter_defaultCenter()

	s.gc_connect_blk = NS.Block_createGlobalWithParam(s, proc "c" (s: rawptr, n: ^NS.Notification) {
		context = (^Mac_State)(s).odin_ctx

		poll_for_new_controllers()
	}, s.allocator)
	notificationCenter->addObserverForName(gc.DidConnectNotification, nil, nil, s.gc_connect_blk)

	s.gc_disconnect_blk = NS.Block_createGlobalWithParam(s, proc "c" (s: rawptr, n: ^NS.Notification) {
		context = (^Mac_State)(s).odin_ctx

		controller := (^gc.Controller)(n->object())
		remove_controller(controller)
	}, s.allocator)
	notificationCenter->addObserverForName(gc.DidDisconnectNotification, nil, nil, s.gc_disconnect_blk)

	application_delegate := NS.application_delegate_register_and_alloc(
		NS.ApplicationDelegateTemplate{
			applicationShouldTerminate = proc(_: ^NS.Application) -> NS.ApplicationTerminateReply {
				append(&s.events, Event_Close_Window_Requested{})
				return .TerminateCancel
			},
		},
		"Karl2DApplicationDelegate",
		context,
	)

	s.app->setDelegate(application_delegate)

	// Setup delegates for events not handled in mac_process_events
	window_delegates := NS.window_delegate_register_and_alloc(
		NS.WindowDelegateTemplate{
			windowDidResize = proc(_: ^NS.Notification) {
				content_rect := s.window->contentLayoutRect()
				scale := f32(s.window->backingScaleFactor())
				new_width := int(f32(content_rect.size.width) * scale)
				new_height := int(f32(content_rect.size.height) * scale)
	
				if new_width != s.screen_width || new_height != s.screen_height {
					s.screen_width = new_width
					s.screen_height = new_height
					if s.window_mode != .Borderless_Fullscreen {
						s.windowed_rect = content_rect
					}
					append(&s.events, Event_Screen_Resize{
						width = s.screen_width,
						height = s.screen_height,
					})
				}
			},

			windowShouldClose = proc(_: ^NS.Window) -> bool {
				append(&s.events, Event_Close_Window_Requested{})
				return true
			},

			// Focus and unfocus events
			windowDidBecomeKey = proc(_: ^NS.Notification) {
				apply_cursor_state()
				append(&s.events, Event_Window_Focused{})
			},

			windowDidResignKey = proc(_: ^NS.Notification) {
				// Tracking is NSTrackingActiveInKeyWindow, so mouseExited won't fire on focus
				// loss. Restore the OS cursor so it stays visible in other apps / the menu bar.
				unhide_cursor_now()
				append(&s.events, Event_Window_Unfocused{})
			},

			windowDidEndLiveResize = proc(_: ^NS.Notification) {
				pressed := ce.Event_pressedMouseButtons()

				if s.left_mouse_held && (pressed & 1) == 0 {
					append(&s.events, Event_Mouse_Button_Went_Up{button = .Left})
					s.left_mouse_held = false
				}
			},

			windowDidChangeBackingProperties = proc(_: ^NS.Notification) {
				new_scale := f32(s.window->backingScaleFactor())
				content_rect := s.window->contentLayoutRect()
				s.screen_width = int(f32(content_rect.size.width) * new_scale)
				s.screen_height = int(f32(content_rect.size.height) * new_scale)

				append(&s.events, Event_Window_Scale_Changed{
					scale = new_scale,
					screen_width = s.screen_width,
					screen_height = s.screen_height,
				})
			},
		},
		"Karl2DWindowDelegate",
		context,
	)

	s.window->setDelegate(window_delegates)

	install_cursor_tracker()

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_mac_gl_glue(s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Mac platform and render backend '" + RENDER_BACKEND_NAME + "'")
	}

	if init_options.disable_auto_scale_hint {
		log.warn("disable_auto_scale_hint not supported on mac")
	}
}

mac_shutdown :: proc() {
	for it := hm.dynamic_iterator_make(&s.custom_cursors); cd, _ in hm.dynamic_iterate(&it) {
		cd.cursor->release()
		delete(cd.pixels, s.allocator)
	}
	hm.dynamic_destroy(&s.custom_cursors)

	if s.window != nil {
		s.window->close()
	}
	delete(s.events)
	a := s.allocator
	free(s.gc_connect_blk, a)
	free(s.gc_disconnect_blk, a)
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
			s.left_mouse_held = true
			append(&s.events, Event_Mouse_Button_Went_Down{button = .Left})

		case .LeftMouseUp:
			s.left_mouse_held = false
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
			if s.mouse_ignore_next_move {
				s.mouse_ignore_next_move = false
				break
			}

			event_window := event->window()

			// event_window is nil when the cursor is outside all windows —
			// in that case locationInWindow() returns screen coords, so convert.
			// If the event belongs to a completely different window, skip it.
			loc: NS.Point
			if event_window == s.window {
				loc = event->locationInWindow()
			} else if event_window == nil {
				loc = s.window->convertPointFromScreen(event->locationInWindow())
			} else {
				break
			}

			// locationInWindow returns points; scale to pixels to match screen_width/height
			scale := NS.Float(s.window->backingScaleFactor())
			px := loc.x * scale
			py := NS.Float(s.screen_height) - loc.y * scale
			
			if s.cursor_locked {
				dx := f32(ce.Event_deltaX(event)) * f32(s.window->backingScaleFactor())
				dy := f32(ce.Event_deltaY(event)) * f32(s.window->backingScaleFactor())
				cx := f32(s.screen_width/2)
				cy := f32(s.screen_height/2)
				append(&s.events, Event_Mouse_Move { position = { cx + dx, cy + dy}})
				append(&s.events, Event_Mouse_Teleported { position = { cx, cy }})
			} else {
				append(&s.events, Event_Mouse_Move { position = { f32(px), f32(py) }})
			}

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

mac_get_screen_width :: proc() -> int {
	return s.screen_width
}

mac_get_screen_height :: proc() -> int {
	return s.screen_height
}

mac_set_window_title :: proc(title: string) {
	title_str := NS.String_alloc()->initWithOdinString(title)
	s.window->setTitle(title_str)
}

mac_set_window_position :: proc(x: int, y: int) {
	// macOS uses bottom-left origin for screen coordinates
	origin := NS.Point{NS.Float(x), NS.Float(y)}
	s.window->setFrameOrigin(origin)
}

mac_set_screen_size :: proc(w, h: int) {
	scale := mac_get_window_scale()
	s.screen_width = int(f32(w) * scale)
	s.screen_height = int(f32(h) * scale)
	ce.Window_setContentSize(s.window, {NS.Float(w), NS.Float(h)})
}

mac_get_window_scale :: proc() -> f32 {
	return f32(s.window->backingScaleFactor())
}

mac_set_cursor_hidden :: proc(hidden: bool) {
	s.cursor_hidden = hidden
	apply_cursor_state()
}

mac_is_cursor_hidden :: proc() -> bool {
	return s.cursor_hidden
}

mac_set_cursor_locked :: proc(locked: bool) {
	s.cursor_locked = locked

	if locked {
		s.mouse_ignore_next_move = true
		ce.CGAssociateMouseAndMouseCursorPosition(false)
		_mac_teleport_cursor_to_center()
	} else {
		ce.CGAssociateMouseAndMouseCursorPosition(true)
	}
}

mac_is_cursor_locked :: proc() -> bool {
	return s.cursor_locked
}

_mac_teleport_cursor_to_center :: proc() {
	cx := s.screen_width/2
	cy := s.screen_height/2
	scale := mac_get_window_scale()
	frame := s.window->frame()
	x := f64(frame.origin.x) + f64(cx)/f64(scale)
	y := f64(frame.origin.y) + f64(s.screen_height)/f64(scale) - f64(cy)/f64(scale)
	ce.CGWarpMouseCursorPosition({x, y})

	append(&s.events, Event_Mouse_Teleported {
		position = {f32(cx), f32(cy)},
	})
}

// NSCursor.hide/unhide are reference counted. These helpers ensure each hide is paired
// with exactly one unhide so the counter never drifts.
hide_cursor_now :: proc() {
	if !s.cursor_hidden_by_us {
		NS.Cursor.hide()
		s.cursor_hidden_by_us = true
	}
}

unhide_cursor_now :: proc() {
	if s.cursor_hidden_by_us {
		NS.Cursor.unhide()
		s.cursor_hidden_by_us = false
	}
}

cursor_in_content_area :: proc() -> bool {
	view := s.window->contentView()
	if view == nil do return false
	pos := ce.Window_mouseLocationOutsideOfEventStream(s.window)
	return bool(ce.View_mouse_inRect(view, pos, ce.View_frame(view)))
}

apply_cursor_state :: proc() {
	if s.cursor_hidden && cursor_in_content_area() {
		hide_cursor_now()
	} else {
		unhide_cursor_now()
	}
}

install_cursor_tracker :: proc() {
	view := s.window->contentView()
	if view == nil do return

	class_name := cstring("Karl2DCursorTracker")
	class := NS.objc_lookUpClass(class_name)
	if class == nil {
		class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), class_name, 0)
		NS.class_addMethod(class, intrinsics.objc_find_selector("mouseEntered:"), auto_cast cursor_tracker_mouse_entered, "v@:@")
		NS.class_addMethod(class, intrinsics.objc_find_selector("mouseExited:"),  auto_cast cursor_tracker_mouse_exited,  "v@:@")
		NS.objc_registerClassPair(class)
	}

	s.cursor_tracker = NS.class_createInstance(class, 0)

	options := ce.TRACKING_MOUSE_ENTERED_AND_EXITED |
	           ce.TRACKING_ACTIVE_IN_KEY_WINDOW |
	           ce.TRACKING_IN_VISIBLE_RECT |
	           ce.TRACKING_ASSUME_INSIDE
	area := ce.TrackingArea_alloc()
	area  = ce.TrackingArea_initWithRect(area, ce.View_frame(view), options, s.cursor_tracker, nil)
	ce.View_addTrackingArea(view, area)
}

cursor_tracker_mouse_entered :: proc "c" (self: NS.id, cmd: NS.SEL, event: NS.id) {
	context = s.odin_ctx
	if s.cursor_hidden {
		hide_cursor_now()
	}
}

cursor_tracker_mouse_exited :: proc "c" (self: NS.id, cmd: NS.SEL, event: NS.id) {
	context = s.odin_ctx
	unhide_cursor_now()
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
	case .None: return 0
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

		// early stop so we shutoff player even if delta isn't past the threshold
		if left < 0.01 {
			stop_haptic_player(&gamepad.haptic_player_left_right[0])
		}
		if right < 0.01 {
			stop_haptic_player(&gamepad.haptic_player_left_right[1])
		}

		// activation threshold, so we don't thrash needlessly (we can tweak this)
		d_intensity_left  := abs(gamepad.old_intensity_left_right[0] - left)
		d_intensity_right := abs(gamepad.old_intensity_left_right[1] - right)
		if abs(d_intensity_left) < .10 && abs(d_intensity_right) < .10 {
			return
		}

		gamepad.old_intensity_left_right = {left, right}

		// prep for new player
		for &player in gamepad.haptic_player_left_right {
			stop_haptic_player(&player)
		}

		// Lazy-init haptic engine
		left_initted := init_haptic_engine(
			&gamepad.haptic_engine_left_right[0],
			gc.LeftHandle,
			gamepad,
		)
		right_initted := init_haptic_engine(
			&gamepad.haptic_engine_left_right[1],
			gc.RightHandle,
			gamepad,
		)

		if !left_initted && !right_initted do return

		create_haptic_player(0, left, gamepad)
		create_haptic_player(1, right, gamepad)
	}
}

mac_open_url :: proc(url: string) -> bool {
	process, process_err := os.process_start(
		{
			command = {
				"open",
				url,
			},
		},
	)

	if process_err != nil {
		return false
	}

	process_state, _ := os.process_wait(process, 1 * time.Second)

	if !process_state.exited {
		_ = os.process_terminate(process)
		return false
	}

	return process_state.exit_code == 0
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

		scale := mac_get_window_scale()
		s.screen_width  = int(f32(content_rect.width) * scale)
		s.screen_height = int(f32(content_rect.height) * scale)
	}
}

mac_create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> Custom_Cursor {
	cursor := Mac_Cursor {
		pixels  = slice.clone(image.pixels, s.allocator),
		width   = image.width,
		height  = image.height,
		hotspot = hotspot,
	}
	mac_build_cursor(&cursor)

	handle, add_err := hm.add(&s.custom_cursors, cursor)

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		cursor.cursor->release()
		delete(cursor.pixels, s.allocator)
		return {}
	}

	return handle
}

// A cursor image is sized in physical pixels, like everything else in Karl2D, but an NSImage is
// sized in points. Without dividing by the backing scale factor a 128x128 cursor would cover
// 256x256 physical pixels on a Retina display, i.e. twice the size of a 128x128 sprite drawn by
// the game, and it would be blurry from being upscaled on the way there.
//
// Neither the size of an NSImage nor the hotspot of an NSCursor can be changed after the fact, so
// this builds the cursor from scratch whenever the scale changes.
mac_build_cursor :: proc(cursor: ^Mac_Cursor) {
	// Released at the end, so that the cursor being replaced stays alive until its replacement
	// exists. It may still be the one on screen at this point.
	old := cursor.cursor

	scale := mac_get_window_scale()

	planes := [?]^u8 {(^u8)(raw_data(cursor.pixels))}

	rep := NS.BitmapImageRep_alloc()->initWithBitmapDataPlanes(
		&planes[0],
		NS.Integer(cursor.width),
		NS.Integer(cursor.height),
		8, 4, true, false,
		NS.DeviceRGBColorSpace,
		NS.BitmapFormatFlags{.AlphaNonpremultiplied},
		NS.Integer(cursor.width * 4),
		32,
	)
	defer rep->release()

	ns_image := NS.Image_alloc()->initWithSize({
		CF.CGFloat(f32(cursor.width) / scale),
		CF.CGFloat(f32(cursor.height) / scale),
	})
	ns_image->addRepresentation((^NS.ImageRep)(rep))
	defer ns_image->release()

	// The hotspot is in the image's coordinate system, so it is in points too.
	cursor.cursor = NS.Cursor_alloc()->initWithImage(ns_image, {
		CF.CGFloat(f32(cursor.hotspot.x) / scale),
		CF.CGFloat(f32(cursor.hotspot.y) / scale),
	})

	cursor.built_for_scale = scale

	if old != nil {
		old->release()
	}
}

mac_set_cursor :: proc(cursor: Cursor) {
	// Reject a stale handle before storing it, so the cursor on screen is left alone on a
	// programming error rather than silently reverting to the default.
	if c, is_custom := cursor.(Custom_Cursor); is_custom {
		if hm.get(&s.custom_cursors, c) == nil {
			log.errorf("Trying to set invalid cursor %v. It may have been destroyed.", c)
			return
		}
	}

	s.current_cursor = cursor
	mac_apply_cursor()
}

// Sets the OS cursor from s.current_cursor, falling back to the default arrow when a custom
// cursor no longer resolves (it was destroyed while on screen).
mac_apply_cursor :: proc() {
	switch c in s.current_cursor {
	case Cursor_Shape:
		mac_cursor_shape(c)->set()

	case Custom_Cursor:
		cd := hm.get(&s.custom_cursors, c)

		if cd == nil {
			mac_cursor_shape(.Default)->set()
			return
		}

		// The scale can change while the game runs, for instance when the window is moved to a
		// monitor with different DPI settings.
		if cd.built_for_scale != mac_get_window_scale() {
			mac_build_cursor(cd)
		}

		cd.cursor->set()
	}
}

// The returned cursor is a shared one owned by AppKit, so it must not be released.
mac_cursor_shape :: proc(shape: Cursor_Shape) -> ^NS.Cursor {
	switch shape {
	case .Default:     return NS.Cursor_arrowCursor()
	case .Text:        return NS.Cursor_IBeamCursor()
	case .Hand:        return NS.Cursor_pointingHandCursor()
	case .Crosshair:   return ce.Cursor_crosshairCursor()
	case .Move:        return ce.Cursor_closedHandCursor()
	case .Resize_EW:   return ce.Cursor_resizeLeftRightCursor()
	case .Resize_NS:   return ce.Cursor_resizeUpDownCursor()
	case .Not_Allowed: return ce.Cursor_operationNotAllowedCursor()

	// AppKit has no public busy cursor and no public diagonal resize cursors. The private
	// selectors that do exist aren't worth shipping in a library, so these show the arrow.
	case .Wait, .Progress, .Resize_NESW, .Resize_NWSE:
		return NS.Cursor_arrowCursor()
	}

	return NS.Cursor_arrowCursor()
}

mac_destroy_custom_cursor :: proc(custom_cursor: Custom_Cursor) {
	cd := hm.get(&s.custom_cursors, custom_cursor)

	if cd == nil {
		log.errorf(
			"Trying to destroy invalid cursor %v. It may already be destroyed.",
			custom_cursor,
		)
		return
	}

	cd.cursor->release()
	delete(cd.pixels, s.allocator)
	hm.remove(&s.custom_cursors, custom_cursor)

	// If that was the cursor on screen it no longer resolves, so re-applying falls back to the
	// default. Cheap enough to do unconditionally.
	mac_apply_cursor()
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
	for &gamepad in s.gamepads {
		if gamepad.controller == controller {
			// haptic support is only available in 11.0.0
			when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
				for &engine in gamepad.haptic_engine_left_right {
					if engine != nil {
						engine->stopWithCompletionHandler(nil)
						engine->release()
					}
				}
				for &player in gamepad.haptic_player_left_right {
					stop_haptic_player(&player)
				}
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
		.None               = nil,
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

	create_haptic_player :: proc(left_right: int, intensity: f32, gamepad: ^Gamepad) {
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

		gamepad.haptic_player_left_right[left_right] = gamepad.haptic_engine_left_right[left_right]->
			createPlayerWithPattern(pattern, nil)
		if gamepad.haptic_player_left_right[left_right] != nil {
			gamepad.haptic_player_left_right[left_right]->startAtTime(gc.TimeImmediate, nil)
		}

	}
}
