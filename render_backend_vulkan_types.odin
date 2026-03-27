// Shared Vulkan types visible across the package.
// These are needed by the platform glue files.
#+build linux, windows

package karl2d

import vk "vendor:vulkan"

// Platform type for Vulkan glue state headers
Vulkan_Glue_Platform_Type :: enum {
        Unknown,
        Wayland,
        X11,
        Win32,
}

// Common header for all Vulkan glue state structs.
// The concrete types (Vulkan_Wayland_Glue_State, Vulkan_X11_Glue_State) place
// these two fields first so the render backend can safely cast the glue state
// pointer and read platform_type / vk_surface regardless of which platform
// glue was actually created.
Vulkan_Glue_State :: struct {
        platform_type: Vulkan_Glue_Platform_Type,
        vk_surface:    vk.SurfaceKHR,
}
