#+vet explicit-allocators

package karl2d_virtual_file_system

import "core:strings"
import "core:fmt"
import "base:runtime"
import "core:encoding/endian"

Virtual_File :: struct {
	data: []u8,
	path: string,
}

Virtual_File_System :: struct {
	files: []Virtual_File,
	path_to_file_index: map[string]int,
	memory: []u8,
}

deserialize :: proc(memory: []u8, allocator: runtime.Allocator) -> (Virtual_File_System, bool) {
	memory := memory

	num_files, num_files_ok := endian.get_u64(memory, .Little)

	if !num_files_ok {
		return {}, false
	}
	
	memory = memory[size_of(u64):]

	
	vfs := Virtual_File_System {
		memory = memory,
		files = make([]Virtual_File, num_files, allocator = allocator),
		path_to_file_index = make(map[string]int, allocator = allocator),
	}

	for i in 0..<num_files {
		path_len, path_len_ok := endian.get_u64(memory, .Little)

		if !path_len_ok {
			return {}, false
		}

		memory = memory[size_of(u64):]

		if len(memory) < int(path_len) {
			return {}, false
		}

		path := string(memory[:path_len])
		memory = memory[path_len:]
		file_size, file_size_ok := endian.get_u64(memory, .Little)

		if !file_size_ok {
			return {}, false
		}

		memory = memory[size_of(u64):]

		if len(memory) < int(file_size) {
			return {}, false
		}

		data := memory[:file_size]
		memory = memory[file_size:]

		vfs.files[i] = {
			path = path,
			data = data,
		}
		
		fmt.println(path)

		vfs.path_to_file_index[path] = int(i)
	}

	return vfs, true
}

serialize :: proc(files: []Virtual_File, allocator: runtime.Allocator) -> []u8 {
	res := make([dynamic]u8, allocator = allocator)

	num_files := u64(len(files))
	num_files_bytes: [size_of(u64)]u8
	endian.put_u64(num_files_bytes[:], .Little, num_files)
	append(&res, ..num_files_bytes[:])

	for f in files {
		path, _ := strings.replace_all(f.path, "\\", "/", context.temp_allocator)
		path_len := u64(len(path))
		path_len_bytes: [size_of(u64)]u8
		endian.put_u64(path_len_bytes[:], .Little, path_len)
		append(&res, ..path_len_bytes[:])
		append(&res, ..transmute([]u8)(path))
		file_size := u64(len(f.data))
		file_size_bytes: [size_of(u64)]u8
		endian.put_u64(file_size_bytes[:], .Little, file_size)
		append(&res, ..file_size_bytes[:])
		append(&res, ..f.data)
	}

	return res[:]
}