// This file is a just a wrapper that takes care of context setup and provides an entry for the
// javascript Odin runtime to call into. `main` will run on start and then `step` will run for each
// frame.
package karl2d_web_entry

import ex "../.."
import "base:runtime"
import "core:log"

ctx: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger()
	ctx = context
	ex.init()
}

@export
step :: proc(dt: f64) -> bool {
	context = ctx
	return ex.step()
}