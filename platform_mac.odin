#+build darwin
#+vet explicit-allocators
#+private package

package karl2d

import NS "vendor:darwin/AppKit"
import CG "core:sys/darwin/CoreGraphics"
import ObjC "core:sys/darwin/ObjectiveC"
import gc "vendor:darwin/GameController"
import CH "vendor:darwin/CoreHaptics"
import "core:os"
import "base:intrinsics"
import "base:runtime"
import "core:time"
import "core:slice"
import "core:strings"
import hm "core:container/handle_map"
import "log"

PLATFORM_MAC :: Platform_Interface {
	init = mac_init,
	shutdown = mac_shutdown,
	get_window_render_glue = mac_get_window_render_glue,
	get_events = mac_get_events,
	before_present = mac_before_present,
	set_window_title = mac_set_window_title,
	set_screen_size = mac_set_screen_size,
	get_screen_width = mac_get_screen_width,
	get_screen_height = mac_get_screen_height,
	set_window_position = mac_set_window_position,
	get_window_position = mac_get_window_position,
	get_window_scale = mac_get_window_scale,
	set_window_mode = mac_set_window_mode,
	get_window_mode = mac_get_window_mode,
	set_window_icon = mac_set_window_icon,
	get_monitors = mac_get_monitors,
	get_window_monitor = mac_get_window_monitor,
	set_window_monitor = mac_set_window_monitor,

	set_cursor_hidden = mac_set_cursor_hidden,
	is_cursor_hidden = mac_is_cursor_hidden,
	set_mouse_locked = mac_set_mouse_locked,
	is_mouse_locked = mac_is_mouse_locked,
	create_custom_cursor = mac_create_custom_cursor,
	set_cursor = mac_set_cursor,
	destroy_custom_cursor = mac_destroy_custom_cursor,

	is_gamepad_active = mac_is_gamepad_active,
	get_gamepad_axis = mac_get_gamepad_axis,
	set_gamepad_vibration = mac_set_gamepad_vibration,
	open_url = mac_open_url,
}

MAC_HAPTICS_SHARPNESS_LEFT  :: 0.1
MAC_HAPTICS_SHARPNESS_RIGHT :: 0.9
MAC_HAPTICS_TIME_IMMEDIATE  :: 0

Mac_State :: struct {
	using _: Platform_State,

	odin_ctx: runtime.Context,
	allocator: runtime.Allocator,
	app: ^NS.Application,
	window: ^NS.Window,
	window_mode: Window_Mode,

	// Cursor visibility (the user's intent). The OS cursor is only actually hidden while
	// the cursor is inside the content area of a key window — see `mac_apply_cursor_state`.
	cursor_hidden: bool,
	cursor_hidden_by_us: bool,
	cursor_tracker: NS.id,

	custom_cursors: hm.Dynamic_Handle_Map(Mac_Cursor, Custom_Cursor),

	// The cursor most recently passed to mac_set_cursor. The zero value is Standard_Cursor.Default.
	current_cursor: Cursor,

	mouse_locked: bool,
	mouse_ignore_next_move: bool,

	screen_width: int,
	screen_height: int,
	windowed_rect: NS.Rect,
	events: [dynamic]Event,

	// for emitting mouse up events after a live resize
	left_mouse_held: bool,

	// macOS reports modifier keys as flag changes, not key up/down. Tracks which ones we've
	// already reported as held so we can tell a press from a release. See `.FlagsChanged`.
	modifier_key_is_held: #sparse [Keyboard_Key]bool,

	window_render_glue: ^Window_Render_Glue,

	// The application icon and the pixels it was built from. Both nil until
	// `mac_set_window_icon` runs.
	icon: ^NS.Image,
	icon_pixels: []Color,

	gamepads: [MAX_GAMEPADS]Mac_Gamepad,
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

Mac_Gamepad :: struct {
	controller: ^gc.Controller,
	extended_gamepad: ^gc.ExtendedGamepad,
	button_inputs: [Gamepad_Button]^gc.ControllerButtonInput,
	button_was_pressed: [Gamepad_Button]bool,
	haptic_engine_left_right: [2]^CH.HapticEngine,
	haptic_player_left_right: [2]^CH.HapticPatternPlayer,
	old_intensity_left_right: [2]f32,
}

mac_init :: proc(
	s: ^Mac_State,
	screen_width: int,
	screen_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s.odin_ctx = context
	s.allocator = allocator
	s.events = make([dynamic]Event, allocator)
	hm.dynamic_init(&s.custom_cursors, allocator)

	// Initialize NSApplication
	s.app = NS.Application_sharedApplication()
	s.app->setActivationPolicy(.Regular)

	NS.scoped_autoreleasepool()

	// Menu bar, needed for manually quitting
	menu_bar := NS.Menu.alloc()->init()
	s.app->setMainMenu(menu_bar)
	app_menu_item := menu_bar->addItemWithTitle(NS.AT(""), nil, NS.AT(""))

	app_menu := NS.Menu.alloc()->init()
	app_menu->addItemWithTitle(NS.AT("Quit"), ObjC.sel_registerName("terminate:"), NS.AT("q"))
	app_menu_item->setSubmenu(app_menu)
	intrinsics.objc_send(nil, s.app, "setAppleMenu:", app_menu)

	// Create the window
	rect := NS.Rect {
		origin = {0, 0},
		size = {NS.Float(screen_width), NS.Float(screen_height)},
	}
	s.window = NS.Window.alloc()

	style := NS.WindowStyleMask{.Titled, .Closable, .Miniaturizable}
	s.window = s.window->initWithContentRect(rect, style, .Buffered, false)
	s.windowed_rect = rect


	title_str := NS.String.alloc()->initWithOdinString(window_title)
	s.window->setTitle(title_str)

	s.window->center()

	if init_options.monitor != MONITOR_NONE {
		monitor_screen := mac_find_screen(init_options.monitor)

		if monitor_screen == nil {
			log.errorf(
				"Cannot use monitor %v, it does not exist. Using the default monitor.",
				init_options.monitor,
			)
		} else {
			monitor_visible_frame := monitor_screen->visibleFrame()
			window_frame := s.window->frame()

			s.window->setFrameOrigin({
				monitor_visible_frame.origin.x +
				(monitor_visible_frame.size.width - window_frame.size.width)/2,
				monitor_visible_frame.origin.y +
				(monitor_visible_frame.size.height - window_frame.size.height)/2,
			})
		}
	}

	s.window->setAcceptsMouseMovedEvents(true)
	s.window->makeKeyAndOrderFront(nil)

	scale := f32(s.window->backingScaleFactor())
	s.screen_width = int(f32(screen_width) * scale)
	s.screen_height = int(f32(screen_height) * scale)

	mac_set_window_mode(s, init_options.window_mode)

	// Activate the application
	s.app->activateIgnoringOtherApps(true)
	s.app->finishLaunching()

	// Add already connected controllers
	mac_poll_for_new_controllers(s)

	// Setup listeners for connected/disconnected controllers
	notificationCenter := NS.NotificationCenter.defaultCenter()

	gc_connect_blk := intrinsics.objc_block(s, proc "c" (n: ^NS.Notification, s: ^Mac_State) {
		context = s.odin_ctx

		mac_poll_for_new_controllers(s)
	})
	notificationCenter->addObserverForName(gc.ControllerDidConnectNotification, nil, nil, gc_connect_blk)

	gc_disconnect_blk := intrinsics.objc_block(s, proc "c" (n: ^NS.Notification, s: ^Mac_State) {
		context = s.odin_ctx

		controller := (^gc.Controller)(n->object())
		mac_remove_controller(s, controller)
	})
	notificationCenter->addObserverForName(gc.ControllerDidDisconnectNotification, nil, nil, gc_disconnect_blk)

	delegate_context := context
	delegate_context.user_ptr = s

	application_delegate := NS.application_delegate_register_and_alloc(
		NS.ApplicationDelegateTemplate{
			applicationShouldTerminate = proc(_: ^NS.Application) -> NS.ApplicationTerminateReply {
				s := (^Mac_State)(context.user_ptr)

				append(&s.events, Event_Close_Window_Requested{})
				return .Cancel
			},
		},
		"Karl2DApplicationDelegate",
		delegate_context,
	)

	s.app->setDelegate(application_delegate)

	// Setup delegates for events not handled in mac_process_events
	window_delegates := NS.window_delegate_register_and_alloc(
		NS.WindowDelegateTemplate{
			windowDidResize = proc(_: ^NS.Notification) {
				s := (^Mac_State)(context.user_ptr)

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
				s := (^Mac_State)(context.user_ptr)

				append(&s.events, Event_Close_Window_Requested{})

				// Returning true closes the window, which also releases it. It's up to the
				// application to decide what a close request means, it may want to show a
				// confirmation dialogue. The window is closed in `mac_shutdown`.
				return false
			},

			// Focus and unfocus events
			windowDidBecomeKey = proc(_: ^NS.Notification) {
				s := (^Mac_State)(context.user_ptr)

				mac_apply_cursor_state(s)
				append(&s.events, Event_Window_Focused{})
			},

			windowDidResignKey = proc(_: ^NS.Notification) {
				s := (^Mac_State)(context.user_ptr)

				// Tracking is NSTrackingActiveInKeyWindow, so mouseExited won't fire on focus
				// loss. Restore the OS cursor so it stays visible in other apps / the menu bar.
				mac_unhide_cursor_now(s)
				append(&s.events, Event_Window_Unfocused{})
				s.modifier_key_is_held = {}
			},

			windowDidEndLiveResize = proc(_: ^NS.Notification) {
				s := (^Mac_State)(context.user_ptr)

				pressed := NS.Event.pressedMouseButtons()

				if s.left_mouse_held && (pressed & 1) == 0 {
					append(&s.events, Event_Mouse_Button_Went_Up{button = .Left})
					s.left_mouse_held = false
				}
			},

			windowDidChangeBackingProperties = proc(_: ^NS.Notification) {
				s := (^Mac_State)(context.user_ptr)

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
		delegate_context,
	)

	s.window->setDelegate(window_delegates)

	mac_install_cursor_tracker(s)

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = create_mac_gl_glue(s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Mac platform and render backend '" + RENDER_BACKEND_NAME + "'")
	}

	if init_options.disable_auto_scale_hint {
		log.warn("disable_auto_scale_hint not supported on mac")
	}
}

mac_shutdown :: proc(s: ^Mac_State) {
	for it := hm.dynamic_iterator_make(&s.custom_cursors); cd, _ in hm.dynamic_iterate(&it) {
		cd.cursor->release()
		delete(cd.pixels, s.allocator)
	}
	hm.dynamic_destroy(&s.custom_cursors)

	if s.icon != nil {
		s.icon->release()
		delete(s.icon_pixels, s.allocator)
		s.icon = nil
	}

	if s.window != nil {
		s.window->close()
	}
	delete(s.events)
}

mac_get_window_render_glue :: proc(s: ^Mac_State) -> ^Window_Render_Glue {
	return s.window_render_glue
}

mac_before_present :: proc(s: ^Mac_State) {
}

mac_get_events :: proc(s: ^Mac_State, events: ^[dynamic]Event) {
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
			key := mac_keycode_to_k2key(event->keyCode())

			if key != .None {
				if event->isARepeat() {
					append(&s.events, Event_Key_Repeat{key = key})
				} else {
					append(&s.events, Event_Key_Went_Down{key = key})
				}
			}

			// Note: `characters()` gives us the text produced by the current keyboard layout, but
			// it doesn't run the input method, so dead keys / accent composition (for example
			// option-e then e to get "e" with an acute accent) won't compose correctly. Doing
			// that properly would require `interpretKeyEvents:` and `insertText:`.
			if event->modifierFlags() & {.Command} == {} {
				for r in event->characters()->odinString() {
					if is_typable_rune(r) && !mac_is_function_key_rune(r) {
						append(&s.events, Event_Typed_Rune{typed = r})
					}
				}
			}

		case .KeyUp:
			key := mac_keycode_to_k2key(event->keyCode())
			if key != .None {
				append(&s.events, Event_Key_Went_Up{key = key})
			}

		case .FlagsChanged:
			key := mac_keycode_to_k2key(event->keyCode())
			flags := event->modifierFlags()
			is_held := false
			is_modifier := true
			#partial switch key {
			case .Left_Shift, .Right_Shift:     is_held = .Shift in flags
			case .Left_Control, .Right_Control: is_held = .Control in flags
			case .Left_Alt, .Right_Alt:         is_held = .Option in flags
			case .Left_Super, .Right_Super:     is_held = .Command in flags
			case .Caps_Lock:                    is_held = .CapsLock in flags
			case:
				// Not one of the modifier keys above (includes .None); FlagsChanged has nothing
				// useful to say about it, so don't synthesize a key event for it.
				is_modifier = false
			}

			if is_modifier {
				// Left and right share a single modifier flag, so the flag being set doesn't
				// mean _this_ key went down: the other side may still be held. The keycode says
				// which key changed, so if we already had it down, this event must be its release.
				if is_held && s.modifier_key_is_held[key] {
					is_held = false
				}
				s.modifier_key_is_held[key] = is_held
				if is_held {
					append(&s.events, Event_Key_Went_Down{key = key})
				} else {
					append(&s.events, Event_Key_Went_Up{key = key})
				}
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
			
			if s.mouse_locked {
				dx := f32(event->deltaX()) * f32(s.window->backingScaleFactor())
				dy := f32(event->deltaY()) * f32(s.window->backingScaleFactor())
				cx := f32(s.screen_width/2)
				cy := f32(s.screen_height/2)
				append(&s.events, Event_Mouse_Move { position = { cx + dx, cy + dy}})
				append(&s.events, Event_Mouse_Teleported { position = { cx, cy }})
			} else {
				append(&s.events, Event_Mouse_Move { position = { f32(px), f32(py) }})
			}

		case .ScrollWheel:
			delta := f32(event->scrollingDeltaY())
			// AppKit measures the horizontal wheel to the left, so that one gets flipped.
			delta_horizontal := f32(-event->scrollingDeltaX())

			// Normalize: trackpad gives precise deltas, mouse wheel gives line deltas
			if event->hasPreciseScrollingDeltas() {
				delta /= 10.0
				delta_horizontal /= 10.0
			}

			append(&s.events, Event_Mouse_Wheel{delta = delta})

			// A vertical-only scroll reports zero here, which is not worth an event.
			if delta_horizontal != 0 {
				append(&s.events, Event_Mouse_Wheel_Horizontal{delta = delta_horizontal})
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

mac_get_screen_width :: proc(s: ^Mac_State) -> int {
	return s.screen_width
}

mac_get_screen_height :: proc(s: ^Mac_State) -> int {
	return s.screen_height
}

mac_set_window_title :: proc(s: ^Mac_State, title: string) {
	title_str := NS.String.alloc()->initWithOdinString(title)
	s.window->setTitle(title_str)
}

mac_set_window_position :: proc(s: ^Mac_State, x: int, y: int) {
	// macOS uses bottom-left origin for screen coordinates
	origin := NS.Point{NS.Float(x), NS.Float(y)}
	s.window->setFrameOrigin(origin)
}

mac_get_window_position :: proc(s: ^Mac_State) -> Vec2 {
	// macOS uses bottom-left origin for screen coordinates
	origin := s.window->frame().origin
	return {f32(origin.x), f32(origin.y)}
}

mac_set_screen_size :: proc(s: ^Mac_State, w, h: int) {
	scale := mac_get_window_scale(s)
	s.screen_width = int(f32(w) * scale)
	s.screen_height = int(f32(h) * scale)
	s.window->setContentSize({NS.Float(w), NS.Float(h)})
}

mac_get_window_scale :: proc(s: ^Mac_State) -> f32 {
	return f32(s.window->backingScaleFactor())
}

mac_get_monitors :: proc(s: ^Mac_State, allocator: runtime.Allocator) -> []Monitor_Info {
	NS.scoped_autoreleasepool()

	if s == nil {
		NS.Application_sharedApplication()
	}

	screens := NS.Screen.screens()
	monitors := make([dynamic]Monitor_Info, 0, int(screens->count()), allocator)
	main_display := CG.MainDisplayID()

	for screen_idx in 0..<screens->count() {
		screen := (^NS.Screen)(screens->objectAtIndex(screen_idx))
		display := CG.DirectDisplayID(mac_screen_monitor_id(screen))
		scale := f32(screen->backingScaleFactor())
		frame := screen->frame()
		physical_size_mm := CG.DisplayScreenSize(display)

		size := [2]int {
			int(f32(frame.size.width) * scale),
			int(f32(frame.size.height) * scale),
		}

		physical_size := [2]int {
			int(physical_size_mm.width + 0.5),
			int(physical_size_mm.height + 0.5),
		}

		if (size.x > size.y && physical_size.x < physical_size.y) ||
		   (size.x < size.y && physical_size.x > physical_size.y) {
			physical_size = {physical_size.y, physical_size.x}
		}

		name, name_err := strings.clone(screen->localizedName()->odinString(), allocator)

		if name_err != nil {
			log.errorf("Failed listing monitors: Copying the name failed with %v", name_err)

			for m in monitors {
				delete(m.name, allocator)
			}

			delete(monitors)
			return nil
		}

		append(&monitors, Monitor_Info {
			id = Monitor_Id(display),
			name = name,
			position = {int(frame.origin.x), int(frame.origin.y)},
			size = size,
			physical_size = physical_size,
			scale = scale,
			primary = display == main_display,
		})
	}

	return monitors[:]
}

mac_get_window_monitor :: proc(s: ^Mac_State) -> Monitor_Id {
	NS.scoped_autoreleasepool()
	screen := s.window->screen()

	if screen == nil {
		return MONITOR_NONE
	}

	return mac_screen_monitor_id(screen)
}

mac_set_window_monitor :: proc(s: ^Mac_State, monitor: Monitor_Id) {
	NS.scoped_autoreleasepool()
	screen := mac_find_screen(monitor)

	if screen == nil {
		log.errorf("Cannot move window to monitor %v, it does not exist.", monitor)
		return
	}

	visible_frame := screen->visibleFrame()

	if s.window_mode == .Borderless_Fullscreen {
		s.windowed_rect.origin = {
			visible_frame.origin.x + (visible_frame.size.width - s.windowed_rect.size.width)/2,
			visible_frame.origin.y + (visible_frame.size.height - s.windowed_rect.size.height)/2,
		}

		s.window->setFrame(screen->frame(), true)

		content_rect := s.window->contentLayoutRect()
		scale := mac_get_window_scale(s)
		s.screen_width = int(f32(content_rect.size.width) * scale)
		s.screen_height = int(f32(content_rect.size.height) * scale)
		return
	}

	frame := s.window->frame()

	s.window->setFrameOrigin({
		visible_frame.origin.x + (visible_frame.size.width - frame.size.width)/2,
		visible_frame.origin.y + (visible_frame.size.height - frame.size.height)/2,
	})
}

mac_screen_monitor_id :: proc(screen: ^NS.Screen) -> Monitor_Id {
	device_description := screen->deviceDescription()
	screen_number := (^NS.Number)(device_description->objectForKey(NS.AT("NSScreenNumber")))

	if screen_number == nil {
		return MONITOR_NONE
	}

	return Monitor_Id(screen_number->unsignedIntValue())
}

mac_find_screen :: proc(monitor: Monitor_Id) -> ^NS.Screen {
	screens := NS.Screen.screens()

	for screen_idx in 0..<screens->count() {
		screen := (^NS.Screen)(screens->objectAtIndex(screen_idx))

		if mac_screen_monitor_id(screen) == monitor {
			return screen
		}
	}

	return nil
}

mac_set_cursor_hidden :: proc(s: ^Mac_State, hidden: bool) {
	s.cursor_hidden = hidden
	mac_apply_cursor_state(s)
}

mac_is_cursor_hidden :: proc(s: ^Mac_State) -> bool {
	return s.cursor_hidden
}

mac_set_mouse_locked :: proc(s: ^Mac_State, locked: bool) {
	s.mouse_locked = locked

	if locked {
		s.mouse_ignore_next_move = true
		CG.AssociateMouseAndMouseCursorPosition(false)
		mac_teleport_cursor_to_center(s)
	} else {
		CG.AssociateMouseAndMouseCursorPosition(true)
	}
}

mac_is_mouse_locked :: proc(s: ^Mac_State) -> bool {
	return s.mouse_locked
}

mac_teleport_cursor_to_center :: proc(s: ^Mac_State) {
	cx := s.screen_width/2
	cy := s.screen_height/2
	scale := mac_get_window_scale(s)
	frame := s.window->frame()
	x := f64(frame.origin.x) + f64(cx)/f64(scale)
	y := f64(frame.origin.y) + f64(s.screen_height)/f64(scale) - f64(cy)/f64(scale)
	CG.WarpMouseCursorPosition({CG.Float(x), CG.Float(y)})

	append(&s.events, Event_Mouse_Teleported {
		position = {f32(cx), f32(cy)},
	})
}

// NSCursor.hide/unhide are reference counted. These helpers ensure each hide is paired
// with exactly one unhide so the counter never drifts.
mac_hide_cursor_now :: proc(s: ^Mac_State) {
	if !s.cursor_hidden_by_us {
		NS.Cursor.hide()
		s.cursor_hidden_by_us = true
	}
}

mac_unhide_cursor_now :: proc(s: ^Mac_State) {
	if s.cursor_hidden_by_us {
		NS.Cursor.unhide()
		s.cursor_hidden_by_us = false
	}
}

mac_cursor_in_content_area :: proc(s: ^Mac_State) -> bool {
	view := s.window->contentView()
	if view == nil do return false
	pos := s.window->mouseLocationOutsideOfEventStream()
	return view->mouse(pos, view->frame())
}

mac_apply_cursor_state :: proc(s: ^Mac_State) {
	if s.cursor_hidden && mac_cursor_in_content_area(s) {
		mac_hide_cursor_now(s)
	} else {
		mac_unhide_cursor_now(s)
	}
}

mac_install_cursor_tracker :: proc(s: ^Mac_State) {
	view := s.window->contentView()
	if view == nil do return

	class_name := cstring("Karl2DCursorTracker")
	class := ObjC.objc_lookUpClass(class_name)
	if class == nil {
		class = ObjC.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), class_name, 0)

		mouse_entered :: proc "c" (self: NS.id, cmd: NS.SEL, event: NS.id) {
			s := (^^Mac_State)(ObjC.object_getIndexedIvars(self))^
			context = s.odin_ctx
			if s.cursor_hidden {
				mac_hide_cursor_now(s)
			}
		}

		mouse_exited :: proc "c" (self: NS.id, cmd: NS.SEL, event: NS.id) {
			s := (^^Mac_State)(ObjC.object_getIndexedIvars(self))^
			context = s.odin_ctx
			mac_unhide_cursor_now(s)
		}

		ObjC.class_addMethod(class, intrinsics.objc_find_selector("mouseEntered:"), auto_cast mouse_entered, "v@:@")
		ObjC.class_addMethod(class, intrinsics.objc_find_selector("mouseExited:"),  auto_cast mouse_exited,  "v@:@")
		ObjC.objc_registerClassPair(class)
	}

	s.cursor_tracker = ObjC.class_createInstance(class, size_of(^Mac_State))
	(^^Mac_State)(ObjC.object_getIndexedIvars(s.cursor_tracker))^ = s

	options := NS.TrackingAreaOptions{.MouseEnteredAndExited, .ActiveInKeyWindow, .InVisibleRect, .AssumeInside}
	area := NS.TrackingArea.alloc()->initWithRect(view->frame(), options, s.cursor_tracker, nil)
	view->addTrackingArea(area)
}

mac_is_gamepad_active :: proc(s: ^Mac_State, gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}
	return s.gamepads[gamepad].controller != nil
}

mac_get_gamepad_axis :: proc(s: ^Mac_State, gamepad: int, axis: Gamepad_Axis) -> f32 {
	if !mac_is_gamepad_active(s, gamepad) {
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

mac_set_gamepad_vibration :: proc(s: ^Mac_State, gamepad_index: int, left: f32, right: f32) {
	when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
		if !mac_is_gamepad_active(s, gamepad_index) do return
		gamepad := &s.gamepads[gamepad_index]

		// early stop so we shutoff player even if delta isn't past the threshold
		if left < 0.01 {
			mac_stop_haptic_player(&gamepad.haptic_player_left_right[0])
		}
		if right < 0.01 {
			mac_stop_haptic_player(&gamepad.haptic_player_left_right[1])
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
			mac_stop_haptic_player(&player)
		}

		// Lazy-init haptic engine
		left_initted := mac_init_haptic_engine(
			&gamepad.haptic_engine_left_right[0],
			gc.HapticsLocalityLeftHandle,
			gamepad,
		)
		right_initted := mac_init_haptic_engine(
			&gamepad.haptic_engine_left_right[1],
			gc.HapticsLocalityRightHandle,
			gamepad,
		)

		if !left_initted && !right_initted do return

		mac_create_haptic_player(0, left, gamepad)
		mac_create_haptic_player(1, right, gamepad)
	}
}

mac_open_url :: proc(s: ^Mac_State, url: string) -> bool {
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

mac_get_window_mode :: proc(s: ^Mac_State) -> Window_Mode {
	return s.window_mode
}

mac_set_window_mode :: proc(s: ^Mac_State, window_mode: Window_Mode) {
	if window_mode == s.window_mode {
		return
	}

	old_mode := s.window_mode
	s.window_mode = window_mode
	style := NS.WindowStyleMask{.Titled, .Closable, .Miniaturizable}

	switch window_mode {
	case .Windowed_Resizable:
		style += {.Resizable}
		fallthrough

	case .Windowed:
		s.window->setStyleMask(style)
		if old_mode == .Borderless_Fullscreen {
			s.window->setLevel(NS.NormalWindowLevel)
			s.window->setFrame(s.windowed_rect, true)
			s.app->setPresentationOptions({})
		}

	case .Borderless_Fullscreen:
		s.windowed_rect = s.window->frame()
		s.window->setStyleMask({})
		window_screen := s.window->screen()

		if window_screen == nil {
			window_screen = NS.Screen.mainScreen()
		}

		screen_frame := window_screen->frame()
		s.window->setFrame(screen_frame, true)
		s.window->setLevel(NS.NormalWindowLevel)
		s.app->setPresentationOptions({.HideMenuBar, .HideDock})

		// same as frame() b/c no decorations, but semantically more correct
		content_rect := s.window->contentLayoutRect()

		scale := mac_get_window_scale(s)
		s.screen_width  = int(f32(content_rect.size.width) * scale)
		s.screen_height = int(f32(content_rect.size.height) * scale)
	}
}

// Wraps `pixels` in an NSImage of `point_size` points. The pixels are not copied: they must stay
// alive for as long as the image does, and stay valid RGBA8 with straight alpha.
//
// Returns nil when AppKit rejects the bitmap, which is logged.
mac_make_ns_image :: proc(
	pixels: []Color,
	width: int,
	height: int,
	point_size: NS.Size,
) -> ^NS.Image {
	planes := [?]^u8 {(^u8)(raw_data(pixels))}

	rep := NS.BitmapImageRep.alloc()->initWithBitmapDataPlanes(
		&planes[0],
		NS.Integer(width),
		NS.Integer(height),
		8,
		4,
		true,
		false,
		NS.DeviceRGBColorSpace,
		NS.BitmapFormat{.AlphaNonpremultiplied},
		NS.Integer(width * 4),
		32,
	)

	if rep == nil {
		log.errorf("initWithBitmapDataPlanes failed for a %vx%v image", width, height)
		return nil
	}

	ns_image := NS.Image.alloc()->initWithSize(point_size)
	ns_image->addRepresentation((^NS.ImageRep)(rep))

	// The image retains the representation, so that can go now.
	rep->release()

	return ns_image
}

// macOS windows have no icon of their own, so this sets the application's icon, the one in the
// Dock. It lasts for as long as the process runs. An app bundle takes its icon from the .icns file
// inside it until this replaces it.
mac_set_window_icon :: proc(s: ^Mac_State, image: Image) -> bool {
	// The NSImage points at these rather than copying them, so a copy of the pixels must stay
	// alive for as long as it does.
	pixels := slice.clone(image.pixels, s.allocator)

	// The Dock decides how big to draw the icon, so the size in points only has to carry the
	// aspect ratio of the pixels.
	ns_image := mac_make_ns_image(pixels, image.width, image.height, {
		CG.Float(image.width),
		CG.Float(image.height),
	})

	if ns_image == nil {
		delete(pixels, s.allocator)
		return false
	}

	s.app->setApplicationIconImage(ns_image)

	// The icon that was in the Dock is only safe to release now that this one has replaced it.
	if s.icon != nil {
		s.icon->release()
		delete(s.icon_pixels, s.allocator)
	}

	s.icon = ns_image
	s.icon_pixels = pixels
	return true
}

mac_create_custom_cursor :: proc(
	s: ^Mac_State,
	image: Image,
	hotspot: [2]int,
) -> (
	Custom_Cursor,
	bool,
) {
	cursor := Mac_Cursor {
		pixels  = slice.clone(image.pixels, s.allocator),
		width   = image.width,
		height  = image.height,
		hotspot = hotspot,
	}
	mac_build_cursor(s, &cursor)

	if cursor.cursor == nil {
		delete(cursor.pixels, s.allocator)
		return {}, false
	}

	handle, add_err := hm.add(&s.custom_cursors, cursor)

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		cursor.cursor->release()
		delete(cursor.pixels, s.allocator)
		return {}, false
	}

	return handle, true
}

// Cursor images are in physical pixels, like the rest of Karl2D, but an NSImage is sized in
// points. Without dividing by the backing scale factor a 128x128 cursor would cover 256x256
// physical pixels on a Retina display, and be blurry from the upscale.
//
// Neither an NSImage's size nor an NSCursor's hotspot can be changed after the fact, so this
// rebuilds from scratch whenever the scale changes.
mac_build_cursor :: proc(s: ^Mac_State, cursor: ^Mac_Cursor) {
	// Released at the end, so that the cursor being replaced stays alive until its replacement
	// exists. It may still be the one on screen at this point.
	old := cursor.cursor

	scale := mac_get_window_scale(s)

	ns_image := mac_make_ns_image(cursor.pixels, cursor.width, cursor.height, {
		CG.Float(f32(cursor.width) / scale),
		CG.Float(f32(cursor.height) / scale),
	})

	// Whatever cursor was there stays on.
	if ns_image == nil {
		return
	}

	// The hotspot is in the image's coordinate system, so it is in points too.
	cursor.cursor = NS.Cursor.alloc()->initWithImage(ns_image, {
		CG.Float(f32(cursor.hotspot.x) / scale),
		CG.Float(f32(cursor.hotspot.y) / scale),
	})

	// The NSCursor retains the image, so it can go now.
	ns_image->release()

	cursor.built_for_scale = scale

	if old != nil {
		old->release()
	}
}

mac_set_cursor :: proc(s: ^Mac_State, cursor: Cursor) {
	// Reject a stale handle, so a programming error leaves the cursor alone.
	if c, is_custom := cursor.(Custom_Cursor); is_custom {
		if hm.get(&s.custom_cursors, c) == nil {
			log.errorf("Trying to set invalid cursor %v. It may have been destroyed.", c)
			return
		}
	}

	s.current_cursor = cursor
	mac_apply_cursor(s)
}

// Sets the OS cursor from s.current_cursor, falling back to the default arrow when a custom
// cursor no longer resolves (it was destroyed while on screen).
mac_apply_cursor :: proc(s: ^Mac_State) {
	switch c in s.current_cursor {
	case Standard_Cursor:
		mac_standard_cursor(c)->set()

	case Custom_Cursor:
		cd := hm.get(&s.custom_cursors, c)

		if cd == nil {
			mac_standard_cursor(.Default)->set()
			return
		}

		// The scale can change while the game runs, for instance when the window is moved to a
		// monitor with different DPI settings.
		if cd.built_for_scale != mac_get_window_scale(s) {
			mac_build_cursor(s, cd)
		}

		cd.cursor->set()
	}
}

// The returned cursor is a shared one owned by AppKit, so it must not be released.
mac_standard_cursor :: proc(cursor: Standard_Cursor) -> ^NS.Cursor {
	switch cursor {
	case .Default:     return NS.Cursor.arrowCursor()
	case .Text:        return NS.Cursor.IBeamCursor()
	case .Hand:        return NS.Cursor.pointingHandCursor()
	case .Crosshair:   return NS.Cursor.crosshairCursor()
	case .Move:        return NS.Cursor.closedHandCursor()
	case .Resize_EW:   return NS.Cursor.resizeLeftRightCursor()
	case .Resize_NS:   return NS.Cursor.resizeUpDownCursor()
	case .Not_Allowed: return NS.Cursor.operationNotAllowedCursor()

	// AppKit has no public busy cursor and no public diagonal resize cursors. The private
	// selectors that do exist aren't worth shipping in a library, so these show the arrow.
	case .Wait, .Progress, .Resize_NESW, .Resize_NWSE:
		return NS.Cursor.arrowCursor()
	}

	return NS.Cursor.arrowCursor()
}

mac_destroy_custom_cursor :: proc(s: ^Mac_State, custom_cursor: Custom_Cursor) {
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

	// Falls back to the default if that was the cursor on screen.
	mac_apply_cursor(s)
}

// macOS reports keys that aren't on a standard keyboard (arrows, F1-F35, Home, End, Page Up/Down,
// forward Delete, etc) as characters in the Unicode Private Use Area range U+F700 to U+F8FF. Those
// are not text, so they must not end up as typed runes.
mac_is_function_key_rune :: proc(r: rune) -> bool {
	return r >= 0xf700 && r <= 0xf8ff
}

// Key code mapping from macOS virtual key codes to Keyboard_Key
mac_keycode_to_k2key :: proc(keycode: u16) -> Keyboard_Key {
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

mac_poll_for_new_controllers :: proc(s: ^Mac_State) {
	controllers := gc.Controller.controllers()
	controller_count := controllers != nil ? int(controllers->count()) : 0

	// Simple algorithm:
	// - Remove the controllers that aren't connected anymore (defensive).
	// - If we have MAX_GAMEPADS registered, and they're still connected, don't add new controllers.
	// - Connect new controllers.

	mac_remove_no_longer_connected_controllers(s, controllers, controller_count)

	connected_count := 0
	for gamepad in s.gamepads {
		if gamepad.controller != nil {
			connected_count += 1
		}
	}
	if connected_count >= MAX_GAMEPADS do return

	for i in 0..<controller_count {
		controller := (^gc.Controller)(controllers->object(NS.UInteger(i)))
		if controller == nil do continue

		extended_gamepad := controller->extendedGamepad()
		if extended_gamepad == nil do continue

		if mac_controller_is_registered(s, controller) do continue

		available_slot := 0
		for gamepad, gamepad_index in s.gamepads {
			if gamepad.controller == nil {
				available_slot = gamepad_index
				break
			}
		}
		
		s.gamepads[available_slot].controller = controller
		s.gamepads[available_slot].extended_gamepad = extended_gamepad

		egp := extended_gamepad
		s.gamepads[available_slot].button_inputs = {
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
}

mac_remove_no_longer_connected_controllers :: proc(
	s: ^Mac_State,
	controllers: ^NS.Array,
	count: int,
) {
	found: [MAX_GAMEPADS]bool

	for i in 0..<count {
		controller := (^gc.Controller)(controllers->object(NS.UInteger(i)))
		if controller == nil do continue

		for gamepad, gamepad_index in s.gamepads {
			if gamepad.controller == controller {
				found[gamepad_index] = true
			}
		}
	}

	for gamepad, gamepad_index in s.gamepads {
		if gamepad.controller != nil && !found[gamepad_index] {
			mac_remove_controller(s, gamepad.controller)
		}
	}
}

mac_controller_is_registered :: proc(s: ^Mac_State, controller: ^gc.Controller) -> bool {
	for gamepad in s.gamepads {
		if gamepad.controller == controller {
			return true
		}
	}
	return false
}

mac_remove_controller :: proc(s: ^Mac_State, controller: ^gc.Controller) {
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
					mac_stop_haptic_player(&player)
				}
			}
			
			// no need to release controller, extended_gamepad, or button_inputs;
			// the gamecontroller framework owns the these
			gamepad = {}
			return
		}
	}
}

when ODIN_MINIMUM_OS_VERSION >= 11_00_00 {
	mac_stop_haptic_player :: proc(player: ^^CH.HapticPatternPlayer) {
		if player^ == nil do return

		player^->stopAtTime(MAC_HAPTICS_TIME_IMMEDIATE)
		player^->release()
		player^ = nil
	}

	mac_init_haptic_engine :: proc(
		engine: ^^CH.HapticEngine,
		locality: ^NS.String,
		gamepad: ^Mac_Gamepad,
	) -> bool {
		if engine^ != nil do return true

		haptics := gamepad.controller->haptics()
		if haptics == nil do return false

		engine^ = (^CH.HapticEngine)(haptics->createEngineWithLocality(locality))
		if engine^ == nil do return false

		success, _ := engine^->startAndReturnError()
		return success
	}

	mac_create_haptic_player :: proc(left_right: int, intensity: f32, gamepad: ^Mac_Gamepad) {
		pattern: ^CH.HapticPattern

		{
			NS.scoped_autoreleasepool()

			sharpness : f32 = left_right == 0 ? MAC_HAPTICS_SHARPNESS_LEFT : MAC_HAPTICS_SHARPNESS_RIGHT

			sharpness_param := CH.HapticEventParameter.alloc()->
				initWithParameterID(CH.HapticEventParameterIDHapticSharpness, sharpness)
			intensity_param := CH.HapticEventParameter.alloc()->
				initWithParameterID(CH.HapticEventParameterIDHapticIntensity, intensity)
			params := [2]NS.id{intensity_param, sharpness_param}
			params_array := NS.Array.alloc()->initWithObjects(&params[0], len(params))

			event := CH.HapticEvent.alloc()->initWithEventType(
				CH.HapticEventTypeHapticContinuous,
				params_array,
				0,
				NS.TimeInterval(gc.HapticDurationInfinite),
			)
			events := [1]NS.id{event}
			events_array := NS.Array.alloc()->initWithObjects(&events[0], len(events))

			pattern = CH.HapticPattern.alloc()->initWithEvents_parameters_error(events_array, nil, nil)
			if pattern == nil do return
		}

		gamepad.haptic_player_left_right[left_right], _ = gamepad.haptic_engine_left_right[left_right]->
			createPlayerWithPattern(pattern)
		if gamepad.haptic_player_left_right[left_right] != nil {
			gamepad.haptic_player_left_right[left_right]->startAtTime(MAC_HAPTICS_TIME_IMMEDIATE)
		}

	}
}
