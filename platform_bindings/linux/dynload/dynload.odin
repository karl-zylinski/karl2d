// Loads shared libraries at runtime. Karl2D compiles in both the X11 and the Wayland backend and
// picks one when it starts, so linking their libraries would force every machine to have both
// installed. Loading them here instead means only the libraries of the backend in use have to be
// present.
package dynload

import "core:dynlib"

// One procedure to resolve. `name` is the symbol in the shared library. `ptr` points at the
// package level procedure variable that receives the address.
Symbol :: struct {
	name: string,
	ptr:  rawptr,
}

Error :: enum {
	None,
	Library_Not_Found,
	Symbol_Not_Found,
}

// Opens `library_name` and fills in every symbol in `symbols`. On failure `what` names the library
// or the symbol that was not found, so the caller can say which one it was.
load :: proc(library_name: string, symbols: []Symbol) -> (err: Error, what: string) {
	lib, lib_ok := dynlib.load_library(library_name)

	if !lib_ok {
		return .Library_Not_Found, library_name
	}

	for s in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, s.name)

		if !addr_ok {
			dynlib.unload_library(lib)
			return .Symbol_Not_Found, s.name
		}

		(^rawptr)(s.ptr)^ = addr
	}

	return .None, ""
}
