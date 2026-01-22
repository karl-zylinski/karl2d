#+build darwin

package nsgl

// NSOpenGL bindings for macOS OpenGL context creation
// These are not included in Odin's standard darwin Foundation bindings

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

msgSend :: intrinsics.objc_send

// Pixel format attribute constants (NSOpenGLPixelFormatAttribute)
OpenGLPFAAllRenderers          :: 1
OpenGLPFADoubleBuffer          :: 5
OpenGLPFAAuxBuffers            :: 7
OpenGLPFAColorSize             :: 8
OpenGLPFAAlphaSize             :: 11
OpenGLPFADepthSize             :: 12
OpenGLPFAStencilSize           :: 13
OpenGLPFAAccumSize             :: 14
OpenGLPFAMinimumPolicy         :: 51
OpenGLPFAMaximumPolicy         :: 52
OpenGLPFASampleBuffers         :: 55
OpenGLPFASamples               :: 56
OpenGLPFAAccelerated           :: 73
OpenGLPFAClosestPolicy         :: 74
OpenGLPFABackingStore          :: 76
OpenGLPFAOpenGLProfile         :: 99
OpenGLPFANoRecovery            :: 72

// OpenGL profile versions
OpenGLProfileVersionLegacy     :: 0x1000  // OpenGL 2.1
OpenGLProfileVersion3_2Core    :: 0x3200  // OpenGL 3.2 Core
OpenGLProfileVersion4_1Core    :: 0x4100  // OpenGL 4.1 Core

// Context parameter for setValues:forParameter:
OpenGLContextParameterSwapInterval :: 222

// NSOpenGLPixelFormat
@(objc_class="NSOpenGLPixelFormat")
OpenGLPixelFormat :: struct { using _: NS.Object }

@(objc_type=OpenGLPixelFormat, objc_name="alloc", objc_is_class_method=true)
OpenGLPixelFormat_alloc :: proc "c" () -> ^OpenGLPixelFormat {
	return msgSend(^OpenGLPixelFormat, OpenGLPixelFormat, "alloc")
}

@(objc_type=OpenGLPixelFormat, objc_name="initWithAttributes")
OpenGLPixelFormat_initWithAttributes :: proc "c" (self: ^OpenGLPixelFormat, attribs: [^]u32) -> ^OpenGLPixelFormat {
	return msgSend(^OpenGLPixelFormat, self, "initWithAttributes:", attribs)
}

// NSOpenGLContext
@(objc_class="NSOpenGLContext")
OpenGLContext :: struct { using _: NS.Object }

@(objc_type=OpenGLContext, objc_name="alloc", objc_is_class_method=true)
OpenGLContext_alloc :: proc "c" () -> ^OpenGLContext {
	return msgSend(^OpenGLContext, OpenGLContext, "alloc")
}

@(objc_type=OpenGLContext, objc_name="initWithFormat")
OpenGLContext_initWithFormat :: proc "c" (self: ^OpenGLContext, format: ^OpenGLPixelFormat, share: ^OpenGLContext) -> ^OpenGLContext {
	return msgSend(^OpenGLContext, self, "initWithFormat:shareContext:", format, share)
}

@(objc_type=OpenGLContext, objc_name="setView")
OpenGLContext_setView :: proc "c" (self: ^OpenGLContext, view: ^NS.View) {
	msgSend(nil, self, "setView:", view)
}

@(objc_type=OpenGLContext, objc_name="view")
OpenGLContext_view :: proc "c" (self: ^OpenGLContext) -> ^NS.View {
	return msgSend(^NS.View, self, "view")
}

@(objc_type=OpenGLContext, objc_name="makeCurrentContext")
OpenGLContext_makeCurrentContext :: proc "c" (self: ^OpenGLContext) {
	msgSend(nil, self, "makeCurrentContext")
}

@(objc_type=OpenGLContext, objc_name="clearCurrentContext", objc_is_class_method=true)
OpenGLContext_clearCurrentContext :: proc "c" () {
	msgSend(nil, OpenGLContext, "clearCurrentContext")
}

@(objc_type=OpenGLContext, objc_name="flushBuffer")
OpenGLContext_flushBuffer :: proc "c" (self: ^OpenGLContext) {
	msgSend(nil, self, "flushBuffer")
}

@(objc_type=OpenGLContext, objc_name="update")
OpenGLContext_update :: proc "c" (self: ^OpenGLContext) {
	msgSend(nil, self, "update")
}

@(objc_type=OpenGLContext, objc_name="setValues")
OpenGLContext_setValues :: proc "c" (self: ^OpenGLContext, vals: [^]i32, param: i32) {
	msgSend(nil, self, "setValues:forParameter:", vals, param)
}

// NSView extension for OpenGL - controls whether to use Retina resolution
// Set to false to render at point size and let macOS stretch to fill window
View_setWantsBestResolutionOpenGLSurface :: proc "c" (self: ^NS.View, wants: bool) {
	msgSend(nil, self, "setWantsBestResolutionOpenGLSurface:", NS.BOOL(wants))
}
