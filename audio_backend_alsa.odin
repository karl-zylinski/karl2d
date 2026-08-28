#+build linux
#+vet explicit-allocators
#+private file
package karl2d

@(private = "package")
AUDIO_BACKEND_ALSA :: Audio_Backend_Interface {
	state_size         = alsa_state_size,
	init               = alsa_init,
	shutdown           = alsa_shutdown,
	set_internal_state = alsa_set_internal_state,
	feed               = alsa_feed,
	remaining_samples  = alsa_remaining_samples,
	queued_samples     = alsa_queued_samples,
	target_samples     = alsa_target_samples,
}

import "base:runtime"
import "core:c"
import "log"
import alsa "platform_bindings/linux/alsa"
import "core:thread"
import "core:time"
import "core:sync"

Alsa_State :: struct {
	pcm: alsa.PCM,

	// This is a "circular" buffer. We write new things at `buf_end` and read from `buf_start`.
	// AUDIO_MIX_CHUNK_SIZE * 3 should be enough, but I added some head room. 3 should be enough
	// because the mixer tends to not never produce more than 2.5 * AUDIO_MIX_CHUNK_SIZE samples
	// (it throws in another chunk if the remaining number of samples is less than
	// 1.5 * AUDIO_MIX_CHUNK_SIZE).
	buf: [AUDIO_MIX_CHUNK_SIZE*5][2]Audio_Sample,
	buf_start: int,
	buf_end: int,

	feed_thread: ^thread.Thread,
	run_thread: bool,

	// How many samples ALSA has taken but not played yet, sampled by the feed thread after every
	// write. The PCM belongs to that thread, so it is the only one that may ask.
	device_delay: int,

	// How many samples the mixer should keep queued. Taken from the buffer ALSA actually gave us,
	// which is not always the one that was asked for.
	target: int,

	// Counts feed thread passes, so the latency log below can be kept to one line every so often.
	delay_log_countdown: int,
}

alsa_state_size :: proc() -> int {
	return size_of(Alsa_State)
}

s: ^Alsa_State

alsa_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	assert(state != nil)
	s = (^Alsa_State)(state)
	log.debug("Init audio backend alsa")

	missing, load_ok := alsa.load()

	if !load_ok {
		log.errorf("No sound. Could not load %v.", missing)
		return
	}

	alsa_err: c.int
	pcm: alsa.PCM
	alsa_err = alsa.pcm_open(&pcm, "default", .PLAYBACK, 0)

	if alsa_err < 0 {
		log.errorf("pcm_open failed for 'default': %s", alsa.strerror(alsa_err))
		return
	}

	// The mixer thread tops the backend up every couple of milliseconds, so the device buffer no
	// longer has to cover a whole frame. Measured end to end through PipeWire this lands at about
	// 17 ms, against about 35 ms at 25000.
	LATENCY_MICROSECONDS :: 10000
	alsa_err = alsa.pcm_set_params(
		pcm,
		.FLOAT_LE,
		.RW_INTERLEAVED,
		2,
		44100,
		1,
		LATENCY_MICROSECONDS,
	)

	if alsa_err < 0 {
		log.errorf("pcm_set_params failed: %s", alsa.strerror(alsa_err))
		alsa.pcm_close(pcm)
		return
	}

	alsa_err = alsa.pcm_prepare(pcm)

	if alsa_err < 0 {
		log.errorf("pcm_prepare failed: %s", alsa.strerror(alsa_err))
		alsa.pcm_close(pcm)
		return
	}

	// `pcm_set_params` treats the latency as a request, so ask what actually came back. A failure
	// here leaves `target` at zero, which just means the mixer uses its own default.
	buffer_size, period_size: c.ulong

	if alsa.pcm_get_params(pcm, &buffer_size, &period_size) == 0 {
		s.target = int(buffer_size)
		log.debugf("alsa buffer %v samples, period %v samples", buffer_size, period_size)
	}

	// Set the PCM before starting the thread: the thread uses it right away.
	s.pcm = pcm
	s.run_thread = true
	s.feed_thread = thread.create(alsa_thread_proc)
	thread.start(s.feed_thread)
}

alsa_thread_proc :: proc(t: ^thread.Thread) {
	for sync.atomic_load(&s.run_thread) {
		time.sleep(5 * time.Millisecond)
		start, end := sync.atomic_load(&s.buf_start), sync.atomic_load(&s.buf_end)

		write :: proc(pcm: alsa.PCM, data: [][2]Audio_Sample) {
			remaining := data

			for len(remaining) > 0 {
				ret := alsa.pcm_writei(pcm, raw_data(remaining), c.ulong(len(remaining)))

				if ret < 0 {
					// Recover from errors. One possible error is an underrun. I.e. ALSA ran out of bytes.
					// In that case we must recover the PCM device and then try feeding it data again.
					recover_ret := alsa.pcm_recover(s.pcm, c.int(ret), 1)

					// Can't recover!
					if recover_ret < 0 {
						log.errorf("Fatal sound error:pcm_writei failed and recovery also failed: %s", alsa.strerror(c.int(ret)))
						sync.atomic_store(&s.run_thread, false)
						return
					}

					continue
				}

				remaining = remaining[ret:]
			}
		}

		if start > end {
			write(s.pcm, s.buf[start:])
			write(s.pcm, s.buf[:end])
		} else {
			write(s.pcm, s.buf[start:end])
		}

		sync.atomic_store(&s.buf_start, end)

		// Ask the device how far behind it is. This happens here rather than in
		// `alsa_queued_samples` because the PCM handle is not safe to touch from two threads.
		delay: c.long

		if alsa.pcm_delay(s.pcm, &delay) == 0 && delay >= 0 {
			sync.atomic_store(&s.device_delay, int(delay))
		}

		// The thread wakes every 5 ms, so this reports roughly every two seconds.
		DELAY_LOG_PASSES :: 400
		s.delay_log_countdown -= 1

		if s.delay_log_countdown <= 0 {
			s.delay_log_countdown = DELAY_LOG_PASSES
			mixer_held := end - start

			if mixer_held < 0 {
				mixer_held += len(s.buf)
			}

			log.debugf(
				"audio latency %.1f ms (mixer %v samples, device %v samples)",
				f32(mixer_held + int(delay)) * 1000 / AUDIO_MIX_SAMPLE_RATE,
				mixer_held,
				delay,
			)
		}
	}
}

alsa_shutdown :: proc() {
	log.debug("Shutdown audio backend alsa")

	sync.atomic_store(&s.run_thread, false)

	// The thread is only created if the whole of `alsa_init` succeeded. It may be nil if for
	// example no ALSA device was available.
	if s.feed_thread != nil {
		thread.join(s.feed_thread)
		thread.destroy(s.feed_thread)
		s.feed_thread = nil
	}

	if s.pcm != nil {
		alsa.pcm_close(s.pcm)
		s.pcm = nil
	}
}

alsa_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Alsa_State)(state)
}

alsa_feed :: proc(samples: [][2]Audio_Sample) {
	if s.pcm == nil || len(samples) == 0 {
		return
	}

	samples := samples
	i := sync.atomic_load(&s.buf_end)
	overflow := (i + len(samples)) - len(s.buf)

	if overflow > 0 {
		to_copy := len(samples) - overflow
		copy(s.buf[i:], samples[:to_copy])
		i = 0
		samples = samples[to_copy:]
	}

	copy(s.buf[i:], samples[:])
	sync.atomic_store(&s.buf_end, i + len(samples))
}

alsa_queued_samples :: proc() -> int {
	if s.pcm == nil {
		return 0
	}

	return sync.atomic_load(&s.device_delay)
}

alsa_target_samples :: proc() -> int {
	if s.pcm == nil {
		return 0
	}

	return s.target
}

alsa_remaining_samples :: proc() -> int {
	if s.pcm == nil {
		return 0
	}

	start, end := sync.atomic_load(&s.buf_start), sync.atomic_load(&s.buf_end)

	if end >= start {
		return end - start
	} 
	
	return len(s.buf) - start + end
}
