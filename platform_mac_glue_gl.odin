// Glues together OpenGL with a macOS window. This is done by making a NSGL context and using it
// to swap back buffer etc.
#+build darwin
#+private file
package karl2d

import "core:os"
import gl "vendor:OpenGL"
import "platform_bindings/darwin/nsgl"
import NS "core:sys/darwin/Foundation"
import "log"
import "base:runtime"

@(private="package")
make_mac_gl_glue :: proc(
	window: ^NS.Window,
	allocator: runtime.Allocator,
	loc := #caller_location
) -> Window_Render_Glue {
	state := new(Mac_GL_Glue_State, allocator, loc)
	state.window = window
	return {
		state = (^Window_Render_Glue_State)(state),

		// these casts just make the proc take a Mac_GL_Glue_State instead of a Window_Render_Glue_State
		make_context = cast(proc(state: ^Window_Render_Glue_State) -> bool)(mac_gl_glue_make_context),
		present = cast(proc(state: ^Window_Render_Glue_State))(mac_gl_glue_present),
		destroy = cast(proc(state: ^Window_Render_Glue_State))(mac_gl_glue_destroy),
		viewport_resized = cast(proc(state: ^Window_Render_Glue_State))(mac_gl_glue_viewport_resized),
	}
}

Mac_GL_Glue_State :: struct {
	window: ^NS.Window,
	gl_ctx: ^nsgl.OpenGLContext,
}

mac_gl_glue_make_context :: proc(s: ^Mac_GL_Glue_State) -> bool {
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
		return false
	}

	// Create OpenGL context
	s.gl_ctx = nsgl.OpenGLContext_alloc()

	if s.gl_ctx == nil {
		log.error("Failed to alloc NSOpenGLContext")
		return false
	}

	s.gl_ctx = s.gl_ctx->initWithFormat(pixel_format, nil)

	if s.gl_ctx == nil {
		log.error("Failed to init NSOpenGLContext")
		return false
	}

	// Disable Retina resolution - render at point size and let macOS stretch
	// This allows draw calls to use expected coords (e.g. 1280x720) without scaling
	// TODO: we should fix this, but will need to decide on how to handle HiDPI
	view := s.window->contentView()
	nsgl.View_setWantsBestResolutionOpenGLSurface(view, false)

	s.gl_ctx->setView(view)
	s.gl_ctx->makeCurrentContext()

	// Enable vsync
	swap_interval := [1]i32{1}
	s.gl_ctx->setValues(raw_data(swap_interval[:]), nsgl.OpenGLContextParameterSwapInterval)

	// the OpenGL shared library is loaded from OpenGL.framework when we initialize it in _gl_get_context
	macos_gl_set_proc_address :: proc(p: rawptr, name: cstring) {
		// special handle meaning "search all currently loaded shared libraries"
		RTLD_DEFAULT :: rawptr(~uintptr(0) - 1) // -2 cast to pointer
		(^rawptr)(p)^ = os._unix_dlsym(RTLD_DEFAULT, name)
	}

	gl.load_up_to(3, 3, macos_gl_set_proc_address)

	return true
}

mac_gl_glue_present :: proc(s: ^Mac_GL_Glue_State) {
	s.gl_ctx->flushBuffer()
}

mac_gl_glue_destroy :: proc(s: ^Mac_GL_Glue_State) {
	nsgl.OpenGLContext_clearCurrentContext()
}

mac_gl_glue_viewport_resized :: proc(s: ^Mac_GL_Glue_State) {
	s.gl_ctx->update()
}
