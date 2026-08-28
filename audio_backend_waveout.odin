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
}

import "base:runtime"
import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:sync"
import "core:slice"

Waveout_State :: struct {
	device: win32.HWAVEOUT,
	headers: [32]win32.WAVEHDR,
	cur_header: int,
	submitted_samples: int,

	// Set when the mixer thread is stopping. It makes the wait for a free header give up.
	interrupted: bool,
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

	// The mixer thread tops the device up every couple of milliseconds. `time.sleep` rounds up to
	// the timer period, which is 15.6 ms by default. This asks Windows for 1 ms instead.
	win32.timeBeginPeriod(1)

	ch(win32.waveOutOpen(
		&s.device,
		win32.WAVE_MAPPER,
		&format,
		0,
		0,
		win32.CALLBACK_NULL,
	))
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
	win32.waveOutClose(s.device)
	win32.timeEndPeriod(1)
}

waveout_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}

waveout_feed :: proc(samples: [][2]Audio_Sample) {
	h := &s.headers[s.cur_header]

	for win32.waveOutUnprepareHeader(s.device, h, size_of(win32.WAVEHDR)) == win32.WAVERR_STILLPLAYING {
		if sync.atomic_load(&s.interrupted) {
			return
		}

		time.sleep(1 * time.Millisecond)
	}

	byte_samples := slice.reinterpret([]u8, samples)

	h^ = {
		dwBufferLength = u32(len(byte_samples)),
		lpData = raw_data(byte_samples),
	}

	win32.waveOutPrepareHeader(s.device, h, size_of(win32.WAVEHDR))
	win32.waveOutWrite(s.device, h, size_of(win32.WAVEHDR))

	s.submitted_samples += len(samples)
	s.cur_header += 1

	if s.cur_header >= len(s.headers) {
		s.cur_header = 0
	}
}

waveout_remaining_samples :: proc() -> int {
	t := win32.MMTIME {
		wType = .TIME_SAMPLES,
	}
	win32.waveOutGetPosition(s.device, &t, size_of(win32.MMTIME))
	return s.submitted_samples - int(t.u.sample)
}

// `feed` checks this flag while it waits for a header, so the wait ends on the next pass.
waveout_stop_feeding :: proc() {
	sync.atomic_store(&s.interrupted, true)
}

// The device is only as full as what the mixer feeds it, so it has nothing of its own to ask for.
waveout_target_samples :: proc() -> int {
	return 0
}
