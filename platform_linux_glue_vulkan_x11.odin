// Glues together Vulkan with an X11 window. Passes the X11 display and window handles
// through the glue state so the Vulkan render backend can create a VkSurfaceKHR from them.
#+build linux

package odingame

import vk "vendor:vulkan"
import X "vendor:x11/xlib"
import "log"
import "base:runtime"

@(private = "package")
make_linux_vulkan_x11_glue :: proc(
	display: ^X.Display,
	window: X.Window,
	allocator: runtime.Allocator,
	loc := #caller_location,
) -> Window_Render_Glue {
	state := new(Vulkan_X11_Glue_State, allocator, loc)
	state.x11_display = display
	state.x11_window = window
	state.platform_type = .X11
	state.allocator = allocator
	return {
		state = (^Window_Render_Glue_State)(state),
		make_context     = cast(proc(state: ^Window_Render_Glue_State) -> bool)(linux_vulkan_x11_glue_make_context),
		present          = cast(proc(state: ^Window_Render_Glue_State))(linux_vulkan_x11_glue_present),
		destroy          = cast(proc(state: ^Window_Render_Glue_State))(linux_vulkan_x11_glue_destroy),
		viewport_resized = cast(proc(state: ^Window_Render_Glue_State))(linux_vulkan_x11_glue_viewport_resized),
	}
}

// The first fields match Vulkan_Glue_State so the render backend can safely cast and read
// platform_type and vk_surface without knowing the full concrete type.
Vulkan_X11_Glue_State :: struct {
	// --- Vulkan_Glue_State header (must be first) ---
	platform_type: Vulkan_Glue_Platform_Type,
	vk_surface:    vk.SurfaceKHR,

	// --- X11-specific ---
	x11_display: ^X.Display,
	x11_window:  X.Window,
	allocator:   runtime.Allocator,
}

linux_vulkan_x11_glue_make_context :: proc(gs: ^Vulkan_X11_Glue_State) -> bool {
	log.info("Vulkan X11 glue: ready (surface will be created by render backend)")
	return true
}

linux_vulkan_x11_glue_present :: proc(gs: ^Vulkan_X11_Glue_State) {
	// Vulkan manages its own presentation.
}

linux_vulkan_x11_glue_destroy :: proc(gs: ^Vulkan_X11_Glue_State) {
	a := gs.allocator
	free(gs, a)
}

linux_vulkan_x11_glue_viewport_resized :: proc(gs: ^Vulkan_X11_Glue_State) {
}
