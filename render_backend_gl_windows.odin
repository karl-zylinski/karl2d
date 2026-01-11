#+build windows

package karl2d

import win32 "core:sys/windows"
import gl "vendor:OpenGL"
import "log"

GL_Context :: struct {
	hglrc: win32.HGLRC,
	hwnd: win32.HWND
}

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	hwnd := win32.HWND(window_handle)
	hdc := win32.GetWindowDC(hwnd)

	pfd := win32.PIXELFORMATDESCRIPTOR {
		nSize = size_of(win32.PIXELFORMATDESCRIPTOR),
		nVersion = 1,
		dwFlags = win32.PFD_DRAW_TO_WINDOW | win32.PFD_SUPPORT_OPENGL | win32.PFD_DOUBLEBUFFER,
		iPixelType = win32.PFD_TYPE_RGBA,
		cColorBits = 32,
		iLayerType = win32.PFD_MAIN_PLANE,
	}

	fmt := win32.ChoosePixelFormat(hdc, &pfd)
	win32.SetPixelFormat(hdc, fmt, &pfd)
	dummy_ctx := win32.wglCreateContext(hdc)

	win32.wglMakeCurrent(hdc, dummy_ctx)

	win32.gl_set_proc_address(&win32.wglChoosePixelFormatARB, "wglChoosePixelFormatARB")
	win32.gl_set_proc_address(&win32.wglCreateContextAttribsARB, "wglCreateContextAttribsARB")
	win32.gl_set_proc_address(&win32.wglSwapIntervalEXT, "wglSwapIntervalEXT")

	if win32.wglChoosePixelFormatARB == nil {
		log.error("Failed fetching wglChoosePixelFormatARB")
		return {}, false
	}

	if win32.wglCreateContextAttribsARB == nil {
		log.error("Failed fetching wglCreateContextAttribsARB")
		return {}, false
	}

	if win32.wglSwapIntervalEXT == nil {
		log.error("Failed fetching wglSwapIntervalEXT")
		return {}, false
	}

	pixel_format_ilist := [?]i32 {
		win32.WGL_DRAW_TO_WINDOW_ARB, 1,
		win32.WGL_SUPPORT_OPENGL_ARB, 1,
		win32.WGL_DOUBLE_BUFFER_ARB, 1,
		win32.WGL_PIXEL_TYPE_ARB, win32.WGL_TYPE_RGBA_ARB,
		win32.WGL_COLOR_BITS_ARB, 32,
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
	hglrc := win32.wglCreateContextAttribsARB(hdc, nil, nil)
	win32.wglMakeCurrent(hdc, hglrc)
	win32.wglSwapIntervalEXT(1)
	return {hglrc, hwnd}, true
}

_gl_destroy_context :: proc(ctx: GL_Context) {
	win32.wglDeleteContext(ctx.hglrc)
}

_gl_load_procs :: proc() {
	gl.load_up_to(3, 3, win32.gl_set_proc_address)
}

_gl_present :: proc(ctx: GL_Context) {
	hdc := win32.GetWindowDC(ctx.hwnd)
	win32.SwapBuffers(hdc)
}

_gl_context_viewport_resized :: proc(_: GL_Context) {}
