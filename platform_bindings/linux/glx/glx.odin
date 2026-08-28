// Partial glX bindings. Just enough to make a context. Loaded with dlopen instead of a static
// foreign import. Karl2D compiles in both the X11 and the Wayland backend and only one of them
// runs, so linking libGL unconditionally would require every machine to have it installed.
package karl2d_glx_bindings

import x11 "../x11"
import "core:dynlib"

RENDER_TYPE :: 0x8011
RGBA_BIT :: 0x00000001
DRAWABLE_TYPE :: 0x8010
WINDOW_BIT :: 0x00000001
DOUBLEBUFFER :: 5
RED_SIZE :: 8
GREEN_SIZE :: 9
BLUE_SIZE :: 10
ALPHA_SIZE :: 11
DEPTH_SIZE :: 12

SAMPLE_BUFFERS :: 100000
SAMPLES        :: 100001

CONTEXT_MAJOR_VERSION_ARB :: 0x2091
CONTEXT_MINOR_VERSION_ARB :: 0x2092

CONTEXT_PROFILE_MASK_ARB :: 0x9126
CONTEXT_CORE_PROFILE_BIT_ARB :: 0x00000001

Context :: struct {}
FBConfig :: struct {}
Drawable :: x11.XID

CreateContext: proc "c" (
	dpy:       ^x11.Display,
	vis:       ^x11.XVisualInfo,
	shareList: ^Context,
	direct:    b32,
) -> ^Context

DestroyContext: proc "c" (dpy: ^x11.Display, ctx: ^Context)

MakeCurrent: proc "c" (dpy: ^x11.Display, drawable: Drawable, ctx: ^Context) -> b32

GetProcAddress: proc "c" (procName: cstring) -> rawptr

SwapBuffers: proc "c" (dpy: ^x11.Display, drawable: Drawable)

ChooseFBConfig: proc "c" (
	dpy:        ^x11.Display,
	screen:     i32,
	attribList: [^]i32,
	nelements:  ^i32,
) -> [^]^FBConfig

CreateContextAttribsARBProc :: proc(
	dpy: ^x11.Display,
	config: ^FBConfig,
	share_context: ^Context,
	direct: b32,
	attrib_list: [^]i32,
) -> ^Context

SwapIntervalEXT :: proc(
	dpy: ^x11.Display,
	drawable: Drawable,
	interval: i32,
)

SetProcAddress :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = GetProcAddress(name)
}

LIB_GL :: "libGL.so.1"

// Loads libGL. On failure `missing` names the library or the symbol that was not found.
load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr:  rawptr,
	} {
		{"glXCreateContext", &CreateContext},
		{"glXDestroyContext", &DestroyContext},
		{"glXMakeCurrent", &MakeCurrent},
		{"glXGetProcAddress", &GetProcAddress},
		{"glXSwapBuffers", &SwapBuffers},
		{"glXChooseFBConfig", &ChooseFBConfig},
	}

	lib, lib_ok := dynlib.load_library(LIB_GL)

	if !lib_ok {
		return LIB_GL, false
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
