#+build linux:android
#+private package
package karl2d

import "base:runtime"
import "log"
import "core:sys/android"
import egl "vendor:egl"
import gl "vendor:OpenGL"

create_android_gl_glue :: proc(
	window: ^android.ANativeWindow,
	allocator: runtime.Allocator,
	loc := #caller_location,
) -> ^Window_Render_Glue {
	state := new(Android_GL_Glue, allocator, loc)
	state.window = window
	state.allocator = allocator

	state.interface = {
		make_context = android_gl_glue_make_context,
		present = android_gl_glue_present,
		set_vsync = android_gl_glue_set_vsync,
		destroy = android_gl_glue_destroy,
		viewport_resized = android_gl_glue_viewport_resized,
	}

	return state
}

Android_GL_Glue :: struct {
	using interface: Window_Render_Glue,
	window: ^android.ANativeWindow,
	egl_display: egl.Display,
	egl_config: egl.Config,
	egl_surface: egl.Surface,
	egl_context: egl.Context,
	vsync: bool,
	allocator: runtime.Allocator,
}

android_gl_glue_make_context :: proc(s: ^Android_GL_Glue, options: Init_Options) -> bool {
	s.vsync = !options.disable_vsync
	s.egl_display = egl.GetDisplay(egl.DEFAULT_DISPLAY)

	if s.egl_display == egl.NO_DISPLAY {
		log.error("Failed to get EGL display")
		return false
	}

	major, minor: i32

	if !egl.Initialize(s.egl_display, &major, &minor) {
		log.error("Can't initialize EGL display")
		return false
	}

	config_attribs := [?]i32 {
		egl.SURFACE_TYPE, egl.WINDOW_BIT,
		egl.RENDERABLE_TYPE, egl.OPENGL_ES3_BIT,
		egl.RED_SIZE, 8,
		egl.GREEN_SIZE, 8,
		egl.BLUE_SIZE, 8,
		egl.ALPHA_SIZE, 0,
		egl.DEPTH_SIZE, options.depth_test ? 24 : 0,
		egl.SAMPLE_BUFFERS, options.anti_alias ? 1 : 0,
		egl.SAMPLES, options.anti_alias ? 4 : 0,
		egl.NONE,
	}

	num_configs: i32
	choose_ok := egl.ChooseConfig(s.egl_display, &config_attribs[0], &s.egl_config, 1, &num_configs)

	if !choose_ok || num_configs == 0 {
		log.error("Failed to find/choose EGL config")
		return false
	}

	egl.BindAPI(egl.OPENGL_ES_API)

	context_attribs := [?]i32 {
		egl.CONTEXT_CLIENT_VERSION, 3,
		egl.NONE,
	}

	s.egl_context = egl.CreateContext(
		s.egl_display,
		s.egl_config,
		egl.NO_CONTEXT,
		&context_attribs[0],
	)

	if s.egl_context == egl.NO_CONTEXT {
		log.error("Failed creating EGL context")
		return false
	}

	android_gl_glue_set_window(s, s.window)

	if s.egl_surface == egl.NO_SURFACE {
		return false
	}

	gl.load_gles_up_to(3, 0, egl.gl_set_proc_address)
	return true
}

android_gl_glue_set_window :: proc(s: ^Android_GL_Glue, window: ^android.ANativeWindow) {
	s.window = window

	if s.egl_context == egl.NO_CONTEXT {
		return
	}

	if s.egl_surface != egl.NO_SURFACE {
		egl.MakeCurrent(s.egl_display, egl.NO_SURFACE, egl.NO_SURFACE, egl.NO_CONTEXT)
		egl.DestroySurface(s.egl_display, s.egl_surface)
		s.egl_surface = egl.NO_SURFACE
	}

	if window == nil {
		return
	}

	s.egl_surface = egl.CreateWindowSurface(
		s.egl_display,
		s.egl_config,
		egl.NativeWindowType(window),
		nil,
	)

	if s.egl_surface == egl.NO_SURFACE {
		log.errorf("Error creating window surface. EGL error: 0x%x", egl.GetError())
		return
	}

	if !egl.MakeCurrent(s.egl_display, s.egl_surface, s.egl_surface, s.egl_context) {
		log.errorf("Failed making EGL context current. EGL error: 0x%x", egl.GetError())
		egl.DestroySurface(s.egl_display, s.egl_surface)
		s.egl_surface = egl.NO_SURFACE
		return
	}

	egl.SwapInterval(s.egl_display, s.vsync ? 1 : 0)
}

android_gl_glue_present :: proc(s: ^Android_GL_Glue) {
	if s.egl_surface != egl.NO_SURFACE {
		egl.SwapBuffers(s.egl_display, s.egl_surface)
	}
}

android_gl_glue_set_vsync :: proc(s: ^Android_GL_Glue, enabled: bool) {
	s.vsync = enabled

	if s.egl_surface != egl.NO_SURFACE {
		egl.SwapInterval(s.egl_display, enabled ? 1 : 0)
	}
}

android_gl_glue_destroy :: proc(s: ^Android_GL_Glue) {
	if s.egl_display != egl.NO_DISPLAY {
		egl.MakeCurrent(s.egl_display, egl.NO_SURFACE, egl.NO_SURFACE, egl.NO_CONTEXT)

		if s.egl_surface != egl.NO_SURFACE {
			egl.DestroySurface(s.egl_display, s.egl_surface)
		}

		if s.egl_context != egl.NO_CONTEXT {
			egl.DestroyContext(s.egl_display, s.egl_context)
		}

		egl.Terminate(s.egl_display)
	}

	a := s.allocator
	free(s, a)
}

android_gl_glue_viewport_resized :: proc(s: ^Android_GL_Glue) {
}
