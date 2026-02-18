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

Alsa_State :: struct {
	pcm: alsa.PCM,
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

	s.pcm = pcm
}

alsa_shutdown :: proc() {
	log.debug("Shutdown audio backend alsa")
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

	remaining := samples

	for len(remaining) > 0 {
		// Note that this blocks. But this should run on a an audio thread, so it will be fine.
		ret := alsa.pcm_writei(s.pcm, raw_data(remaining), c.ulong(len(remaining)))

		if ret < 0 {
			// Recover from errors. One possible error is an underrun. I.e. ALSA ran out of bytes.
			// In that case we must recover the PCM device and then try feeding it data again.
			recover_ret := alsa.pcm_recover(s.pcm, c.int(ret), 1)

			// Can't recover!
			if recover_ret < 0 {
				break
			}

			continue
		}

		written := int(ret)
		remaining = remaining[written:]
	}
}

alsa_remaining_samples :: proc() -> int {
	if s.pcm == nil {
		return 0
	}

	// The delay in ALSA says how many frames are buffered. So it means: "If you submit a sample
	// now, how many frames will be played before it?". This means that it is essentially the same
	// as "remaining samples".
	delay: c.long
	ret := alsa.pcm_delay(s.pcm, &delay)

	if ret < 0 {
		recover_ret := alsa.pcm_recover(s.pcm, ret, 1)

		if recover_ret < 0 {
			return 0
		}

		ret = alsa.pcm_delay(s.pcm, &delay)

		if ret < 0 {
			return 0
		}
	}

	if delay < 0 {
		return 0
	}

	return int(delay)
}
