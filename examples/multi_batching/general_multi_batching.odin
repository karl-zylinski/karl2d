// A minimal program that opens a window and draws some text in it each frame.
//
// There's a web-compatible version of this example in `../minimal_hello_world_web`.
package general_multi_batching

import k2 "../.."
import lin"core:math/linalg"
import fmt"core:fmt"
	

main :: proc() {
	k2.init(1280, 720, "Greetings from Karl2D!",{window_mode = .Windowed_Resizable})

	batch_1:=k2.create_batch(context.allocator)
	batch_2:=k2.create_batch(context.allocator)
	batch_3:=k2.create_batch(context.allocator)

	// at the start of the program batch 2 is drawn 1 time then updated "uploaded to the gpu" 
	// and then rendered to the screen every frame
	k2.draw_text("Hellope! batch 3", {50, 350}, 100, k2.DARK_BLUE, batch = batch_3)
	k2.update_batch(batch_3)

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)

		// no batch is specified so will use the current batch which is currently the default batch
		k2.draw_text("Hellope! default batch", {50, 50}, 100, k2.DARK_BLUE)

		// sets the current batch to batch 1
		k2.set_current_batch(batch_1)
		// no batch is specified so will use current batch 
		k2.draw_text("Hellope! batch 1", {50, 150}, 100, k2.DARK_BLUE)
		// set_current_batch() was left empty so it will set it to the default batch that is created on init
		k2.set_current_batch()

		// batch 2 is specified
		k2.draw_text("Hellope! batch 2", {50, 250}, 100, k2.DARK_BLUE,batch = batch_2)

		// instead of doing present we do________________________________________________
		
		// this updates renders and clears the current batch which is currently the default batch
		k2.update_render_clear_batch()

		// this updates renders and clears batch_1
		k2.update_render_clear_batch(batch_1)

		// this updates renders and clears batch_2 but one at a time
		//  it is the same as doing k2.update_render_clear_batch(batch_2)
		k2.update_batch(batch_2)
		k2.render_batch(batch_2)
		k2.clear_batch(batch_2)

		// we just render batch 3 it has already been updated and has not changed 
		k2.render_batch(batch_3)

		// ends the frame 
		k2.end_frame()
	}
	// Close the window and clean up the library's internal state.
	k2.shutdown()
}
