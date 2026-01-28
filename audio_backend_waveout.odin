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

	test = waveout_test,
}

import "base:runtime"
import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:math"

Waveout_State :: struct {
	device: win32.HWAVEOUT,
	allocator: runtime.Allocator,
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

waveout_test :: proc() {
	log.info("Testing sound")

	freq :: 1000
	num_periods :: f64(44100) / freq
	log.info(num_periods)
	inc := (2*math.PI) / num_periods

	test_sound_block := make([]u16, 44100*2*5, s.allocator)

	tt: f64
	for &samp, i in test_sound_block {
		if i % 2 == 0 {
			tt += f64(inc)
		}
		sf := f32(math.sin(tt))
		sf += 1
		sf *= f32(max(u16)/2)

		if i % 2 == 1 {
			samp = u16(sf)
		}
	}

	{
		header := win32.WAVEHDR {
			dwBufferLength = u32(len(test_sound_block)*2),
			lpData = ([^]u8)(raw_data(test_sound_block)),
		}

		win32.waveOutPrepareHeader(s.device, &header, size_of(win32.WAVEHDR))

		win32.waveOutWrite(s.device, &header, size_of(win32.WAVEHDR))

		time.sleep(1000 * time.Millisecond)
		for win32.waveOutUnprepareHeader(s.device, &header, size_of(win32.WAVEHDR)) == win32.WAVERR_STILLPLAYING {
			time.sleep(10 * time.Millisecond)
		}
	}
}