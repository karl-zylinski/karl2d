package udev

import "core:c"

// udev minimal bindings for gamepad connection listening
udev :: struct {}
device :: struct {}
monitor :: struct {}

foreign import udev_lib "system:udev"

@(default_calling_convention = "c", link_prefix = "udev_")
foreign udev_lib {
	new :: proc() -> ^udev ---
	unref :: proc(udev: ^udev) ---

	device_get_devnode :: proc(dev: ^device) -> cstring ---
	device_get_action :: proc(dev: ^device) -> cstring ---
	device_unref :: proc(dev: ^device) ---

	monitor_new_from_netlink :: proc(udev: ^udev, name: cstring) -> ^monitor ---
	monitor_filter_add_match_subsystem_devtype :: proc(
		mon: ^monitor,
		subsystem: cstring,
		devtype: cstring,
	) -> c.int ---
	monitor_enable_receiving :: proc(mon: ^monitor) ---
	monitor_get_fd :: proc(mon: ^monitor) -> c.int ---
	monitor_receive_device :: proc(mon: ^monitor) -> ^device ---
	monitor_unref :: proc(mon: ^monitor) ---
}
