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
}

import "base:runtime"
import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:math"
import "core:slice"

Waveout_State :: struct {
	device: win32.HWAVEOUT,
	allocator: runtime.Allocator,
	headers: [32]win32.WAVEHDR,
	cur_header: int,
	submitted_samples: int,
}

waveout_state_size :: proc() -> int {
	return size_of(Waveout_State)
}

s: ^Waveout_State

waveout_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	assert(state != nil)
	s = (^Waveout_State)(state)
	s.allocator = allocator
	log.debug("Init audio backend waveout")

	format := win32.WAVEFORMATEX {
		nSamplesPerSec = 44100,
		wBitsPerSample = 16,
		nChannels = 2,
		wFormatTag = win32.WAVE_FORMAT_PCM,
		cbSize = size_of(win32.WAVEFORMATEX),
	}

	format.nBlockAlign = (format.wBitsPerSample * format.nChannels) / 8 // see nBlockAlign docs
	format.nAvgBytesPerSec = (u32(format.wBitsPerSample * format.nChannels) * format.nSamplesPerSec) / 8

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
}

waveout_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}

waveout_feed :: proc(samples: []Audio_Sample) {
	h := &s.headers[s.cur_header]

	for win32.waveOutUnprepareHeader(s.device, h, size_of(win32.WAVEHDR)) == win32.WAVERR_STILLPLAYING {
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