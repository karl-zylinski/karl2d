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
	mixes_itself       = true,
	feed               = alsa_feed,
	remaining_samples  = alsa_remaining_samples,
}

import "base:runtime"
import "core:c"
import "log"
import alsa "platform_bindings/linux/alsa"
import "core:thread"
import "core:sync"

// How many samples the mixer is asked for at a time. `pcm_writei` waits until the device has room
// for them, so this is how often the thread wakes rather than a latency figure. The device buffer
// set by `LATENCY_MICROSECONDS` below is what decides the latency.
ALSA_BUFFER_SAMPLES :: 700

Alsa_State :: struct {
	pcm: alsa.PCM,

	// The mixer fills this and the thread writes it straight to the device.
	buf: [ALSA_BUFFER_SAMPLES][2]Audio_Sample,

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
	s.run_thread = true
	s.feed_thread = thread.create(alsa_thread_proc)
	s.feed_thread.init_context = _audio_thread_context()
	thread.start(s.feed_thread)
}

// Has the mixer fill the buffer and writes it to the device.
//
// There is no sleep in this loop and it does not spin. `alsa_init` opens the PCM with a mode of
// zero rather than `PCM_Open_Mode.NONBLOCK`, so `pcm_writei` waits in the kernel until the device
// has taken the frames. The device sets the pace, which is what the old five millisecond sleep was
// approximating, and it does it exactly rather than by guessing.
alsa_thread_proc :: proc(t: ^thread.Thread) {
	for sync.atomic_load(&s.run_thread) {
		_mix_audio(s.buf[:])

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

		write(s.pcm, s.buf[:])
	}

	_destroy_audio_thread_temp_allocator()
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

// The thread asks the mixer for samples, so nothing hands them over.
alsa_feed :: proc(samples: [][2]Audio_Sample) {
}

alsa_remaining_samples :: proc() -> int {
	return 0
}
