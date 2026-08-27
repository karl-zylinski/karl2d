// Glues together OpenGL with a Wayland window. This is done by making an EGL context and using it to
// SwapBuffers etc.
#+build linux

package karl2d

import gl "vendor:OpenGL"
import "log"
import egl "platform_bindings/linux/egl"
import wl "platform_bindings/linux/wayland"
import "base:runtime"
import "core:slice"
import "core:sys/posix"

@(private="package")
make_linux_gl_wayland_glue :: proc(
	display: ^wl.Display,
	surface: ^wl.Surface,
	window: ^wl.EGL_Window,
	allocator: runtime.Allocator,
	loc := #caller_location
) -> Window_Render_Glue {
	state := new(Linux_GL_Wayland_Glue_State, allocator, loc)
	state.display = display
	state.surface = surface
	state.window = window
	state.allocator = allocator
	return {
		state = (^Window_Render_Glue_State)(state),

		// these casts just make the proc take a Windows_GL_Glue_State instead of a Window_Render_Glue_State
		make_context = cast(proc(state: ^Window_Render_Glue_State, options: Init_Options) -> bool)(linux_gl_wayland_glue_make_context),
		present = cast(proc(state: ^Window_Render_Glue_State))(linux_gl_wayland_glue_present),
		destroy = cast(proc(state: ^Window_Render_Glue_State))(linux_gl_wayland_glue_destroy),
		viewport_resized = cast(proc(state: ^Window_Render_Glue_State))(linux_gl_wayland_glue_viewport_resized),
	}
}

Linux_GL_Wayland_Glue_State :: struct {
	display: ^wl.Display,
	surface: ^wl.Surface,
	frame_callback: ^wl.Callback,
	window: ^wl.EGL_Window,
	egl_context: egl.Context,
	egl_display: egl.Display,
	egl_surface: egl.Surface,
	allocator: runtime.Allocator,
}

linux_gl_wayland_glue_make_context :: proc(s: ^Linux_GL_Wayland_Glue_State, options: Init_Options) -> bool {
	if missing, ok := egl.load(); !ok {
		log.errorf("Failed loading EGL. Could not load %v.", missing)
		return false
	}

	// Get a valid EGL configuration based on some attribute guidelines
	// Create a context based on a "chosen" configuration
	EGL_CONTEXT_FLAGS_KHR :: 0x30FC
	EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR :: 0x00000001
	EGL_SAMPLE_BUFFERS :: 0x3032
	EGL_SAMPLES :: 0x3031

	major, minor, n: i32
	egl_config: egl.Config

	config_attribs := slice.to_dynamic(
		[]i32 {
			egl.SURFACE_TYPE, egl.WINDOW_BIT,
			egl.RED_SIZE, 8,
			egl.GREEN_SIZE, 8,
			egl.BLUE_SIZE, 8,
			egl.ALPHA_SIZE, 0, // Disable surface alpha for now
			egl.DEPTH_SIZE, 24, // Request 24-bit depth buffer
			egl.RENDERABLE_TYPE, egl.OPENGL_BIT,
		},
		frame_allocator,
	)

	if options.anti_alias {
		append(&config_attribs, EGL_SAMPLE_BUFFERS, 1)
		append(&config_attribs, EGL_SAMPLES, 4)
	}

	// null termination
	append(&config_attribs, egl.NONE)

	context_flags_bitfield: i32 = EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR

	context_attribs: []i32 = {
		egl.CONTEXT_CLIENT_VERSION, 3,
		EGL_CONTEXT_FLAGS_KHR, context_flags_bitfield,
		egl.NONE,
	}
	s.egl_display = egl.GetDisplay(egl.NativeDisplayType(s.display))
	if s.egl_display == egl.NO_DISPLAY {
		log.error("Failed to create EGL display")
		return false
	}
	if !egl.Initialize(s.egl_display, &major, &minor) {
		log.error("Can't initialize egl display")
		return false
	}
	if !egl.ChooseConfig(s.egl_display, raw_data(config_attribs), &egl_config, 1, &n) {
		log.error("Failed to find/choose EGL config")
		return false
	}

	s.egl_surface = egl.CreateWindowSurface(
		s.egl_display,
		egl_config,
		egl.NativeWindowType(s.window),
		nil,
	)

	if s.egl_surface == egl.NO_SURFACE {
		log.error("Error creating window surface")
		return false
	}
	// This call must be here before CreateContext
	egl.BindAPI(egl.OPENGL_API)

	s.egl_context = egl.CreateContext(
		s.egl_display,
		egl_config,
		egl.NO_CONTEXT,
		raw_data(context_attribs),
	)
	if s.egl_context == egl.NO_CONTEXT {
		panic("Failed creating EGL context")
	}

	if egl.MakeCurrent(s.egl_display, s.egl_surface, s.egl_surface, s.egl_context) {
		gl.load_up_to(3, 3, egl.gl_set_proc_address)

		// Disable EGL vsync (swap interval = 0)
		// Otherwise egl.SwapBuffers would block indefinitely for unfocused windows.
		// Frame timing is managed in linux_gl_wayland_glue_present using frame callbacks,
		// which ensures that the event loop stays responsive.
		egl.SwapInterval(s.egl_display, interval=0)

		return true
	}

	return false
}

linux_gl_wayland_glue_present :: proc(s: ^Linux_GL_Wayland_Glue_State) {

	wl.display_dispatch_pending(s.display)
	wl.display_flush(s.display)

	if s.frame_callback != nil {
		// Wait for the frame callback done event
		fd := posix.FD(wl.display_get_fd(s.display))

		for s.frame_callback != nil {
			pfd := posix.pollfd{
				fd     = fd,
				events = {posix.Poll_Event_Bits.IN},
			}
			if posix.poll(&pfd, nfds=1, timeout=20) == 0 {
				break // Timeout
			}
			// Drain events until frame_callback get's called
			wl.display_dispatch(s.display)
		}
	}

	if s.frame_callback == nil {
		@static listener := wl.Callback_Listener {
			proc "c" (data: rawptr, callback: ^wl.Callback, callback_data: u32) {
				wl.destroy(callback)
				(^^wl.Callback)(data)^ = nil // Clear callback to exit the loop
			},
		}
		s.frame_callback = wl.surface_frame(s.surface)
		wl.add_listener(s.frame_callback, &listener, &s.frame_callback)
	}

	// Non-blocking swap (egl.SwapInterval is 0)
	egl.SwapBuffers(s.egl_display, s.egl_surface)
}

linux_gl_wayland_glue_destroy :: proc(s: ^Linux_GL_Wayland_Glue_State) {
	if s.frame_callback != nil {
		wl.destroy(s.frame_callback)
	}
	egl.DestroyContext(s.egl_display, s.egl_context)
	a := s.allocator
	free(s, a)
}

linux_gl_wayland_glue_viewport_resized :: proc(s: ^Linux_GL_Wayland_Glue_State) {
}
