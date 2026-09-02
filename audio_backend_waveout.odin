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
	has_mixer_thread = true,
}

import "base:runtime"
import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:slice"
import "core:sync"
import "core:thread"

WAVEOUT_BUFFER_SAMPLES :: 700
WAVEOUT_BUFFER_COUNT :: 4

Waveout_State :: struct {
	device: win32.HWAVEOUT,
	headers: [WAVEOUT_BUFFER_COUNT]win32.WAVEHDR,

	buffers: [WAVEOUT_BUFFER_COUNT][WAVEOUT_BUFFER_SAMPLES][2]Audio_Sample,
	cur_header: int,

	mix_thread: ^thread.Thread,
	run_mix_thread: bool,
}

waveout_state_size :: proc() -> int {
	return size_of(Waveout_State)
}

s: ^Waveout_State

waveout_init :: proc(state: rawptr, allocator: runtime.Allocator) -> bool {
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
		return false
	}

	win32.timeBeginPeriod(1)

	s.run_mix_thread = true
	s.mix_thread = thread.create(waveout_thread_proc)
	// Don't set `s.mix_thread.init_context` here. We set the parts of the context we need in the thread
	// proc. `init_context` has too many unpredictable side-effects.
	thread.start(s.mix_thread)
	return true
}

waveout_thread_proc :: proc(t: ^thread.Thread) {
	context = _audio_thread_context()

	thread_loop: for sync.atomic_load(&s.run_mix_thread) {
		h := &s.headers[s.cur_header]

		// There is a circular buffer of headers that are playing audio. If one is still playing,
		// then it means we have wrapped around to the start of the buffer. Then we can only wait.
		//
		// The game may quit while we wait. Therefore we do an internal check of `run_mix_thread`.
		for win32.waveOutUnprepareHeader(s.device, h, size_of(win32.WAVEHDR)) == win32.WAVERR_STILLPLAYING {
			if !sync.atomic_load(&s.run_mix_thread) {
				break thread_loop
			}

			time.sleep(1 * time.Millisecond)
		}

		buffer := s.buffers[s.cur_header][:]
		_mix_audio_into_buffer(buffer)
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

		free_all(context.temp_allocator)
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
	sync.atomic_store(&s.run_mix_thread, false)

	if s.mix_thread != nil {
		thread.join(s.mix_thread)
		thread.destroy(s.mix_thread)
		s.mix_thread = nil
		win32.timeEndPeriod(1)
	}

	win32.waveOutReset(s.device)
	win32.waveOutClose(s.device)
}

waveout_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}
