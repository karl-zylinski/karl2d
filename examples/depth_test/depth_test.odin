package karl2d_depth_test_example

import k2 "../.."

main :: proc() {
	k2.init(1280, 720, "Depth test", options = { depth_supported = true })

	shd := k2.load_shader_from_file("depth_test_shader.hlsl", "depth_test_shader.hlsl")
	k2.set_shader(shd)

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)
		k2.draw_rect({120, 120, 50, 50}, k2.WHITE)
		k2.draw_rect({100, 100, 50, 50}, k2.BLACK)
		k2.draw_rect({50, 50, 200, 200}, k2.ORANGE)
		k2.present()
	}

	k2.shutdown()
}