
const karl2dAudioJsImports = {
	karl2d_web_audio: {
		_web_audio_init: function () {
			async function boot_audio() {
				const audioCtx = new AudioContext();
				await audioCtx.audioWorklet.addModule("./audio_backend_web_audio_processor.js");
				const audioWorkletNode = new AudioWorkletNode(audioCtx, "karl2d-audio-processor");
				audioWorkletNode.connect(audioCtx.destination);

				document.querySelector('body').addEventListener('click', function() {
					audioCtx.resume()
				});
			}

			boot_audio();
		}
	}
}