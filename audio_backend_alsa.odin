#+build linux
#+vet explicit-allocators
#+private package
package karl2d

import "core:c"
import "log"
import alsa "platform_bindings/linux/alsa"
import "core:thread"
import "core:sync"

ALSA_BUFFER_SAMPLES :: 700

AUDIO_BACKEND_ALSA :: Audio_Backend_Interface {
	state_type = Alsa_State,
	init = alsa_init,
	shutdown = alsa_shutdown,
	mix_chunk_size = ALSA_BUFFER_SAMPLES,
	has_mixer_thread = true,
	push_samples = nil,
	pushed_samples_remaining = nil,
}

Alsa_State :: struct {
	using base: Audio_Backend_State,
	pcm: alsa.PCM,
	buf: [ALSA_BUFFER_SAMPLES][2]Audio_Sample,
	mix_thread: ^thread.Thread,
	run_mix_thread: bool,
}

alsa_init :: proc(s: ^Alsa_State) -> bool {
	log.debug("Init audio backend alsa")

	missing, load_ok := alsa.load()

	if !load_ok {
		log.errorf("No sound. Could not load %v.", missing)
		return false
	}

	alsa_err: c.int
	pcm: alsa.PCM
	alsa_err = alsa.pcm_open(&pcm, "default", .PLAYBACK, 0)

	if alsa_err < 0 {
		log.errorf("pcm_open failed for 'default': %s", alsa.strerror(alsa_err))
		return false
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
		return false
	}

	alsa_err = alsa.pcm_prepare(pcm)

	if alsa_err < 0 {
		log.errorf("pcm_prepare failed: %s", alsa.strerror(alsa_err))
		alsa.pcm_close(pcm)
		return false
	}
	
	s.pcm = pcm
	s.run_mix_thread = true
	s.mix_thread = thread.create(alsa_thread_proc)

	if s.mix_thread == nil {
		log.errorf("Failed creating ALSA mixer thread")
		alsa.pcm_close(pcm)
		return false
	}

	s.mix_thread.data = s
	thread.start(s.mix_thread)
	return true
}

alsa_thread_proc :: proc(t: ^thread.Thread) {
	context = _audio_thread_context()

	s := (^Alsa_State)(t.data)

	for sync.atomic_load(&s.run_mix_thread) {
		_mix_audio_into_buffer(s.buf[:])

		write :: proc(s: ^Alsa_State, data: [][2]Audio_Sample) {
			remaining := data

			for len(remaining) > 0 {
				ret := alsa.pcm_writei(s.pcm, raw_data(remaining), c.ulong(len(remaining)))

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

		write(s, s.buf[:])
		free_all(context.temp_allocator)
	}
}

alsa_shutdown :: proc(s: ^Alsa_State) {
	log.debug("Shutdown audio backend alsa")

	if s.mix_thread != nil {
		sync.atomic_store(&s.run_mix_thread, false)
		thread.join(s.mix_thread)
		thread.destroy(s.mix_thread)
	}

	alsa.pcm_close(s.pcm)
}

