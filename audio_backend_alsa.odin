#+build linux
#+vet explicit-allocators
#+private file
package karl2d

@(private = "package")
AUDIO_BACKEND_ALSA :: Audio_Backend_Interface {
	state_size = alsa_state_size,
	init = alsa_init,
	shutdown = alsa_shutdown,
	set_internal_state = alsa_set_internal_state,
	has_mixer_thread = true,
}

import "core:c"
import "log"
import alsa "platform_bindings/linux/alsa"
import "core:thread"
import "core:sync"

ALSA_BUFFER_SAMPLES :: 700

Alsa_State :: struct {
	pcm: alsa.PCM,
	buf: [ALSA_BUFFER_SAMPLES][2]Audio_Sample,
	mix_thread: ^thread.Thread,
	run_mix_thread: bool,
}

alsa_state_size :: proc() -> int {
	return size_of(Alsa_State)
}

s: ^Alsa_State

alsa_init :: proc(state: rawptr) -> bool {
	assert(state != nil)
	s = (^Alsa_State)(state)
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

	// Set the PCM before starting the thread: the thread uses it right away.
	s.pcm = pcm
	s.run_mix_thread = true
	s.mix_thread = thread.create(alsa_thread_proc)

	if s.mix_thread == nil {
		log.errorf("Failed creating ALSA mixer thread")
		alsa.pcm_close(pcm)
		return false
	}

	thread.start(s.mix_thread)
	return true
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

	thread.join(s.mix_thread)
	thread.destroy(s.mix_thread)
	alsa.pcm_close(s.pcm)
}

alsa_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	new_state := (^Alsa_State)(state)
	sync.atomic_store(&new_state.run_mix_thread, false)
	thread.join(new_state.mix_thread)
	thread.destroy(new_state.mix_thread)
	s = new_state
	s.run_mix_thread = true
	s.mix_thread = thread.create(alsa_thread_proc)
	thread.start(s.mix_thread)
}
