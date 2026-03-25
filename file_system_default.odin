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
import "virtual_file_system"

set_vfs :: proc(vfs: ^virtual_file_system.Virtual_File_System) {
	vfs_state = vfs
}

@(private="file")
vfs_state: ^virtual_file_system.Virtual_File_System

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	if vfs_state == nil {
		return {}, false
	}

	if vfs_file_idx, vfs_file_idx_ok := vfs_state.path_to_file_index[path]; vfs_file_idx_ok {
		return vfs_state.files[vfs_file_idx].data, true
	}

	content, err := os.read_entire_file(path, allocator)
	
	if err != nil {
		log.errorf("Failed reading file %v. Error: %v", path, err)
		return {}, false
	}

	return content, true	
}
