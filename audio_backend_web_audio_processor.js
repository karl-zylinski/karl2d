class Karl2DAudioProcessor extends AudioWorkletProcessor {
	process(inputs, outputs, parameters) {
		const output = outputs[0];
		output.forEach((channel) => {
			for (let i = 0; i < channel.length; i++) {
				channel[i] = (Math.random() * 2 - 1)*0.2;
			}
		});
		return true;
	}
}

registerProcessor("karl2d-audio-processor", Karl2DAudioProcessor);