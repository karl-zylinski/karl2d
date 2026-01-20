#+vet explicit-allocators
#+build linux
#+private file
package karl2d

import "base:runtime"
import "log"
import "core:mem"
import "core:os"
import "core:sys/linux"
import "core:sys/posix"
import "core:strings"
import "linux/udev"
import "linux/evdev"
import "core:bytes"
import "core:fmt"

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

	// Initialize gamepads
	linux_init_gamepads()
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
	linux_get_gamepad_events(events)
	// new_gp, has_new_gp := gamepad_check_udev(s.udev_mon) 
	// if has_new_gp {
	// }
	// Check for new gamepads and add them in the first empty slot new_pad
	pfd := posix.pollfd {
		fd	 = posix.FD(s.udev_fd),
		events = {posix.Poll_Event_Bits.IN},
	}

	ret := posix.poll(&pfd, 1, 0)

	if ret <= 0 {
		return
	}

	dev := udev.monitor_receive_device(s.udev_mon)
	path_cstr := udev.device_get_devnode(dev)
	path := string(path_cstr)
	
	if !evdev.is_device_gamepad(path) {
		return 
	}

	action := udev.device_get_action(dev)
	if action == "add" {
		pad, ok := linux_create_gamepad(path)
		if ok {
			for i in 0 ..<MAX_GAMEPADS {
				if s.gamepads[i].active == false {
					// Clean up the old gamepad before replacing it
					linux_close_gamepad(&s.gamepads[i])
					s.gamepads[i] = pad
					break
				}
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

linux_init_gamepads :: proc() {
	DEVICES_DIR :: "/dev/input"

	devices_handle, devices_handle_ok := os.open(DEVICES_DIR) 

	if devices_handle_ok != nil {
		return 
	}

	defer os.close(devices_handle)

	file_infos, file_infos_ok := os.read_dir(devices_handle, -1, frame_allocator)

	if file_infos_ok != nil {
		return 
	}

	gamepad_idx := 0

	for fi in file_infos {
		if !strings.starts_with(fi.name, "event") {
			continue
		}

		if !evdev.is_device_gamepad(fi.fullpath) {
			continue
		}

		if gamepad, gamepad_ok := linux_create_gamepad(fi.fullpath); gamepad_ok {
			s.gamepads[gamepad_idx] = gamepad
			gamepad_idx += 1	
		}
	}

	// Initialize udev machinery
	udev_ptr := udev.new()
	udev_mon_ptr := udev.monitor_new_from_netlink(udev_ptr, "udev")

	udev.monitor_filter_add_match_subsystem_devtype(udev_mon_ptr, "input", nil)
	udev.monitor_enable_receiving(udev_mon_ptr)
	udev_fd := udev.monitor_get_fd(udev_mon_ptr)

	s.udev_fd = udev_fd
	s.udev_mon = udev_mon_ptr
}

linux_create_gamepad :: proc(device_path: string) -> (Linux_Gamepad, bool) {
	fd, err := os.open(device_path, os.O_RDWR | os.O_NONBLOCK)

	if err != nil {
		log.errorf("Failed creating gamepad for device %v", device_path)
		return Linux_Gamepad{}, false
	}

	name_buf: [256]u8
	name_len := linux.ioctl(linux.Fd(fd), evdev.EVIOCGNAME(size_of(name_buf)), cast(uintptr)&name_buf)
	name := name_len > 0 ? strings.string_from_ptr(raw_data(&name_buf), int(name_len-1)) : "" 

	gamepad := Linux_Gamepad {
		fd = fd,
		name = strings.clone(name, s.allocator),
		active = true,
	}

	ev_bits: [evdev.EV_MAX / (8 * size_of(u64)) + 1]u64
	linux.ioctl(linux.Fd(fd), evdev.EVIOCGBIT(0, size_of(ev_bits)), cast(uintptr)&ev_bits)
	has_analogue_axes := evdev.test_bit(ev_bits[:], evdev.EV_ABS)
	has_vibration := evdev.test_bit(ev_bits[:], evdev.EV_FF)

	log.debugf("New gamepad %s", name)
	log.debugf("\tdevice_path -> '%s'", device_path)
	log.debugf("\thas_buttons-> '%t'", evdev.test_bit(ev_bits[:], evdev.EV_KEY))
	log.debugf("\thas_analogue_axes-> '%t'", has_analogue_axes)
	log.debugf("\thas_vibration-> '%t'", has_vibration)
	log.debugf("\thas_relative_movement-> '%t'", evdev.test_bit(ev_bits[:], evdev.EV_REL))
	
	if has_analogue_axes {
		abs_bits: [evdev.EV_ABS / (8 * size_of(u64)) + 1]u64 = {}
		linux.ioctl(linux.Fd(fd), evdev.EVIOCGBIT(evdev.EV_ABS, size_of(abs_bits)), cast(uintptr)&abs_bits)

		for i in evdev.Axis.X ..< evdev.Axis.TOOL_WIDTH + evdev.Axis(1) {
			has_axis := evdev.test_bit(abs_bits[:], u64(i))
			if has_axis {
				axis_info: Linux_Axis_Info
				linux.ioctl(linux.Fd(fd), evdev.EVIOCGABS(u32(i)), cast(uintptr)&axis_info.absinfo)
				gamepad.axes[i] = axis_info
			}
		}
	}
	
	if has_vibration {
		ff_bits: [evdev.FF_MAX / (8 * size_of(u64)) + 1]u64 
		linux.ioctl(linux.Fd(fd), evdev.EVIOCGBIT(evdev.EV_FF, size_of(ff_bits)), cast(uintptr)&ff_bits)
		has_rumble_effect := evdev.test_bit(ff_bits[:], u64(evdev.FF_Effect_Type.RUMBLE)) 

		if has_rumble_effect {
			effect := evdev.ff_effect {
				type = .RUMBLE,
				id = -1,
				direction = 0,
				trigger = {button = 0, interval = 0},
				replay = {length = 0, delay = 0},
			}

			effect.rumble = {
				strong_magnitude = 0,
				weak_magnitude   = 0,
			}

			linux.ioctl(linux.Fd(fd), evdev.EVIOCSFF(), cast(uintptr)&effect)
			gamepad.rumble_effect_id = u32(effect.id)
			gamepad.has_rumble_support = true
		}
	}
	return gamepad, true
}

linux_close_gamepad :: proc(gamepad: ^Linux_Gamepad) {
	if gamepad.active {
		os.close(gamepad.fd)
		gamepad.active = false
	}
	// Clean up allocated resources
	delete(gamepad.name, s.allocator)
	delete(gamepad.axes)
	delete(gamepad.previous_hat_values)
}

linux_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad > len(s.gamepads) - 1 || gamepad > MAX_GAMEPADS {
		return false
	}

	return s.gamepads[gamepad].active
}

linux_get_gamepad_events :: proc(events: ^[dynamic]Event) {
	frame_events := events
	buf: [size_of(evdev.input_event)]u8

	for &gp, idx in s.gamepads {
		if !gp.active {
			continue
		}

		for {
			n, read_err := os.read(gp.fd, buf[:])
			if read_err != nil && read_err != .EAGAIN {
				// Gamepad disconnected - close the file descriptor
				os.close(gp.fd)
				gp.active = false
				break
			}
			if n != size_of(evdev.input_event) {
				break
			}

			event := transmute(evdev.input_event)buf
			switch event.type {
			case evdev.EV_KEY:
				btn := evdev.Button(event.code)
				val := evdev.Button_State(event.value)
				button: Maybe(Gamepad_Button)
				#partial switch btn {
				case .DPAD_UP: button = .Left_Face_Right
				case .DPAD_DOWN: button = .Left_Face_Down
				case .DPAD_LEFT: button = .Left_Face_Left
				case .DPAD_RIGHT: button = .Left_Face_Up

				// This mapping is slightly different from Xinput. Up and Left are swapped
				case .A: button = .Right_Face_Down
				case .B: button = .Right_Face_Right
				case .X: button = .Right_Face_Up
				case .Y: button = .Right_Face_Left

				case .TL: button = .Left_Shoulder
				case .TL2: button = .Left_Trigger
				case .TR: button = .Right_Shoulder
				case .TR2: button = .Right_Trigger

				case .SELECT: button = .Middle_Face_Left
				case .MODE: button = .Middle_Face_Middle
				case .START: button = .Middle_Face_Right
				case .THUMBL: button = .Left_Stick_Press
				case .THUMBR: button = .Right_Stick_Press

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
			case evdev.EV_ABS: 
				laxis := evdev.Axis(event.code)
				axis := &gp.axes[laxis]
				axis.value = f32(event.value)
				min := f32(axis.absinfo.minimum)
				max := f32(axis.absinfo.maximum)

				if laxis ==.Z || laxis == .RZ {
					axis.normalized_value = axis.value / max
				} else {
					axis.normalized_value = 2.0 * (axis.value - min) / (max - min) - 1.0
				}

				// The following deals with Gamepads emitting d-pad events
				// as an analog axis. We need to store the previous value
				// so that we emit the correct Event_Gamepad_Button_Went_Up 
				// events.
				// NOTE(quadrado): This probably could be refactored into 
				// gamepad code.
				evt: Event
				negative_button: Gamepad_Button
				positive_button: Gamepad_Button

				#partial switch evdev.Axis(event.code) {
				case .HAT0X: 
					negative_button = .Left_Face_Left 
					positive_button = .Left_Face_Right 

				case .HAT0Y:
					negative_button = .Left_Face_Up 
					positive_button = .Left_Face_Down 
				case:
					continue
				}

				if axis.normalized_value < 0 {
					evt = Event_Gamepad_Button_Went_Down {
						gamepad = idx,
						button = negative_button,
					}
					gp.previous_hat_values[laxis] = axis.normalized_value
				}
				if axis.normalized_value > 0 {
					evt = Event_Gamepad_Button_Went_Down {
						gamepad = idx,
						button = positive_button,
					}
					gp.previous_hat_values[laxis] = axis.normalized_value
				}
				if axis.normalized_value == 0 {
					if gp.previous_hat_values[laxis] == -1 {
						evt = Event_Gamepad_Button_Went_Up {
							gamepad = idx,
							button = negative_button,
						}
					} else if gp.previous_hat_values[laxis] == 1  {
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
}

@rodata
evdev_axis_from_gamepad_axis := [Gamepad_Axis]evdev.Axis {
	.Left_Stick_X = .X,
	.Left_Stick_Y = .Y,
	.Right_Stick_X = .RX,
	.Right_Stick_Y = .RY,
	.Left_Trigger = .Z,
	.Right_Trigger = .RZ,
}

linux_get_gamepad_axis :: proc(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32 {
	if axis < min(Gamepad_Axis) || axis > max(Gamepad_Axis) {
		return 0
	}

	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return s.gamepads[gamepad].axes[evdev_axis_from_gamepad_axis[axis]].normalized_value
}

linux_set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}

	gp := s.gamepads[gamepad]

	if !gp.has_rumble_support {
		return
	}

	fd := gp.fd

	effect := evdev.ff_effect {
		type = .RUMBLE,
		id = i16(gp.rumble_effect_id),
		direction = 0,
		trigger = {button = 0, interval = 0},
		replay = {length = 0, delay = 0},
	}

	effect.rumble = evdev.ff_rumble_effect {
		strong_magnitude = u16(left * 0xFFFF),
		weak_magnitude   = u16(right * 0xFFFF),
	}

	linux.ioctl(linux.Fd(fd), evdev.EVIOCSFF(), cast(uintptr)&effect)
	
	rumble_event := evdev.input_event {
		type  = evdev.EV_FF,
		code  = u16(gp.rumble_effect_id),
		value = 1,
	}

	os.write(fd, mem.any_to_bytes(rumble_event))

	// To "close" the rumble event
	syn_event := evdev.input_event {
		type = evdev.EV_SYN,
	}

	os.write(fd, mem.any_to_bytes(syn_event))
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

	gamepads: [MAX_GAMEPADS]Linux_Gamepad,
	udev_fd: i32,
	udev_mon: ^udev.monitor,
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

Linux_Axis_Info :: struct {
	absinfo: evdev.input_absinfo,
	value: f32, // originaly a c.int
	normalized_value: f32,
	previous_value: f32,
}

Linux_Gamepad :: struct {
	fd: os.Handle,
	active: bool,
	name: string,
	axes: map[evdev.Axis]Linux_Axis_Info,

	// This is needed to emit the correct Event_Gamepad_Button_Went_Up events
	previous_hat_values: map[evdev.Axis]f32,
	has_rumble_support: bool,
	rumble_effect_id: u32,
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
