// Web has no threads, so `update_audio_mixer` produces the audio instead. See
// `audio_mixer_thread_default.odin` for the version used everywhere else.
#+build js
package karl2d

@(private = "package")
_start_audio_mixer_thread :: proc() {
}

@(private = "package")
_stop_audio_mixer_thread :: proc() {
}
