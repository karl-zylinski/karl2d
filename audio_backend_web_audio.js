let wasmMemory = null;

function setWasmMemory(memory) {
  wasmMemory = memory;
}

const karl2dAudioJsImports = {
	karl2d_web_audio: {
		_web_audio_init: function () {
			this.remaining_samples = 0;

			async function boot_audio() {
				const audio_ctx = new AudioContext({sampleRate: 44100});

				try {
					await audio_ctx.audioWorklet.addModule("./audio_backend_web_audio_processor.js");
				} catch (e) {
					console.error("Failed to load audio processor:", e);
					return;
				}

				this.audio_node = new AudioWorkletNode(
					audio_ctx,
					"karl2d-audio-processor",
					{
						outputChannelCount: [2]
					}
				);

				this.audio_node.connect(audio_ctx.destination);

				this.audio_node.port.onmessage = (event) => {
					if (event.data.type === 'samples_consumed') {
						this.remaining_samples -= event.data.data;
					}
				};

				const resume_audio = () => {
					if (audio_ctx.state === 'suspended') {
						audio_ctx.resume();
					}
				};

				document.addEventListener('click', resume_audio, {once: false});
				document.addEventListener('keydown', resume_audio, {once: false});
				document.addEventListener('touchstart', resume_audio, {once: false});
			}

			boot_audio();
		},

		_web_audio_feed: function(samples_f32_ptr, samples_f32_len) {
			if (this.audio_node == null) {
				return;
			}

			let samples = new Float32Array(wasmMemory.buffer, samples_f32_ptr, samples_f32_len);
			this.remaining_samples += samples.length / 2; // Stereo, two samples per stereo pair.

			this.audio_node.port.postMessage({
				type: 'samples',
				data: new Float32Array(samples),
			});
		},

		_web_audio_remaining_samples: function() {
			return this.remaining_samples;
		}
	}
};

window.setKarl2dAudioWasmMemory = setWasmMemory;
