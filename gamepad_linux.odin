package karl2d

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/linux"
import "core:sys/posix"

// udev minimal bindings for gamepad connection listening
udev :: struct {}
udev_device :: struct {}
udev_monitor :: struct {}

foreign import _udev "system:udev"

@(default_calling_convention = "c", link_prefix = "udev_")
foreign _udev {
    @(link_prefix = "")
	udev_new :: proc() -> ^udev ---
	unref :: proc(_: ^udev) ---

	device_get_devnode :: proc(_: ^udev_device) -> cstring ---
	device_get_action :: proc(_: ^udev_device) -> cstring ---
	device_unref :: proc(_: ^udev_device) ---

	monitor_new_from_netlink :: proc(_: ^udev, _: cstring) -> ^udev_monitor ---
	monitor_filter_add_match_subsystem_devtype :: proc(
        mon: ^udev_monitor,
        _: cstring,
        _: cstring,
    ) -> c.int ---
	monitor_enable_receiving :: proc(_: ^udev_monitor) ---
	monitor_get_fd :: proc(_: ^udev_monitor) -> c.int ---
	monitor_receive_device :: proc(_: ^udev_monitor) -> ^udev_device ---
}

// ioctl() related utilities
_IOC_READ :: 2
_IOC_NRSHIFT :: 0
_IOC_TYPESHIFT :: (_IOC_NRSHIFT + _IOC_NRBITS)
_IOC_SIZESHIFT :: (_IOC_TYPESHIFT + _IOC_TYPEBITS)
_IOC_DIRSHIFT :: (_IOC_SIZESHIFT + _IOC_SIZEBITS)

_IOC_NRBITS :: 8
_IOC_TYPEBITS :: 8
_IOC_SIZEBITS :: 14

_IOC :: proc(dir: u32, type: u32, nr: u32, size: u32) -> u32 {

	return(
		((dir) << _IOC_DIRSHIFT) |
		((type) << _IOC_TYPESHIFT) |
		((nr) << _IOC_NRSHIFT) |
		((size) << _IOC_SIZESHIFT) \
	)
}
// This is not working, not sure why size_of(T) is 8 when i pass it input_absinfo
_IOR :: proc(type: u32, nr: u32, T: typeid) -> u32 {
	return _IOC(_IOC_READ, (type), (nr), (size_of(T)))
}

// Evdev related ioctl() calls

// Get device name
EVIOCGNAME :: proc(len: u32) -> u32 {
	return _IOC(_IOC_READ, u32('E'), 0x06, len)
}

// Get list of supported event types if called with ev == 0
// Get list of supported codes for a give event if ev == event_type
EVIOCGBIT :: proc(ev: u32, len: u32) -> u32 {
	return _IOC(_IOC_READ, u32('E'), 0x20 + (ev), len)
}

// Get Absolute Axes info (maximum, minimum, etc)
EVIOCGABS :: proc(abs: u32) -> u32 {
	return _IOC(_IOC_READ, 'E', 0x40 + (abs), size_of(input_absinfo))
}

// Helper for bitfield testing
test_bit :: proc(bits: []u64, bit: u64) -> bool {
	word_bits: u64 = size_of(u64) * 8
	idx := bit / word_bits
	pos := bit % word_bits

	return bits[idx] & (1 << pos) != 0
}

// Event types
EV_SYN :: 0x00
EV_KEY :: 0x01
EV_REL :: 0x02
EV_ABS :: 0x03
EV_MSC :: 0x04
EV_SW :: 0x05
EV_LED :: 0x11
EV_SND :: 0x12
EV_REP :: 0x14
EV_FF :: 0x15
EV_PWR :: 0x16
EV_FF_STATUS :: 0x17
EV_MAX :: 0x1f
EV_CNT :: (EV_MAX + 1)

KEY_MAX :: 0x2ff

// This is the first and base button
// This is used as the bit index to check for existence
// and also the as the event code
BTN_GAMEPAD :: 0x130

// In linux/input.h there are 15 different mapped buttons + d-pad 
// that for some reason appear further down....
Linux_Button :: enum u32 {
	BTN_A          = BTN_GAMEPAD,
	BTN_B          = BTN_GAMEPAD + 1,
	BTN_C          = BTN_GAMEPAD + 2,
	BTN_X          = BTN_GAMEPAD + 3,
	BTN_Y          = BTN_GAMEPAD + 4,
	BTN_Z          = BTN_GAMEPAD + 5,
	BTN_TL         = BTN_GAMEPAD + 6,
	BTN_TR         = BTN_GAMEPAD + 7,
	BTN_TL2        = BTN_GAMEPAD + 8,
	BTN_TR2        = BTN_GAMEPAD + 9,
	BTN_SELECT     = BTN_GAMEPAD + 10,
	BTN_START      = BTN_GAMEPAD + 11,
	BTN_MODE       = BTN_GAMEPAD + 12,
	BTN_THUMBL     = BTN_GAMEPAD + 13,
	BTN_THUMBR     = BTN_GAMEPAD + 14,
	BTN_DPAD_UP    = 0x220,
	BTN_DPAD_DOWN  = 0x221,
	BTN_DPAD_LEFT  = 0x222,
	BTN_DPAD_RIGHT = 0x223,
}

// Evdev EV_KEY events can have these states
Linux_Button_State :: enum u32 {
	Released = 0,
	Pressed  = 1,
	Repeated = 2,
}

// Dont use the same base that we use for buttons because they start at 0x00
Linux_Axis :: enum u32 {
	X          = 0x00,
	Y          = 0x01,
	Z          = 0x02,
	RX         = 0x03,
	RY         = 0x04,
	RZ         = 0x05,
	THROTTLE   = 0x06,
	RUDDER     = 0x07,
	WHEEL      = 0x08,
	GAS        = 0x09,
	BRAKE      = 0x0a,
	HAT0X      = 0x10,
	HAT0Y      = 0x11,
	HAT1X      = 0x12,
	HAT1Y      = 0x13,
	HAT2X      = 0x14,
	HAT2Y      = 0x15,
	HAT3X      = 0x16,
	HAT3Y      = 0x17,
	PRESSURE   = 0x18,
	DISTANCE   = 0x19,
	TILT_X     = 0x1a,
	TILT_Y     = 0x1b,
	TOOL_WIDTH = 0x1c,
}

// Canonical event when read()'ing from evdev file
input_event :: struct {
	time:  linux.Time_Val,
	type:  u16,
	code:  u16,
	value: c.int,
}

// Canonical absolute axis information gotten from ioctl() when using EVIOCGABS
input_absinfo :: struct {
	value:      i32,
	minimum:    i32,
	maximum:    i32,
	fuzz:       i32,
	flat:       i32,
	resolution: i32,
}

// Odin structs
Linux_Axis_Info :: struct {
	absinfo:          input_absinfo,
	value:            f32, // originaly a c.int
	normalized_value: f32,
	previous_value:   f32,
}

Linux_Gamepad :: struct {
	fd:                  os.Handle,
	active:              bool,
	name:                string,
	axes:                map[Linux_Axis]Linux_Axis_Info,

	// This is needed to emit the correct Event_Gamepad_Button_Went_Up events
	previous_hat_values: map[Linux_Axis]f32,
}

Linux_GamepadEvent :: union {
	Linux_ButtonEvent,
	Linux_AxisEvent,
}

Linux_ButtonEvent :: struct {
	button: Linux_Button,
	value:  Linux_Button_State,
}

Linux_AxisEvent :: struct {
	axis:             Linux_Axis,
	normalized_value: f32,
}

check_for_btn_gamepad :: proc(path: string) -> bool {
	fd, err := os.open(path, os.O_RDONLY | os.O_NONBLOCK)

	if err != nil {
		return false
	}
	key_bits: [KEY_MAX / (8 * size_of(u64)) + 1]u64 = {}
	linux.ioctl(linux.Fd(fd), EVIOCGBIT(EV_KEY, size_of(key_bits)), cast(uintptr)&key_bits)

	return test_bit(key_bits[:], u64(BTN_GAMEPAD))
}

gamepad_init_devices :: proc() -> []Linux_Gamepad {
	gamepads: [dynamic]Linux_Gamepad
	devices_dir := "/dev/input"

	f := os.open(devices_dir) or_else panic("Can't open /dev/input directory")

	fis := os.read_dir(f, -1) or_else panic("Can't list /dev/input directory")

	for fi in fis {
		if strings.starts_with(fi.name, "event") {
			is_gamepad := check_for_btn_gamepad(fi.fullpath)

			if !is_gamepad {
				continue
			}
			gamepad, _ := gamepad_create(fi.fullpath)
			append(&gamepads, gamepad)
		}
	}

	return gamepads[:]
}

gamepad_create :: proc(device_path: string) -> (Linux_Gamepad, bool) {
	fd, err := os.open(device_path, os.O_RDONLY | os.O_NONBLOCK)
	if err != nil {
        return Linux_Gamepad{}, false
	}
	name: [256]u8
	linux.ioctl(linux.Fd(fd), EVIOCGNAME(size_of(name)), cast(uintptr)&name)

	// Create gamepad
	gamepad := Linux_Gamepad {
		fd     = fd,
		name   = strings.clone_from_cstring(cstring(raw_data(name[:]))),
		active = true,
	}

	fmt.printf("New gamepad %s\n", name)
	fmt.printf("\tdevice_path -> '%s'\n", device_path)

	ev_bits: [EV_MAX / (8 * size_of(u64)) + 1]u64 = {}
	linux.ioctl(linux.Fd(fd), EVIOCGBIT(0, size_of(ev_bits)), cast(uintptr)&ev_bits)
	has_abs := test_bit(ev_bits[:], EV_ABS)
	fmt.printf("\thas_buttons-> '%t'\n", test_bit(ev_bits[:], EV_KEY))
	fmt.printf("\thas_absolute_movement-> '%t'\n", has_abs)
	fmt.printf("\thas_relative_movement-> '%t'\n", test_bit(ev_bits[:], EV_REL))

	if has_abs {
		abs_bits: [EV_ABS / (8 * size_of(u64)) + 1]u64 = {}
		linux.ioctl(linux.Fd(fd), EVIOCGBIT(EV_ABS, size_of(abs_bits)), cast(uintptr)&abs_bits)

		for i in Linux_Axis.X ..< Linux_Axis.TOOL_WIDTH + Linux_Axis(1) {
			has_axis := test_bit(abs_bits[:], u64(i))
			if has_axis {
				axis_info := Linux_Axis_Info{}
				linux.ioctl(linux.Fd(fd), EVIOCGABS(u32(i)), cast(uintptr)&axis_info.absinfo)
				gamepad.axes[i] = axis_info
			}
		}
	}

	return gamepad, true
}

gamepad_close :: proc(gamepad: ^Linux_Gamepad) {
	os.close(gamepad.fd)
}

gamepad_check_udev_events :: proc() -> (Linux_Gamepad, bool) {
	// udev := udev_new()

	// mon := monitor_new_from_netlink(udev, "udev")

	// monitor_filter_add_match_subsystem_devtype(mon, "input", nil)
	// monitor_enable_receiving(mon)

	// fd_int := monitor_get_fd(mon)

    // pfd := posix.pollfd {
        // fd = posix.FD(fd_int),
        // events = { posix.Poll_Event_Bits.IN },
    // }
  
	// ret := posix.poll(&pfd, 1, 5)

    // if ret > 0  {
        // fmt.println(ret)
        // dev := monitor_receive_device(mon)

        // path := device_get_devnode(dev)
        // action := device_get_action(dev)
        // if action == "add" {
            // pad, ok := gamepad_create(strings.clone_from_cstring(path))
            // if ok {
                // return pad, true
            // }
        // }
    // }
    return Linux_Gamepad{}, false
}

gamepad_poll :: proc(gamepad: ^Linux_Gamepad) -> []Linux_GamepadEvent {
	res: [dynamic]Linux_GamepadEvent
	buf: [size_of(input_event)]u8

	for {
		n, read_err := os.read(gamepad.fd, buf[:])

		if read_err != nil && read_err != .EAGAIN {
			gamepad.active = false
			break
		}
		if n != size_of(input_event) {
			break
		}

		event := transmute(input_event)buf

		// Ignore "trivial" events for now
		// SYN is data tranmission control events, SYN_REPORT might be
		// important to sync composite events like touch gestures in modern gamepads.
		// MSC is Misc that I don't really know what they mean...
		// https://docs.kernel.org/input/event-codes.html
		if event.type == EV_SYN || event.type == EV_MSC do continue

		if event.type == EV_KEY {
			append(
				&res,
				Linux_ButtonEvent {
					button = Linux_Button(event.code),
					value = Linux_Button_State(event.value),
				},
			)
		}
		if event.type == EV_ABS {
			axis := &gamepad.axes[Linux_Axis(event.code)]
			axis.value = f32(event.value)
			min := f32(axis.absinfo.minimum)
			max := f32(axis.absinfo.maximum)
			axis.normalized_value = 2.0 * (axis.value - min) / (max - min) - 1.0
			append(
				&res,
				Linux_AxisEvent {
					axis = Linux_Axis(event.code),
					normalized_value = axis.normalized_value,
				},
			)
		}
	}

	return res[:]
}
