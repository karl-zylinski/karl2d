#+build darwin
#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_CORE_AUDIO :: Audio_Backend_Interface {
	state_size = core_audio_state_size,
	init = core_audio_init,
	shutdown = core_audio_shutdown,
	set_internal_state = core_audio_set_internal_state,

	feed = core_audio_feed,

	remaining_samples = core_audio_remaining_samples,
	stop_feeding = core_audio_stop_feeding,
	target_samples = core_audio_target_samples,
	drives_itself = core_audio_drives_itself,
}

import "base:intrinsics"
import "base:runtime"

import       "log"
import CA    "platform_bindings/mac/CoreAudio"
import Audio "platform_bindings/mac/AudioToolbox"

// How many samples one queue buffer holds, and how many buffers there are. The queue hands a
// buffer back on its own thread once it has been played, and the mixer fills it there and then.
// Four buffers of 700 samples is 63 milliseconds of audio at most.
CORE_AUDIO_BUFFER_SAMPLES :: 700
CORE_AUDIO_BUFFER_COUNT :: 4
BUFFER_SIZE :: CORE_AUDIO_BUFFER_SAMPLES * size_of([2]Audio_Sample)

Core_Audio_State :: struct {
	queue:   Audio.QueueRef,
	buffers: [CORE_AUDIO_BUFFER_COUNT]Audio.QueueBufferRef,

	// Cleared before the queue is stopped. The callback checks it so that it stops handing
	// buffers back to a queue that is going away.
	running: bool,
}

core_audio_state_size :: proc() -> int {
	return size_of(Core_Audio_State)
}

s: ^Core_Audio_State

core_audio_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	assert(state != nil)
	s = (^Core_Audio_State)(state)

	log.debug("Init audio backend CoreAudio")

	descriptor: CA.StreamBasicDescription
	descriptor.mSampleRate       = 44100
	descriptor.mFormatID         = .LinearPCM
	descriptor.mFormatFlags      = {.IsFloat, .IsPacked}
	descriptor.mFramesPerPacket  = 1
	descriptor.mChannelsPerFrame = 2
	descriptor.mBitsPerChannel   = size_of(f32) * 8
	descriptor.mBytesPerFrame    = descriptor.mChannelsPerFrame * (descriptor.mBitsPerChannel / 8)
	descriptor.mBytesPerPacket   = descriptor.mBytesPerFrame * descriptor.mFramesPerPacket

	if !ch(Audio.QueueNewOutput(
		&descriptor,
		_core_audio_callback,
		s,
		nil,
		nil,
		0,
		&s.queue,
	)) { return }

	s.running = true

	// Fill every buffer once and hand it to the queue. From here on the callback keeps them going
	// as the queue plays them.
	for &buffer in s.buffers {
		if !ch(Audio.QueueAllocateBuffer(s.queue, BUFFER_SIZE, &buffer)) {
			return
		}

		core_audio_fill_and_enqueue(buffer)
	}

	if !ch(Audio.QueueStart(s.queue, nil)) {
		return
	}
}

// Asks the mixer to fill a buffer and gives it back to the queue. Runs on the queue's own thread
// when the callback calls it, and on the game thread once per buffer while starting up.
core_audio_fill_and_enqueue :: proc "contextless" (buffer: Audio.QueueBufferRef) {
	context = runtime.default_context()
	context.allocator, context.logger = _audio_thread_context()

	samples := ([^][2]Audio_Sample)(buffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
	_pull_audio(samples)
	buffer.mAudioDataByteSize = u32(BUFFER_SIZE)
	Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)
}

// The queue hands a buffer back once it has been played. That is when the mixer fills it again.
_core_audio_callback :: proc "c" (
	inUserData: rawptr,
	inAQ: Audio.QueueRef,
	inBuffer: Audio.QueueBufferRef,
) {
	state := (^Core_Audio_State)(inUserData)

	if !intrinsics.atomic_load(&state.running) {
		return
	}

	core_audio_fill_and_enqueue(inBuffer)
}

core_audio_shutdown :: proc() {
	// Stop the callback re-filling buffers before the queue goes away. `QueueStop` waits for the
	// queue to finish, so no callback is running by the time `QueueDispose` runs.
	intrinsics.atomic_store(&s.running, false)
	Audio.QueueStop(s.queue, true)
	Audio.QueueDispose(s.queue, true)
}

core_audio_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Core_Audio_State)(state)
}

// The callback asks the mixer for samples, so nothing hands them over.
core_audio_feed :: proc(samples: [][2]Audio_Sample) {
}

core_audio_remaining_samples :: proc() -> int {
	return 0
}

core_audio_stop_feeding :: proc() {
}

core_audio_target_samples :: proc() -> int {
	return 0
}

ch :: proc(status: Audio.CFOSStatus, loc := #caller_location) -> bool {
	if status == 0 {
		return true
	}

	log.errorf("CoreAudio error %v", status, location=loc)
	return false
}

// The queue hands a played buffer back on its own thread, and the callback fills it there.
core_audio_drives_itself :: proc() -> bool {
	return true
}
