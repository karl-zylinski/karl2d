// Wraps the slice of vendor:egl that Karl2D's Wayland GL glue needs, loading it with dlopen
// instead of a static foreign import. Karl2D compiles in both the X11 and the Wayland backend and
// only one of them runs, so linking libEGL unconditionally would require every machine to have it
// installed.
//
// vendor:egl stays imported for its types and constants, which links nothing on its own. Calling
// a procedure directly on it puts libEGL straight back into the link list.
package karl2d_egl_bindings

import vendor_egl "vendor:egl"
import "../dynload"

//-------//
// TYPES //
//-------//

Boolean           :: vendor_egl.Boolean
Config            :: vendor_egl.Config
Context           :: vendor_egl.Context
Display           :: vendor_egl.Display
NativeDisplayType :: vendor_egl.NativeDisplayType
NativeWindowType  :: vendor_egl.NativeWindowType
Surface           :: vendor_egl.Surface

//-----------//
// CONSTANTS //
//-----------//

NO_CONTEXT :: vendor_egl.NO_CONTEXT
NO_DISPLAY :: vendor_egl.NO_DISPLAY
NO_SURFACE :: vendor_egl.NO_SURFACE

NONE                    :: vendor_egl.NONE
ALPHA_SIZE              :: vendor_egl.ALPHA_SIZE
BLUE_SIZE               :: vendor_egl.BLUE_SIZE
CONTEXT_CLIENT_VERSION  :: vendor_egl.CONTEXT_CLIENT_VERSION
DEPTH_SIZE              :: vendor_egl.DEPTH_SIZE
GREEN_SIZE              :: vendor_egl.GREEN_SIZE
OPENGL_API              :: vendor_egl.OPENGL_API
OPENGL_BIT              :: vendor_egl.OPENGL_BIT
RED_SIZE                :: vendor_egl.RED_SIZE
RENDERABLE_TYPE         :: vendor_egl.RENDERABLE_TYPE
SURFACE_TYPE            :: vendor_egl.SURFACE_TYPE
WINDOW_BIT              :: vendor_egl.WINDOW_BIT

//------------//
// PROCEDURES //
//------------//

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

//------//
// LOAD //
//------//

LIB_EGL :: "libEGL.so.1"

load :: proc() -> (err: dynload.Error, what: string) {
	symbols := []dynload.Symbol {
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

	return dynload.load(LIB_EGL, symbols)
}
