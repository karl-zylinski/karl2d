#+build darwin

package cocoa_extras

// Extra Cocoa/AppKit bindings not included in Odin's standard darwin Foundation bindings

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

msgSend :: intrinsics.objc_send

// NSApplication presentation options (for fullscreen mode)
Application_setPresentationOptions :: proc "c" (self: ^NS.Application, options: NS.ApplicationPresentationOptions) {
	msgSend(nil, self, "setPresentationOptions:", options)
}

Application_presentationOptions :: proc "c" (self: ^NS.Application) -> NS.ApplicationPresentationOptions {
	return msgSend(NS.ApplicationPresentationOptions, self, "presentationOptions")
}

// NSWindow content size (sets the size of the content area, excluding decorations)
Window_setContentSize :: proc "c" (self: ^NS.Window, size: NS.Size) {
	msgSend(nil, self, "setContentSize:", size)
}

// NSTrackingArea options (bit flags). See NSTrackingArea documentation for the full list.
TRACKING_MOUSE_ENTERED_AND_EXITED :: NS.UInteger(0x01)
TRACKING_CURSOR_UPDATE            :: NS.UInteger(0x04)
TRACKING_ACTIVE_IN_KEY_WINDOW     :: NS.UInteger(0x20)
TRACKING_ACTIVE_ALWAYS            :: NS.UInteger(0x80)
TRACKING_ASSUME_INSIDE            :: NS.UInteger(0x100)
TRACKING_IN_VISIBLE_RECT          :: NS.UInteger(0x200)
TRACKING_ENABLED_DURING_MOUSE_DRAG :: NS.UInteger(0x400)

@(objc_class="NSTrackingArea")
TrackingArea :: struct {using _: NS.Object}

TrackingArea_alloc :: proc "c" () -> ^TrackingArea {
	return msgSend(^TrackingArea, TrackingArea, "alloc")
}

TrackingArea_initWithRect :: proc "c" (self: ^TrackingArea, rect: NS.Rect, options: NS.UInteger, owner: NS.id, userInfo: NS.id) -> ^TrackingArea {
	return msgSend(^TrackingArea, self, "initWithRect:options:owner:userInfo:", rect, options, owner, userInfo)
}

View_addTrackingArea :: proc "c" (self: ^NS.View, area: ^TrackingArea) {
	msgSend(nil, self, "addTrackingArea:", area)
}

View_frame :: proc "c" (self: ^NS.View) -> NS.Rect {
	return msgSend(NS.Rect, self, "frame")
}

View_mouse_inRect :: proc "c" (self: ^NS.View, point: NS.Point, rect: NS.Rect) -> NS.BOOL {
	return msgSend(NS.BOOL, self, "mouse:inRect:", point, rect)
}

Window_mouseLocationOutsideOfEventStream :: proc "c" (self: ^NS.Window) -> NS.Point {
	return msgSend(NS.Point, self, "mouseLocationOutsideOfEventStream")
}
