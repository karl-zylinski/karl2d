#+build darwin
#+vet explicit-allocators
#+private file
package karl2d

@(private = "package")
AUDIO_BACKEND_COREAUDIO :: Audio_Backend_Interface {
	state_size         = coreaudio_state_size,
	init               = coreaudio_init,
	shutdown           = coreaudio_shutdown,
	set_internal_state = coreaudio_set_internal_state,
	feed               = coreaudio_feed,
	remaining_samples  = coreaudio_remaining_samples,
}

import "base:runtime"
import "core:time"
import "log"
import aq "platform_bindings/mac/audiotoolbox"

NUM_BUFFERS :: 8

CoreAudio_State :: struct {
	queue:             aq.AudioQueueRef,
	timeline:          aq.AudioQueueTimelineRef,
	buffers:           [NUM_BUFFERS]aq.AudioQueueBufferRef,
	buffer_busy:       [NUM_BUFFERS]bool,
	cur_buffer:        int,
	submitted_samples: int,
}

coreaudio_state_size :: proc() -> int {
	return size_of(CoreAudio_State)
}

cs: ^CoreAudio_State

coreaudio_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	cs = (^CoreAudio_State)(state)
	log.debug("[coreaudio] Init audio backend coreaudio")

	format := make_pcm_format(sample_rate = 44100.0, channels = 2, bits_per_channel = 32)

	status := aq.AudioQueueNewOutput(&format, audio_queue_callback, cs, nil, nil, 0, &cs.queue)
	if status != .NoErr {
		log.errorf("[coreaudio] Failed to create audio queue. Error code: %v", status)
		return
	}

	status = aq.AudioQueueCreateTimeline(cs.queue, &cs.timeline)
	if status != .NoErr {
		log.warnf("[coreaudio] Failed to create audio queue timeline. Error code: %v", status)
		cs.timeline = nil
	}

	buffer_size := u32(AUDIO_MIX_CHUNK_SIZE * size_of(Audio_Sample))
	for i in 0 ..< NUM_BUFFERS {
		aq.AudioQueueAllocateBuffer(cs.queue, buffer_size, &cs.buffers[i])
	}

	if aq.AudioQueueStart(cs.queue, nil) != .NoErr {
		log.errorf("[coreaudio] Failed to start audio queue. Error code: %v", status)
		return
	}
}

coreaudio_feed :: proc(samples: []Audio_Sample) {
	if cs == nil || cs.queue == nil {
		return
	}

	// sync wait
	for cs.buffer_busy[cs.cur_buffer] {
		time.sleep(1 * time.Millisecond)
	}

	buffer := cs.buffers[cs.cur_buffer]
	copy_len := min(len(samples), AUDIO_MIX_CHUNK_SIZE)
	byte_size := copy_len * size_of(Audio_Sample)

	runtime.mem_copy(buffer.mAudioData, raw_data(samples), byte_size)
	buffer.mAudioDataByteSize = u32(byte_size)
	cs.buffer_busy[cs.cur_buffer] = true

	if aq.AudioQueueEnqueueBuffer(cs.queue, buffer, 0, nil) == .NoErr {
		cs.submitted_samples += copy_len
		cs.cur_buffer = (cs.cur_buffer + 1) % NUM_BUFFERS
	}
}

coreaudio_remaining_samples :: proc() -> int {
	if cs == nil || cs.queue == nil {
		return 0
	}
	timestamp: aq.AudioTimeStamp
	discontinuity: bool

	status := aq.AudioQueueGetCurrentTime(cs.queue, cs.timeline, &timestamp, &discontinuity)
	if status == .NoErr && .Sample_Time_Valid in timestamp.mFlags {
		return max(cs.submitted_samples - int(timestamp.mSampleTime), 0)
	}

	return 0
}

coreaudio_shutdown :: proc() {
	if cs != nil && cs.queue != nil {
		if cs.timeline != nil {
			aq.AudioQueueDisposeTimeline(cs.queue, cs.timeline)
			cs.timeline = nil
		}
		aq.AudioQueueStop(cs.queue, true)
		aq.AudioQueueDispose(cs.queue, true)
		cs.queue = nil
	}
}

coreaudio_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	cs = (^CoreAudio_State)(state)
}

audio_queue_callback :: proc "c" (
	user_data: rawptr,
	queue: aq.AudioQueueRef,
	buffer: aq.AudioQueueBufferRef,
) {
	s := (^CoreAudio_State)(user_data)
	for b, i in s.buffers {
		if b == buffer {
			s.buffer_busy[i] = false
			return
		}
	}
}

make_pcm_format :: proc(
	sample_rate: f64,
	channels: u32,
	bits_per_channel: u32,
) -> aq.AudioStreamBasicDescription {
	bytes_per_sample := bits_per_channel / 8
	return aq.AudioStreamBasicDescription {
		mSampleRate = sample_rate,
		mFormatID = .Linear_PCM,
		mFormatFlags = {.Is_Float, .Is_Packed},
		mBytesPerPacket = bytes_per_sample * channels,
		mFramesPerPacket = 1,
		mBytesPerFrame = bytes_per_sample * channels,
		mChannelsPerFrame = channels,
		mBitsPerChannel = bits_per_channel,
		mReserved = 0,
	}
}
