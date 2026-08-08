package files_dropped

import k2 "../.."
import "core:fmt"

main :: proc() {
    k2.init(1280, 720, "Files Dropped Example")

    for k2.update() {
        if k2.is_file_dropped() {
			paths := k2.get_dropped_files()
			defer k2.destroy_dropped_files(paths)
			for path in paths {
				fmt.println(path)
			}
		}

        k2.clear(k2.BLACK)
        k2.present()
    }

    k2.shutdown()
}
