#+build linux

package karl2d

import "linux/glx"
import gl "vendor:OpenGL"
import "log"
import "vendor:egl"
import "core:fmt"

_ :: log

GL_Context :: union {
    GL_Context_GLX,
    GL_Context_EGL
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

    switch whl in handle {
    case Window_Handle_Linux_X11:
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

    case Window_Handle_Linux_Wayland:
        fmt.println("Creating Context")
        EGL_CONTEXT_FLAGS_KHR :: 0x30FC
        EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR :: 0x00000001

        context_flags_bitfield: i32 = EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR
        context_attribs: []i32 = {
            egl.CONTEXT_CLIENT_VERSION, 3,
            EGL_CONTEXT_FLAGS_KHR, context_flags_bitfield,
            egl.NONE,
        }
        egl_context := egl.CreateContext(
            whl.egl_display,
            whl.egl_config,
            egl.NO_CONTEXT,
            raw_data(context_attribs),
        )
        if egl_context == egl.NO_CONTEXT {
            panic("Failed creating EGL context")
        }
        fmt.println("Done creating Context")
        return GL_Context_EGL { window_handle = whl, ctx = egl_context, egl_display = whl.egl_display }, true
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

_gl_load_procs :: proc() {
	gl.load_up_to(3, 3, glx.SetProcAddress)
}

_gl_present :: proc(window_handle: Window_Handle) {
	handle := (^Window_Handle_Linux)(window_handle)
    switch &whl in handle {
        case Window_Handle_Linux_X11:
	        glx.SwapBuffers(whl.display, whl.window)
        case Window_Handle_Linux_Wayland:
            wayland_gl_present(&whl)
    }
}

import wl "linux/wayland"
@(private="package")
wayland_gl_present :: proc(window_handle: ^Window_Handle_Linux_Wayland) {
	if window_handle.redraw {
		// Get the callback and flag it already to not redraw
		callback := wl.wl_surface_frame(window_handle.surface)
		window_handle.redraw = false

		// Add the listener
		wl.wl_callback_add_listener(callback, &frame_callback, nil)

		// Swap the buffers
		egl.SwapBuffers(window_handle.egl_display, window_handle.egl_surface^)
	}
	wl.display_dispatch(window_handle.display)
	wl.display_flush(window_handle.display)
}
