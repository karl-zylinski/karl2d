#+build js

package space_cat
import "core:time"

file_version :: proc(filename: string) -> time.Time {
	return {}
}

get_file_contents :: proc($name: string) -> ([]byte, bool) {
	return #load(name), true
}

write_file :: proc(name: string, contents: []u8) -> bool {
	return false
}