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
	has_mixer_thread   = true,
}

import "base:runtime"
import "core:c"
import "log"
import alsa "platform_bindings/linux/alsa"
import "core:thread"
import "core:sync"

ALSA_BUFFER_SAMPLES :: 700

Alsa_State :: struct {
	pcm: alsa.PCM,

	// TODO-UPDATE-COMMENT this is no longer circular. The mixer fills it and the thread writes
	// all of it to the device.
	// This is a "circular" buffer. We write new things at `buf_end` and read from `buf_start`.
	// AUDIO_MIX_CHUNK_SIZE * 3 should be enough, but I added some head room. 3 should be enough
	// because the mixer tends to not never produce more than 2.5 * AUDIO_MIX_CHUNK_SIZE samples
	// (it throws in another chunk if the remaining number of samples is less than
	// 1.5 * AUDIO_MIX_CHUNK_SIZE).
	buf: [ALSA_BUFFER_SAMPLES][2]Audio_Sample,

	mix_thread: ^thread.Thread,
	run_mix_thread: bool,
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

	// Set the PCM before starting the thread: the thread uses it right away.
	s.pcm = pcm
	s.run_mix_thread = true
	s.mix_thread = thread.create(alsa_thread_proc)
	thread.start(s.mix_thread)
}

alsa_thread_proc :: proc(t: ^thread.Thread) {
	context = _audio_thread_context()

	for sync.atomic_load(&s.run_mix_thread) {
		_mix_audio_into_buffer(s.buf[:])

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
						sync.atomic_store(&s.run_mix_thread, false)
						return
					}

					continue
				}

				remaining = remaining[ret:]
			}
		}

		write(s.pcm, s.buf[:])
		free_all(context.temp_allocator)
	}
}

alsa_shutdown :: proc() {
	log.debug("Shutdown audio backend alsa")

	sync.atomic_store(&s.run_mix_thread, false)

	// The thread is only created if the whole of `alsa_init` succeeded. It may be nil if for
	// example no ALSA device was available.
	if s.mix_thread != nil {
		thread.join(s.mix_thread)
		thread.destroy(s.mix_thread)
		s.mix_thread = nil
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
