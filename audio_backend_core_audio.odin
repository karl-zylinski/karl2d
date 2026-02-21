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
}

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:sync"

import CA    "platform_bindings/mac/CoreAudio"
import Audio "platform_bindings/mac/AudioToolbox"

BUFFER_SIZE :: AUDIO_MIX_CHUNK_SIZE * size_of(Audio_Sample)

Core_Audio_State :: struct {
	queue:          Audio.QueueRef,
	semaphore:      sync.Sema,
	buffers:        [3]Audio.QueueBufferRef,
	buffer:         int,
	posted_samples: int,
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
	descriptor.mChannelsPerFrame = len(Audio_Sample)
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

	if !ch(Audio.QueueStart(s.queue, nil)) {
		return
	}

	for &buffer in s.buffers {
		if !ch(Audio.QueueAllocateBuffer(s.queue, BUFFER_SIZE, &buffer)) {
			return
		}
	}
	sync.sema_post(&s.semaphore, len(s.buffers))

	_core_audio_callback :: proc "c" (inUserData: rawptr, inAQ: Audio.QueueRef, inBuffer: Audio.QueueBufferRef) {
		sync.sema_post(&s.semaphore)
	}
}

core_audio_shutdown :: proc() {
	Audio.QueueStop(s.queue, true)
	Audio.QueueDispose(s.queue, true)
}

core_audio_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Core_Audio_State)(state)
}

core_audio_feed :: proc(samples: []Audio_Sample) {
	remaining := samples
	for len(remaining) > 0 {
		sync.sema_wait(&s.semaphore)
		buffer := s.buffers[s.buffer]
		s.buffer = (s.buffer + 1) % len(s.buffers)

		to_write_samples := min(int(buffer.mAudioDataBytesCapacity / size_of(Audio_Sample)), len(remaining))
		to_write_bytes   := to_write_samples * size_of(Audio_Sample)
		intrinsics.mem_copy_non_overlapping(buffer.mAudioData, raw_data(remaining), to_write_bytes)
		buffer.mAudioDataByteSize = u32(to_write_bytes)
		remaining = remaining[to_write_samples:]

		if !ch(Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)) {
			return
		}

		s.posted_samples += to_write_samples
	}
}

core_audio_remaining_samples :: proc() -> int {
	if s.posted_samples == 0 {
		return 0
	}

	time: CA.TimeStamp
	ch(Audio.QueueGetCurrentTime(s.queue, nil, &time, nil))

	return s.posted_samples - int(time.mSampleTime)
}

ch :: proc(status: Audio.CFOSStatus, loc := #caller_location) -> bool {
	if status == 0 {
		return true
	}

	log.errorf("CoreAudio error %v", status, location=loc)
	return false
}
