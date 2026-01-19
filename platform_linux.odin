#+build linux
#+private file
package karl2d

import "base:runtime"
import "core:mem"
import "log"
import "core:os"

@(private="package")
PLATFORM_LINUX :: Platform_Interface {
	state_size = linux_state_size,
	init = linux_init,
	shutdown = linux_shutdown,
	get_window_render_glue = linux_get_window_render_glue,
	get_events = linux_get_events,
	get_width = linux_get_width,
	get_height = linux_get_height,
	set_position = linux_set_position,
	set_size = linux_set_size,
	get_window_scale = linux_get_window_scale,
	set_window_mode = linux_set_window_mode,
	is_gamepad_active = linux_is_gamepad_active,
	get_gamepad_axis = linux_get_gamepad_axis,
	set_gamepad_vibration = linux_set_gamepad_vibration,
	set_internal_state = linux_set_internal_state,
}

s: ^Linux_State

linux_state_size :: proc() -> int {
	return size_of(Linux_State)
}

linux_init :: proc(
	window_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	options: Init_Options,
	allocator: runtime.Allocator,
) {
	assert(window_state != nil)
	s = (^Linux_State)(window_state)
	s.allocator = allocator
	xdg_session_type := os.get_env("XDG_SESSION_TYPE", frame_allocator)
	
	if xdg_session_type == "wayland" {
		s.win = LINUX_WINDOW_WAYLAND
	} else {
		s.win = LINUX_WINDOW_X11
	}

	win_state_alloc_error: runtime.Allocator_Error
	s.win_state, win_state_alloc_error = mem.alloc(
		s.win.state_size(),
		allocator = allocator,
	)

	log.assertf(win_state_alloc_error == nil,
		"Failed allocating memory for Linux windowing: %v",
		win_state_alloc_error,
	)

	s.win.init(
		s.win_state,
		screen_width,
		screen_height,
		window_title,
		options,
		allocator,
	)

    s.gamepad_controller = gamepad_new_controller()
}

linux_shutdown :: proc() {
	s.win.shutdown()
	a := s.allocator
	free(s.win_state, a)
}

linux_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.win.get_window_render_glue()
}

linux_get_events :: proc(events: ^[dynamic]Event) {
	s.win.get_events(events)

    frame_events := events

    for &gp, idx in s.gamepad_controller.gamepads {
        if !gp.active {
            continue
        }
        events := gamepad_poll(&gp)
        _ = events
        for event in events {
            #partial switch e in event {
            case Linux_ButtonEvent:
                btn := e.button
                val := e.value
                button: Maybe(Gamepad_Button)
                #partial switch btn {
                case .BTN_DPAD_UP: button = .Left_Face_Right
                case .BTN_DPAD_DOWN: button = .Left_Face_Down
                case .BTN_DPAD_LEFT: button = .Left_Face_Left
                case .BTN_DPAD_RIGHT: button = .Left_Face_Up

                // This mapping is slightly different from Xinput. Up and Left are swapped
                case .BTN_A: button = .Right_Face_Down
                case .BTN_B: button = .Right_Face_Right
                case .BTN_X: button = .Right_Face_Up
                case .BTN_Y: button = .Right_Face_Left

                case .BTN_TL: button = .Left_Shoulder
                case .BTN_TL2: button = .Left_Trigger
                case .BTN_TR: button = .Right_Shoulder
                case .BTN_TR2: button = .Right_Trigger

			    case .BTN_SELECT: button = .Middle_Face_Left
			    case .BTN_MODE: button = .Middle_Face_Middle
			    case .BTN_START: button = .Middle_Face_Right
                case .BTN_THUMBL: button = .Left_Stick_Press
                case .BTN_THUMBR: button = .Right_Stick_Press

                case: continue
                }
                evt: Event
                if val == .Pressed {
                    evt = Event_Gamepad_Button_Went_Down {
                        gamepad = idx,
                        button = button.?,
                    }
                }
                if val == .Released {
                    evt = Event_Gamepad_Button_Went_Up {
                        gamepad = idx,
                        button = button.?,
                    }
                }
                if evt != nil {
				    append(frame_events, evt)
			    }
            case Linux_AxisEvent: 
                // The following deals with Gamepads emitting d-pad events
                // as an analog axis. We need to store the previous value
                // so that we emit the correct Event_Gamepad_Button_Went_Up 
                // events.
                // NOTE(quadrado): This probably could be refactored into 
                // gamepad code.
                evt: Event
                negative_button: Gamepad_Button
                positive_button: Gamepad_Button

                #partial switch e.axis {
                case .HAT0X: 
                    negative_button = .Left_Face_Left 
                    positive_button = .Left_Face_Right 
                
                case .HAT0Y:
                    negative_button = .Left_Face_Up 
                    positive_button = .Left_Face_Down 
                case:
                    continue
                }

                if e.normalized_value < 0 {
                    evt = Event_Gamepad_Button_Went_Down {
                        gamepad = idx,
                        button = negative_button,
                    }
                    gp.previous_hat_values[e.axis] = e.normalized_value
                }
                if e.normalized_value > 0 {
                    evt = Event_Gamepad_Button_Went_Down {
                        gamepad = idx,
                        button = positive_button,
                    }
                    gp.previous_hat_values[e.axis] = e.normalized_value
                }
                if e.normalized_value == 0 {
                    if gp.previous_hat_values[e.axis] == -1 {
                        evt = Event_Gamepad_Button_Went_Up {
                            gamepad = idx,
                            button = negative_button,
                        }
                    } else if gp.previous_hat_values[e.axis] == 1  {
                        evt = Event_Gamepad_Button_Went_Up {
                            gamepad = idx,
                            button = positive_button,
                        }
                    }
                }

                if evt != nil {
				    append(frame_events, evt)
			    }
            }
        }
    }

    // Check for new gamepads and add them in the first empty slot
    new_pad, has_new_pad := gamepad_controller_udev_events(s.gamepad_controller)
    if has_new_pad {
        for i in 0 ..<MAX_GAMEPADS {
            if s.gamepad_controller.gamepads[i].active == false {
                // Clean up the old gamepad before replacing it
                gamepad_close(&s.gamepad_controller.gamepads[i])
                s.gamepad_controller.gamepads[i] = new_pad
                break
            }
        }
    }
}

linux_get_width :: proc() -> int {
	return s.win.get_width()
}

linux_get_height :: proc() -> int {
	return s.win.get_height()
}

linux_set_position :: proc(x: int, y: int) {
	s.win.set_position(x, y)
}

linux_set_size :: proc(w, h: int) {
	s.win.set_size(w, h)
}

linux_get_window_scale :: proc() -> f32 {
	return s.win.get_window_scale()
}

linux_is_gamepad_active :: proc(gamepad: int) -> bool {
    if gamepad < 0 || gamepad > len(s.gamepad_controller.gamepads) - 1 || gamepad > MAX_GAMEPADS {
        return false
    }

    return s.gamepad_controller.gamepads[gamepad].active
}

linux_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
    gamepad := &s.gamepad_controller.gamepads[gamepad]

    switch axis {
    case .Left_Stick_X: return gamepad.axes[Linux_Axis.X].normalized_value
    case .Left_Stick_Y: return gamepad.axes[Linux_Axis.Y].normalized_value
    case .Right_Stick_X: return gamepad.axes[Linux_Axis.RX].normalized_value  
    case .Right_Stick_Y: return gamepad.axes[Linux_Axis.RY].normalized_value
    case .Left_Trigger: return gamepad.axes[Linux_Axis.Z].normalized_value // Not sure 
    case .Right_Trigger: return gamepad.axes[Linux_Axis.RZ].normalized_value // Not sure 
    }

    // Return axis state
	return 0
}

linux_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {

}

linux_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Linux_State)(state)
	s.win.set_internal_state(s.win_state)
}

linux_set_window_mode :: proc(window_mode: Window_Mode) {
	s.win.set_window_mode(window_mode)
}

Linux_State :: struct {
	win: Linux_Window_Interface,
	win_state: rawptr,
	allocator: runtime.Allocator,
    gamepad_controller: Linux_Gamepad_Controller,
    // gamepads: []Linux_Gamepad,
}

@(private="package")
Linux_Window_Interface :: struct {
	state_size: proc() -> int,

	init: proc(
		window_state: rawptr,
		window_width: int,
		window_height: int,
		window_title: string,
		init_options: Init_Options,
		allocator: runtime.Allocator,
	),

	shutdown: proc(),
	get_window_render_glue: proc() -> Window_Render_Glue,
	get_events: proc(events: ^[dynamic]Event),
	set_position: proc(x: int, y: int),
	set_size: proc(w, h: int),
	get_width: proc() -> int,
	get_height: proc() -> int,
	get_window_scale: proc() -> f32,
	set_window_mode: proc(window_mode: Window_Mode),

	set_internal_state: proc(state: rawptr),
}

@(private="package")
key_from_xkeycode :: proc(kc: u32) -> Keyboard_Key {
	if kc >= 255 {
		return .None
	}

	return KEY_FROM_XKEYCODE[u8(kc)]
}

@(private="package")
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
