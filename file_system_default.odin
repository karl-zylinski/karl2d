// Platforms that support OS API (file I/O etc) have some implementations in this file.
//
// Rational for a separate file: In the past `core:os` could be imported as long as the usages were
// behind `when` checks. But these days `core:os` will compile-time error on web targets. Therefore
// I put underscore-prefixed implementations of some procs in this file and `karl2d_no_fs.odin`.
#+build !js
#+build !freestanding
package karl2d

import "core:os"
import "log"
import "base:runtime"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	content, err := os.read_entire_file(path, allocator)
	
	if err != nil {
		log.errorf("Failed reading file %v. Error: %v", path, err)
		return {}, false
	}

	return content, true	
}
