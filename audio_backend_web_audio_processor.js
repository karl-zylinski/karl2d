// This file takes care of sending samples of audio to the browser. The stuff in here actually runs
// on a separate thread.
class Karl2DAudioProcessor extends AudioWorkletProcessor {
	process(inputs, outputs, parameters) {
		if (this.chunks.length == 0 || outputs[0].length !== 2) {
			return true;
		}

		const left = outputs[0][0];
		const right = outputs[0][1];
		let chunk = this.chunks[0];

		let sample_idx = 0;
		const num_samples = left.length;
		for (; sample_idx < num_samples; sample_idx++) {
			left[sample_idx] = chunk[this.cur_chunk_idx];
			right[sample_idx] = chunk[this.cur_chunk_idx + 1];
			this.cur_chunk_idx += 2;
			
			if (this.cur_chunk_idx >= chunk.length) {
				this.chunks.shift();
				this.cur_chunk_idx = 0;

				if (this.chunks.length == 0) {
					sample_idx += 1;
					
					let silence_fill_idx = sample_idx;
					for (; silence_fill_idx < num_samples; silence_fill_idx++) {
						left[silence_fill_idx] = 0;
						right[silence_fill_idx] = 0;
					}
					break;
				}
				chunk = this.chunks[0];
			}
		}
		
		// Sometimes we don't consume as many samples as `num_samples`. Specifically, we may run out
		// of chunks before filling out all the output samples.
		this.consumed_samples += sample_idx;
		
		if (this.consumed_samples >= num_samples) {
			this.port.postMessage({
				type: 'samples_consumed',
				data: this.consumed_samples,
			});
			this.consumed_samples = 0;
		}

		return true;
	}
	
	constructor() {
		super();
		this.chunks = [];
		this.cur_chunk_idx = 0;
		this.consumed_samples = 0;

		this.port.onmessage = (event) => {
			if (event.data.type === 'samples') {
				this.chunks.push(event.data.data);
			}
		};
	}
}

registerProcessor("karl2d-audio-processor", Karl2DAudioProcessor);