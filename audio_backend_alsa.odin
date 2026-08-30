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
	stop_feeding       = alsa_stop_feeding,
	target_samples     = alsa_target_samples,
	drives_itself      = alsa_drives_itself,
}

import "base:runtime"
import "core:c"
import "log"
import alsa "platform_bindings/linux/alsa"
import "core:thread"
import "core:sync"

// How many samples the mixer is asked for at a time. `pcm_writei` blocks until the device has
// taken them, so this is the granularity the feed thread runs at rather than a latency figure.
ALSA_BUFFER_SAMPLES :: 700

Alsa_State :: struct {
	pcm: alsa.PCM,

	// The mixer fills this and the feed thread writes it straight to the device. `pcm_writei`
	// waits until the device has room, which is what paces the thread.
	buf: [ALSA_BUFFER_SAMPLES][2]Audio_Sample,

	feed_thread: ^thread.Thread,
	run_thread: bool,

	// Counts feed thread passes, so the latency log below can be kept to one line every so often.
	delay_log_countdown: int,

	// How many times the device ran dry and had to be recovered. Reported by the latency log,
	// because a crackle that shows up here and one that does not have different causes.
	underruns: int,
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

	// Do not lower this to chase latency. On PipeWire the ALSA plugin passes the request down to
	// the graph, which drops its quantum to match. At 10000 the graph went to 64 samples and the
	// sink began xrunning, heard as crackling, while ALSA itself still reported every write as
	// fine. The latency worth winning is in how much the mixer keeps queued, not in this buffer.
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

	// `pcm_set_params` treats the latency as a request, so report what actually came back. The
	// device buffer is what decides the latency now that the thread writes straight to it.
	buffer_size, period_size: c.ulong

	if alsa.pcm_get_params(pcm, &buffer_size, &period_size) == 0 {
		log.debugf("alsa buffer %v samples, period %v samples", buffer_size, period_size)
	}

	// Set the PCM before starting the thread: the thread uses it right away.
	s.pcm = pcm
	s.run_thread = true
	s.feed_thread = thread.create(alsa_thread_proc)
	thread.start(s.feed_thread)
}

// Asks the mixer for samples and writes them to the device. `pcm_writei` waits until the device
// has room for them, so the device sets the pace and this thread never has to guess at one.
alsa_thread_proc :: proc(t: ^thread.Thread) {
	context.allocator, context.logger = _audio_thread_context()

	write :: proc(pcm: alsa.PCM, data: [][2]Audio_Sample) {
		remaining := data

		for len(remaining) > 0 {
			ret := alsa.pcm_writei(pcm, raw_data(remaining), c.ulong(len(remaining)))

			if ret < 0 {
				// Recover from errors. One possible error is an underrun. I.e. ALSA ran out of bytes.
				// In that case we must recover the PCM device and then try feeding it data again.
				s.underruns += 1
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

	for sync.atomic_load(&s.run_thread) {
		_pull_audio(s.buf[:])
		write(s.pcm, s.buf[:])

		// How far behind the device is. Only this thread may ask. Two threads must not touch the
		// PCM handle.
		delay: c.long
		alsa.pcm_delay(s.pcm, &delay)

		// One pass covers ALSA_BUFFER_SAMPLES, so this reports every few seconds.
		DELAY_LOG_PASSES :: 128
		s.delay_log_countdown -= 1

		if s.delay_log_countdown <= 0 {
			s.delay_log_countdown = DELAY_LOG_PASSES

			log.debugf(
				"audio latency %.1f ms (device %v, underruns %v)",
				f32(delay) * 1000 / AUDIO_MIX_SAMPLE_RATE,
				delay,
				s.underruns,
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

// The feed thread asks the mixer for samples, so nothing hands them over.
alsa_feed :: proc(samples: [][2]Audio_Sample) {
}

alsa_stop_feeding :: proc() {
}

alsa_target_samples :: proc() -> int {
	return 0
}

alsa_remaining_samples :: proc() -> int {
	return 0
}

// The feed thread asks the mixer for samples whenever the device has room for more.
alsa_drives_itself :: proc() -> bool {
	return true
}
