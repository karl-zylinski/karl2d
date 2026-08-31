// Minimal D-Bus bindings. Just enough to ask the desktop a question and read a number back.
// Loaded with dlopen instead of a static foreign import: a machine without D-Bus should still run
// the game, it just doesn't get to answer any questions about how the desktop is set up.
package dbus

import "core:c"
import "core:dynlib"

Connection :: distinct rawptr
Message :: distinct rawptr

Bus_Type :: enum c.int {
	Session = 0,
	System  = 1,
	Starter = 2,
}

// The type codes are the same letters that appear in a D-Bus signature.
TYPE_INVALID :: c.int(0)
TYPE_STRING :: c.int('s')
TYPE_UINT32 :: c.int('u')
TYPE_VARIANT :: c.int('v')

// Filled in by the calls that take one. `name` is a D-Bus error name like
// "org.freedesktop.DBus.Error.UnknownMethod", and is nil when nothing went wrong. This is
// `DBusError` from dbus-errors.h, whose five one-bit fields are the `bits` below.
Error :: struct {
	name:     cstring,
	message:  cstring,
	bits:     u32,
	_padding: u32,
	padding1: rawptr,
}

ERROR_UNKNOWN_METHOD :: "org.freedesktop.DBus.Error.UnknownMethod"

// Opaque to us, but the caller has to provide the storage, so the size has to be right. This is
// `DBusMessageIter` from dbus-message.h with its fields spelled out.
Message_Iter :: struct {
	dummy1:  rawptr,
	dummy2:  rawptr,
	dummy3:  u32,
	dummy4:  c.int,
	dummy5:  c.int,
	dummy6:  c.int,
	dummy7:  c.int,
	dummy8:  c.int,
	dummy9:  c.int,
	dummy10: c.int,
	dummy11: c.int,
	pad1:    c.int,
	pad2:    rawptr,
	pad3:    rawptr,
}

error_init: proc "c" (error: ^Error)

// Frees what the library put in the error, not the error itself.
error_free: proc "c" (error: ^Error)

// A private connection, rather than the shared one `dbus_bus_get` hands out, so that closing it
// afterwards affects nobody else.
bus_get_private: proc "c" (type: Bus_Type, error: ^Error) -> Connection

// Without this libdbus calls exit() on the whole game if the bus goes away.
connection_set_exit_on_disconnect: proc "c" (connection: Connection, exit_on_disconnect: c.int)

connection_close: proc "c" (connection: Connection)

connection_unref: proc "c" (connection: Connection)

connection_send_with_reply_and_block: proc "c" (
	connection: Connection,
	message: Message,
	timeout_milliseconds: c.int,
	error: ^Error,
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

@(private)
lib: dynlib.Library

// Loads libdbus. On failure `missing` names the library or the symbol that was not found.
load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr:  rawptr,
	} {
		{"dbus_error_init", &error_init},
		{"dbus_error_free", &error_free},
		{"dbus_bus_get_private", &bus_get_private},
		{"dbus_connection_set_exit_on_disconnect", &connection_set_exit_on_disconnect},
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

	lib_ok: bool
	lib, lib_ok = dynlib.load_library(LIB_DBUS)

	if !lib_ok {
		lib = nil
		return LIB_DBUS, false
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

// Closes the library again, for when one of the symbols turns out to be missing.
unload :: proc() {
	if lib != nil {
		dynlib.unload_library(lib)
		lib = nil
	}
}
