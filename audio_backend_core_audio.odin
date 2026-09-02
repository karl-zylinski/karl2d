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

	mixes_itself = true,
}

import "base:intrinsics"
import "base:runtime"

import       "log"
import CA    "platform_bindings/mac/CoreAudio"
import Audio "platform_bindings/mac/AudioToolbox"

CORE_AUDIO_BUFFER_SAMPLES :: 700
BUFFER_SIZE :: CORE_AUDIO_BUFFER_SAMPLES * size_of([2]Audio_Sample)

Core_Audio_State :: struct {
	queue:   Audio.QueueRef,
	buffers: [4]Audio.QueueBufferRef,

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

	for &buffer in s.buffers {
		if !ch(Audio.QueueAllocateBuffer(s.queue, BUFFER_SIZE, &buffer)) {
			return
		}

		core_audio_fill(buffer)
	}

	if !ch(Audio.QueueStart(s.queue, nil)) {
		return
	}
}

core_audio_fill :: proc "contextless" (buffer: Audio.QueueBufferRef) {
	context = _audio_thread_context()

	samples := ([^][2]Audio_Sample)(buffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
	_mix_audio_into_buffer(samples)
	buffer.mAudioDataByteSize = u32(BUFFER_SIZE)
	Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)
	free_all(context.temp_allocator)
}

// TODO-UPDATE-COMMENT the callback has the mixer fill the buffer again and gives it back to the
// queue. Nothing counts samples any more.
// The queue hands a buffer back once it has been played. That is the moment its samples stop
// counting towards what is left to play.
_core_audio_callback :: proc "c" (
	inUserData: rawptr,
	inAQ: Audio.QueueRef,
	inBuffer: Audio.QueueBufferRef,
) {
	state := (^Core_Audio_State)(inUserData)

	if !intrinsics.atomic_load(&state.running) {
		return
	}

	core_audio_fill(inBuffer)
}

core_audio_shutdown :: proc() {
	intrinsics.atomic_store(&s.running, false)
	Audio.QueueStop(s.queue, true)
	Audio.QueueDispose(s.queue, true)
}

core_audio_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Core_Audio_State)(state)
}

ch :: proc(status: Audio.CFOSStatus, loc := #caller_location) -> bool {
	if status == 0 {
		return true
	}

	log.errorf("CoreAudio error %v", status, location=loc)
	return false
}
