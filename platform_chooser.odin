package karl2d

// The platform is picked at compile time, so this is a constant rather than a global assigned
// during `init`. That is what lets the monitor queries in karl2d.odin run before `init`: `pf` is
// already there. Note the backends' own state is still allocated by `init`, so anything reachable
// before that must not touch it -- see `ensure_basic_setup` in each backend.
when ODIN_OS == .Windows {
	@(private="package")
	pf :: PLATFORM_WINDOWS
} else when ODIN_OS == .JS {
	@(private="package")
	pf :: PLATFORM_WEB
} else when ODIN_OS == .Linux {
	@(private="package")
	pf :: PLATFORM_LINUX
} else when ODIN_OS == .Darwin {
	@(private="package")
	pf :: PLATFORM_MAC
} else {
	#panic("Unsupported platform")
}
