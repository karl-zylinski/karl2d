package karl2d_glx_bindings

import "vendor:x11/xlib"

foreign import lib "system:GL"

RGBA :: 4
DOUBLE_BUFFER :: 5
DEPTH_SIZE :: 12

Context :: struct {}

GLXDrawable :: xlib.XID

@(default_calling_convention="c", link_prefix="glX")
foreign lib {
	ChooseVisual :: proc(dpy: ^xlib.Display, screen: i32, attribList: [^]i32) -> ^xlib.XVisualInfo ---
	CreateContext :: proc(dpy: ^xlib.Display, vis: ^xlib.XVisualInfo, shareList: ^Context, direct: b32) -> ^Context ---
	MakeCurrent :: proc(dpy: ^xlib.Display, drawable: GLXDrawable, ctx: ^Context) -> b32 ---
	GetProcAddress :: proc(procName: cstring) -> rawptr ---
	SwapBuffers :: proc(dpy: ^xlib.Display, drawable: GLXDrawable) ---
}

SetProcAddress :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = GetProcAddress(name)
}