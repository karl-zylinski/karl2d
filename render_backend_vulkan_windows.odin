// Vulkan proc address loader for Windows.
#+build windows

package odingame

import "core:sys/windows"
import "log"

@(private="package")
vk_get_proc_address :: proc() -> rawptr {
        lib := windows.LoadLibraryW(windows.L("vulkan-1.dll"))
        if lib == nil {
                log.error("Vulkan: Failed to load vulkan-1.dll")
                return nil
        }
        return rawptr(windows.GetProcAddress(lib, "vkGetInstanceProcAddr"))
}
