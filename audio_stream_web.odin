// On web we currently do not support audio streams. This file just contains stubs. An error will
// be printed if you try to load an audio stream.
//
// Web audio streams may be supported in the future. They need:
// - A way to read files. May need to use Fetch API or similar.
// - A way to decode audio data. For example, stb_vorbis can be used on web, but the one in vendor
// currently is not set up for it.
#+build js
package karl2d

import "log"
import "base:runtime"
import hm "core:container/handle_map"

Audio_Stream_Manager :: struct {}

audio_stream_init_manager :: proc(
	as: ^Audio_Stream_Manager,
	buffers: ^hm.Dynamic_Handle_Map(Audio_Buffer, Audio_Buffer_Handle),
	playing_buffers: ^hm.Dynamic_Handle_Map(Playing_Audio_Buffer, Playing_Audio_Buffer_Handle),
	allocator: runtime.Allocator,
) {
}

audio_stream_destroy_manager :: proc(as: ^Audio_Stream_Manager) {
}

audio_stream_load_from_file :: proc(as: ^Audio_Stream_Manager, filename: string) -> Audio_Stream {
	log.error("Loading audio stream is currently not supported on this platform.")
	return AUDIO_STREAM_NONE
}

audio_stream_destroy :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
}

audio_stream_play :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, loop: bool) {
}

audio_stream_pause :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
}

audio_stream_stop :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
}

audio_stream_set_volume :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, volume: f32) {
}

audio_stream_set_pan :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, pan: f32) {
}

audio_stream_set_pitch :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, pitch: f32) {
}

audio_stream_update :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
}