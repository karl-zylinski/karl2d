#+build windows

package karl2d

import win32 "core:sys/windows"
import gl "vendor:OpenGL"
import "core:log"

GL_Context :: win32.HGLRC

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	hdc := win32.GetWindowDC(win32.HWND(window_handle))

	pfd := win32.PIXELFORMATDESCRIPTOR {
		size_of(win32.PIXELFORMATDESCRIPTOR),
		1,
		win32.PFD_DRAW_TO_WINDOW | win32.PFD_SUPPORT_OPENGL | win32.PFD_DOUBLEBUFFER,    // Flags
		win32.PFD_TYPE_RGBA, // The kind of framebuffer. RGBA or palette.
		32,                  // Colordepth of the framebuffer.
		0, 0, 0, 0, 0, 0,
		0,
		0,
		0,
		0, 0, 0, 0,
		24,                  // Number of bits for the depthbuffer
		8,                   // Number of bits for the stencilbuffer
		0,                   // Number of Aux buffers in the framebuffer.
		win32.PFD_MAIN_PLANE,
		0,
		0, 0, 0,
	}

	fmt := win32.ChoosePixelFormat(hdc, &pfd)
	win32.SetPixelFormat(hdc, fmt, &pfd)
	dummy_ctx := win32.wglCreateContext(hdc)

	win32.wglMakeCurrent(hdc, dummy_ctx)

	win32.gl_set_proc_address(&win32.wglChoosePixelFormatARB, "wglChoosePixelFormatARB")
	win32.gl_set_proc_address(&win32.wglCreateContextAttribsARB, "wglCreateContextAttribsARB")

	if win32.wglChoosePixelFormatARB == nil {
		log.error("Failed fetching wglChoosePixelFormatARB")
		return {}, false
	}

	if win32.wglCreateContextAttribsARB == nil {
		log.error("Failed fetching wglCreateContextAttribsARB")
		return {}, false
	}

	pixel_format_ilist := [?]i32 {
		win32.WGL_DRAW_TO_WINDOW_ARB, 1,
		win32.WGL_SUPPORT_OPENGL_ARB, 1,
		win32.WGL_DOUBLE_BUFFER_ARB, 1,
		win32.WGL_PIXEL_TYPE_ARB, win32.WGL_TYPE_RGBA_ARB,
		win32.WGL_COLOR_BITS_ARB, 32,
		win32.WGL_DEPTH_BITS_ARB, 24,
		win32.WGL_STENCIL_BITS_ARB, 8,
		0,
	}

	pixel_format: i32
	num_formats: u32

	valid_pixel_format := win32.wglChoosePixelFormatARB(hdc, raw_data(pixel_format_ilist[:]),
		nil, 1, &pixel_format, &num_formats)

	if !valid_pixel_format {
		return {}, false
	}

	win32.SetPixelFormat(hdc, pixel_format, nil)
	ctx := win32.wglCreateContextAttribsARB(hdc, nil, nil)
	win32.wglMakeCurrent(hdc, ctx)
	return ctx, true
}

_gl_destroy_context :: proc(ctx: GL_Context) {
	win32.wglDeleteContext(ctx)
}

_gl_load_procs :: proc() {
	gl.load_up_to(3, 3, win32.gl_set_proc_address)
}

_gl_present :: proc(window_handle: Window_Handle) {
	hdc := win32.GetWindowDC(win32.HWND(window_handle))
	win32.SwapBuffers(hdc)
}