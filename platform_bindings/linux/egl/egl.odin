// Partial EGL bindings. Just enough for the Wayland GL glue to make a context. Loaded with dlopen
// instead of a static foreign import. Karl2D compiles in both the X11 and the Wayland backend and
// only one of them runs, so linking libEGL unconditionally would require every machine to have it
// installed.
package karl2d_egl_bindings

import "core:dynlib"

NativeDisplayType :: distinct rawptr
NativeWindowType :: distinct rawptr
Display :: distinct rawptr
Surface :: distinct rawptr
Config :: distinct rawptr
Context :: distinct rawptr

Boolean :: b32

NO_DISPLAY :: Display(uintptr(0))
NO_SURFACE :: Surface(uintptr(0))
NO_CONTEXT :: Context(uintptr(0))

WINDOW_BIT :: 0x0004
OPENGL_BIT :: 0x0008

ALPHA_SIZE :: 0x3021
BLUE_SIZE :: 0x3022
GREEN_SIZE :: 0x3023
RED_SIZE :: 0x3024
DEPTH_SIZE :: 0x3025

SURFACE_TYPE :: 0x3033
NONE :: 0x3038
RENDERABLE_TYPE :: 0x3040

CONTEXT_CLIENT_VERSION :: 0x3098
OPENGL_API :: 0x30A2

GetDisplay: proc "c" (display: NativeDisplayType) -> Display

Initialize: proc "c" (display: Display, major: ^i32, minor: ^i32) -> Boolean

ChooseConfig: proc "c" (
	display:     Display,
	attrib_list: ^i32,
	configs:     [^]Config,
	config_size: i32,
	num_config:  ^i32,
) -> Boolean

CreateWindowSurface: proc "c" (
	display:       Display,
	config:        Config,
	native_window: NativeWindowType,
	attrib_list:   ^i32,
) -> Surface

BindAPI: proc "c" (api: u32) -> Boolean

CreateContext: proc "c" (
	display:       Display,
	config:        Config,
	share_context: Context,
	attrib_list:   ^i32,
) -> Context

MakeCurrent: proc "c" (display: Display, draw: Surface, read: Surface, ctx: Context) -> Boolean

SwapInterval: proc "c" (display: Display, interval: i32) -> Boolean

SwapBuffers: proc "c" (display: Display, surface: Surface) -> Boolean

DestroyContext: proc "c" (display: Display, ctx: Context) -> Boolean

GetProcAddress: proc "c" (name: cstring) -> rawptr

// Wraps `GetProcAddress` to match `gl.Set_Proc_Address_Type`, which uses the default calling
// convention rather than "c".
gl_set_proc_address :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = GetProcAddress(name)
}

LIB_EGL :: "libEGL.so.1"

// Loads libEGL. On failure `missing` names the library or the symbol that was not found.
load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr:  rawptr,
	} {
		{"eglGetDisplay", &GetDisplay},
		{"eglInitialize", &Initialize},
		{"eglChooseConfig", &ChooseConfig},
		{"eglCreateWindowSurface", &CreateWindowSurface},
		{"eglBindAPI", &BindAPI},
		{"eglCreateContext", &CreateContext},
		{"eglMakeCurrent", &MakeCurrent},
		{"eglSwapInterval", &SwapInterval},
		{"eglSwapBuffers", &SwapBuffers},
		{"eglDestroyContext", &DestroyContext},
		{"eglGetProcAddress", &GetProcAddress},
	}

	lib, lib_ok := dynlib.load_library(LIB_EGL)

	if !lib_ok {
		return LIB_EGL, false
	}

	for s in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, s.name)

		if !addr_ok {
			dynlib.unload_library(lib)
			return s.name, false
		}

		(^rawptr)(s.ptr)^ = addr
	}

	return "", true
}
