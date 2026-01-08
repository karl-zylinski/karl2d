#+build linux

package karl2d

import "linux/glx"
import gl "vendor:OpenGL"
import "log"
import "vendor:egl"
import wl "linux/wayland"

_ :: log

GL_Context :: union {
    GL_Context_GLX,
    GL_Context_EGL,
}

GL_Context_GLX :: struct {
	ctx: ^glx.Context,
	window_handle: Window_Handle_Linux,
}

GL_Context_EGL :: struct {
	ctx: egl.Context,
    egl_display: egl.Display,
	window_handle: Window_Handle_Linux,
}

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	handle := (^Window_Handle_Linux)(window_handle)

    switch &whl in handle {
    case Window_Handle_Linux_X11:
        return x11_gl_get_context(whl)
    case Window_Handle_Linux_Wayland:
        return wayland_gl_get_context(&whl)
    }

	return {}, false
}

_gl_destroy_context :: proc(ctx: GL_Context) {
    switch gl_ctx in ctx {
    case GL_Context_GLX:
	        glx.DestroyContext(gl_ctx.window_handle.(Window_Handle_Linux_X11).display, gl_ctx.ctx)
    case GL_Context_EGL:
            egl.DestroyContext(gl_ctx.egl_display, gl_ctx.ctx)
    }
}

_gl_load_procs :: proc(window_handle: Window_Handle) {
	handle := (^Window_Handle_Linux)(window_handle)
    switch whl in handle {
    case Window_Handle_Linux_X11:
        gl.load_up_to(3, 3, glx.SetProcAddress)
    case Window_Handle_Linux_Wayland:
	    gl.load_up_to(3, 3, egl.gl_set_proc_address)
    }
}

_gl_present :: proc(window_handle: Window_Handle) {
	handle := (^Window_Handle_Linux)(window_handle)
    switch &whl in handle {
    case Window_Handle_Linux_X11:
        x11_gl_present(&whl)
    case Window_Handle_Linux_Wayland:
        wayland_gl_present(&whl)
    }
}

x11_gl_get_context :: proc(whl: Window_Handle_Linux_X11) -> (GL_Context, bool) {
    visual_attribs := []i32 {
        glx.RENDER_TYPE, glx.RGBA_BIT,
        glx.DRAWABLE_TYPE, glx.WINDOW_BIT,
        glx.DOUBLEBUFFER, 1,
        glx.RED_SIZE, 8,
        glx.GREEN_SIZE, 8,
        glx.BLUE_SIZE, 8,
        glx.ALPHA_SIZE, 8,
        0,
    }

    num_fbc: i32
    fbc := glx.ChooseFBConfig(whl.display, whl.screen, raw_data(visual_attribs), &num_fbc)
   
    if fbc == nil {
        log.error("Failed choosing GLX framebuffer config")
        return {}, false
    }

    glxCreateContextAttribsARB: glx.CreateContextAttribsARBProc
    glx.SetProcAddress((rawptr)(&glxCreateContextAttribsARB), "glXCreateContextAttribsARB")
    
    if glxCreateContextAttribsARB == {} {
        log.error("Failed fetching glXCreateContextAttribsARB")
        return {}, false
    }

    context_attribs := []i32 {
        glx.CONTEXT_MAJOR_VERSION_ARB, 3,
        glx.CONTEXT_MINOR_VERSION_ARB, 3,
        glx.CONTEXT_PROFILE_MASK_ARB, glx.CONTEXT_CORE_PROFILE_BIT_ARB,
        0,
    }

    ctx := glxCreateContextAttribsARB(whl.display, fbc[0], nil, true, raw_data(context_attribs))

    if glx.MakeCurrent(whl.display, whl.window, ctx) {
        return GL_Context_GLX {ctx = ctx, window_handle = whl}, true
    }
    return {}, false
}

x11_gl_present :: proc(whl: ^Window_Handle_Linux_X11) {
	glx.SwapBuffers(whl.display, whl.window)
}


import "core:fmt"

wayland_gl_get_context :: proc(whl: ^Window_Handle_Linux_Wayland) -> (GL_Context, bool) {
    fmt.println(whl)
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
    egl_display := egl.GetDisplay(egl.NativeDisplayType(whl.display))
    if egl_display == egl.NO_DISPLAY {
        panic("Failed to create EGL display")
    }
    if !egl.Initialize(egl_display, &major, &minor) {
        panic("Can't initialise egl display")
    }
    if !egl.ChooseConfig(egl_display, raw_data(config_attribs), &egl_config, 1, &n) {
        panic("Failed to find/choose EGL config")
    }

	egl_surface := egl.CreateWindowSurface(
		egl_display,
		egl_config,
		egl.NativeWindowType(whl.egl_window),
		nil,
	)

	if egl_surface == egl.NO_SURFACE {
	    panic("Error creating window surface")
	}
    // This call must be here before CreateContext
    egl.BindAPI(egl.OPENGL_API)

    fmt.println("Creating Context")
    egl_context := egl.CreateContext(
        egl_display,
        egl_config,
        egl.NO_CONTEXT,
        raw_data(context_attribs),
    )
    if egl_context == egl.NO_CONTEXT {
        panic("Failed creating EGL context")
    }
    fmt.println("Done creating Context")
    if (egl.MakeCurrent(egl_display, egl_surface, egl_surface, egl_context)) {
        whl.egl_display = egl_display
        whl.egl_context = egl_context
        whl.egl_surface = egl_surface
        return GL_Context_EGL { window_handle = whl^, ctx = egl_context, egl_display = egl_display }, true
    }
    return {}, false
}

wayland_gl_present :: proc(whl: ^Window_Handle_Linux_Wayland) {
	if whl.redraw {
		// Get the callback and flag it already to not redraw
		callback := wl.wl_surface_frame(whl.surface)
		whl.redraw = false

		// Add the listener
		wl.wl_callback_add_listener(callback, &frame_callback, whl)

		// Swap the buffers
		egl.SwapBuffers(whl.egl_display, whl.egl_surface)
	}
	wl.display_dispatch(whl.display)
}

