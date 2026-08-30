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

import "core:sync"

import       "log"
import CA    "platform_bindings/mac/CoreAudio"
import Audio "platform_bindings/mac/AudioToolbox"

BUFFER_SIZE :: AUDIO_MIX_CHUNK_SIZE * size_of([2]Audio_Sample)

Core_Audio_State :: struct {
	queue:          Audio.QueueRef,
	semaphore:      sync.Sema,
	buffers:        [3]Audio.QueueBufferRef,
	buffer:         int,
	queued_samples: int,

	// Set when the mixer thread is being stopped, so the wait for a free buffer gives up.
	interrupted:    bool,
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

	if !ch(Audio.QueueStart(s.queue, nil)) {
		return
	}

	for &buffer in s.buffers {
		if !ch(Audio.QueueAllocateBuffer(s.queue, BUFFER_SIZE, &buffer)) {
			return
		}
	}
	sync.sema_post(&s.semaphore, len(s.buffers))

	// The queue hands a buffer back once it has been played. That is the moment its samples stop
	// counting towards what is left to play.
	_core_audio_callback :: proc "c" (inUserData: rawptr, inAQ: Audio.QueueRef, inBuffer: Audio.QueueBufferRef) {
		state := (^Core_Audio_State)(inUserData)
		played := int(inBuffer.mAudioDataByteSize) / size_of([2]Audio_Sample)
		intrinsics.atomic_sub(&state.queued_samples, played)
		sync.sema_post(&state.semaphore)
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

core_audio_feed :: proc(samples: [][2]Audio_Sample) {
	remaining := samples
	for len(remaining) > 0 {
		sync.sema_wait(&s.semaphore)

		if intrinsics.atomic_load(&s.interrupted) {
			return
		}

		buffer := s.buffers[s.buffer]
		s.buffer = (s.buffer + 1) % len(s.buffers)

		to_write_samples := min(int(buffer.mAudioDataBytesCapacity / size_of([2]Audio_Sample)), len(remaining))
		to_write_bytes   := to_write_samples * size_of([2]Audio_Sample)
		intrinsics.mem_copy_non_overlapping(buffer.mAudioData, raw_data(remaining), to_write_bytes)
		buffer.mAudioDataByteSize = u32(to_write_bytes)
		remaining = remaining[to_write_samples:]

		// Count the samples before handing the buffer over. The queue may play it and call the
		// callback right away, and the callback takes them off again.
		intrinsics.atomic_add(&s.queued_samples, to_write_samples)

		if !ch(Audio.QueueEnqueueBuffer(s.queue, buffer, 0, nil)) {
			intrinsics.atomic_sub(&s.queued_samples, to_write_samples)
			return
		}
	}
}

// How many samples the queue still has left to play. This counts what is in the buffers that have
// been enqueued and not handed back yet.
//
// It is deliberately not the queue's own playback position. The mixer uses this number to decide
// when to feed, and `feed` blocks until the queue hands a buffer back, so the two have to agree.
// The playback position says nothing about which buffers are free, so it can send the mixer into
// `feed` while all of them are still in flight. The frame then stalls until one is played.
core_audio_remaining_samples :: proc() -> int {
	return intrinsics.atomic_load(&s.queued_samples)
}

// Posts once per buffer, so a `feed` waiting on any of them wakes up and sees the flag.
core_audio_stop_feeding :: proc() {
	intrinsics.atomic_store(&s.interrupted, true)
	sync.sema_post(&s.semaphore, len(s.buffers))
}

// The queue is only as deep as what the mixer feeds it, so it has nothing of its own to ask for.
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

// The audio queue hands buffers back on its own thread, but the mixer is still fed rather than
// asked. See `_pull_audio` for the shape a backend that drives itself uses.
core_audio_drives_itself :: proc() -> bool {
	return false
}
