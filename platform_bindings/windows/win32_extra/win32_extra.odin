#+build windows
package windows_extra

import win32 "core:sys/windows"

foreign import user32 "system:User32.lib"
foreign import gdi32 "system:Gdi32.lib"

MONITORINFOF_PRIMARY :: 0x00000001

HORZSIZE :: 4
VERTSIZE :: 6

QDC_ALL_PATHS :: 0x00000001
QDC_ONLY_ACTIVE_PATHS :: 0x00000002
QDC_DATABASE_CURRENT :: 0x00000004
QDC_VIRTUAL_MODE_AWARE :: 0x00000010
QDC_INCLUDE_HMD :: 0x00000020
QDC_VIRTUAL_REFRESH_RATE_AWARE :: 0x00000040

DISPLAYCONFIG_DEVICE_INFO_TYPE :: enum u32 {
	GET_SOURCE_NAME = 1,
	GET_TARGET_NAME = 2,
	GET_TARGET_PREFERRED_MODE = 3,
	GET_ADAPTER_NAME = 4,
	SET_TARGET_PERSISTENCE = 5,
	GET_TARGET_BASE_TYPE = 6,
	GET_SUPPORT_VIRTUAL_RESOLUTION = 7,
	SET_SUPPORT_VIRTUAL_RESOLUTION = 8,
	GET_ADVANCED_COLOR_INFO = 9,
	SET_ADVANCED_COLOR_STATE = 10,
	GET_SDR_WHITE_LEVEL = 11,
}

DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY :: enum u32 {
	OTHER = 0xFFFFFFFF,
	HD15 = 0,
	SVIDEO = 1,
	COMPOSITE_VIDEO = 2,
	COMPONENT_VIDEO = 3,
	DVI = 4,
	HDMI = 5,
	LVDS = 6,
	D_JPN = 8,
	SDI = 9,
	DISPLAYPORT_EXTERNAL = 10,
	DISPLAYPORT_EMBEDDED = 11,
	UDI_EXTERNAL = 12,
	UDI_EMBEDDED = 13,
	SDTVDONGLE = 14,
	MIRACAST = 15,
	INDIRECT_WIRED = 16,
	INDIRECT_VIRTUAL = 17,
	DISPLAYPORT_USB_TUNNEL = 18,
	INTERNAL = 0x80000000,
}

DISPLAYCONFIG_MODE_INFO_TYPE :: enum u32 {
	SOURCE = 1,
	TARGET = 2,
	DESKTOP_IMAGE = 3,
}

DISPLAYCONFIG_TOPOLOGY_ID :: enum u32 {
	INTERNAL = 0x00000001,
	CLONE = 0x00000002,
	EXTEND = 0x00000004,
	EXTERNAL = 0x00000008,
}

DISPLAYCONFIG_RATIONAL :: struct {
	Numerator: u32,
	Denominator: u32,
}

DISPLAYCONFIG_2DREGION :: struct {
	cx: u32,
	cy: u32,
}

DISPLAYCONFIG_PATH_SOURCE_INFO :: struct {
	adapterId: win32.LUID,
	id: u32,
	modeInfoIdx: u32,
	statusFlags: u32,
}

DISPLAYCONFIG_PATH_TARGET_INFO :: struct {
	adapterId: win32.LUID,
	id: u32,
	modeInfoIdx: u32,
	outputTechnology: DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY,
	rotation: u32,
	scaling: u32,
	refreshRate: DISPLAYCONFIG_RATIONAL,
	scanLineOrdering: u32,
	targetAvailable: win32.BOOL,
	statusFlags: u32,
}

DISPLAYCONFIG_PATH_INFO :: struct {
	sourceInfo: DISPLAYCONFIG_PATH_SOURCE_INFO,
	targetInfo: DISPLAYCONFIG_PATH_TARGET_INFO,
	flags: u32,
}

DISPLAYCONFIG_VIDEO_SIGNAL_INFO :: struct {
	pixelRate: u64,
	hSyncFreq: DISPLAYCONFIG_RATIONAL,
	vSyncFreq: DISPLAYCONFIG_RATIONAL,
	activeSize: DISPLAYCONFIG_2DREGION,
	totalSize: DISPLAYCONFIG_2DREGION,
	videoStandard: u32,
	scanLineOrdering: u32,
}

DISPLAYCONFIG_TARGET_MODE :: struct {
	targetVideoSignalInfo: DISPLAYCONFIG_VIDEO_SIGNAL_INFO,
}

DISPLAYCONFIG_SOURCE_MODE :: struct {
	width: u32,
	height: u32,
	pixelFormat: u32,
	position: win32.POINT,
}

DISPLAYCONFIG_DESKTOP_IMAGE_INFO :: struct {
	PathSourceSize: win32.POINT,
	DesktopImageRegion: win32.RECT,
	DesktopImageClip: win32.RECT,
}

DISPLAYCONFIG_MODE_INFO :: struct {
	infoType: DISPLAYCONFIG_MODE_INFO_TYPE,
	id: u32,
	adapterId: win32.LUID,
	using _: struct #raw_union {
		targetMode: DISPLAYCONFIG_TARGET_MODE,
		sourceMode: DISPLAYCONFIG_SOURCE_MODE,
		desktopImageInfo: DISPLAYCONFIG_DESKTOP_IMAGE_INFO,
	},
}

DISPLAYCONFIG_DEVICE_INFO_HEADER :: struct {
	type: DISPLAYCONFIG_DEVICE_INFO_TYPE,
	size: u32,
	adapterId: win32.LUID,
	id: u32,
}

DISPLAYCONFIG_SOURCE_DEVICE_NAME :: struct {
	header: DISPLAYCONFIG_DEVICE_INFO_HEADER,
	viewGdiDeviceName: [win32.CCHDEVICENAME]u16,
}

DISPLAYCONFIG_TARGET_DEVICE_NAME :: struct {
	header: DISPLAYCONFIG_DEVICE_INFO_HEADER,
	flags: u32,
	outputTechnology: DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY,
	edidManufactureId: u16,
	edidProductCodeId: u16,
	connectorInstance: u32,
	monitorFriendlyDeviceName: [64]u16,
	monitorDevicePath: [128]u16,
}

#assert(size_of(DISPLAYCONFIG_PATH_INFO) == 72)
#assert(size_of(DISPLAYCONFIG_MODE_INFO) == 64)
#assert(size_of(DISPLAYCONFIG_SOURCE_DEVICE_NAME) == 84)
#assert(size_of(DISPLAYCONFIG_TARGET_DEVICE_NAME) == 420)

@(default_calling_convention="system")
foreign user32 {
	GetDisplayConfigBufferSizes :: proc(
		flags: u32,
		numPathArrayElements: ^u32,
		numModeInfoArrayElements: ^u32,
	) -> win32.LONG ---

	QueryDisplayConfig :: proc(
		flags: u32,
		numPathArrayElements: ^u32,
		pathArray: [^]DISPLAYCONFIG_PATH_INFO,
		numModeInfoArrayElements: ^u32,
		modeInfoArray: [^]DISPLAYCONFIG_MODE_INFO,
		currentTopologyId: ^DISPLAYCONFIG_TOPOLOGY_ID,
	) -> win32.LONG ---

	DisplayConfigGetDeviceInfo :: proc(
		requestPacket: ^DISPLAYCONFIG_DEVICE_INFO_HEADER,
	) -> win32.LONG ---
}

@(default_calling_convention="system")
foreign gdi32 {
	CreateDCW :: proc(
		pwszDriver: win32.LPCWSTR,
		pwszDevice: win32.LPCWSTR,
		pszPort: win32.LPCWSTR,
		pdm: ^win32.DEVMODEW,
	) -> win32.HDC ---
}
