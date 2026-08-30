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

	mixes_itself = true,
	feed = waveout_feed,
	remaining_samples = waveout_remaining_samples,
}

import "base:runtime"
import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:slice"
import "core:sync"
import "core:thread"

// waveOut has no callback that can fill a buffer, so a thread waits for one to finish playing and
// has the mixer fill it. Four buffers of 700 samples is 63 milliseconds of audio at worst, and the
// three that are normally in flight are 47 milliseconds.
WAVEOUT_BUFFER_SAMPLES :: 700
WAVEOUT_BUFFER_COUNT :: 4

Waveout_State :: struct {
	device: win32.HWAVEOUT,
	headers: [WAVEOUT_BUFFER_COUNT]win32.WAVEHDR,

	// The mixer writes straight into these, so a buffer belongs to the header that plays it.
	buffers: [WAVEOUT_BUFFER_COUNT][WAVEOUT_BUFFER_SAMPLES][2]Audio_Sample,
	cur_header: int,

	mix_thread: ^thread.Thread,
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

	if ch(win32.waveOutOpen(
		&s.device,
		win32.WAVE_MAPPER,
		&format,
		0,
		0,
		win32.CALLBACK_NULL,
	)) != 0 {
		return
	}

	// The thread waits a millisecond at a time for a buffer to finish. `time.sleep` rounds up to
	// the timer period, which is 15.6 ms by default, so ask Windows for 1 ms instead.
	win32.timeBeginPeriod(1)

	// Set the device before starting the thread: the thread uses it right away.
	s.run_thread = true
	s.mix_thread = thread.create(waveout_thread_proc)
	s.mix_thread.init_context = _audio_thread_context()
	thread.start(s.mix_thread)
}

// Has the mixer fill a buffer and gives it to the device. waveOut plays straight out of the
// buffer, so one is only refilled once the device has finished with it.
//
waveout_thread_proc :: proc(t: ^thread.Thread) {
	waiting_for_header: bool

	for sync.atomic_load(&s.run_thread) {
		h := &s.headers[s.cur_header]
		waiting_for_header = false

		for win32.waveOutUnprepareHeader(s.device, h, size_of(win32.WAVEHDR)) == win32.WAVERR_STILLPLAYING {
			if !sync.atomic_load(&s.run_thread) {
				waiting_for_header = true
				break
			}

			time.sleep(1 * time.Millisecond)
		}

		if waiting_for_header {
			break
		}

		buffer := s.buffers[s.cur_header][:]
		_mix_audio(buffer)
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

	_destroy_audio_thread_temp_allocator()
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

	// The thread is only created once the device is open. It stays nil if opening it failed.
	if s.mix_thread != nil {
		thread.join(s.mix_thread)
		thread.destroy(s.mix_thread)
		s.mix_thread = nil
		win32.timeEndPeriod(1)
	}

	// Take back the buffers the device is still playing before the state they live in goes away.
	win32.waveOutReset(s.device)
	win32.waveOutClose(s.device)
}

waveout_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}

// The thread asks the mixer for samples, so nothing hands them over.
waveout_feed :: proc(samples: [][2]Audio_Sample) {
}

waveout_remaining_samples :: proc() -> int {
	return 0
}