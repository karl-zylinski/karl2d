// Loaded with dlopen instead of a static foreign import, same reasoning as wayland_core.odin:
// libdecor is only wanted on compositors that don't decorate windows themselves, so linking it
// unconditionally would require every machine to have it installed.
package libdecor

import "core:c"
import "core:dynlib"
import wl "../wayland"

Libdecor :: struct {}
Frame :: struct {}
State :: struct {}
Configuration :: struct {}

context_new: proc "c" (display: ^wl.Display, iface: ^Interface) -> ^Libdecor

context_unref: proc "c" (ctx: ^Libdecor)

dispatch: proc "c" (ctx: ^Libdecor, timeout_ms: c.int) -> c.int

decorate: proc "c" (
	ctx:       ^Libdecor,
	surface:   ^wl.Surface,
	iface:     ^Frame_Interface,
	user_data: rawptr,
) -> ^Frame

frame_unref: proc "c" (frame: ^Frame)

frame_map: proc "c" (frame: ^Frame)

frame_set_title: proc "c" (frame: ^Frame, title: cstring)

frame_set_min_content_size: proc "c" (frame: ^Frame, width: c.int, height: c.int)

frame_set_max_content_size: proc "c" (frame: ^Frame, width: c.int, height: c.int)

frame_set_capabilities: proc "c" (frame: ^Frame, capabilities: c.uint32_t)

frame_unset_capabilities: proc "c" (frame: ^Frame, capabilities: c.uint32_t)

frame_set_fullscreen: proc "c" (frame: ^Frame, output: ^wl.Output)

frame_unset_fullscreen: proc "c" (frame: ^Frame)

frame_commit: proc "c" (frame: ^Frame, state: ^State, configuration: ^Configuration)

state_new: proc "c" (width: c.int, height: c.int) -> ^State

state_free: proc "c" (state: ^State)

configuration_get_content_size: proc "c" (
	configuration: ^Configuration,
	frame:         ^Frame,
	width:         ^c.int,
	height:        ^c.int,
) -> c.bool

// The two vtables libdecor calls back through. Field order and count must match libdecor.h
// exactly, reserved slots included, since libdecor reads them as a plain C struct.

Interface :: struct {
	error:    proc "c" (ctx: ^Libdecor, error: c.uint32_t, message: cstring),
	reserved: [10]rawptr,
}

Frame_Interface :: struct {
	configure:     proc "c" (frame: ^Frame, configuration: ^Configuration, user_data: rawptr),
	close:         proc "c" (frame: ^Frame, user_data: rawptr),
	commit:        proc "c" (frame: ^Frame, user_data: rawptr),
	dismiss_popup: proc "c" (frame: ^Frame, seat_name: cstring, user_data: rawptr),
	reserved:      [10]rawptr,
}

WINDOW_STATE_NONE :: 0
WINDOW_STATE_ACTIVE :: 1 << 0
WINDOW_STATE_MAXIMIZED :: 1 << 1
WINDOW_STATE_FULLSCREEN :: 1 << 2
WINDOW_STATE_TILED_LEFT :: 1 << 3
WINDOW_STATE_TILED_RIGHT :: 1 << 4
WINDOW_STATE_TILED_TOP :: 1 << 5
WINDOW_STATE_TILED_BOTTOM :: 1 << 6
WINDOW_STATE_SUSPENDED :: 1 << 7

CAPABILITY_MOVE :: 1 << 0
CAPABILITY_RESIZE :: 1 << 1
CAPABILITY_MINIMIZE :: 1 << 2
CAPABILITY_FULLSCREEN :: 1 << 3
CAPABILITY_CLOSE :: 1 << 4

LIB_LIBDECOR :: "libdecor-0.so.0"

Symbol :: struct {
	name: string,
	ptr:  rawptr,
}

@(private)
lib: dynlib.Library

// Loads libdecor and fills in every symbol above. On failure `missing` names the library or the
// symbol that was not found.
load :: proc() -> (missing: string, ok: bool) {
	symbols := []Symbol {
		{"libdecor_new", &context_new},
		{"libdecor_unref", &context_unref},
		{"libdecor_dispatch", &dispatch},
		{"libdecor_decorate", &decorate},
		{"libdecor_frame_unref", &frame_unref},
		{"libdecor_frame_map", &frame_map},
		{"libdecor_frame_set_title", &frame_set_title},
		{"libdecor_frame_set_min_content_size", &frame_set_min_content_size},
		{"libdecor_frame_set_max_content_size", &frame_set_max_content_size},
		{"libdecor_frame_set_capabilities", &frame_set_capabilities},
		{"libdecor_frame_unset_capabilities", &frame_unset_capabilities},
		{"libdecor_frame_set_fullscreen", &frame_set_fullscreen},
		{"libdecor_frame_unset_fullscreen", &frame_unset_fullscreen},
		{"libdecor_frame_commit", &frame_commit},
		{"libdecor_state_new", &state_new},
		{"libdecor_state_free", &state_free},
		{"libdecor_configuration_get_content_size", &configuration_get_content_size},
	}

	lib_ok: bool
	lib, lib_ok = dynlib.load_library(LIB_LIBDECOR)

	if !lib_ok {
		return LIB_LIBDECOR, false
	}

	for sym in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, sym.name)

		if !addr_ok {
			dynlib.unload_library(lib)
			lib = nil
			return sym.name, false
		}

		(^rawptr)(sym.ptr)^ = addr
	}

	return "", true
}

// Closes the library again, for when libdecor turns out to be unusable after all.
unload :: proc() {
	if lib != nil {
		dynlib.unload_library(lib)
		lib = nil
	}
}
