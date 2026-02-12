#+build js
package karl2d

import "base:runtime"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	panic("Not implemented on web")
}