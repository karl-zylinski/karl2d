package karlib

import "core:strings"

temp_cstring :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator)
}