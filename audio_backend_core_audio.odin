#+build darwin
#+vet explicit-allocators
#+private package
package karl2d

import "base:runtime"
import "core:slice"
import "core:sync"

import "log"
import CA "platform_bindings/mac/CoreAudio"
import Audio "platform_bindings/mac/AudioToolbox"

CORE_AUDIO_BACKEND_INTERFACE :: Audio_Backend_Interface {
	destroy = core_audio_destroy,
	start_mixer_thread = core_audio_start_mixer_thread,
	mix_chunk_size = CORE_AUDIO_BUFFER_SAMPLES,
	has_mixer_thread = true,
}

CORE_AUDIO_BUFFER_SAMPLES :: 700
CORE_AUDIO_BUFFER_SIZE :: CORE_AUDIO_BUFFER_SAMPLES * size_of([2]Audio_Sample)

Core_Audio_State :: struct {
	using interface: Audio_Backend_Interface,
	allocator: Allocator,
	queue: Audio.QueueRef,
	buffers: [4]Audio.QueueBufferRef,

	callback_mutex: sync.Mutex,
	running: bool,
	fill_context: runtime.Context,
}

core_audio_create :: proc(
	allocator: Allocator,
	loc := #caller_location,
) -> ^Audio_Backend_Interface {
	s := new(Core_Audio_State, allocator, loc)
	s.interface = CORE_AUDIO_BACKEND_INTERFACE
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
		free(s, allocator)
		return nil
	}

	for &buffer in s.buffers {
		buffer_err := Audio.QueueAllocateBuffer(s.queue, CORE_AUDIO_BUFFER_SIZE, &buffer)
		if buffer_err != 0 {
			Audio.QueueDispose(s.queue, true)
			log.errorf("CoreAudio: Audio.QueueAllocateBuffer failed. Error code: %v", buffer_err)
			free(s, allocator)
			return nil
		}

		samples := ([^][2]Audio_Sample)(buffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
		slice.zero(samples)
		buffer.mAudioDataByteSize = u32(CORE_AUDIO_BUFFER_SIZE)
		Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)
	}

	return s
}

core_audio_start_mixer_thread :: proc(s: ^Core_Audio_State) -> bool {
	s.running = true
	queue_start_err := Audio.QueueStart(s.queue, nil)
	if queue_start_err != 0 {
		s.running = false
		log.errorf("CoreAudio: Audio.QueueStart failed. Error code: %v", queue_start_err)
		return false
	}

	return true
}

_core_audio_callback :: proc "c" (
	inUserData: rawptr,
	inAQ: Audio.QueueRef,
	inBuffer: Audio.QueueBufferRef,
) {
	state := (^Core_Audio_State)(inUserData)
	sync.mutex_lock(&state.callback_mutex)

	if state.running {
		context = state.fill_context
		samples := ([^][2]Audio_Sample)(inBuffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
		_mix_audio_into_buffer(samples)
		inBuffer.mAudioDataByteSize = u32(CORE_AUDIO_BUFFER_SIZE)
		Audio.QueueEnqueueBuffer(state.queue, inBuffer, 0, nil)
		free_all(context.temp_allocator)
	}

	sync.mutex_unlock(&state.callback_mutex)
}

core_audio_destroy :: proc(s: ^Core_Audio_State) {
	sync.mutex_lock(&s.callback_mutex)
	s.running = false
	sync.mutex_unlock(&s.callback_mutex)
	Audio.QueueStop(s.queue, true)
	Audio.QueueDispose(s.queue, true)
	a := s.allocator
	free(s, a)
}
