// Minimal ALSA bindings. The enums are missing some members. This is just the stuff Karl2D needs.
package alsa

import "core:c"

foreign import lib "system:asound"

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

@(default_calling_convention="c", link_prefix="snd_")
foreign lib {
	pcm_open :: proc(pcm: ^PCM, name: cstring, stream: PCM_Stream, mode: c.int) -> c.int ---
	pcm_close :: proc(pcm: PCM) -> c.int ---
	
	pcm_set_params :: proc(
		pcm: PCM,
		format: PCM_Format,
		access: PCM_Access,
		channels: c.uint,
		rate: c.uint,
		soft_resample: c.int,
		latency: c.ulong,
	) -> c.int ---

	pcm_prepare :: proc(pcm: PCM) -> c.int ---
	pcm_writei :: proc(pcm: PCM, buffer: rawptr, size: c.ulong) -> c.long ---
	pcm_delay :: proc(pcm: PCM, delay: ^c.long) -> c.int ---
	pcm_recover :: proc(pcm: PCM, err: c.int, silent: c.int) -> c.int ---
	strerror :: proc(errnum: c.int) -> cstring ---
}
