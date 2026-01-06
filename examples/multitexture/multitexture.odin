package karl2d_multitexture_example

import k2 "../.."
import "core:mem"
import "core:log"
import "core:fmt"

_ :: fmt
_ :: mem

main :: proc() {
	context.logger = log.create_console_logger()
	init()
	for step() {}
	shutdown()
}

shd: k2.Shader
tex1: k2.Texture
tex2: k2.Texture

init :: proc() {
	k2.init(1080, 1080, "Karl2D Multitexture Example")

	when k2.RENDER_BACKEND_NAME == "gl" {
		shd = k2.load_shader_from_file("gl_multitexture_vertex_shader.glsl", "gl_multitexture_fragment_shader.glsl")
	} else when k2.RENDER_BACKEND_NAME == "webgl" {
		shd = k2.load_shader_from_bytes(#load("gl_multitexture_vertex_shader.glsl"), #load("gl_multitexture_fragment_shader.glsl"))
	} else {
		shd = k2.load_shader_from_file("multitexture_shader.hlsl", "multitexture_shader.hlsl")	
	}
	
	tex1 = k2.load_texture_from_bytes(#load("../minimal/sixten.jpg"))
	tex2 = k2.load_texture_from_bytes(#load("../snake/food.png"))

	shd.texture_bindpoints[shd.texture_lookup["tex2"]] = tex2.handle
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.set_shader(shd)
	k2.clear(k2.BLUE)

	k2.draw_rect({10, 10, 60, 60}, k2.GREEN)
	k2.draw_rect({20, 20, 40, 40}, k2.BLACK)
	k2.draw_circle({120, 40}, 30, k2.BLACK)
	k2.draw_circle({120, 40}, 20, k2.GREEN)
	k2.draw_text("Hellöpe!", {10, 100}, 64, k2.WHITE)
	k2.draw_texture_ex(tex1, {0, 0, f32(tex1.width), f32(tex1.height)}, {10, 200, 900, 500}, {}, 0)

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.destroy_texture(tex1)
	k2.destroy_texture(tex2)
	k2.destroy_shader(shd)
	k2.shutdown()
}