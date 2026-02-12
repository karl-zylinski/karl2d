#+build !js
package karl2d
import "core:os"
import "base:runtime"

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
	content, err := os.read_entire_file(path, allocator)
	if err != nil {
		return {}, false
	}
	return content, true	
}
