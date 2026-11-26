#+build linux:android
#+vet explicit-allocators
#+private package
package karl2d

import "core:sync"
import "core:thread"

import "log"
import aa "vendor:android/aaudio"

AAUDIO_MIX_CHUNK_SIZE :: 512

AUDIO_BACKEND_AAUDIO :: Audio_Backend_Interface {
	state_type = AAudio_State,
	init = aaudio_init,
	shutdown = aaudio_shutdown,
	mix_chunk_size = AAUDIO_MIX_CHUNK_SIZE,
	has_mixer_thread = true,
	push_samples = nil,
	pushed_samples_remaining = nil,
	suspend = aaudio_suspend,
	resume = aaudio_resume,
}

AAudio_State :: struct {
	using _: Audio_Backend_State,
	stream: ^aa.AAudioStream,
	stream_mutex: sync.Mutex,
	chunk: [AAUDIO_MIX_CHUNK_SIZE][2]Audio_Sample,
	chunk_read_pos: int,
	reopen_thread: ^thread.Thread,
	reopen_sema: sync.Sema,
	running: bool,
	suspended: bool,
}

aaudio_init :: proc(s: ^AAudio_State) -> bool {
	log.debug("Init audio backend AAudio")
	s.chunk_read_pos = len(s.chunk)
	s.running = true
	s.reopen_thread = thread.create(aaudio_reopen_thread_proc)

	if s.reopen_thread == nil {
		log.error("AAudio: Failed creating stream reopen thread")
		return false
	}

	s.reopen_thread.data = s
	thread.start(s.reopen_thread)

	sync.mutex_lock(&s.stream_mutex)
	stream, stream_ok := aaudio_open_stream(s)
	s.stream = stream
	sync.mutex_unlock(&s.stream_mutex)

	if !stream_ok {
		aaudio_stop_reopen_thread(s)
		return false
	}

	return true
}

aaudio_shutdown :: proc(s: ^AAudio_State) {
	log.debug("Shutdown audio backend AAudio")
	aaudio_stop_reopen_thread(s)

	sync.mutex_lock(&s.stream_mutex)
	aaudio_close_stream(s.stream)
	s.stream = nil
	sync.mutex_unlock(&s.stream_mutex)
}

aaudio_suspend :: proc(s: ^AAudio_State) {
	sync.mutex_lock(&s.stream_mutex)
	defer sync.mutex_unlock(&s.stream_mutex)
	s.suspended = true

	if s.stream == nil {
		return
	}

	pause_res := aa.AAudioStream_requestPause(s.stream)

	if pause_res != .OK {
		log.errorf(
			"AAudio: AAudioStream_requestPause failed: %v",
			aa.AAudio_convertResultToText(pause_res),
		)
	}
}

aaudio_resume :: proc(s: ^AAudio_State) {
	sync.mutex_lock(&s.stream_mutex)
	defer sync.mutex_unlock(&s.stream_mutex)
	s.suspended = false

	if s.stream == nil {
		return
	}

	start_res := aa.AAudioStream_requestStart(s.stream)

	if start_res != .OK {
		log.errorf(
			"AAudio: AAudioStream_requestStart failed: %v",
			aa.AAudio_convertResultToText(start_res),
		)
	}
}

aaudio_stop_reopen_thread :: proc(s: ^AAudio_State) {
	sync.atomic_store(&s.running, false)
	sync.sema_post(&s.reopen_sema)
	thread.join(s.reopen_thread)
	thread.destroy(s.reopen_thread)
	s.reopen_thread = nil
}

aaudio_open_stream :: proc(s: ^AAudio_State) -> (^aa.AAudioStream, bool) {
	builder: ^aa.AAudioStreamBuilder
	builder_res := aa.AAudio_createStreamBuilder(&builder)

	if builder_res != .OK {
		log.errorf(
			"AAudio: AAudio_createStreamBuilder failed: %v",
			aa.AAudio_convertResultToText(builder_res),
		)
		return nil, false
	}

	defer aa.AAudioStreamBuilder_delete(builder)

	aa.AAudioStreamBuilder_setDirection(builder, .OUTPUT)
	aa.AAudioStreamBuilder_setFormat(builder, .PCM_FLOAT)
	aa.AAudioStreamBuilder_setChannelCount(builder, 2)
	aa.AAudioStreamBuilder_setSampleRate(builder, AUDIO_MIX_SAMPLE_RATE)
	aa.AAudioStreamBuilder_setSharingMode(builder, .SHARED)
	aa.AAudioStreamBuilder_setPerformanceMode(builder, .LOW_LATENCY)
	aa.AAudioStreamBuilder_setUsage(builder, .USAGE_GAME)
	aa.AAudioStreamBuilder_setDataCallback(builder, aaudio_data_callback, s)
	aa.AAudioStreamBuilder_setErrorCallback(builder, aaudio_error_callback, s)

	stream: ^aa.AAudioStream
	open_res := aa.AAudioStreamBuilder_openStream(builder, &stream)

	if open_res != .OK {
		log.errorf(
			"AAudio: AAudioStreamBuilder_openStream failed: %v",
			aa.AAudio_convertResultToText(open_res),
		)
		return nil, false
	}

	sample_rate := aa.AAudioStream_getSampleRate(stream)

	if sample_rate != AUDIO_MIX_SAMPLE_RATE {
		log.errorf(
			"AAudio: Stream opened with sample rate %v, but %v is required",
			sample_rate,
			AUDIO_MIX_SAMPLE_RATE,
		)
		aa.AAudioStream_close(stream)
		return nil, false
	}

	format := aa.AAudioStream_getFormat(stream)

	if format != .PCM_FLOAT {
		log.errorf("AAudio: Stream opened with format %v, but PCM_FLOAT is required", format)
		aa.AAudioStream_close(stream)
		return nil, false
	}

	channel_count := aa.AAudioStream_getChannelCount(stream)

	if channel_count != 2 {
		log.errorf("AAudio: Stream opened with %v channels, but 2 are required", channel_count)
		aa.AAudioStream_close(stream)
		return nil, false
	}

	if s.suspended {
		return stream, true
	}

	start_res := aa.AAudioStream_requestStart(stream)

	if start_res != .OK {
		log.errorf(
			"AAudio: AAudioStream_requestStart failed: %v",
			aa.AAudio_convertResultToText(start_res),
		)
		aa.AAudioStream_close(stream)
		return nil, false
	}

	return stream, true
}

aaudio_close_stream :: proc(stream: ^aa.AAudioStream) {
	if stream == nil {
		return
	}

	aa.AAudioStream_requestStop(stream)
	aa.AAudioStream_close(stream)
}

aaudio_reopen_thread_proc :: proc(t: ^thread.Thread) {
	context = _audio_thread_context()
	s := (^AAudio_State)(t.data)

	for {
		sync.sema_wait(&s.reopen_sema)

		if !sync.atomic_load(&s.running) {
			return
		}

		log.debug("AAudio: Reopening disconnected stream")
		sync.mutex_lock(&s.stream_mutex)
		aaudio_close_stream(s.stream)
		stream, _ := aaudio_open_stream(s)
		s.stream = stream
		sync.mutex_unlock(&s.stream_mutex)
	}
}

aaudio_data_callback :: proc "c" (
	stream: ^aa.AAudioStream,
	user_data: rawptr,
	audio_data: rawptr,
	num_frames: i32,
) -> aa.aaudio_data_callback_result_t {
	s := (^AAudio_State)(user_data)
	context = _audio_thread_context()
	out := ([^][2]Audio_Sample)(audio_data)[:num_frames]

	for len(out) > 0 {
		if s.chunk_read_pos == len(s.chunk) {
			_mix_audio_into_buffer(s.chunk[:])
			s.chunk_read_pos = 0
		}

		num_copied := copy(out, s.chunk[s.chunk_read_pos:])
		s.chunk_read_pos += num_copied
		out = out[num_copied:]
	}

	free_all(context.temp_allocator)
	return .CONTINUE
}

aaudio_error_callback :: proc "c" (
	stream: ^aa.AAudioStream,
	user_data: rawptr,
	error: aa.aaudio_result_t,
) {
	s := (^AAudio_State)(user_data)
	context = _audio_thread_context()

	if error != .ERROR_DISCONNECTED {
		log.errorf("AAudio: Stream error: %v", aa.AAudio_convertResultToText(error))
		return
	}

	sync.sema_post(&s.reopen_sema)
}
