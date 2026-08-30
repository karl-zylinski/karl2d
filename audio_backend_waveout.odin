#+build windows
#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_WAVEOUT :: Audio_Backend_Interface {
	state_size = waveout_state_size,
	init = waveout_init,
	shutdown = waveout_shutdown,
	set_internal_state = waveout_set_internal_state,

	feed = waveout_feed,
	remaining_samples = waveout_remaining_samples,
	stop_feeding = waveout_stop_feeding,
	target_samples = waveout_target_samples,
	drives_itself = waveout_drives_itself,
}

import "base:runtime"
import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:sync"
import "core:slice"
import "core:thread"

// How many samples one buffer holds, and how many buffers there are. waveOut has no callback that
// can fill a buffer, so a thread waits for one to finish playing and asks the mixer to fill it.
// Four buffers of 700 samples is 63 milliseconds of audio at most, and three of them in flight is
// the 47 milliseconds the mixer used to aim for.
WAVEOUT_BUFFER_SAMPLES :: 700
WAVEOUT_BUFFER_COUNT :: 4

Waveout_State :: struct {
	device: win32.HWAVEOUT,
	headers: [WAVEOUT_BUFFER_COUNT]win32.WAVEHDR,

	// The mixer writes straight into these, so each buffer belongs to one header.
	buffers: [WAVEOUT_BUFFER_COUNT][WAVEOUT_BUFFER_SAMPLES][2]Audio_Sample,
	cur_header: int,

	feed_thread: ^thread.Thread,
	run_thread: bool,
}

waveout_state_size :: proc() -> int {
	return size_of(Waveout_State)
}

s: ^Waveout_State

waveout_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	assert(state != nil)
	s = (^Waveout_State)(state)
	log.debug("Init audio backend waveout")

	// Added constant missing in bindings:
	// KSDATAFORMAT_SUBTYPE_IEEE_FLOAT GUID: 00000003-0000-0010-8000-00aa00389b71
	KSDATAFORMAT_SUBTYPE_IEEE_FLOAT :: win32.GUID{0x00000003, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}}

	format := win32.WAVEFORMATEXTENSIBLE {
		Format = {
			nSamplesPerSec = 44100,
			wBitsPerSample = 32,
			nChannels = 2,
			wFormatTag = win32.WAVE_FORMAT_EXTENSIBLE,
			cbSize = size_of(win32.WAVEFORMATEXTENSIBLE) - size_of(win32.WAVEFORMATEX),
		},
		Samples = {
			wValidBitsPerSample = 32,
		},
		dwChannelMask = { .FRONT_LEFT, .FRONT_RIGHT },
		SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT,
	}

	format.nBlockAlign = (format.wBitsPerSample * format.nChannels) / 8 // see nBlockAlign docs
	format.nAvgBytesPerSec = (u32(format.wBitsPerSample * format.nChannels) * format.nSamplesPerSec) / 8

	// The feed thread waits a millisecond at a time for a buffer to finish. `time.sleep` rounds up
	// to the timer period, which is 15.6 ms by default. This asks Windows for 1 ms instead.
	win32.timeBeginPeriod(1)

	ch(win32.waveOutOpen(
		&s.device,
		win32.WAVE_MAPPER,
		&format,
		0,
		0,
		win32.CALLBACK_NULL,
	))

	// Set the device before starting the thread: the thread uses it right away.
	s.run_thread = true
	s.feed_thread = thread.create(waveout_thread_proc)
	thread.start(s.feed_thread)
}

// Asks the mixer for samples and hands them to the device, one buffer at a time. waveOut plays
// straight out of the buffer, so a buffer is only refilled once the device has finished with it.
waveout_thread_proc :: proc(t: ^thread.Thread) {
	context.allocator, context.logger = _audio_thread_context()

	for sync.atomic_load(&s.run_thread) {
		h := &s.headers[s.cur_header]

		for win32.waveOutUnprepareHeader(s.device, h, size_of(win32.WAVEHDR)) == win32.WAVERR_STILLPLAYING {
			if !sync.atomic_load(&s.run_thread) {
				return
			}

			time.sleep(1 * time.Millisecond)
		}

		buffer := s.buffers[s.cur_header][:]
		_pull_audio(buffer)
		byte_samples := slice.reinterpret([]u8, buffer)

		h^ = {
			dwBufferLength = u32(len(byte_samples)),
			lpData = raw_data(byte_samples),
		}

		win32.waveOutPrepareHeader(s.device, h, size_of(win32.WAVEHDR))
		win32.waveOutWrite(s.device, h, size_of(win32.WAVEHDR))

		s.cur_header += 1

		if s.cur_header >= len(s.headers) {
			s.cur_header = 0
		}
	}
}

ch :: proc(mr: win32.MMRESULT, loc := #caller_location) -> win32.MMRESULT {
	if mr == 0 {
		return mr
	}

	log.errorf("waveout error. Error code: %v", u32(mr), location = loc)
	return mr
}

waveout_shutdown :: proc() {
	log.debug("Shutdown audio backend waveout")
	sync.atomic_store(&s.run_thread, false)

	// The thread is only created once the device is open. It is nil if opening it failed.
	if s.feed_thread != nil {
		thread.join(s.feed_thread)
		thread.destroy(s.feed_thread)
		s.feed_thread = nil
	}

	win32.waveOutReset(s.device)
	win32.waveOutClose(s.device)
	win32.timeEndPeriod(1)
}

waveout_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}

// The feed thread asks the mixer for samples, so nothing hands them over.
waveout_feed :: proc(samples: [][2]Audio_Sample) {
}

waveout_remaining_samples :: proc() -> int {
	return 0
}

waveout_stop_feeding :: proc() {
}

waveout_target_samples :: proc() -> int {
	return 0
}

waveout_drives_itself :: proc() -> bool {
	return true
}
