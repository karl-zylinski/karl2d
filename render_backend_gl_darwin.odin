#+build darwin

package karl2d

import "core:os"
import gl "vendor:OpenGL"
import "darwin/nsgl"
import "log"

GL_Context :: ^nsgl.OpenGLContext

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	// Create pixel format attributes (null-terminated array)
	attrs := [?]u32 {
		nsgl.OpenGLPFADoubleBuffer,
		nsgl.OpenGLPFAColorSize, 24,
		nsgl.OpenGLPFAAlphaSize, 8,
		nsgl.OpenGLPFADepthSize, 24,
		nsgl.OpenGLPFAAccelerated,
		nsgl.OpenGLPFANoRecovery,
		nsgl.OpenGLPFAOpenGLProfile, nsgl.OpenGLProfileVersion3_2Core,
		0, // Terminator
	}

	// Create pixel format
	pixel_format := nsgl.OpenGLPixelFormat_alloc()
	pixel_format = pixel_format->initWithAttributes(raw_data(attrs[:]))

	if pixel_format == nil {
		log.error("Failed to create NSOpenGLPixelFormat")
		return {}, false
	}

	// Create OpenGL context
	opengl_context := nsgl.OpenGLContext_alloc()
	opengl_context = opengl_context->initWithFormat(pixel_format, nil)

	if opengl_context == nil {
		log.error("Failed to create NSOpenGLContext")
		return {}, false
	}

	// Disable Retina resolution - render at point size and let macOS stretch
	// This allows draw calls to use expected coords (e.g. 1280x720) without scaling
	// TODO: we should fix this, but will need to decide on how to handle HiDPI
	wh := (Window_Handle_Darwin)(window_handle)
	view := wh->contentView()
	nsgl.View_setWantsBestResolutionOpenGLSurface(view, false)

	opengl_context->setView(view)
	opengl_context->makeCurrentContext()

	// Enable vsync
	swap_interval := [1]i32{1}
	opengl_context->setValues(raw_data(swap_interval[:]), nsgl.OpenGLContextParameterSwapInterval)

	return opengl_context, true
}

_gl_destroy_context :: proc(_: GL_Context) {
	nsgl.OpenGLContext_clearCurrentContext()
}

_gl_load_procs :: proc(ctx: GL_Context) {
	gl.load_up_to(3, 3, macos_gl_set_proc_address)
}

// the OpenGL shared library is loaded from OpenGL.framework when we initialize it in _gl_get_context
macos_gl_set_proc_address :: proc(p: rawptr, name: cstring) {
	// special handle meaning "search all currently loaded shared libraries"
	RTLD_DEFAULT :: rawptr(~uintptr(0) - 1) // -2 cast to pointer
	(^rawptr)(p)^ = os._unix_dlsym(RTLD_DEFAULT, name)
}

_gl_present :: proc(ctx: GL_Context) {
	ctx->flushBuffer()
}

_gl_context_viewport_resized :: proc(ctx: GL_Context) {
	ctx->update()
}
