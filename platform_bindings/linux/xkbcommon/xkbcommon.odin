// Minimal bindings for libxkbcommon, only covering what Karl2D needs to translate Wayland key
// events into typed text (taking the current keyboard layout into account).
package xkbcommon

import "core:c"

foreign import lib "system:xkbcommon"

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

@(default_calling_convention = "c", link_prefix = "xkb_")
foreign lib {
	context_new :: proc(flags: Context_Flags) -> ^Context ---
	context_unref :: proc(ctx: ^Context) ---

	keymap_new_from_string :: proc(
		ctx: ^Context,
		str: cstring,
		format: Keymap_Format,
		flags: Keymap_Compile_Flags,
	) -> ^Keymap ---
	keymap_unref :: proc(keymap: ^Keymap) ---

	state_new :: proc(keymap: ^Keymap) -> ^State ---
	state_unref :: proc(state: ^State) ---

	state_update_mask :: proc(
		state: ^State,
		depressed_mods: u32,
		latched_mods: u32,
		locked_mods: u32,
		depressed_layout: u32,
		latched_layout: u32,
		locked_layout: u32,
	) -> State_Component ---

	// Returns the UTF-8 encoding of the text produced by `key` in the current state, written into
	// `buffer` (which must be at least `size` bytes). Returns the number of bytes that would have
	// been written (excluding the null terminator), like `snprintf`. `key` uses the "XKB keycode"
	// convention, which is the Linux evdev keycode plus 8.
	state_key_get_utf8 :: proc(
		state: ^State,
		key: Keycode,
		buffer: [^]u8,
		size: c.size_t,
	) -> c.int ---
}
