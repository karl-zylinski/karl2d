// The mixer thread produces audio in the background, so games don't have to run at at least 31.5
// frames per second (44100/1400) to keep up with the audio backend. See
// `audio_mixer_thread_web.odin` for the web version, which has no threads and lets
// `update_audio_mixer` do the work instead.
#+build !js
package karl2d

import "core:thread"
import "core:time"

_audio_mixer_thread_proc :: proc(t: ^thread.Thread) {
	context.allocator, context.logger = _audio_mixer_thread_context()

	for _audio_mixer_thread_should_run() {
		_audio_mixer_thread_tick()
		time.sleep(2 * time.Millisecond)
	}
}

@(private = "package")
_start_audio_mixer_thread :: proc() {
	_audio_mixer_thread_begin()
	t := thread.create(_audio_mixer_thread_proc)
	thread.start(t)
	_audio_mixer_thread_set(t)
}

@(private = "package")
_stop_audio_mixer_thread :: proc() {
	_audio_mixer_thread_request_stop()

	if t := _audio_mixer_thread_get(); t != nil {
		thread.join((^thread.Thread)(t))
		thread.destroy((^thread.Thread)(t))
		_audio_mixer_thread_set(nil)
	}
}
