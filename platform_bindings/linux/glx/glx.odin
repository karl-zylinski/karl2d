// Partial glX bindings. Just enough to make a context. The library is loaded at runtime, so that
// machines that only have Wayland do not need it installed.
package karl2d_glx

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

DestroyContext: proc "c" (dpy: ^x11.Display, ctx: ^Context)

MakeCurrent: proc "c" (dpy: ^x11.Display, drawable: Drawable, ctx: ^Context) -> b32

GetProcAddress: proc "c" (procName: cstring) -> rawptr

SwapBuffers: proc "c" (dpy: ^x11.Display, drawable: Drawable)

ChooseFBConfig: proc "c" (
	dpy: ^x11.Display,
	screen: i32,
	attribList: [^]i32,
	nelements: ^i32,
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

load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr: rawptr,
	} {
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
