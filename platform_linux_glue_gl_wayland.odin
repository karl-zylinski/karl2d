// Glues together OpenGL with a Wayland window. This is done by making an EGL context and using
// it to SwapBuffers etc.
#+build linux

package karl2d

import gl "vendor:OpenGL"
import "log"
import egl "platform_bindings/linux/egl"
import wl "platform_bindings/linux/wayland"
import "base:runtime"
import "core:c"
import "core:slice"
import "core:sys/posix"
import "core:time"

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
	state.window = window
	state.allocator = allocator

	// The frame callback gets an event queue of its own. It is requested on a proxy wrapper of
	// the surface, which is what makes its `done` event land in that queue instead of in the
	// default one. Waiting for a frame in `linux_gl_wayland_glue_present` then dispatches only
	// frame callbacks. Input and `xdg_toplevel.configure` stay queued and are dispatched at the
	// top of the next frame, where the rest of the code expects them.
	state.frame_queue = wl.display_create_queue(display)
	state.frame_surface = (^wl.Surface)(wl.proxy_create_wrapper(surface))
	wl.proxy_set_queue(state.frame_surface, state.frame_queue)

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
	frame_queue: ^wl.Event_Queue,
	frame_surface: ^wl.Surface,
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

// How long `linux_gl_wayland_glue_present` waits for the compositor to signal that it wants a new
// frame. The wait needs a timeout because a compositor sends no frame callbacks at all for a window
// it doesn't show, and the game would hang. It also must not fire while the window is visible: a
// whole frame is at stake, so anything shorter than the display's frame time times out every frame
// and the game free runs. 50 ms leaves room down to 20 Hz.
FRAME_CALLBACK_TIMEOUT :: 50*time.Millisecond

linux_gl_wayland_glue_present :: proc(s: ^Linux_GL_Wayland_Glue_State) {
	if s.frame_callback != nil {
		// Hand the frame to the GPU before going to sleep, so it has something to work on
		// during the wait.
		gl.Flush()
		wayland_wait_for_frame(s)
	}

	// Nothing to request while the previous callback is still pending, which is the case when
	// the wait above timed out. That one is waited for again next frame.
	if s.frame_callback == nil {
		@static listener := wl.Callback_Listener {
			proc "c" (data: rawptr, callback: ^wl.Callback, callback_data: u32) {
				wl.destroy(callback)
				(^^wl.Callback)(data)^ = nil // Clear callback to exit the loop
			},
		}
		s.frame_callback = wl.surface_frame(s.frame_surface)
		wl.add_listener(s.frame_callback, &listener, &s.frame_callback)
	}

	// Non-blocking swap (egl.SwapInterval is 0). It commits the surface, which is what carries
	// the frame request above to the compositor.
	egl.SwapBuffers(s.egl_display, s.egl_surface)
}

// Waits for the frame callback the previous `linux_gl_wayland_glue_present` requested. This is what
// throttles the frame rate now that EGL's own vsync is off. Returns when the callback arrives, when
// `FRAME_CALLBACK_TIMEOUT` runs out or when the connection to the compositor breaks. The timeout is
// a budget for the whole wait, not for each poll, so unrelated events arriving in a stream cannot
// stretch it indefinitely.
@(private="file")
wayland_wait_for_frame :: proc(s: ^Linux_GL_Wayland_Glue_State) {
	fd := posix.FD(wl.display_get_fd(s.display))
	deadline := time.tick_add(time.tick_now(), FRAME_CALLBACK_TIMEOUT)

	for s.frame_callback != nil {
		// Reading the socket has to be announced first. That fails while the frame queue still
		// holds events, and dispatching those may be all that is needed.
		for wl.display_prepare_read_queue(s.display, s.frame_queue) != 0 {
			if wl.display_dispatch_queue_pending(s.display, s.frame_queue) < 0 {
				return
			}
		}

		if s.frame_callback == nil {
			wl.display_cancel_read(s.display)
			return
		}

		// Sends the frame request off. EAGAIN only means the socket buffer is full, and the
		// poll below gives the compositor time to drain it.
		if wl.display_flush(s.display) < 0 && posix.errno() != .EAGAIN {
			wl.display_cancel_read(s.display)
			return
		}

		remaining := time.tick_diff(time.tick_now(), deadline)

		if remaining <= 0 {
			wl.display_cancel_read(s.display)
			return
		}

		pfd := posix.pollfd {
			fd     = fd,
			events = {.IN},
		}

		// Rounded up so that a sliver of remaining time doesn't turn into a zero timeout, which
		// would spin.
		timeout_ms := c.int((remaining + time.Millisecond - 1)/time.Millisecond)
		poll_res := posix.poll(&pfd, nfds=1, timeout=timeout_ms)

		if poll_res <= 0 {
			wl.display_cancel_read(s.display)

			// Zero is the timeout. -1 with EINTR or EAGAIN is just a signal arriving, so try
			// again until the deadline runs out. Anything else is a real error.
			if poll_res < 0 && (posix.errno() == .EINTR || posix.errno() == .EAGAIN) {
				continue
			}

			return
		}

		if wl.display_read_events(s.display) < 0 {
			return
		}

		if wl.display_dispatch_queue_pending(s.display, s.frame_queue) < 0 {
			return
		}
	}
}

linux_gl_wayland_glue_destroy :: proc(s: ^Linux_GL_Wayland_Glue_State) {
	if s.frame_callback != nil {
		wl.destroy(s.frame_callback)
	}

	wl.proxy_wrapper_destroy(s.frame_surface)
	wl.event_queue_destroy(s.frame_queue)
	egl.DestroyContext(s.egl_display, s.egl_context)
	a := s.allocator
	free(s, a)
}

linux_gl_wayland_glue_viewport_resized :: proc(s: ^Linux_GL_Wayland_Glue_State) {
}
