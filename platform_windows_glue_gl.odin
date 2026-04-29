// Glues together OpenGL with a Windows window. This is done by making a WGL context and using it
// to SwapBuffers etc.
#+build windows
#+private file
package karl2d

import win32 "core:sys/windows"
import gl "vendor:OpenGL"
import "base:runtime"
import "core:slice"
import "log"

@(private="package")
make_windows_gl_glue :: proc(
	hwnd: win32.HWND,
	allocator: runtime.Allocator,
	loc := #caller_location
) -> Window_Render_Glue {
	state := new(Windows_GL_Glue_State, allocator, loc)
	state.hwnd = hwnd
	state.allocator = allocator
	return {
		state = (^Window_Render_Glue_State)(state),

		// these casts just make the proc take a Windows_GL_Glue_State instead of a Window_Render_Glue_State
		make_context = cast(proc(state: ^Window_Render_Glue_State, init_options: Init_Options) -> bool)(windows_gl_glue_make_context),
		present = cast(proc(state: ^Window_Render_Glue_State))(windows_gl_glue_present),
		destroy = cast(proc(state: ^Window_Render_Glue_State))(windows_gl_glue_destroy),
		viewport_resized = cast(proc(state: ^Window_Render_Glue_State))(windows_gl_glue_viewport_resized),
	}
}

Windows_GL_Glue_State :: struct {
	hwnd: win32.HWND,
	gl_ctx: win32.HGLRC,
	device_ctx: win32.HDC,
	allocator: runtime.Allocator,
}

windows_gl_glue_make_context :: proc(s: ^Windows_GL_Glue_State, options: Init_Options) -> bool {
	// We make an invisible dummy window and use that to get a dummy context. We need the dummy
	// context because we can't get the actual context we need without already having a context.
	DUMMY_CLASS :: "karl2d_wgl_dummy"

	wc := win32.WNDCLASSW{
		style = win32.CS_OWNDC,
		lpfnWndProc = win32.DefWindowProcW,
		hInstance = win32.HINSTANCE(win32.GetModuleHandleW(nil)),
		lpszClassName = DUMMY_CLASS,
	}

	win32.RegisterClassW(&wc)

	dummy_hwnd := win32.CreateWindowExW(
		0,
		wc.lpszClassName,
		"dummy",
		0, // hidden
		0, 0, 1, 1,
		nil, nil,
		wc.hInstance,
		nil,
	)

	if dummy_hwnd == nil {
		return false
	}

	defer win32.DestroyWindow(dummy_hwnd)

	dummy_dc := win32.GetDC(dummy_hwnd)

	if dummy_dc == nil {
		return false
	}

	defer win32.ReleaseDC(dummy_hwnd, dummy_dc)

	pfd := win32.PIXELFORMATDESCRIPTOR {
		nSize = size_of(win32.PIXELFORMATDESCRIPTOR),
		nVersion = 1,
		dwFlags = win32.PFD_DRAW_TO_WINDOW | win32.PFD_SUPPORT_OPENGL | win32.PFD_DOUBLEBUFFER,
		iPixelType = win32.PFD_TYPE_RGBA,
		cColorBits = 32,
		iLayerType = win32.PFD_MAIN_PLANE,
	}

	fmt := win32.ChoosePixelFormat(dummy_dc, &pfd)
	win32.SetPixelFormat(dummy_dc, fmt, &pfd)
	dummy_ctx := win32.wglCreateContext(dummy_dc)
	defer win32.wglDeleteContext(dummy_ctx)

	win32.wglMakeCurrent(dummy_dc, dummy_ctx)

	win32.gl_set_proc_address(&win32.wglChoosePixelFormatARB, "wglChoosePixelFormatARB")
	win32.gl_set_proc_address(&win32.wglCreateContextAttribsARB, "wglCreateContextAttribsARB")
	win32.gl_set_proc_address(&win32.wglSwapIntervalEXT, "wglSwapIntervalEXT")

	if win32.wglChoosePixelFormatARB == nil {
		log.error("Failed fetching wglChoosePixelFormatARB")
		return false
	}

	if win32.wglCreateContextAttribsARB == nil {
		log.error("Failed fetching wglCreateContextAttribsARB")
		return false
	}

	if win32.wglSwapIntervalEXT == nil {
		log.error("Failed fetching wglSwapIntervalEXT")
		return false
	}

	pixel_format_ilist := slice.to_dynamic(
		[]i32 {
			win32.WGL_DRAW_TO_WINDOW_ARB, 1,
			win32.WGL_SUPPORT_OPENGL_ARB, 1,
			win32.WGL_DOUBLE_BUFFER_ARB, 1,
			win32.WGL_PIXEL_TYPE_ARB, win32.WGL_TYPE_RGBA_ARB,
			win32.WGL_COLOR_BITS_ARB, 32,
			win32.WGL_ALPHA_BITS_ARB, 8,
			win32.WGL_DEPTH_BITS_ARB, 24,
		},
		frame_allocator,
	)

	if options.anti_alias {
		append(&pixel_format_ilist, win32.WGL_SAMPLE_BUFFERS_ARB, 1)
		append(&pixel_format_ilist, win32.WGL_SAMPLES_ARB, 4)
	}

	// null termination of list
	append(&pixel_format_ilist, 0)

	pixel_format: i32
	num_formats: u32

	s.device_ctx = win32.GetWindowDC(s.hwnd)
	valid_pixel_format := win32.wglChoosePixelFormatARB(
		s.device_ctx,
		raw_data(pixel_format_ilist[:]),
		nil,
		1,
		&pixel_format,
		&num_formats,
	)

	if !valid_pixel_format {
		return false
	}

	win32.SetPixelFormat(s.device_ctx, pixel_format, nil)
	s.gl_ctx = win32.wglCreateContextAttribsARB(s.device_ctx, nil, nil)
	win32.wglMakeCurrent(s.device_ctx, s.gl_ctx)

	// vsync
	win32.wglSwapIntervalEXT(1)
	
	gl.load_up_to(3, 3, win32.gl_set_proc_address)

	return true
}

windows_gl_glue_present :: proc(s: ^Windows_GL_Glue_State) {
	win32.SwapBuffers(s.device_ctx)
}

windows_gl_glue_destroy :: proc(s: ^Windows_GL_Glue_State) {
	win32.wglDeleteContext(s.gl_ctx)
	a := s.allocator
	free(s, a)
}

windows_gl_glue_viewport_resized :: proc(s: ^Windows_GL_Glue_State) {
}