// Partial glX bindings. Just enough to make a context.
package karl2d_glx_bindings

import "vendor:x11/xlib"

foreign import lib "system:GL"

RENDER_TYPE :: 0x8011
RGBA_BIT :: 0x00000001
DRAWABLE_TYPE :: 0x8010
WINDOW_BIT :: 0x00000001
DOUBLEBUFFER :: 5
DEPTH_SIZE :: 12
RED_SIZE :: 8
GREEN_SIZE :: 9
BLUE_SIZE :: 0
ALPHA_SIZE :: 1

CONTEXT_MAJOR_VERSION_ARB :: 0x2091
CONTEXT_MINOR_VERSION_ARB :: 0x2092

CONTEXT_PROFILE_MASK_ARB :: 0x9126
CONTEXT_CORE_PROFILE_BIT_ARB :: 0x00000001

Context :: struct {}
FBConfig :: struct {}
Drawable :: xlib.XID

@(default_calling_convention="c", link_prefix="glX")
foreign lib {
	CreateContext :: proc(dpy: ^xlib.Display, vis: ^xlib.XVisualInfo, shareList: ^Context, direct: b32) -> ^Context ---
	DestroyContext :: proc(dpy: ^xlib.Display, ctx: ^Context) ---
	MakeCurrent :: proc(dpy: ^xlib.Display, drawable: Drawable, ctx: ^Context) -> b32 ---
	GetProcAddress :: proc(procName: cstring) -> rawptr ---
	SwapBuffers :: proc(dpy: ^xlib.Display, drawable: Drawable) ---
	ChooseFBConfig :: proc(dpy: ^xlib.Display, screen: i32, attribList: [^]i32, nelements: ^i32) -> [^]^FBConfig ---
}

CreateContextAttribsARBProc :: proc(
	dpy: ^xlib.Display,
	config: ^FBConfig,
	share_context: ^Context,
	direct: b32,
	attrib_list: [^]i32,
) -> ^Context

SetProcAddress :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = GetProcAddress(name)
}