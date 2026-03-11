#+build darwin

package corevideo

// CoreVideo bindings for CVDisplayLink
// CVDisplayLink provides a display-refresh-synchronized timer that continues running
// even when the main thread is blocked by Cocoa's modal resize loop.

import "core:c"

@(require)
foreign import CoreVideo "system:CoreVideo.framework"

// Opaque reference to a display link
CVDisplayLinkRef :: distinct rawptr

// Return type for CoreVideo functions
CVReturn :: distinct i32
kCVReturnSuccess :: CVReturn(0)

// Option flags for display link
CVOptionFlags :: u64

// Time stamp structure - simplified version with only the fields needed for the callback signature
CVTimeStamp :: struct {
	version:             u32,
	videoTimeScale:      i32,
	videoTime:           i64,
	hostTime:            u64,
	rateScalar:          f64,
	videoRefreshPeriod:  i64,
	smpteTime:           CVSMPTETime,
	flags:               u64,
	reserved:            u64,
}

CVSMPTETime :: struct {
	subframes:        i16,
	subframeDivisor:  i16,
	counter:          u32,
	type:             u32,
	flags:            u32,
	hours:            i16,
	minutes:          i16,
	seconds:          i16,
	frames:           i16,
}

// Callback function type for CVDisplayLink
CVDisplayLinkOutputCallback :: #type proc "c" (
	displayLink: CVDisplayLinkRef,
	inNow: ^CVTimeStamp,
	inOutputTime: ^CVTimeStamp,
	flagsIn: CVOptionFlags,
	flagsOut: ^CVOptionFlags,
	displayLinkContext: rawptr,
) -> CVReturn

@(default_calling_convention="c")
foreign CoreVideo {
	// Creates a display link capable of being used with all active displays
	CVDisplayLinkCreateWithActiveCGDisplays :: proc(displayLinkOut: ^CVDisplayLinkRef) -> CVReturn ---

	// Sets the callback function for the display link
	CVDisplayLinkSetOutputCallback :: proc(
		displayLink: CVDisplayLinkRef,
		callback: CVDisplayLinkOutputCallback,
		userInfo: rawptr,
	) -> CVReturn ---

	// Starts the display link
	CVDisplayLinkStart :: proc(displayLink: CVDisplayLinkRef) -> CVReturn ---

	// Stops the display link
	CVDisplayLinkStop :: proc(displayLink: CVDisplayLinkRef) -> CVReturn ---

	// Releases the display link (decrements reference count)
	CVDisplayLinkRelease :: proc(displayLink: CVDisplayLinkRef) ---
}
