// This file implements the JS parts that audio_backend_web_audio.odin needs. It's sets up the
// audio processor (see audio_backend_web_audio_processor.js) and handles communication with it.
// The procs in here are bound using the foreign block in audio_backend_web_audio.odin.

let wasmMemory = null;

function setWasmMemory(memory) {
	wasmMemory = memory;
}

const karl2dAudioJsImports = {
	karl2d_web_audio: {
		web_audio_init: function () {
			this.remaining_samples = 0;

			// Used to count off samples while the browser refuses to play anything. See
			// `web_audio_remaining_samples`.
			this.blocked_since = performance.now();
			this.was_blocked = true;

			async function boot_audio() {
				this.audio_ctx = new AudioContext({sampleRate: 44100});

				try {
					await this.audio_ctx.audioWorklet.addModule("./audio_backend_web_audio_processor.js");
				} catch (e) {
					console.error("Failed to load audio processor:", e);
					return;
				}

				this.audio_node = new AudioWorkletNode(
					this.audio_ctx,
					"karl2d-audio-processor",
					{
						outputChannelCount: [2]
					}
				);

				this.audio_node.connect(this.audio_ctx.destination);

				this.audio_node.port.onmessage = (event) => {
					if (event.data.type === 'samples_consumed') {
						this.remaining_samples -= event.data.data;
					}
				};

				this.resume_audio = () => {
					if (this.audio_ctx.state === 'suspended') {
						this.audio_ctx.resume();
					}
				};

				document.addEventListener('click', this.resume_audio);
				document.addEventListener('keydown', this.resume_audio);
				document.addEventListener('touchstart', this.resume_audio);
			}

			boot_audio();
		},

		web_audio_shutdown: function() {
			if (this.resume_audio) {
				document.removeEventListener('click', this.resume_audio);
				document.removeEventListener('keydown', this.resume_audio);
				document.removeEventListener('touchstart', this.resume_audio);
			}

			if (this.audio_node) {
				this.audio_node.disconnect();
			}

			if (this.audio_ctx) {
				this.audio_ctx.close();
			}

			this.audio_node = null;
			this.audio_ctx = null;
			this.resume_audio = null;
			this.remaining_samples = 0;
		},

		web_audio_feed: function(samples_f32_ptr, samples_f32_len) {
			// Count the samples even when they can't be sent anywhere, so that the mixer is fed
			// at the same rate either way. `web_audio_remaining_samples` counts them off again.
			this.remaining_samples += samples_f32_len / 2;

			if (this.audio_node == null || this.audio_ctx.state === 'suspended') {
				return;
			}

			let samples = new Float32Array(wasmMemory.buffer, samples_f32_ptr, samples_f32_len);

			this.audio_node.port.postMessage({
				type: 'samples',
				data: new Float32Array(samples),
			});
		},

		web_audio_remaining_samples: function() {
			let now = performance.now();
			let blocked = this.audio_node == null || this.audio_ctx.state === 'suspended';

			if (blocked) {
				// The audio processor isn't running, so it isn't telling us that it consumed
				// anything. Count off what it would have consumed by now, using the clock. That
				// keeps the mixer running at the rate it will run at once audio starts, so the
				// game carries on as usual and just can't be heard yet.
				let consumed = (now - this.blocked_since)*44100/1000;
				this.remaining_samples = Math.max(this.remaining_samples - consumed, 0);
			} else if (this.was_blocked) {
				// Audio just started. Nothing we fed while it was blocked reached the audio
				// processor, so start counting from nothing.
				this.remaining_samples = 0;
			}

			this.blocked_since = now;
			this.was_blocked = blocked;
			return this.remaining_samples;
		}
	}
};

window.setKarl2dAudioWasmMemory = setWasmMemory;
