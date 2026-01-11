#+build linux

package karl2d

import "linux/glx"
import gl "vendor:OpenGL"
import "log"

_ :: log

GL_Context :: struct {
	ctx: ^glx.Context,
	window_handle: Window_Handle_Linux,
}

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	whl := (^Window_Handle_Linux)(window_handle)

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
		return {ctx = ctx, window_handle = whl^}, true
	}

	return {}, false
}

_gl_destroy_context :: proc(ctx: GL_Context) {
	glx.DestroyContext(ctx.window_handle.display, ctx.ctx)
}

_gl_load_procs :: proc() {
	gl.load_up_to(3, 3, glx.SetProcAddress)
}

_gl_present :: proc(ctx: GL_Context) {
	glx.SwapBuffers(ctx.window_handle.display, ctx.window_handle.window)
}