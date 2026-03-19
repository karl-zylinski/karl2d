// For platforms with filesystem support, this file contains some stub implementations that just
// print errors and return. See `file_system_default.odin` for the implemenatations that are used on
// platforms that do support filesystems.
#+build js, freestanding
package karl2d

import "log"
import "base:runtime"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	log.error("Reading files is currently not supported on this platform.")
	return {}, false
}
