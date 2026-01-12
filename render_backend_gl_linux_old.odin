#+build linux

package karl2d

import gl "vendor:OpenGL"
import "log"
import "vendor:egl"

_ :: log

GL_Context :: struct {
    egl_context: egl.Context,
    egl_display: egl.Display,
    egl_surface: egl.Surface,
    window_handle: Window_Handle_Wayland,
}

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
    whw := (^Window_Handle_Wayland)(window_handle)^
    return wayland_gl_get_context(whw)
}

_gl_destroy_context :: proc(ctx: GL_Context) {
    egl.DestroyContext(ctx.egl_display, ctx.egl_context)
}

_gl_load_procs :: proc(ctx: GL_Context) {
    gl.load_up_to(3, 3, egl.gl_set_proc_address)
}

_gl_present :: proc(ctx: GL_Context) {
    wayland_gl_present(ctx)
}

_gl_context_viewport_resized :: proc(ctx: GL_Context) {}


import "core:fmt"

wayland_gl_get_context :: proc(whw: Window_Handle_Wayland) -> (GL_Context, bool) {
    // Get a valid EGL configuration based on some attribute guidelines
    // Create a context based on a "chosen" configuration
    EGL_CONTEXT_FLAGS_KHR :: 0x30FC
    EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR :: 0x00000001

    major, minor, n: i32
    egl_config: egl.Config
    config_attribs: []i32 = {
        egl.SURFACE_TYPE, egl.WINDOW_BIT,
        egl.RED_SIZE, 8,
        egl.GREEN_SIZE, 8,
        egl.BLUE_SIZE, 8,
        egl.ALPHA_SIZE, 0, // Disable surface alpha for now
        egl.DEPTH_SIZE, 24, // Request 24-bit depth buffer
        egl.RENDERABLE_TYPE, egl.OPENGL_BIT,
        egl.NONE,
    }
    context_flags_bitfield: i32 = EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR

    context_attribs: []i32 = {
        egl.CONTEXT_CLIENT_VERSION, 3,
        EGL_CONTEXT_FLAGS_KHR, context_flags_bitfield,
        egl.NONE,
    }
    egl_display := egl.GetDisplay(egl.NativeDisplayType(whw.display))
    if egl_display == egl.NO_DISPLAY {
        panic("Failed to create EGL display")
    }
    if !egl.Initialize(egl_display, &major, &minor) {
        panic("Can't initialize egl display")
    }
    if !egl.ChooseConfig(egl_display, raw_data(config_attribs), &egl_config, 1, &n) {
        panic("Failed to find/choose EGL config")
    }

	egl_surface := egl.CreateWindowSurface(
		egl_display,
		egl_config,
		egl.NativeWindowType(whw.window),
		nil,
	)

	if egl_surface == egl.NO_SURFACE {
	    panic("Error creating window surface")
	}
    // This call must be here before CreateContext
    egl.BindAPI(egl.OPENGL_API)

    egl_context := egl.CreateContext(
        egl_display,
        egl_config,
        egl.NO_CONTEXT,
        raw_data(context_attribs),
    )
    if egl_context == egl.NO_CONTEXT {
        panic("Failed creating EGL context")
    }
    if egl.MakeCurrent(egl_display, egl_surface, egl_surface, egl_context) {
        return GL_Context {
            window_handle = whw,
            egl_display = egl_display,
            egl_context = egl_context,
            egl_surface = egl_surface,
        }, true
    }
    return {}, false
}

wayland_gl_present :: proc(ctx: GL_Context) {
	egl.SwapBuffers(ctx.egl_display, ctx.egl_surface)

    //wl.surface_damage(ctx.window_handle.surface, 0, 0, i32(500), i32(500))
    //wl.surface_commit(ctx.window_handle.surface)
	
}

