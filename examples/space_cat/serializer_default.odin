#+build !js

package space_cat

import "core:os"
import "core:time"

file_version :: proc(filename: string) -> time.Time {
	t, t_err := os.modification_time_by_path(filename)

	if t_err != nil {
		return {}
	}

	return t
}

get_file_contents :: proc($name: string) -> ([]byte, bool) {
	data, data_err := os.read_entire_file(name, context.temp_allocator)

	if data_err == nil {
		return data, true
	}

	return {}, false
}

write_file :: proc(name: string, contents: []u8) -> bool {
	err := os.write_entire_file(name, contents)
	return err == nil
}
