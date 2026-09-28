#+build windows
#+vet explicit-allocators
#+private package
package karl2d

import "log"
import win32 "core:sys/windows"
import "core:time"
import "core:slice"
import "core:sync"
import "core:thread"

WAVEOUT_BACKEND_INTERFACE :: Audio_Backend_Interface {
	destroy = waveout_destroy,
	start_mixer_thread = waveout_start_mixer_thread,
	mix_chunk_size = WAVEOUT_BUFFER_SAMPLES,
	has_mixer_thread = true,
}

WAVEOUT_BUFFER_SAMPLES :: 700
WAVEOUT_BUFFER_COUNT :: 4

Waveout_State :: struct {
	using interface: Audio_Backend_Interface,
	allocator: Allocator,
	device: win32.HWAVEOUT,
	headers: [WAVEOUT_BUFFER_COUNT]win32.WAVEHDR,

	buffers: [WAVEOUT_BUFFER_COUNT][WAVEOUT_BUFFER_SAMPLES][2]Audio_Sample,
	cur_header: int,

	mix_thread: ^thread.Thread,
	run_mix_thread: bool,
}

waveout_create :: proc(allocator: Allocator, loc := #caller_location) -> ^Audio_Backend_Interface {
	s := new(Waveout_State, allocator, loc)
	s.interface = WAVEOUT_BACKEND_INTERFACE
	s.allocator = allocator
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

	open_err := win32.waveOutOpen(
		&s.device,
		win32.WAVE_MAPPER,
		&format,
		0,
		0,
		win32.CALLBACK_NULL,
	)

	if open_err != 0 {
		log.errorf("waveOutOpen failed. Error code: %v", int(open_err))
		free(s, allocator)
		return nil
	}

	return s
}

waveout_start_mixer_thread :: proc(s: ^Waveout_State) {
	win32.timeBeginPeriod(1)
	s.run_mix_thread = true
	s.mix_thread = thread.create(waveout_thread_proc)

	if s.mix_thread == nil {
		log.panic("Failed creating waveout mixer thread")
	}

	s.mix_thread.data = s

	// Don't set `s.mix_thread.init_context` here. We set the parts of the context we need in the
	// thread proc. `init_context` has too many unpredictable side-effects.
	thread.start(s.mix_thread)
}

waveout_thread_proc :: proc(t: ^thread.Thread) {
	context = _audio_thread_context()

	s := (^Waveout_State)(t.data)

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

waveout_destroy :: proc(s: ^Waveout_State) {
	log.debug("Shutdown audio backend waveout")
	log.ensure(s.mix_thread != nil)
	sync.atomic_store(&s.run_mix_thread, false)
	thread.join(s.mix_thread)
	thread.destroy(s.mix_thread)
	win32.timeEndPeriod(1)
	win32.waveOutReset(s.device)
	win32.waveOutClose(s.device)
	a := s.allocator
	free(s, a)
}
