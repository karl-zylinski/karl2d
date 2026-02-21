#+build darwin
package AudioToolbox

import CA "../CoreAudio"

foreign import audio_toolbox "system:AudioToolbox.framework"

CFOSStatus    :: i32
CFBoolean     :: bool
CFRunLoopRef  :: distinct rawptr
CFRunLoopMode :: distinct rawptr

QueueRef :: distinct rawptr

QueueTimelineRef :: distinct rawptr

QueueBuffer :: struct {
	mAudioDataBytesCapacity:    u32,
	mAudioData:                 rawptr,
	mAudioDataByteSize:         u32,
	mUserData:                  rawptr,
	mPacketDescriptionCapacity: u32,
	mPacketDescriptions:        ^CA.StreamPacketDescription,
	mPacketDescriptionCount:    u32,
}
QueueBufferRef :: ^QueueBuffer

QueueOutputCallback :: proc "c" (inUserData: rawptr, inAQ: QueueRef, inBuffer: QueueBufferRef)

@(link_prefix="Audio")
foreign audio_toolbox {
	QueueNewOutput :: proc(
		inFormat: ^CA.StreamBasicDescription,
		inCallbackProc: QueueOutputCallback,
		inUserData: rawptr,
		inCallbackRunLoop: CFRunLoopMode,
		inCallbackRunLoopMode: CFRunLoopMode,
		inFlags: u32,
		outAQ: ^QueueRef,
	) -> CFOSStatus ---

	QueueStart :: proc(inAQ: QueueRef, inStartTime: ^CA.TimeStamp) -> CFOSStatus ---

	QueueAllocateBuffer :: proc(inAQ: QueueRef, inBufferByteSize: u32, outbuffer: ^QueueBufferRef) -> CFOSStatus ---

	QueueEnqueueBuffer :: proc(
		inAQ: QueueRef,
		inBuffer: QueueBufferRef,
		inNumPacketDescs: u32,
		inPacketDescs: ^CA.StreamPacketDescription,
	) -> CFOSStatus ---

	QueueGetCurrentTime :: proc(
		inAQ: QueueRef,
		inTimeline: QueueTimelineRef,
		outTimeStamp: ^CA.TimeStamp,
		outTimelineDiscontinuity: ^CFBoolean,
	) -> CFOSStatus ---

	QueueStop :: proc(inAQ: QueueRef, inImmediate: bool) -> CFOSStatus ---
	QueueDispose :: proc(inAQ: QueueRef, inImmediate: bool) -> CFOSStatus ---
}
