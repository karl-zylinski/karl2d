// Vulkan proc address loader for Linux.
#+build linux

package odingame

import "core:dynlib"
import "log"

@(private="package")
vk_get_proc_address :: proc() -> rawptr {
        lib, ok := dynlib.load_library("libvulkan.so.1", {})
        if !ok {
                lib, ok = dynlib.load_library("libvulkan.so", {})
        }
        if !ok {
                log.error("Vulkan: Failed to load libvulkan.so")
                return nil
        }
        addr, _ := dynlib.symbol_address(lib, "vkGetInstanceProcAddr")
        return addr
}
