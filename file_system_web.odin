// For platforms with filesystem support, this file contains some stub implementations that just
// print errors and return. See `file_system_default.odin` for the implemenatations that are used on
// platforms that do support filesystems.
#+build js, freestanding
package karl2d

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
	
	return {}, false
}
