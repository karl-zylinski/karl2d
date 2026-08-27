// Partial Xlib and Xcursor bindings. Just enough to open a window, read its events and set a
// cursor. Loaded with dlopen instead of a static foreign import. Karl2D compiles in both the X11
// and the Wayland backend and only one of them runs, so linking libX11 unconditionally would
// require every machine to have it installed.
package x11

import "core:dynlib"

XID :: distinct uint
Window :: XID
Pixmap :: XID
Cursor :: XID
Drawable :: XID

Atom :: distinct uint
VisualID :: distinct uint
Time :: distinct uint

// A keysym is an XID naming a symbol on a key, such as "a" or "Left". Karl2D reads keys from the
// keycode instead and only ever passes a keysym back out to Xlib, so the names are not bound.
KeySym :: distinct uint

CurrentTime :: 0

Display :: distinct struct {}

XExtData :: struct {
	number:       i32,
	next:         ^XExtData,
	free_private: #type proc "c" (extension: ^XExtData) -> Status,
	private_data: rawptr,
}

Visual :: struct {
	ext_data:     ^XExtData,
	visualid:     VisualID,
	class:        i32,
	red_mask:     uint,
	green_mask:   uint,
	blue_mask:    uint,
	bits_per_rgb: i32,
	map_entries:  i32,
}

XVisualInfo :: struct {
	visual:        ^Visual,
	visualid:      VisualID,
	screen:        i32,
	depth:         i32,
	class:         i32,
	red_mask:      uint,
	green_mask:    uint,
	blue_mask:     uint,
	colormap_size: i32,
	bits_per_rgb:  i32,
}

XColor :: struct {
	pixel: uint,
	red:   u16,
	green: u16,
	blue:  u16,
	flags: u8,
	pad:   u8,
}

XComposeStatus :: struct {
	compose_ptr:   rawptr,
	chars_matched: i32,
}

SizeHints :: bit_set[SizeHintsBits; int]

SizeHintsBits :: enum {
	USPosition  = 0,
	USSize      = 1,
	PPosition   = 2,
	PSize       = 3,
	PMinSize    = 4,
	PMaxSize    = 5,
	PResizeInc  = 6,
	PAspect     = 7,
	PBaseSize   = 8,
	PWinGravity = 9,
}

XSizeHints :: struct {
	flags:       SizeHints,
	x:           i32,
	y:           i32,
	width:       i32,
	height:      i32,
	min_width:   i32,
	min_height:  i32,
	max_width:   i32,
	max_height:  i32,
	width_inc:   i32,
	height_inc:  i32,
	min_aspect:  struct {x, y: i32},
	max_aspect:  struct {x, y: i32},
	base_width:  i32,
	base_height: i32,
	win_gravity: i32,
}

Status :: enum i32 {
	Success             = 0,
	BadRequest          = 1,
	BadValue            = 2,
	BadWindow           = 3,
	BadPixmap           = 4,
	BadAtom             = 5,
	BadCursor           = 6,
	BadFont             = 7,
	BadMatch            = 8,
	BadDrawable         = 9,
	BadAccess           = 10,
	BadAlloc            = 11,
	BadColor            = 12,
	BadGC               = 13,
	BadIDChoice         = 14,
	BadName             = 15,
	BadLength           = 16,
	BadImplementation   = 17,
	FirstExtensionError = 128,
	LastExtensionError  = 255,
}

GrabMode :: enum i32 {
	GrabModeSync  = 0,
	GrabModeAsync = 1,
}

LookupStringStatus :: enum i32 {
	BufferOverflow = -1,
	LookupNone     = 1,
	LookupChars    = 2,
	LookupKeySym   = 3,
	LookupBoth     = 4,
}

// Xlib itself stops naming buttons at 5. The horizontal wheel reports 6 and 7.
MouseButton :: enum i32 {
	Button1 = 1,
	Button2 = 2,
	Button3 = 3,
	Button4 = 4,
	Button5 = 5,
}

EventType :: enum i32 {
	KeyPress         = 2,
	KeyRelease       = 3,
	ButtonPress      = 4,
	ButtonRelease    = 5,
	MotionNotify     = 6,
	EnterNotify      = 7,
	LeaveNotify      = 8,
	FocusIn          = 9,
	FocusOut         = 10,
	KeymapNotify     = 11,
	Expose           = 12,
	GraphicsExpose   = 13,
	NoExpose         = 14,
	VisibilityNotify = 15,
	CreateNotify     = 16,
	DestroyNotify    = 17,
	UnmapNotify      = 18,
	MapNotify        = 19,
	MapRequest       = 20,
	ReparentNotify   = 21,
	ConfigureNotify  = 22,
	ConfigureRequest = 23,
	GravityNotify    = 24,
	ResizeRequest    = 25,
	CirculateNotify  = 26,
	CirculateRequest = 27,
	PropertyNotify   = 28,
	SelectionClear   = 29,
	SelectionRequest = 30,
	SelectionNotify  = 31,
	ColormapNotify   = 32,
	ClientMessage    = 33,
	MappingNotify    = 34,
	GenericEvent     = 35,
}

EventMask :: bit_set[EventMaskBits; int]

EventMaskBits :: enum i32 {
	KeyPress             = 0,
	KeyRelease           = 1,
	ButtonPress          = 2,
	ButtonRelease        = 3,
	EnterWindow          = 4,
	LeaveWindow          = 5,
	PointerMotion        = 6,
	PointerMotionHint    = 7,
	Button1Motion        = 8,
	Button2Motion        = 9,
	Button3Motion        = 10,
	Button4Motion        = 11,
	Button5Motion        = 12,
	ButtonMotion         = 13,
	KeymapState          = 14,
	Exposure             = 15,
	VisibilityChange     = 16,
	StructureNotify      = 17,
	ResizeRedirect       = 18,
	SubstructureNotify   = 19,
	SubstructureRedirect = 20,
	FocusChange          = 21,
	PropertyChange       = 22,
	ColormapChange       = 23,
	OwnerGrabButton      = 24,
}

InputMask :: bit_set[InputMaskBits; i32]

InputMaskBits :: enum {
	ShiftMask   = 0,
	LockMask    = 1,
	ControlMask = 2,
	Mod1Mask    = 3,
	Mod2Mask    = 4,
	Mod3Mask    = 5,
	Mod4Mask    = 6,
	Mod5Mask    = 7,
	Button1Mask = 8,
	Button2Mask = 9,
	Button3Mask = 10,
	Button4Mask = 11,
	Button5Mask = 12,
	AnyModifier = 15,
}

XAnyEvent :: struct {
	type:       EventType,
	serial:     uint,
	send_event: b32,
	display:    ^Display,
	window:     Window,
}

XKeyEvent :: struct {
	type:        EventType,
	serial:      uint,
	send_event:  b32,
	display:     ^Display,
	window:      Window,
	root:        Window,
	subwindow:   Window,
	time:        Time,
	x:           i32,
	y:           i32,
	x_root:      i32,
	y_root:      i32,
	state:       InputMask,
	keycode:     u32,
	same_screen: b32,
}

XKeyPressedEvent :: XKeyEvent

XButtonEvent :: struct {
	type:        EventType,
	serial:      uint,
	send_event:  b32,
	display:     ^Display,
	window:      Window,
	root:        Window,
	subwindow:   Window,
	time:        Time,
	x:           i32,
	y:           i32,
	x_root:      i32,
	y_root:      i32,
	state:       InputMask,
	button:      MouseButton,
	same_screen: b32,
}

XMotionEvent :: struct {
	type:        EventType,
	serial:      uint,
	send_event:  b32,
	display:     ^Display,
	window:      Window,
	root:        Window,
	subwindow:   Window,
	time:        Time,
	x:           i32,
	y:           i32,
	x_root:      i32,
	y_root:      i32,
	state:       InputMask,
	is_hint:     b8,
	same_screen: b32,
}

XConfigureEvent :: struct {
	type:              EventType,
	serial:            uint,
	send_event:        b32,
	display:           ^Display,
	event:             Window,
	window:            Window,
	x:                 i32,
	y:                 i32,
	width:             i32,
	height:            i32,
	border_width:      i32,
	above:             Window,
	override_redirect: b32,
}

XClientMessageEvent :: struct {
	type:         EventType,
	serial:       uint,
	send_event:   b32,
	display:      ^Display,
	window:       Window,
	message_type: Atom,
	format:       i32,
	data: struct #raw_union {
		b: [20]i8,
		s: [10]i16,
		l: [5]int,
	},
}

// Only the events Karl2D reads are named. The trailing padding is what fixes the size of the
// union, so `NextEvent` writing any of the events that are not named here stays in bounds.
XEvent :: struct #raw_union {
	type:       EventType,
	xany:       XAnyEvent,
	xkey:       XKeyEvent,
	xbutton:    XButtonEvent,
	xmotion:    XMotionEvent,
	xconfigure: XConfigureEvent,
	xclient:    XClientMessageEvent,
	_:          [24]int,
}

// Input method and input context, for turning key presses into typed text.
XIM :: distinct rawptr
XIC :: distinct rawptr

XrmHashBucket :: distinct rawptr

XNInputStyle: cstring : "inputStyle"
XNClientWindow: cstring : "clientWindow"
XNFocusWindow: cstring : "focusWindow"

XIMPreeditNothing :: 0x0008
XIMStatusNothing :: 0x0400

CursorDim :: u32
CursorUInt :: u32
CursorPixel :: u32

CursorImage :: struct {
	version: CursorDim,
	size:    CursorDim,
	width:   CursorDim,
	height:  CursorDim,
	xhot:    CursorDim,
	yhot:    CursorDim,
	delay:   CursorUInt,
	pixels:  ^CursorPixel, // ARGB
}

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
	fg:      ^XColor,
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

CloseIM: proc "c" (im: XIM) -> Status

SetLocaleModifiers: proc "c" (modifiers: cstring) -> cstring

CreateIC: proc "c" (
	im: XIM,
	#c_vararg args: ..any,
) -> XIC

DestroyIC: proc "c" (ic: XIC)

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

cursorImageCreate: proc "c" (width: i32, height: i32) -> ^CursorImage

cursorImageDestroy: proc "c" (img: rawptr)

cursorImageLoadCursor: proc "c" (display: ^Display, img: ^CursorImage) -> Cursor

cursorLibraryLoadCursor: proc "c" (display: ^Display, name: cstring) -> Cursor

LIB_X11 :: "libX11.so.6"
LIB_XCURSOR :: "libXcursor.so.1"

Symbol :: struct {
	name: string,
	ptr:  rawptr,
}

// Loads `library_name` and fills in every symbol in `symbols`. On failure `missing` names the
// library or the symbol that was not found.
@(private)
load_symbols :: proc(library_name: string, symbols: []Symbol) -> (missing: string, ok: bool) {
	lib, lib_ok := dynlib.load_library(library_name)

	if !lib_ok {
		return library_name, false
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

// Loads libX11 and libXcursor. On failure `missing` names the library or symbol that was not
// found, which is how a machine without X11 installed is detected.
load :: proc() -> (missing: string, ok: bool) {
	x11_symbols := []Symbol {
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
		{"XCloseIM", &CloseIM},
		{"XSetLocaleModifiers", &SetLocaleModifiers},
		{"XCreateIC", &CreateIC},
		{"XDestroyIC", &DestroyIC},
		{"XSetICFocus", &SetICFocus},
		{"XUnsetICFocus", &UnsetICFocus},
		{"XkbSetDetectableAutoRepeat", &XkbSetDetectableAutoRepeat},
		{"Xutf8LookupString", &Xutf8LookupString},
	}

	missing, ok = load_symbols(LIB_X11, x11_symbols)

	if !ok {
		return
	}

	xcursor_symbols := []Symbol {
		{"XcursorImageCreate", &cursorImageCreate},
		{"XcursorImageDestroy", &cursorImageDestroy},
		{"XcursorImageLoadCursor", &cursorImageLoadCursor},
		{"XcursorLibraryLoadCursor", &cursorLibraryLoadCursor},
	}

	return load_symbols(LIB_XCURSOR, xcursor_symbols)
}
