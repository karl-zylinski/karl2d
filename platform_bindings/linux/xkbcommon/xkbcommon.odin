// Minimal bindings for libxkbcommon, only covering what Karl2D needs to translate Wayland key
// events into typed text (taking the current keyboard layout into account). Loaded with dlopen
// instead of a static foreign import. Karl2D compiles in both the X11 and the Wayland backend and
// only one of them runs, so linking libxkbcommon unconditionally would require every machine to
// have it installed.
package xkbcommon

import "core:c"
import "core:dynlib"

Context :: struct {}
Keymap :: struct {}
State :: struct {}

Keycode :: distinct u32

Context_Flags :: enum c.int {
	No_Flags = 0,
}

Keymap_Format :: enum c.int {
	Text_V1 = 1,
}

Keymap_Compile_Flags :: enum c.int {
	No_Flags = 0,
}

// A bitmask of `xkb_state_component`. We don't need to interpret the value, we only pass along
// what `state_update_mask` returns.
State_Component :: distinct c.int

context_new: proc "c" (flags: Context_Flags) -> ^Context

context_unref: proc "c" (ctx: ^Context)

keymap_new_from_string: proc "c" (
	ctx:    ^Context,
	str:    cstring,
	format: Keymap_Format,
	flags:  Keymap_Compile_Flags,
) -> ^Keymap

keymap_unref: proc "c" (keymap: ^Keymap)

state_new: proc "c" (keymap: ^Keymap) -> ^State

state_unref: proc "c" (state: ^State)

state_update_mask: proc "c" (
	state:             ^State,
	depressed_mods:    u32,
	latched_mods:      u32,
	locked_mods:       u32,
	depressed_layout:  u32,
	latched_layout:    u32,
	locked_layout:     u32,
) -> State_Component

// Returns the UTF-8 encoding of the text produced by `key` in the current state, written into
// `buffer` (which must be at least `size` bytes). Returns the number of bytes that would have
// been written (excluding the null terminator), like `snprintf`. `key` uses the "XKB keycode"
// convention, which is the Linux evdev keycode plus 8.
state_key_get_utf8: proc "c" (
	state:  ^State,
	key:    Keycode,
	buffer: [^]u8,
	size:   c.size_t,
) -> c.int

LIB_XKBCOMMON :: "libxkbcommon.so.0"

@(private)
lib: dynlib.Library

// Loads libxkbcommon. On failure `missing` names the library or the symbol that was not found.
load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr:  rawptr,
	} {
		{"xkb_context_new", &context_new},
		{"xkb_context_unref", &context_unref},
		{"xkb_keymap_new_from_string", &keymap_new_from_string},
		{"xkb_keymap_unref", &keymap_unref},
		{"xkb_state_new", &state_new},
		{"xkb_state_unref", &state_unref},
		{"xkb_state_update_mask", &state_update_mask},
		{"xkb_state_key_get_utf8", &state_key_get_utf8},
	}

	lib_ok: bool
	lib, lib_ok = dynlib.load_library(LIB_XKBCOMMON)

	if !lib_ok {
		lib = nil
		return LIB_XKBCOMMON, false
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

// Closes the library again, for when Wayland turns out to be unusable after all.
unload :: proc() {
	if lib != nil {
		dynlib.unload_library(lib)
		lib = nil
	}
}
