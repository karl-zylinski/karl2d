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
	buf: [AUDIO_MIX_CHUNK_SIZE*5]Audio_Sample,
	buf_start: int,
	buf_end: int,

	feed_thread: ^thread.Thread,
	run_thread: bool,
}

alsa_state_size :: proc() -> int {
	return size_of(Alsa_State)
}

s: ^Alsa_State

alsa_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	assert(state != nil)
	s = (^Alsa_State)(state)
	log.debug("Init audio backend alsa")

	alsa_err: c.int
	pcm: alsa.PCM
	alsa_err = alsa.pcm_open(&pcm, "default", .PLAYBACK, 0)

	if alsa_err < 0 {
		log.errorf("pcm_open failed for 'default': %s", alsa.strerror(alsa_err))
		return
	}

	LATENCY_MICROSECONDS :: 25000
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

	s.run_thread = true
	s.feed_thread = thread.create(alsa_thread_proc)
	thread.start(s.feed_thread)
	s.pcm = pcm
}

alsa_thread_proc :: proc(t: ^thread.Thread) {
	for s.run_thread {
		time.sleep(5 * time.Millisecond)
		start, end := sync.atomic_load(&s.buf_start), sync.atomic_load(&s.buf_end)

		write :: proc(pcm: alsa.PCM, data: []Audio_Sample) {
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
						s.run_thread = false
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
	}
}

alsa_shutdown :: proc() {
	log.debug("Shutdown audio backend alsa")

	s.run_thread = false
	thread.join(s.feed_thread)
	thread.destroy(s.feed_thread)

	if s.pcm != nil {
		alsa.pcm_close(s.pcm)
		s.pcm = nil
	}
}

alsa_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Alsa_State)(state)
}

alsa_feed :: proc(samples: []Audio_Sample) {
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
