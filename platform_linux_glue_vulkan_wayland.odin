// Glues together Vulkan with a Wayland window. Passes the Wayland display and surface handles
// through the glue state so the Vulkan render backend can create a VkSurfaceKHR from them.
// This follows the same pattern as D3D11 on Windows where the HWND is passed through glue.state.
#+build linux

package karl2d

import vk "vendor:vulkan"
import wl "platform_bindings/linux/wayland"
import "log"
import "base:runtime"

@(private = "package")
make_linux_vulkan_wayland_glue :: proc(
	display: ^wl.Display,
	surface: ^wl.Surface,
	allocator: runtime.Allocator,
	loc := #caller_location,
) -> Window_Render_Glue {
	state := new(Vulkan_Wayland_Glue_State, allocator, loc)
	state.wl_display = display
	state.wl_surface = surface
	state.platform_type = .Wayland
	state.allocator = allocator
	return {
		state = (^Window_Render_Glue_State)(state),
		make_context     = cast(proc(state: ^Window_Render_Glue_State) -> bool)(linux_vulkan_wayland_glue_make_context),
		present          = cast(proc(state: ^Window_Render_Glue_State))(linux_vulkan_wayland_glue_present),
		destroy          = cast(proc(state: ^Window_Render_Glue_State))(linux_vulkan_wayland_glue_destroy),
		viewport_resized = cast(proc(state: ^Window_Render_Glue_State))(linux_vulkan_wayland_glue_viewport_resized),
	}
}

// The first field matches Vulkan_Glue_State so the render backend can safely cast and read
// platform_type and vk_surface without knowing the full concrete type.
Vulkan_Wayland_Glue_State :: struct {
	// --- Vulkan_Glue_State header (must be first) ---
	platform_type: Vulkan_Glue_Platform_Type,
	vk_surface:    vk.SurfaceKHR,

	// --- Wayland-specific ---
	wl_display: ^wl.Display,
	wl_surface: ^wl.Surface,
	allocator:  runtime.Allocator,
}

linux_vulkan_wayland_glue_make_context :: proc(gs: ^Vulkan_Wayland_Glue_State) -> bool {
	// The VkSurfaceKHR is created by the Vulkan render backend (vk_init) which reads the
	// Wayland handles from this struct. This callback just signals success so init proceeds.
	log.info("Vulkan Wayland glue: ready (surface will be created by render backend)")
	return true
}

linux_vulkan_wayland_glue_present :: proc(gs: ^Vulkan_Wayland_Glue_State) {
	// Vulkan manages its own presentation via vkQueuePresentKHR.
}

linux_vulkan_wayland_glue_destroy :: proc(gs: ^Vulkan_Wayland_Glue_State) {
	a := gs.allocator
	free(gs, a)
}

linux_vulkan_wayland_glue_viewport_resized :: proc(gs: ^Vulkan_Wayland_Glue_State) {
	// Swapchain recreation is handled by the render backend.
}
