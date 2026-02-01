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
