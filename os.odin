#+build !js
package karl2d
import "core:os"
import "core:io"
import "base:runtime"
import "log"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	content, err := os.read_entire_file(path, allocator)
	if err != nil {
		return {}, false
	}
	return content, true	
}

File :: ^os.File

open_file_read :: proc(name: string) -> ^os.File {
	f, err := os.open(name)

	if err != nil {
		log.error("Failed opening file %v. Error: %v", name, err)
		return nil
	}

	return f
}

close_file :: proc(f: ^os.File) {
	err := os.close(f)
	if err != nil {
		log.error("Failed closing file. Error: %v", err)
	}
}

file_seek :: proc(f: ^os.File, offset: i64, whence: io.Seek_From) -> i64 {
	new_offset, err := os.seek(f, offset, whence)
	if err != nil {
		log.error("Failed seeking file. Error: %v", err)
		return -1
	}
	return new_offset
}

file_read :: proc(f: ^os.File, buffer: []u8) -> int {
	n, err := os.read(f, buffer)
	if err != nil {
		log.error("Failed reading file. Error: %v", err)
		return -1
	}
	return n
}