// Minimal D-Bus bindings. Just enough to ask the desktop a question and read a number back. The
// library is loaded at runtime, so that the game can start on machines without libdbus.
//
// `Message_Iter` is `DBusMessageIter` from dbus-message.h. Its fields are never read, but its size
// must match, since the caller provides the storage.
package karl2d_dbus

import "core:c"
import "core:dynlib"

Connection :: distinct rawptr
Message :: distinct rawptr

Bus_Type :: enum c.int {
	Session = 0,
	System  = 1,
	Starter = 2,
}

TYPE_STRING :: c.int('s')
TYPE_UINT32 :: c.int('u')
TYPE_VARIANT :: c.int('v')

Message_Iter :: struct {
	dummy1: rawptr,
	dummy2: rawptr,
	dummy3: u32,
	dummy4: c.int,
	dummy5: c.int,
	dummy6: c.int,
	dummy7: c.int,
	dummy8: c.int,
	dummy9: c.int,
	dummy10: c.int,
	dummy11: c.int,
	pad1: c.int,
	pad2: rawptr,
	pad3: rawptr,
}

bus_get_private: proc "c" (type: Bus_Type, error: rawptr) -> Connection

connection_close: proc "c" (connection: Connection)

connection_unref: proc "c" (connection: Connection)

connection_send_with_reply_and_block: proc "c" (
	connection: Connection,
	message: Message,
	timeout_milliseconds: c.int,
	error: rawptr,
) -> Message

message_new_method_call: proc "c" (
	bus_name: cstring,
	path: cstring,
	interface: cstring,
	method: cstring,
) -> Message

message_unref: proc "c" (message: Message)

message_iter_init_append: proc "c" (message: Message, iter: ^Message_Iter)

message_iter_append_basic: proc "c" (
	iter: ^Message_Iter,
	type: c.int,
	value: rawptr,
) -> c.int

message_iter_init: proc "c" (message: Message, iter: ^Message_Iter) -> c.int

message_iter_recurse: proc "c" (iter: ^Message_Iter, sub: ^Message_Iter)

message_iter_get_arg_type: proc "c" (iter: ^Message_Iter) -> c.int

message_iter_get_basic: proc "c" (iter: ^Message_Iter, value: rawptr)

LIB_DBUS :: "libdbus-1.so.3"

load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr: rawptr,
	} {
		{"dbus_bus_get_private", &bus_get_private},
		{"dbus_connection_close", &connection_close},
		{"dbus_connection_unref", &connection_unref},
		{"dbus_connection_send_with_reply_and_block", &connection_send_with_reply_and_block},
		{"dbus_message_new_method_call", &message_new_method_call},
		{"dbus_message_unref", &message_unref},
		{"dbus_message_iter_init_append", &message_iter_init_append},
		{"dbus_message_iter_append_basic", &message_iter_append_basic},
		{"dbus_message_iter_init", &message_iter_init},
		{"dbus_message_iter_recurse", &message_iter_recurse},
		{"dbus_message_iter_get_arg_type", &message_iter_get_arg_type},
		{"dbus_message_iter_get_basic", &message_iter_get_basic},
	}

	lib, lib_ok := dynlib.load_library(LIB_DBUS)

	if !lib_ok {
		return LIB_DBUS, false
	}

	for s in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, s.name)

		if !addr_ok {
			dynlib.unload_library(lib)
			return s.name, false
		}

		(^rawptr)(s.ptr)^ = addr
	}

	return "", true
}
