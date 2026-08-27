// Wraps the slice of vendor:x11/xlib and libXcursor that Karl2D's X11 backend needs, loading them
// with dlopen instead of a static foreign import. Karl2D compiles in both the X11 and the Wayland
// backend and only one of them runs, so linking libX11 unconditionally would require every
// machine to have it installed.
//
// vendor:x11/xlib stays imported for its types and constants, which links nothing on its own.
// Calling a procedure directly on it puts libX11 straight back into the link list.
package x11

import xlib "vendor:x11/xlib"
import "../dynload"

//-------//
// TYPES //
//-------//

Atom               :: xlib.Atom
Cursor             :: xlib.Cursor
CursorDim          :: xlib.CursorDim
CursorImage        :: xlib.CursorImage
Display            :: xlib.Display
Drawable           :: xlib.Drawable
EventMask          :: xlib.EventMask
GrabMode           :: xlib.GrabMode
KeySym             :: xlib.KeySym
LookupStringStatus :: xlib.LookupStringStatus
MouseButton        :: xlib.MouseButton
Pixmap             :: xlib.Pixmap
Status             :: xlib.Status
Time               :: xlib.Time
Window             :: xlib.Window
XColor             :: xlib.XColor
XComposeStatus     :: xlib.XComposeStatus
XEvent             :: xlib.XEvent
XIC                :: xlib.XIC
XID                :: xlib.XID
XIM                :: xlib.XIM
XKeyEvent          :: xlib.XKeyEvent
XKeyPressedEvent   :: xlib.XKeyPressedEvent
XSizeHints         :: xlib.XSizeHints
XVisualInfo        :: xlib.XVisualInfo
XrmHashBucket      :: xlib.XrmHashBucket

//-----------//
// CONSTANTS //
//-----------//

CurrentTime       :: xlib.CurrentTime
XIMPreeditNothing :: xlib.XIMPreeditNothing
XIMStatusNothing  :: xlib.XIMStatusNothing
XNClientWindow    :: xlib.XNClientWindow
XNFocusWindow     :: xlib.XNFocusWindow
XNInputStyle      :: xlib.XNInputStyle

//------------//
// PROCEDURES //
//------------//

OpenDisplay: proc "c" (name: cstring) -> ^Display

DefaultScreen: proc "c" (display: ^Display) -> i32

DefaultRootWindow: proc "c" (display: ^Display) -> Window

CreateSimpleWindow: proc "c" (
	display:  ^Display,
	parent:   Window,
	x:        i32,
	y:        i32,
	width:    u32,
	height:   u32,
	bordersz: u32,
	border:   uint,
	bg:       uint,
) -> Window

DestroyWindow: proc "c" (display: ^Display, window: Window)

MapWindow: proc "c" (display: ^Display, window: Window) -> b32

StoreName: proc "c" (display: ^Display, window: Window, name: cstring)

SelectInput: proc "c" (display: ^Display, window: Window, mask: EventMask)

InternAtom: proc "c" (display: ^Display, name: cstring, existing: b32) -> Atom

SetWMProtocols: proc "c" (
	display:   ^Display,
	window:    Window,
	protocols: [^]Atom,
	count:     i32,
) -> Status

SetWMNormalHints: proc "c" (display: ^Display, window: Window, hints: ^XSizeHints)

Flush: proc "c" (display: ^Display) -> i32

NextEvent: proc "c" (display: ^Display, event: ^XEvent)

PeekEvent: proc "c" (display: ^Display, event: ^XEvent)

Pending: proc "c" (display: ^Display) -> i32

SendEvent: proc "c" (
	display:   ^Display,
	window:    Window,
	propagate: b32,
	mask:      EventMask,
	event:     ^XEvent,
) -> Status

MoveWindow: proc "c" (display: ^Display, window: Window, x: i32, y: i32)

ResizeWindow: proc "c" (display: ^Display, window: Window, width: u32, height: u32)

TranslateCoordinates: proc "c" (
	display:    ^Display,
	src_window: Window,
	dst_window: Window,
	src_x:      i32,
	src_y:      i32,
	dst_x:      ^i32,
	dst_y:      ^i32,
	dst_child:  ^Window,
) -> b32

WarpPointer: proc "c" (
	display:    ^Display,
	src_window: Window,
	dst_window: Window,
	src_x:      i32,
	src_y:      i32,
	src_width:  u32,
	src_height: u32,
	dst_x:      i32,
	dst_y:      i32,
)

GrabPointer: proc "c" (
	display:       ^Display,
	grab_window:   Window,
	owner_events:  b32,
	mask:          EventMask,
	pointer_mode:  GrabMode,
	keyboard_mode: GrabMode,
	confine_to:    Window,
	cursor:        Cursor,
	time:          Time,
) -> i32

UngrabPointer: proc "c" (display: ^Display, time: Time) -> i32

DefineCursor: proc "c" (display: ^Display, window: Window, cursor: Cursor) -> i32

UndefineCursor: proc "c" (display: ^Display, window: Window) -> i32

FreeCursor: proc "c" (display: ^Display, cursor: Cursor)

CreatePixmap: proc "c" (
	display:  ^Display,
	drawable: Drawable,
	width:    u32,
	height:   u32,
	depth:    u32,
) -> Pixmap

CreatePixmapCursor: proc "c" (
	display: ^Display,
	source:  Pixmap,
	mask:    Pixmap,
	fg:      XColor,
	bg:      ^XColor,
	x:       u32,
	y:       u32,
) -> Cursor

FreePixmap: proc "c" (display: ^Display, pixmap: Pixmap)

LookupString: proc "c" (
	event:  ^XKeyEvent,
	buffer: [^]u8,
	count:  i32,
	keysym: ^KeySym,
	status: ^XComposeStatus,
) -> i32

FilterEvent: proc "c" (event: ^XEvent, window: Window) -> b32

OpenIM: proc "c" (
	display:   ^Display,
	rdb:       XrmHashBucket,
	res_name:  cstring,
	res_class: cstring,
) -> XIM

SetLocaleModifiers: proc "c" (modifiers: cstring) -> cstring

CreateIC: proc "c" (
	im: XIM,
	#c_vararg args: ..any,
) -> XIC

SetICFocus: proc "c" (ic: XIC)

UnsetICFocus: proc "c" (ic: XIC)

XkbSetDetectableAutoRepeat: proc "c" (
	display:    ^Display,
	detectable: b32,
	supported:  ^b32,
) -> b32

Xutf8LookupString: proc "c" (
	ic:            XIC,
	event:         ^XKeyPressedEvent,
	buffer_return: cstring,
	bytes_buffer:  i32,
	keysym_return: ^KeySym,
	status_return: ^LookupStringStatus,
) -> i32

DestroyIC: proc "c" (ic: XIC)

CloseIM: proc "c" (im: XIM) -> Status

cursorImageCreate: proc "c" (width: i32, height: i32) -> ^CursorImage

cursorImageDestroy: proc "c" (img: rawptr)

cursorImageLoadCursor: proc "c" (display: ^Display, img: ^CursorImage) -> Cursor

cursorLibraryLoadCursor: proc "c" (display: ^Display, name: cstring) -> Cursor

//------//
// LOAD //
//------//

LIB_X11     :: "libX11.so.6"
LIB_XCURSOR :: "libXcursor.so.1"

load :: proc() -> (err: dynload.Error, what: string) {
	x11_symbols := []dynload.Symbol {
		{"XOpenDisplay", &OpenDisplay},
		{"XDefaultScreen", &DefaultScreen},
		{"XDefaultRootWindow", &DefaultRootWindow},
		{"XCreateSimpleWindow", &CreateSimpleWindow},
		{"XDestroyWindow", &DestroyWindow},
		{"XMapWindow", &MapWindow},
		{"XStoreName", &StoreName},
		{"XSelectInput", &SelectInput},
		{"XInternAtom", &InternAtom},
		{"XSetWMProtocols", &SetWMProtocols},
		{"XSetWMNormalHints", &SetWMNormalHints},
		{"XFlush", &Flush},
		{"XNextEvent", &NextEvent},
		{"XPeekEvent", &PeekEvent},
		{"XPending", &Pending},
		{"XSendEvent", &SendEvent},
		{"XMoveWindow", &MoveWindow},
		{"XResizeWindow", &ResizeWindow},
		{"XTranslateCoordinates", &TranslateCoordinates},
		{"XWarpPointer", &WarpPointer},
		{"XGrabPointer", &GrabPointer},
		{"XUngrabPointer", &UngrabPointer},
		{"XDefineCursor", &DefineCursor},
		{"XUndefineCursor", &UndefineCursor},
		{"XFreeCursor", &FreeCursor},
		{"XCreatePixmap", &CreatePixmap},
		{"XCreatePixmapCursor", &CreatePixmapCursor},
		{"XFreePixmap", &FreePixmap},
		{"XLookupString", &LookupString},
		{"XFilterEvent", &FilterEvent},
		{"XOpenIM", &OpenIM},
		{"XSetLocaleModifiers", &SetLocaleModifiers},
		{"XCreateIC", &CreateIC},
		{"XSetICFocus", &SetICFocus},
		{"XUnsetICFocus", &UnsetICFocus},
		{"XkbSetDetectableAutoRepeat", &XkbSetDetectableAutoRepeat},
		{"Xutf8LookupString", &Xutf8LookupString},
		{"XDestroyIC", &DestroyIC},
		{"XCloseIM", &CloseIM},
	}

	err, what = dynload.load(LIB_X11, x11_symbols)

	if err != .None {
		return
	}

	xcursor_symbols := []dynload.Symbol {
		{"XcursorImageCreate", &cursorImageCreate},
		{"XcursorImageDestroy", &cursorImageDestroy},
		{"XcursorImageLoadCursor", &cursorImageLoadCursor},
		{"XcursorLibraryLoadCursor", &cursorLibraryLoadCursor},
	}

	return dynload.load(LIB_XCURSOR, xcursor_symbols)
}
