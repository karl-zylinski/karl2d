package clipboard

import k2 "../.."
import "core:fmt"

main :: proc() {
    k2.init(1280, 720, "Clipboard")

    for k2.update() {
        if k2.get_held_modifiers() == {.Control} && k2.key_went_down(.V) {
			text := k2.get_clipboard_text(context.temp_allocator)
			fmt.println(text)
		}

        k2.clear(k2.BLACK)
        k2.present()

        free_all(context.temp_allocator)
    }
}
