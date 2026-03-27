// For platforms without filesystem support, this file contains some stub implementations that just
// print errors and return. See `file_system_default.odin` for the implemenatations that are used on
// platforms that do support filesystems.
#+build js, freestanding
package karl2d

import "log"
import "base:runtime"
import "core:io"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	log.error("Reading files is currently not supported on this platform.")
	return {}, false
}

File :: struct {}
File_Error :: enum {
	Unsupported_On_Web,
	EOF,
}

file_open :: proc(filename: string) -> (^File, File_Error) {
	log.error("file_open not available on web")
	return nil, .Unsupported_On_Web
}

file_read :: proc(f: ^File, p: []byte) -> (n: int, err: File_Error) {
	log.error("file_read not available on web")
	return 0, .Unsupported_On_Web
}

file_seek :: proc(f: ^File, offset: i64, whence: io.Seek_From) -> (ret: i64, err: File_Error) {
	log.error("file-seek not available on web")
	return 0, .Unsupported_On_Web
}

file_close :: proc(f: ^File) -> File_Error {
	log.error("file_close not available on web")
	return .Unsupported_On_Web
}