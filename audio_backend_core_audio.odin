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

CORE_AUDIO_BUFFER_SAMPLES :: 700
CORE_AUDIO_BUFFER_SIZE :: CORE_AUDIO_BUFFER_SAMPLES * size_of([2]Audio_Sample)

Audio_Backend_Core_Audio :: struct {
	using interface: I_Audio_Backend,
	queue: Audio.QueueRef,
	buffers: [4]Audio.QueueBufferRef,

	callback_mutex: sync.Mutex,
	running: bool,
	fill_context: runtime.Context,
}

AUDIO_BACKEND_CORE_AUDIO_PROTOTYPE :: Audio_Backend_Core_Audio {
	interface = {
		init = core_audio_init,
		shutdown = core_audio_shutdown,
		mix_chunk_size = CORE_AUDIO_BUFFER_SAMPLES,
		has_mixer_thread = true,
		pushed_samples_remaining = nil,
		push_samples = nil,
	},
}

core_audio_init :: proc(s: ^Audio_Backend_Core_Audio) -> bool {
	log.debug("Init audio backend CoreAudio")
	s.fill_context = _audio_thread_context()

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

	for &buffer in s.buffers {
		buffer_err := Audio.QueueAllocateBuffer(s.queue, CORE_AUDIO_BUFFER_SIZE, &buffer)
		if buffer_err != 0 {
			Audio.QueueDispose(s.queue, true)
			log.errorf("CoreAudio: Audio.QueueAllocateBuffer failed. Error code: %v", buffer_err)
			return false
		}

		samples := ([^][2]Audio_Sample)(buffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
		slice.zero(samples)
		buffer.mAudioDataByteSize = u32(CORE_AUDIO_BUFFER_SIZE)
		Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)
	}

	s.running = true
	queue_start_err := Audio.QueueStart(s.queue, nil)
	if queue_start_err != 0 {
		s.running = false
		Audio.QueueDispose(s.queue, true)
		log.errorf("CoreAudio: Audio.QueueStart failed. Error code: %v", queue_start_err)
		return false
	}

	return true
}

core_audio_shutdown :: proc(s: ^Audio_Backend_Core_Audio) {
	sync.mutex_lock(&s.callback_mutex)
	s.running = false
	sync.mutex_unlock(&s.callback_mutex)
	Audio.QueueStop(s.queue, true)
	Audio.QueueDispose(s.queue, true)
}

_core_audio_callback :: proc "c" (
	inUserData: rawptr,
	inAQ: Audio.QueueRef,
	inBuffer: Audio.QueueBufferRef,
) {
	s := (^Audio_Backend_Core_Audio)(inUserData)
	context = s.fill_context
	sync.mutex_lock(&s.callback_mutex)

	if s.running {
		samples := ([^][2]Audio_Sample)(inBuffer.mAudioData)[:CORE_AUDIO_BUFFER_SAMPLES]
		_mix_audio_into_buffer(samples)
		inBuffer.mAudioDataByteSize = u32(CORE_AUDIO_BUFFER_SIZE)
		Audio.QueueEnqueueBuffer(s.queue, inBuffer, 0, nil)
	}

	sync.mutex_unlock(&s.callback_mutex)
	free_all(context.temp_allocator)
}