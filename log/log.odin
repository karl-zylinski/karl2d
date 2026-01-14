// A logger that can default to "stdout" if no logger is set.
package karl2d_logger

import "core:fmt"
import "core:log"
import "base:runtime"

has_logger :: proc() -> bool {
	return context.logger.procedure != runtime.default_logger_proc
}


debugf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	if has_logger() {
		log.debugf(fmt_str, ..args, location=location)	
	} else {
		fmt.print("Debug: ")
		fmt.printfln(fmt_str, ..args)
	}
}

infof :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	if has_logger() {
		log.infof(fmt_str, ..args, location=location)	
	} else {
		fmt.print("Info: ")
		fmt.printfln(fmt_str, ..args)
	}
}

warnf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	if has_logger() {
		log.warnf(fmt_str, ..args, location=location)	
	} else {
		fmt.eprint("Warning: ")
		fmt.eprintfln(fmt_str, ..args)
	}
}

errorf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	if has_logger() {
		log.errorf(fmt_str, ..args, location=location)	
	} else {
		fmt.eprint("Error: ")
		fmt.eprintfln(fmt_str, ..args)
	}
}

fatalf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	if has_logger() {
		log.fatalf(fmt_str, ..args, location=location)	
	} else {
		fmt.eprint("FATAL ERROR: ")
		fmt.eprintfln(fmt_str, ..args)
	}
}


debug :: proc(args: ..any, location := #caller_location) {
	if has_logger() {
		log.debug(..args, location=location)	
	} else {
		fmt.print("Debug: ")
		fmt.println(..args)
	}
}

info :: proc(args: ..any, location := #caller_location) {
	if has_logger() {
		log.info(..args, location=location)	
	} else {
		fmt.print("Info: ")
		fmt.println(..args)
	}
}

warn :: proc(args: ..any, location := #caller_location) {
	if has_logger() {
		log.warn(..args, location=location)	
	} else {
		fmt.eprint("Warning: ")
		fmt.eprintln(..args)
	}
}

error :: proc(args: ..any, location := #caller_location) {
	if has_logger() {
		log.error(..args, location=location)	
	} else {
		fmt.eprint("Error: ")
		fmt.eprintln(..args)
	}
}

fatal :: proc(args: ..any, location := #caller_location) {
	if has_logger() {
		log.fatal(..args, location=location)	
	} else {
		fmt.eprint("FATAL ERROR: ")
		fmt.eprintln(..args)
	}
}


panic :: proc(args: ..any, location := #caller_location) -> ! {
	if has_logger() {
		log.panic(..args, location=location)	
	} else {
		fmt.eprint("PANIC: ")
		fmt.eprintln(..args)
		runtime.panic("log.panic", location)
	}
}

panicf :: proc(fmt_str: string, args: ..any, location := #caller_location) -> ! {
	if has_logger() {
		log.panicf(fmt_str, ..args, location=location)	
	} else {
		fmt.eprint("PANIC: ")
		fmt.eprintfln(fmt_str, ..args)
		runtime.panic("log.panic", location)
	}
}


@(disabled=ODIN_DISABLE_ASSERT)
assert :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) {
	if has_logger() {
		log.assert(condition, message, loc)
	} else {
		runtime.assert(condition, message, loc)
	}
}

@(disabled=ODIN_DISABLE_ASSERT)
assertf :: proc(condition: bool, fmt_str: string, args: ..any, loc := #caller_location) {
	if has_logger() {
		log.assertf(condition, fmt_str, ..args, loc = loc)
	} else {
		fmt.assertf(condition, fmt_str, ..args, loc = loc)
	}
}


ensure :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) {
	if has_logger() {
		log.ensure(condition, message, loc)
	} else {
		runtime.ensure(condition, message, loc)
	}
}

ensuref :: proc(condition: bool, fmt_str: string, args: ..any, loc := #caller_location) {
	if has_logger() {
		log.ensuref(condition, fmt_str, ..args, loc = loc)
	} else {
		fmt.ensuref(condition, fmt_str, ..args, loc = loc)
	}
}
