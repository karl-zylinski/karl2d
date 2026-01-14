// Glues together OpenGL with an X11 window. This is done by making a glX context and using it to
// SwapBuffers etc.
#+build linux

package karl2d

import "linux/glx"
import gl "vendor:OpenGL"
import X "vendor:x11/xlib"
import "log"

@(private="package")
make_linux_gl_x11_glue :: proc(
	display: ^X.Display,
	window: ^X.Window,
	allocator: runtime.Allocator,
	loc := #caller_location
) -> Window_Render_Glue {
	state := new(Linux_GL_X11_Glue_State, allocator, loc)
	state.display = display
	state.window = window
	return {
		state = (^Window_Render_Glue_State)(state),

		// these casts just make the proc take a Windows_GL_Glue_State instead of a Window_Render_Glue_State
		make_context = cast(proc(state: ^Window_Render_Glue_State) -> bool)(linux_gl_x11_glue_make_context),
		present = cast(proc(state: ^Window_Render_Glue_State))(linux_gl_x11_glue_present),
		destroy = cast(proc(state: ^Window_Render_Glue_State))(linux_gl_x11_glue_destroy),
		viewport_resized = cast(proc(state: ^Window_Render_Glue_State))(linux_gl_x11_glue_viewport_resized),
	}
}

Linux_GL_X11_Glue_State :: struct {
	display: ^X.Display,
	window: ^X.Window,
	gl_ctx: ^glx.Context,
}

linux_gl_x11_glue_make_context :: proc(s: ^Linux_GL_X11_Glue_State) -> bool {
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
	screen := X.DefaultScreen(s.window)
	fbc := glx.ChooseFBConfig(s.display, screen, raw_data(visual_attribs), &num_fbc)
   
	if fbc == nil {
		log.error("Failed choosing GLX framebuffer config")
		return false
	}

	glxCreateContextAttribsARB: glx.CreateContextAttribsARBProc
	glx.SetProcAddress((rawptr)(&glxCreateContextAttribsARB), "glXCreateContextAttribsARB")
	
	if glxCreateContextAttribsARB == {} {
		log.error("Failed fetching glXCreateContextAttribsARB")
		return false
	}

	context_attribs := []i32 {
		glx.CONTEXT_MAJOR_VERSION_ARB, 3,
		glx.CONTEXT_MINOR_VERSION_ARB, 3,
		glx.CONTEXT_PROFILE_MASK_ARB, glx.CONTEXT_CORE_PROFILE_BIT_ARB,
		0,
	}

	s.gl_ctx = glxCreateContextAttribsARB(s.display, fbc[0], nil, true, raw_data(context_attribs))

	if glx.MakeCurrent(s.display, s.window, s.gl_ctx) {
		gl.load_up_to(3, 3, glx.SetProcAddress)

		return true
	}

	return false
}

linux_gl_x11_glue_present :: proc(s: ^Linux_GL_X11_Glue_State) {
	glx.SwapBuffers(s.display, s.window)
}

linux_gl_x11_glue_destroy :: proc(s: ^Linux_GL_X11_Glue_State) {
	glx.DestroyContext(s.display, s.gl_ctx)
}

linux_gl_x11_glue_viewport_resized :: proc(s: ^Linux_GL_X11_Glue_State) {
}