package evdev

import "core:c"
import "core:os"
import "core:sys/linux"


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
Button :: enum u32 {
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
Button_State :: enum u32 {
	Released = 0,
	Pressed  = 1,
	Repeated = 2,
}

// Dont use the same base that we use for buttons because they start at 0x00
Axis :: enum u32 {
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

// Helper for bitfield testing
test_bit :: proc(bits: []u64, bit: u64) -> bool {
	word_bits: u64 = size_of(u64) * 8
	idx := bit / word_bits
	pos := bit % word_bits

	return bits[idx] & (1 << pos) != 0
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
