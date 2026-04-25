// Development game exe. Loads game.dll and reloads it whenever it changes.

package karl2d_hot_reload_main

import "core:dynlib"
import "core:fmt"
import "core:c/libc"
import "core:os"
import "core:log"
import "core:mem"
import "core:time"
import "core:strings"
import "base:runtime"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

copy_dll :: proc(to: string) -> bool {
	exit: i32
	when ODIN_OS == .Windows {
		exit = libc.system(fmt.ctprintf("copy bin\\hot_reload\\game.dll {0}", to))
	} else {
		exit = libc.system(fmt.ctprintf("cp game" + DLL_EXT + " {0}", to))
	}

	if exit != 0 {
		log.errorf("Failed to copy game" + DLL_EXT + " to {0}", to)
		return false
	}

	return true
}

Game_API :: struct {
	lib: dynlib.Library,
	startup: proc(allocator: runtime.Allocator) -> (k2_state: rawptr),
	shutdown: proc(),
	init_state: proc(k2_state: rawptr, allocator: runtime.Allocator),
	destroy_state: proc(),
	update: proc() -> bool,
	memory: proc() -> rawptr,
	memory_size: proc() -> int,
	hot_reloaded: proc(mem: rawptr, k2_state: rawptr),
	force_restart: proc() -> bool,
	modification_time: time.Time,
	api_version: int,
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name("bin/hot_reload/game" + DLL_EXT)
	if mod_time_error != os.ERROR_NONE {
		log.errorf(
			"Failed getting last write time of game" + DLL_EXT + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	// NOTE: this needs to be a relative path for Linux to work.
	game_dll_name := fmt.tprintf("{0}game_{1}" + DLL_EXT, "./" when ODIN_OS != .Windows else "", api_version)
	copy_dll(game_dll_name) or_return

	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "app_", "lib")
	if !ok {
		log.panicf("Failed initializing symbols: {0}. API struct: %v", dynlib.last_error(), api)
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			log.errorf("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf("game_{0}" + DLL_EXT, api.api_version)) != nil {
		log.errorf("Failed to remove game_{0}" + DLL_EXT + " copy", api.api_version)
	}
}


main :: proc() {
	context.logger = log.create_console_logger()

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> ([]mem.Tracking_Allocator_Entry, bool) {
		err := false
		leaks := make([dynamic]mem.Tracking_Allocator_Entry, context.temp_allocator)

		for _, value in a.allocation_map {
			append(&leaks, value)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return leaks[:], err
	}

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		log.error("Failed to load Game API")
		return
	}

	game_api_version += 1
	k2_state := game_api.startup(context.allocator)
	game_api.init_state(k2_state, context.allocator)

	old_game_apis := make([dynamic]Game_API, default_allocator)

	window_open := true
	for window_open {
		if game_api.force_restart() {
			game_api.destroy_state()
			game_api.init_state(k2_state, context.allocator)
		}
		
		window_open = game_api.update()

		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name("bin/hot_reload/game" + DLL_EXT)
		reload := game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version)

			if new_game_api_ok {
				append(&old_game_apis, game_api)
				
				if game_api.memory_size() != new_game_api.memory_size() {
					game_api.destroy_state()
					game_api = new_game_api
					game_api.init_state(k2_state, context.allocator)
				} else {
					game_memory := game_api.memory()
					game_api = new_game_api
					game_api.hot_reloaded(game_memory, k2_state)
				}

				game_api_version += 1
			}
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_api.destroy_state()
	game_api.shutdown()
	
	if leaks, has_leaks := reset_tracking_allocator(&tracking_allocator); has_leaks {
		for l in leaks {
			fmt.eprintfln("%v: Leaked %v bytes", l.location, l.size)
		}

		panic("Memory leaks detected!")
	}

	for &g in old_game_apis {
		unload_game_api(&g)
	}

	delete(old_game_apis)

	unload_game_api(&game_api)
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// make game use good GPU on laptops etc

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
