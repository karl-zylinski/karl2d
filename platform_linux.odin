#+build linux
#+private file
#+vet explicit-allocators

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

	// Create gamepads that were connected on program boot
	{
		// Gamepads are described by device files at path `/dev/input/eventXX`
		devices_handle, devices_handle_ok := os.open("/dev/input") 

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

			if gamepad_idx >= MAX_GAMEPADS {
				log.errorf("A maximum of %v gamepads is supported", MAX_GAMEPADS)
				break					
			}

			if gamepad, gamepad_ok := linux_create_gamepad(fi.fullpath); gamepad_ok {
				s.gamepads[gamepad_idx] = gamepad
				gamepad_idx += 1
			}
		}
	}

	// Set up monitoring for new gamepads. This uses udev. It looks for `input` devices being added.
	// The monitor is polled in `linux_get_events`.
	{
		s.udev_ptr = udev.new()
		s.udev_mon = udev.monitor_new_from_netlink(s.udev_ptr, "udev")
		udev.monitor_filter_add_match_subsystem_devtype(s.udev_mon, "input", nil)
		udev.monitor_enable_receiving(s.udev_mon)
	}
}

linux_shutdown :: proc() {
	for &g in s.gamepads {
		linux_destroy_gamepad(&g)
	}

	udev.monitor_unref(s.udev_mon)
	udev.unref(s.udev_ptr)

	s.win.shutdown()
	a := s.allocator
	free(s.win_state, a)
}

linux_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.win.get_window_render_glue()
}

linux_get_events :: proc(events: ^[dynamic]Event) {
	s.win.get_events(events)
	linux_poll_for_new_gamepads()
	linux_get_gamepad_events(events)
}

linux_poll_for_new_gamepads :: proc() {
	pfd := posix.pollfd {
		fd = posix.FD(udev.monitor_get_fd(s.udev_mon)),
		events = {posix.Poll_Event_Bits.IN},
	}

	ret := posix.poll(&pfd, 1, 0)

	if ret <= 0 {
		return
	}

	dev := udev.monitor_receive_device(s.udev_mon)
	defer udev.device_unref(dev)

	path_cstr := udev.device_get_devnode(dev)
	path := string(path_cstr)
	is_gamepad := evdev.is_device_gamepad(path)

	if is_gamepad && udev.device_get_action(dev) == "add" {
		// Find a slot for the new gamepad
		idx := -1

		for gp, gp_idx in s.gamepads {
			if gp.active == false {
				idx = gp_idx
				break
			}
		}

		if idx != -1 {
			if gp, gp_ok := linux_create_gamepad(path); gp_ok {
				s.gamepads[idx] = gp
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

linux_create_gamepad :: proc(device_path: string) -> (Linux_Gamepad, bool) {
	fd, err := os.open(device_path, os.O_RDWR | os.O_NONBLOCK)

	if err != nil {
		log.errorf("Failed creating gamepad for device %v", device_path)
		return {}, false
	}

	name_buf: [256]u8
	name_len := linux.ioctl(linux.Fd(fd), evdev.EVIOCGNAME(size_of(name_buf)), cast(uintptr)&name_buf)
	name := name_len > 0 ? string(name_buf[:name_len-1]) : "" 
	type := Linux_Gamepad_Type.Other

	if strings.contains(name, "Microsoft") {
		type = .Microsoft
	} else if strings.contains(name, "Sony") {
		type = .Sony
	}

	gamepad := Linux_Gamepad {
		fd = fd,
		type = type,
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

			if !has_axis {
				continue
			}

			axis := gamepad_axis_from_evdev_axis(i)

			if axis != .None {
				absinfo: evdev.input_absinfo
				linux.ioctl(linux.Fd(fd), evdev.EVIOCGABS(u32(i)), cast(uintptr)&absinfo)
				gamepad.axes[axis] = {
					event_min = absinfo.minimum,
					event_max = absinfo.maximum,
				}
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
			}

			linux.ioctl(linux.Fd(fd), evdev.EVIOCSFF(), cast(uintptr)&effect)
			gamepad.rumble_effect_id = u32(effect.id)
			gamepad.has_rumble_support = true
		}
	}

	return gamepad, true
}

gamepad_axis_from_evdev_axis :: proc(evdev_axis: evdev.Axis) -> Gamepad_Axis {
	#partial switch evdev_axis {
		case .X:  return .Left_Stick_X
		case .Y:  return .Left_Stick_Y
		case .RX: return .Right_Stick_X
		case .RY: return .Right_Stick_Y
		case .Z:  return .Left_Trigger
		case .RZ: return .Right_Trigger
	}

	return .None
}

linux_destroy_gamepad :: proc(gamepad: ^Linux_Gamepad) {
	os.close(gamepad.fd)
	delete(gamepad.name, s.allocator)
	gamepad.active = false
}

linux_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad > len(s.gamepads) - 1 || gamepad > MAX_GAMEPADS {
		return false
	}

	return s.gamepads[gamepad].active
}

@rodata
evdev_button_mapping_microsoft := #sparse [evdev.Button]Gamepad_Button {
	.DPAD_UP = .Left_Face_Right,
	.DPAD_DOWN = .Left_Face_Down,
	.DPAD_LEFT = .Left_Face_Left,
	.DPAD_RIGHT = .Left_Face_Up,

	.A = .Right_Face_Down,
	.B = .Right_Face_Right,
	.X = .Right_Face_Left,
	.Y = .Right_Face_Up,

	.TL = .Left_Shoulder,
	.TL2 = .Left_Trigger,
	.TR = .Right_Shoulder,
	.TR2 = .Right_Trigger,

	.SELECT = .Middle_Face_Left,
	.MODE = .Middle_Face_Middle,
	.START = .Middle_Face_Right,
	.THUMBL = .Left_Stick_Press,
	.THUMBR = .Right_Stick_Press,

	.C = .None,
	.Z = .None,
}

@rodata
evdev_button_mapping_sony := #sparse [evdev.Button]Gamepad_Button {
	.DPAD_UP = .Left_Face_Right,
	.DPAD_DOWN = .Left_Face_Down,
	.DPAD_LEFT = .Left_Face_Left,
	.DPAD_RIGHT = .Left_Face_Up,

	.A = .Right_Face_Down,
	.B = .Right_Face_Right,
	.X = .Right_Face_Up,
	.Y = .Right_Face_Left,

	.TL = .Left_Shoulder,
	.TL2 = .Left_Trigger,
	.TR = .Right_Shoulder,
	.TR2 = .Right_Trigger,

	.SELECT = .Middle_Face_Left,
	.MODE = .Middle_Face_Middle,
	.START = .Middle_Face_Right,
	.THUMBL = .Left_Stick_Press,
	.THUMBR = .Right_Stick_Press,

	.C = .None,
	.Z = .None,
}

linux_get_gamepad_events :: proc(events: ^[dynamic]Event) {
	event: evdev.input_event

	for &gp, idx in s.gamepads {
		if !gp.active {
			continue
		}

		for {
			event_read_bytes, event_read_err := os.read(gp.fd, mem.any_to_bytes(event))

			if event_read_err != nil && event_read_err != .EAGAIN {
				log.debugf("Gamepad %v disconnected", idx)
				linux_destroy_gamepad(&gp)
				break
			}

			if event_read_bytes != size_of(event) {
				break
			}

			switch event.type {
			case evdev.EV_KEY:
				evdev_button := evdev.Button(event.code)
				button: Gamepad_Button

				switch gp.type {
				case .Microsoft:
					button = evdev_button_mapping_microsoft[evdev_button]
				case .Sony:
					button = evdev_button_mapping_sony[evdev_button]
				}

				if button != .None {
					switch evdev.Button_State(event.value) {
					case .Pressed:
						append(events, Event_Gamepad_Button_Went_Down {
							gamepad = idx,
							button = button,
						})

					case .Released:
						append(events, Event_Gamepad_Button_Went_Up {
							gamepad = idx,
							button = button,
						})

					case .Repeated:
						// Do nothing
					}
				}
			case evdev.EV_ABS: 
				evdev_axis := evdev.Axis(event.code)

				if evdev_axis == .Z || evdev_axis == .RZ {
					// ^ triggers, goes between 0 an 1
					axis := gamepad_axis_from_evdev_axis(evdev_axis)
					value := f32(event.value) / f32(gp.axes[axis].event_max)

					// MS gamepads don't have trigger button event, so we fake it
					if gp.type == .Microsoft {
						prev_value := gp.axes[axis].value
						TRIGGER_THRESHOLD :: 0.001
						button: Gamepad_Button = evdev_axis == .Z ? .Left_Trigger : .Right_Trigger
						
						if prev_value > TRIGGER_THRESHOLD && value <= TRIGGER_THRESHOLD {
							append(events, Event_Gamepad_Button_Went_Up {
								gamepad = idx,
								button = button,
							})
						} else if prev_value <= TRIGGER_THRESHOLD && value > TRIGGER_THRESHOLD {
							append(events, Event_Gamepad_Button_Went_Down {
								gamepad = idx,
								button =button,
							})
						}
					}

					gp.axes[axis].value = value
				} else if evdev_axis == .HAT0X {
					// ^ DPAD horizontal. It's an axis, but the event values are just 0, -1 or 1

					if gp.previous_dpad_horizontal != 0 && gp.previous_dpad_horizontal != event.value {
						append(events, Event_Gamepad_Button_Went_Up {
							gamepad = idx,
							button = gp.previous_dpad_horizontal == -1 ? .Left_Face_Left : .Left_Face_Right,
						})
					} else if event.value != 0 {
						append(events, Event_Gamepad_Button_Went_Down {
							gamepad = idx,
							button = event.value == -1 ? .Left_Face_Left : .Left_Face_Right,
						})
					}

					gp.previous_dpad_horizontal = event.value
				} else if evdev_axis == .HAT0Y { 
					// ^ DPAD vertical. It's an axis, but the event values are just 0, -1 or 1

					if gp.previous_dpad_vertical != 0 && gp.previous_dpad_vertical != event.value {
						append(events, Event_Gamepad_Button_Went_Up {
							gamepad = idx,
							button = gp.previous_dpad_vertical == -1 ? .Left_Face_Up : .Left_Face_Down,
						})
					} else if event.value != 0 {
						append(events, Event_Gamepad_Button_Went_Down {
							gamepad = idx,
							button = event.value == -1 ? .Left_Face_Up : .Left_Face_Down,
						})
					}

					gp.previous_dpad_vertical = event.value
				} else {
					// Other analogue sticks. These are for example thumbsticks that go between
					// -1 and 1. These often have a big min and max value. This code normalizes
					// that integer value range into a float range of -1 to 1.

					axis := gamepad_axis_from_evdev_axis(evdev_axis)

					if axis != .None {
						min := f32(gp.axes[axis].event_min)
						max := f32(gp.axes[axis].event_max)
						val := f32(event.value)
						gp.axes[axis].value = 2.0 * (val - min) / (max - min) - 1.0
					}
				}
			}
		}
	}
}

linux_get_gamepad_axis :: proc(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32 {
	if axis < min(Gamepad_Axis) || axis > max(Gamepad_Axis) {
		return 0
	}

	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return s.gamepads[gamepad].axes[axis].value
}

linux_set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}

	gp := s.gamepads[gamepad]

	if !gp.active || !gp.has_rumble_support {
		return
	}

	effect := evdev.ff_effect {
		type = .RUMBLE,
		id = i16(gp.rumble_effect_id),
		direction = 0,
		trigger = {button = 0, interval = 0},

		// I put 1000 ms here because on some gamepads, if the effect is "too short" then it never
		// starts. Especially true on XBox gamepad slow motor. It seems to have a low frequency and
		// doesn't spin the motor if the length is 0 or very short.
		replay = {length = 1000, delay = 0},
	}

	effect.rumble = evdev.ff_rumble_effect {
		strong_magnitude = u16(left * 0xFFFF),
		weak_magnitude   = u16(right * 0xFFFF),
	}

	linux.ioctl(linux.Fd(gp.fd), evdev.EVIOCSFF(), cast(uintptr)&effect)
	
	rumble_event := evdev.input_event {
		type  = evdev.EV_FF,
		code  = u16(gp.rumble_effect_id),
		value = 1,
	}

	os.write(gp.fd, mem.any_to_bytes(rumble_event))

	// To "close" the rumble event
	syn_event := evdev.input_event {
		type = evdev.EV_SYN,
	}

	os.write(gp.fd, mem.any_to_bytes(syn_event))
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
	udev_ptr: ^udev.udev,
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

Linux_Gamepad_Axis_Info :: struct {
	value: f32,

	// The range of the events that can be reported for this axis.
	event_max: i32,
	event_min: i32,
}

// We differentiate between these types because some buttons are in different plaes. The evdev
// buttons for .Right_Face_Left and .Right_Face_Up will differ on for example PS4 and XBox gamepads.
Linux_Gamepad_Type :: enum {
	Microsoft, // XBox
	Sony, // PlayStation
	Other = Microsoft,
}

Linux_Gamepad :: struct {
	fd: os.Handle,
	active: bool,
	name: string,
	axes: [Gamepad_Axis]Linux_Gamepad_Axis_Info,
	type: Linux_Gamepad_Type,

	// This is needed to emit the correct Event_Gamepad_Button_Went_Up events because the DPAD
	// events come as values on a HAT axis.
	previous_dpad_horizontal: i32,
	previous_dpad_vertical: i32,

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
