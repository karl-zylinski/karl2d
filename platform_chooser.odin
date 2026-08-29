package karl2d

when ODIN_OS == .Windows {
	PLATFORM :: PLATFORM_WINDOWS
} else when ODIN_OS == .JS {
	PLATFORM :: PLATFORM_WEB
} else when ODIN_OS == .Linux {
	PLATFORM :: PLATFORM_LINUX
} else when ODIN_OS == .Darwin {
	PLATFORM :: PLATFORM_MAC
} else {
	#panic("Unsupported platform")
}
