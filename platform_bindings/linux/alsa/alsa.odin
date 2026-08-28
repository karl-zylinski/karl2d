// Minimal ALSA bindings. The enums are missing some members. This is just the stuff Karl2D needs.
// Loaded with dlopen instead of a static foreign import. A static foreign import would need
// libasound to be present just to start the game, and sound is not worth refusing to launch over.
package alsa

import "core:c"
import "core:dynlib"

PCM :: distinct rawptr

PCM_Stream :: enum c.int {
	PLAYBACK = 0,
	CAPTURE  = 1,
}

PCM_Open_Mode :: enum c.int {
	NONBLOCK = 1,
	ASYNC    = 2,
}

PCM_Access :: enum c.int {
	RW_INTERLEAVED = 3,
}

PCM_Format :: enum c.int {
	FLOAT_LE = 14,
}

pcm_open: proc "c" (pcm: ^PCM, name: cstring, stream: PCM_Stream, mode: c.int) -> c.int

pcm_close: proc "c" (pcm: PCM) -> c.int

pcm_set_params: proc "c" (
	pcm:           PCM,
	format:        PCM_Format,
	access:        PCM_Access,
	channels:      c.uint,
	rate:          c.uint,
	soft_resample: c.int,
	latency:       c.ulong,
) -> c.int

pcm_prepare: proc "c" (pcm: PCM) -> c.int

pcm_writei: proc "c" (pcm: PCM, buffer: rawptr, size: c.ulong) -> c.long

pcm_delay: proc "c" (pcm: PCM, delay: ^c.long) -> c.int

pcm_recover: proc "c" (pcm: PCM, err: c.int, silent: c.int) -> c.int

strerror: proc "c" (errnum: c.int) -> cstring

LIB_ASOUND :: "libasound.so.2"

@(private)
lib: dynlib.Library

// Loads libasound. On failure `missing` names the library or the symbol that was not found.
load :: proc() -> (missing: string, ok: bool) {
	symbols := [?]struct {
		name: string,
		ptr:  rawptr,
	} {
		{"snd_pcm_open", &pcm_open},
		{"snd_pcm_close", &pcm_close},
		{"snd_pcm_set_params", &pcm_set_params},
		{"snd_pcm_prepare", &pcm_prepare},
		{"snd_pcm_writei", &pcm_writei},
		{"snd_pcm_delay", &pcm_delay},
		{"snd_pcm_recover", &pcm_recover},
		{"snd_strerror", &strerror},
	}

	lib_ok: bool
	lib, lib_ok = dynlib.load_library(LIB_ASOUND)

	if !lib_ok {
		lib = nil
		return LIB_ASOUND, false
	}

	for s in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, s.name)

		if !addr_ok {
			unload()
			return s.name, false
		}

		(^rawptr)(s.ptr)^ = addr
	}

	return "", true
}

// Closes the library again, for when one of the symbols turns out to be missing.
unload :: proc() {
	if lib != nil {
		dynlib.unload_library(lib)
		lib = nil
	}
}
