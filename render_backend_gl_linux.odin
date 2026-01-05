#+build linux

package karl2d

import "linux/glx"
import gl "vendor:OpenGL"

GL_Context :: ^glx.Context

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	whl := (^Window_Handle_Linux)(window_handle)
	choose_visual_params := []i32 {
		glx.RGBA,
		glx.DEPTH_SIZE, 24,
		glx.DOUBLE_BUFFER,
		0,
	}
	visual := glx.ChooseVisual(whl.display, 0, raw_data(choose_visual_params))

	ctx := glx.CreateContext(whl.display, visual, nil, true)

	if glx.MakeCurrent(whl.display, whl.window, ctx) {
		return ctx, true
	}

	return {}, false
}

_gl_destroy_context :: proc(ctx: GL_Context) {
}


_gl_load_procs :: proc() {
	gl.load_up_to(3, 3, glx.SetProcAddress)
}

_gl_present :: proc(window_handle: Window_Handle) {
	whl := (^Window_Handle_Linux)(window_handle)
	glx.SwapBuffers(whl.display, whl.window)
	//hdc := win32.GetWindowDC(win32.HWND(window_handle))
	//win32.SwapBuffers(hdc)
}