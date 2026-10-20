package udev

import "core:c"
import "core:dynlib"

// udev minimal bindings for gamepad connection listening
udev :: struct {}
device :: struct {}
monitor :: struct {}

new: proc "c" () -> ^udev
unref: proc "c" (u: ^udev) -> ^udev

device_get_devnode: proc "c" (dev: ^device) -> cstring
device_get_action: proc "c" (dev: ^device) -> cstring
device_unref: proc "c" (dev: ^device) -> ^device

monitor_new_from_netlink: proc "c" (u: ^udev, name: cstring) -> ^monitor
monitor_filter_add_match_subsystem_devtype: proc "c" (
	mon: ^monitor,
	subsystem: cstring,
	devtype: cstring,
) -> c.int
monitor_enable_receiving: proc "c" (mon: ^monitor) -> c.int
monitor_get_fd: proc "c" (mon: ^monitor) -> c.int
monitor_receive_device: proc "c" (mon: ^monitor) -> ^device
monitor_unref: proc "c" (mon: ^monitor) -> ^monitor

LIB_UDEV :: "libudev.so.1"

@(private)
lib: dynlib.Library

load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr: rawptr,
	} {
		{"udev_new", &new},
		{"udev_unref", &unref},
		{"udev_device_get_devnode", &device_get_devnode},
		{"udev_device_get_action", &device_get_action},
		{"udev_device_unref", &device_unref},
		{"udev_monitor_new_from_netlink", &monitor_new_from_netlink},
		{"udev_monitor_filter_add_match_subsystem_devtype", &monitor_filter_add_match_subsystem_devtype},
		{"udev_monitor_enable_receiving", &monitor_enable_receiving},
		{"udev_monitor_get_fd", &monitor_get_fd},
		{"udev_monitor_receive_device", &monitor_receive_device},
		{"udev_monitor_unref", &monitor_unref},
	}

	lib_ok: bool
	lib, lib_ok = dynlib.load_library(LIB_UDEV)

	if !lib_ok {
		lib = nil
		return LIB_UDEV, false
	}

	for s in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, s.name)

		if !addr_ok {
			unload()
			return s.name, false
		}

		(^rawptr)(s.ptr)^ = addr
	}

	return "", true
}

unload :: proc() {
	if lib != nil {
		dynlib.unload_library(lib)
		lib = nil
	}
}
