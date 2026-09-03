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
	has_mixer_thread = true,
}

import "base:runtime"
import "core:sync"

import "log"
import CA "platform_bindings/mac/CoreAudio"
import Audio "platform_bindings/mac/AudioToolbox"

CORE_AUDIO_BUFFER_SAMPLES :: 700
BUFFER_SIZE :: CORE_AUDIO_BUFFER_SAMPLES * size_of([2]Audio_Sample)

Core_Audio_State :: struct {
	allocator: runtime.Allocator,
	queue: Audio.QueueRef,
	buffers: [4]Audio.QueueBufferRef,

	callback_mutex: sync.Mutex,
	running: bool,
	fill_context: runtime.Context,
}

core_audio_state_size :: proc() -> int {
	return size_of(Core_Audio_State)
}

s: ^Core_Audio_State

core_audio_init :: proc(state: rawptr, allocator: runtime.Allocator) -> bool {
	assert(state != nil)
	s = (^Core_Audio_State)(state)
	s.allocator = allocator
	s.fill_context = _audio_thread_context()

	log.debug("Init audio backend CoreAudio")

	descriptor := CA.StreamBasicDescription {
		mSampleRate = 44100,
		mFormatID = .LinearPCM,
		mFormatFlags = {.IsFloat, .IsPacked},
		mFramesPerPacket = 1,
		mChannelsPerFrame = 2,
		mBitsPerChannel = size_of(f32) * 8,
	}

	descriptor.mBytesPerFrame = descriptor.mChannelsPerFrame * (descriptor.mBitsPerChannel / 8)
	descriptor.mBytesPerPacket = descriptor.mBytesPerFrame * descriptor.mFramesPerPacket

	queue_err := Audio.QueueNewOutput(
		&descriptor,
		_core_audio_callback,
		s,
		nil,
		nil,
		0,
		&s.queue,
	)

	if queue_err != 0 {
		log.errorf("CoreAudio: Audio.QueueNewOutput failed. Error code: %v", queue_err)
		return false
	}

	s.running = true

	for &buffer in s.buffers {
		buffer_err := Audio.QueueAllocateBuffer(s.queue, BUFFER_SIZE, &buffer)
		if buffer_err != 0 {
			s.running = false
			Audio.QueueDispose(s.queue, true)
			log.errorf("CoreAudio: Audio.QueueAllocateBuffer failed. Error code: %v", buffer_err)
			return false
		}

		_core_audio_fill(buffer)
	}

	queue_start_err := Audio.QueueStart(s.queue, nil)
	if queue_start_err != 0 {
		s.running = false
		Audio.QueueDispose(s.queue, true)
		log.errorf("CoreAudio: Audio.QueueStart failed. Error code: %v", queue_start_err)
		return false
	}

	return true
}

_core_audio_fill :: proc "contextless" (buffer: Audio.QueueBufferRef) {
	context = s.fill_context
	samples := ([^][2]Audio_Sample)(buffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
	_mix_audio_into_buffer(samples)
	buffer.mAudioDataByteSize = u32(BUFFER_SIZE)
	Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)
	free_all(context.temp_allocator)
}

_core_audio_callback :: proc "c" (
	inUserData: rawptr,
	inAQ: Audio.QueueRef,
	inBuffer: Audio.QueueBufferRef,
) {
	state := (^Core_Audio_State)(inUserData)
	sync.mutex_lock(&state.callback_mutex)

	if state.running {
		_core_audio_fill(inBuffer)
	}

	sync.mutex_unlock(&state.callback_mutex)
}

core_audio_shutdown :: proc() {
	sync.mutex_lock(&s.callback_mutex)
	s.running = false
	sync.mutex_unlock(&s.callback_mutex)
	Audio.QueueStop(s.queue, true)
	Audio.QueueDispose(s.queue, true)
}

core_audio_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Core_Audio_State)(state)
	allocator := s.allocator
	core_audio_shutdown()
	core_audio_init(state, allocator)
}
