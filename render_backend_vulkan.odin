#+build windows
#+vet explicit-allocators
#+private package
package karl2d

import vk "vendor:vulkan"
import win32 "core:sys/windows"
import sc "shader_compiler"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import hm "core:container/handle_map"
import "base:runtime"
import "log"

RENDER_BACKEND_VULKAN :: Render_Backend_Interface {
	state_type = VK_State,
	init = vk_init,
	shutdown = vk_shutdown,
	clear = vk_clear,
	present = vk_present,
	set_vsync = vk_set_vsync,
	draw = vk_draw,
	resize_swapchain = vk_resize_swapchain,
	get_swapchain_width = vk_get_swapchain_width,
	get_swapchain_height = vk_get_swapchain_height,
	create_texture = vk_create_texture,
	load_texture = vk_load_texture,
	update_texture = vk_update_texture,
	generate_mipmap = vk_generate_mipmap,
	destroy_texture = vk_destroy_texture,
	flip_render_textures = false,
	create_render_texture = vk_create_render_texture,
	destroy_render_target = vk_destroy_render_target,
	shader_format = .SPIRV,
	load_shader = vk_load_shader,
	destroy_shader = vk_destroy_shader,
	read_backbuffer = vk_read_backbuffer,
	get_depth_clip_range = vk_get_depth_clip_range,
}

VK_UNIFORM_BUFFER_SIZE :: 16 * 1024 * 1024
VK_MAX_DESCRIPTOR_SETS :: 16384
VK_MAX_SAMPLER_DESCRIPTORS :: 65536
VK_OFFSCREEN_FORMAT :: vk.Format.R8G8B8A8_UNORM
VK_RENDER_TEXTURE_FORMAT :: vk.Format.R32G32B32A32_SFLOAT

VK_Texture :: struct {
	handle: Render_Backend_Texture,
	image: vk.Image,
	memory: vk.DeviceMemory,
	view: vk.ImageView,
	width: int,
	height: int,
	mip_levels: int,
	format: Pixel_Format,
}

VK_Render_Target :: struct {
	handle: Render_Target_Handle,
	texture: Render_Backend_Texture,
	width: int,
	height: int,
}

VK_Shader :: struct {
	handle: Shader_Handle,
	vertex_module: vk.ShaderModule,
	fragment_module: vk.ShaderModule,
	set_layout: vk.DescriptorSetLayout,
	pipeline_layout: vk.PipelineLayout,
	pipelines: [Blend_Mode][2]vk.Pipeline,
	stride: int,
	constants_size: int,
	num_textures: int,
}

VK_State :: struct {
	using _: Render_Backend_State,
	allocator: runtime.Allocator,

	library: dynlib.Library,
	instance: vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	surface: vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	memory_properties: vk.PhysicalDeviceMemoryProperties,
	uniform_alignment: int,
	device: vk.Device,
	queue: vk.Queue,
	queue_family: u32,
	command_pool: vk.CommandPool,
	command_buffer: vk.CommandBuffer,
	fence: vk.Fence,
	acquire_fence: vk.Fence,

	hwnd: win32.HWND,
	swapchain: vk.SwapchainKHR,
	swapchain_images: []vk.Image,
	swapchain_extent: vk.Extent2D,
	width: int,
	height: int,
	vsync: bool,

	offscreen_image: vk.Image,
	offscreen_memory: vk.DeviceMemory,
	offscreen_view: vk.ImageView,

	vertex_buffer: vk.Buffer,
	vertex_memory: vk.DeviceMemory,
	vertex_mapped: [^]u8,

	uniform_buffer: vk.Buffer,
	uniform_memory: vk.DeviceMemory,
	uniform_mapped: [^]u8,

	descriptor_pool: vk.DescriptorPool,

	textures: hm.Dynamic_Handle_Map(VK_Texture, Render_Backend_Texture),
	render_targets: hm.Dynamic_Handle_Map(VK_Render_Target, Render_Target_Handle),
	shaders: hm.Dynamic_Handle_Map(VK_Shader, Shader_Handle),
	samplers: map[Texture_Sampler]vk.Sampler,
	white_texture: Render_Backend_Texture,
}

vk_debug_callback :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	types: vk.DebugUtilsMessageTypeFlagsEXT,
	data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.eprintfln("[vulkan %v] %s", severity, data.pMessage)
	return false
}

vk_check :: proc(r: vk.Result, loc := #caller_location) -> bool {
	if r == .SUCCESS {
		return true
	}

	log.errorf("Vulkan error: %v", r, location = loc)
	return false
}

vk_init :: proc(
	s: ^VK_State,
	glue: ^Window_Render_Glue,
	swapchain_width: int,
	swapchain_height: int,
	options: Init_Options,
	allocator := context.allocator,
) {
	s.allocator = allocator
	hm.dynamic_init(&s.shaders, allocator)
	hm.dynamic_init(&s.textures, allocator)
	hm.dynamic_init(&s.render_targets, allocator)
	s.samplers = make(map[Texture_Sampler]vk.Sampler, allocator)
	s.hwnd = win32.HWND(glue)
	s.width = swapchain_width
	s.height = swapchain_height
	s.vsync = !options.disable_vsync

	if options.anti_alias {
		log.warn("Vulkan backend: anti_alias is not supported, ignoring it.")
	}

	if options.depth_test {
		log.warn("Vulkan backend: depth_test is not supported, ignoring it.")
	}

	lib, lib_ok := dynlib.load_library("vulkan-1.dll", allocator = allocator)

	if !lib_ok {
		log.panic("Vulkan backend: cannot load vulkan-1.dll")
	}

	s.library = lib
	get_instance_proc_addr, gipa_ok := dynlib.symbol_address(lib, "vkGetInstanceProcAddr", allocator = allocator)

	if !gipa_ok {
		log.panic("Vulkan backend: cannot find vkGetInstanceProcAddr")
	}

	vk.load_proc_addresses_global(get_instance_proc_addr)

	use_validation := false

	when ODIN_DEBUG {
		layer_count: u32
		vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		layers := make([]vk.LayerProperties, layer_count, frame_allocator)
		vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers))

		for &l in layers {
			if string(cstring(raw_data(l.layerName[:]))) == "VK_LAYER_KHRONOS_validation" {
				use_validation = true
			}
		}

		if !use_validation {
			log.info("Vulkan backend: VK_LAYER_KHRONOS_validation not available")
		}
	}

	layer_names := []cstring{ "VK_LAYER_KHRONOS_validation" }
	extension_names := make([dynamic]cstring, frame_allocator)
	append(&extension_names, vk.KHR_SURFACE_EXTENSION_NAME, vk.KHR_WIN32_SURFACE_EXTENSION_NAME)

	if use_validation {
		append(&extension_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	app_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = "karl2d",
		pEngineName = "karl2d",
		apiVersion = vk.API_VERSION_1_3,
	}

	instance_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
		enabledExtensionCount = u32(len(extension_names)),
		ppEnabledExtensionNames = raw_data(extension_names),
	}

	if use_validation {
		instance_info.enabledLayerCount = 1
		instance_info.ppEnabledLayerNames = raw_data(layer_names)
	}

	if !vk_check(vk.CreateInstance(&instance_info, nil, &s.instance)) {
		log.panic("Vulkan backend: vkCreateInstance failed")
	}

	vk.load_proc_addresses_instance(s.instance)

	if use_validation {
		messenger_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.WARNING, .ERROR},
			messageType = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = vk_debug_callback,
		}

		vk_check(vk.CreateDebugUtilsMessengerEXT(s.instance, &messenger_info, nil, &s.debug_messenger))
	}

	surface_info := vk.Win32SurfaceCreateInfoKHR {
		sType = .WIN32_SURFACE_CREATE_INFO_KHR,
		hinstance = win32.HINSTANCE(win32.GetModuleHandleW(nil)),
		hwnd = s.hwnd,
	}

	if !vk_check(vk.CreateWin32SurfaceKHR(s.instance, &surface_info, nil, &s.surface)) {
		log.panic("Vulkan backend: vkCreateWin32SurfaceKHR failed")
	}

	device_count: u32
	vk.EnumeratePhysicalDevices(s.instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count, frame_allocator)
	vk.EnumeratePhysicalDevices(s.instance, &device_count, raw_data(devices))
	found := false
	best_is_discrete := false

	for pd in devices {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(pd, &props)

		if props.apiVersion < vk.API_VERSION_1_3 {
			continue
		}

		family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &family_count, nil)
		families := make([]vk.QueueFamilyProperties, family_count, frame_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &family_count, raw_data(families))

		for f, f_idx in families {
			if .GRAPHICS not_in f.queueFlags {
				continue
			}

			present_support: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(pd, u32(f_idx), s.surface, &present_support)

			if !present_support {
				continue
			}

			is_discrete := props.deviceType == .DISCRETE_GPU

			if found && (best_is_discrete || !is_discrete) {
				break
			}

			s.physical_device = pd
			s.queue_family = u32(f_idx)
			s.uniform_alignment = int(props.limits.minUniformBufferOffsetAlignment)
			best_is_discrete = is_discrete
			found = true
			log.infof("Vulkan backend: using %s", cstring(raw_data(props.deviceName[:])))
			break
		}
	}

	if !found {
		log.panic("Vulkan backend: no Vulkan 1.3 device with graphics and present support")
	}

	vk.GetPhysicalDeviceMemoryProperties(s.physical_device, &s.memory_properties)

	queue_priority: f32 = 1
	queue_info := vk.DeviceQueueCreateInfo {
		sType = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = s.queue_family,
		queueCount = 1,
		pQueuePriorities = &queue_priority,
	}

	features13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
	}

	device_extensions := []cstring{ vk.KHR_SWAPCHAIN_EXTENSION_NAME }

	device_info := vk.DeviceCreateInfo {
		sType = .DEVICE_CREATE_INFO,
		pNext = &features13,
		queueCreateInfoCount = 1,
		pQueueCreateInfos = &queue_info,
		enabledExtensionCount = u32(len(device_extensions)),
		ppEnabledExtensionNames = raw_data(device_extensions),
	}

	if !vk_check(vk.CreateDevice(s.physical_device, &device_info, nil, &s.device)) {
		log.panic("Vulkan backend: vkCreateDevice failed")
	}

	vk.load_proc_addresses_device(s.device)
	vk.GetDeviceQueue(s.device, s.queue_family, 0, &s.queue)

	pool_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = s.queue_family,
	}

	vk_check(vk.CreateCommandPool(s.device, &pool_info, nil, &s.command_pool))

	cmd_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = s.command_pool,
		level = .PRIMARY,
		commandBufferCount = 1,
	}

	vk_check(vk.AllocateCommandBuffers(s.device, &cmd_info, &s.command_buffer))

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}

	vk_check(vk.CreateFence(s.device, &fence_info, nil, &s.fence))
	vk_check(vk.CreateFence(s.device, &fence_info, nil, &s.acquire_fence))

	vb_ok: bool
	vb_mapped: rawptr
	s.vertex_buffer, s.vertex_memory, vb_mapped, vb_ok = vk_create_host_buffer(s, VERTEX_BUFFER_MAX, {.VERTEX_BUFFER})

	if !vb_ok {
		log.panic("Vulkan backend: cannot create vertex buffer")
	}

	s.vertex_mapped = ([^]u8)(vb_mapped)

	ub_ok: bool
	ub_mapped: rawptr
	s.uniform_buffer, s.uniform_memory, ub_mapped, ub_ok = vk_create_host_buffer(s, VK_UNIFORM_BUFFER_SIZE, {.UNIFORM_BUFFER})

	if !ub_ok {
		log.panic("Vulkan backend: cannot create uniform buffer")
	}

	s.uniform_mapped = ([^]u8)(ub_mapped)

	pool_sizes := [2]vk.DescriptorPoolSize {
		{ type = .UNIFORM_BUFFER, descriptorCount = VK_MAX_DESCRIPTOR_SETS },
		{ type = .COMBINED_IMAGE_SAMPLER, descriptorCount = VK_MAX_SAMPLER_DESCRIPTORS },
	}

	descriptor_pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets = VK_MAX_DESCRIPTOR_SETS,
		poolSizeCount = len(pool_sizes),
		pPoolSizes = &pool_sizes[0],
	}

	vk_check(vk.CreateDescriptorPool(s.device, &descriptor_pool_info, nil, &s.descriptor_pool))

	vk_create_swapchain(s)

	white := [4]u8{ 255, 255, 255, 255 }
	white_levels := [1][]u8{ white[:] }
	s.white_texture, _ = vk_create_texture_internal(s, 1, 1, .RGBA_8_Norm, white_levels[:], false)
}

vk_shutdown :: proc(s: ^VK_State) {
	vk.DeviceWaitIdle(s.device)

	tex_it := hm.iterator_make(&s.textures)

	for tex, _ in hm.iterate(&tex_it) {
		vk_release_texture(s, tex^)
	}

	shd_it := hm.iterator_make(&s.shaders)

	for shd, _ in hm.iterate(&shd_it) {
		vk_release_shader(s, shd^)
	}

	for _, smp in s.samplers {
		if smp != 0 {
			vk.DestroySampler(s.device, smp, nil)
		}
	}

	delete(s.samplers)
	vk_destroy_swapchain(s)
	vk.DestroyDescriptorPool(s.device, s.descriptor_pool, nil)
	vk.DestroyBuffer(s.device, s.vertex_buffer, nil)
	vk.FreeMemory(s.device, s.vertex_memory, nil)
	vk.DestroyBuffer(s.device, s.uniform_buffer, nil)
	vk.FreeMemory(s.device, s.uniform_memory, nil)
	vk.DestroyFence(s.device, s.fence, nil)
	vk.DestroyFence(s.device, s.acquire_fence, nil)
	vk.DestroyCommandPool(s.device, s.command_pool, nil)
	vk.DestroyDevice(s.device, nil)
	vk.DestroySurfaceKHR(s.instance, s.surface, nil)

	if s.debug_messenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(s.instance, s.debug_messenger, nil)
	}

	vk.DestroyInstance(s.instance, nil)
	dynlib.unload_library(s.library)
	hm.dynamic_destroy(&s.shaders)
	hm.dynamic_destroy(&s.textures)
	hm.dynamic_destroy(&s.render_targets)
}

vk_find_memory_type :: proc(s: ^VK_State, type_bits: u32, props: vk.MemoryPropertyFlags) -> (u32, bool) {
	for i in 0..<s.memory_properties.memoryTypeCount {
		if type_bits & (1 << i) == 0 {
			continue
		}

		if s.memory_properties.memoryTypes[i].propertyFlags & props != props {
			continue
		}

		return i, true
	}

	return 0, false
}

vk_create_host_buffer :: proc(
	s: ^VK_State,
	size: int,
	usage: vk.BufferUsageFlags,
) -> (
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	mapped: rawptr,
	ok: bool,
) {
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = vk.DeviceSize(size),
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	if !vk_check(vk.CreateBuffer(s.device, &buffer_info, nil, &buffer)) {
		return
	}

	reqs: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(s.device, buffer, &reqs)
	type_index, type_ok := vk_find_memory_type(s, reqs.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT})

	if !type_ok {
		log.error("Vulkan backend: no host visible memory type")
		vk.DestroyBuffer(s.device, buffer, nil)
		return
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = reqs.size,
		memoryTypeIndex = type_index,
	}

	if !vk_check(vk.AllocateMemory(s.device, &alloc_info, nil, &memory)) {
		vk.DestroyBuffer(s.device, buffer, nil)
		return
	}

	vk.BindBufferMemory(s.device, buffer, memory, 0)

	if !vk_check(vk.MapMemory(s.device, memory, 0, vk.DeviceSize(size), {}, &mapped)) {
		vk.DestroyBuffer(s.device, buffer, nil)
		vk.FreeMemory(s.device, memory, nil)
		return
	}

	ok = true
	return
}

vk_destroy_host_buffer :: proc(s: ^VK_State, buffer: vk.Buffer, memory: vk.DeviceMemory) {
	vk.DestroyBuffer(s.device, buffer, nil)
	vk.FreeMemory(s.device, memory, nil)
}

vk_begin :: proc(s: ^VK_State) -> vk.CommandBuffer {
	cmd := s.command_buffer
	vk.ResetCommandBuffer(cmd, {})

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(cmd, &begin_info)
	vk_global_barrier(cmd)
	return cmd
}

vk_global_barrier :: proc(cmd: vk.CommandBuffer) {
	barrier := vk.MemoryBarrier {
		sType = .MEMORY_BARRIER,
		srcAccessMask = {.MEMORY_WRITE},
		dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
	}

	vk.CmdPipelineBarrier(cmd, {.ALL_COMMANDS}, {.ALL_COMMANDS}, {}, 1, &barrier, 0, nil, 0, nil)
}

vk_submit :: proc(s: ^VK_State) {
	cmd := s.command_buffer
	vk_global_barrier(cmd)
	vk.EndCommandBuffer(cmd)

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &cmd,
	}

	vk_check(vk.QueueSubmit(s.queue, 1, &submit_info, s.fence))
	vk_check(vk.WaitForFences(s.device, 1, &s.fence, true, max(u64)))
	vk.ResetFences(s.device, 1, &s.fence)
}

vk_image_barrier :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.MEMORY_WRITE},
		dstAccessMask = {.MEMORY_READ, .MEMORY_WRITE},
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			levelCount = vk.REMAINING_MIP_LEVELS,
			layerCount = vk.REMAINING_ARRAY_LAYERS,
		},
	}

	vk.CmdPipelineBarrier(cmd, {.ALL_COMMANDS}, {.ALL_COMMANDS}, {}, 0, nil, 0, nil, 1, &barrier)
}

vk_create_image :: proc(
	s: ^VK_State,
	width: int,
	height: int,
	format: vk.Format,
	mip_levels: int,
	usage: vk.ImageUsageFlags,
) -> (
	image: vk.Image,
	memory: vk.DeviceMemory,
	view: vk.ImageView,
	ok: bool,
) {
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = { u32(width), u32(height), 1 },
		mipLevels = u32(mip_levels),
		arrayLayers = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}

	if !vk_check(vk.CreateImage(s.device, &image_info, nil, &image)) {
		return
	}

	reqs: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(s.device, image, &reqs)
	type_index, type_ok := vk_find_memory_type(s, reqs.memoryTypeBits, {.DEVICE_LOCAL})

	if !type_ok {
		log.error("Vulkan backend: no device local memory type")
		vk.DestroyImage(s.device, image, nil)
		return
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = reqs.size,
		memoryTypeIndex = type_index,
	}

	if !vk_check(vk.AllocateMemory(s.device, &alloc_info, nil, &memory)) {
		vk.DestroyImage(s.device, image, nil)
		return
	}

	vk.BindImageMemory(s.device, image, memory, 0)

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = {
			aspectMask = {.COLOR},
			levelCount = u32(mip_levels),
			layerCount = 1,
		},
	}

	if !vk_check(vk.CreateImageView(s.device, &view_info, nil, &view)) {
		vk.DestroyImage(s.device, image, nil)
		vk.FreeMemory(s.device, memory, nil)
		return
	}

	cmd := vk_begin(s)
	vk_image_barrier(cmd, image, .UNDEFINED, .GENERAL)
	clear_color: vk.ClearColorValue

	clear_range := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = vk.REMAINING_MIP_LEVELS,
		layerCount = 1,
	}

	vk.CmdClearColorImage(cmd, image, .GENERAL, &clear_color, 1, &clear_range)
	vk_submit(s)
	ok = true
	return
}

vk_create_swapchain :: proc(s: ^VK_State) {
	caps: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(s.physical_device, s.surface, &caps)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(s.physical_device, s.surface, &format_count, nil)
	formats := make([]vk.SurfaceFormatKHR, format_count, frame_allocator)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(s.physical_device, s.surface, &format_count, raw_data(formats))
	surface_format := formats[0]

	for f in formats {
		if f.format == .B8G8R8A8_UNORM {
			surface_format = f
		}
	}

	mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(s.physical_device, s.surface, &mode_count, nil)
	modes := make([]vk.PresentModeKHR, mode_count, frame_allocator)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(s.physical_device, s.surface, &mode_count, raw_data(modes))
	present_mode := vk.PresentModeKHR.FIFO

	if !s.vsync {
		for m in modes {
			if m == .IMMEDIATE {
				present_mode = .IMMEDIATE
			}
		}
	}

	extent := caps.currentExtent

	if extent.width == max(u32) {
		extent.width = clamp(u32(max(s.width, 1)), caps.minImageExtent.width, caps.maxImageExtent.width)
		extent.height = clamp(u32(max(s.height, 1)), caps.minImageExtent.height, caps.maxImageExtent.height)
	}

	s.swapchain_extent = extent
	image_count := caps.minImageCount + 1

	if caps.maxImageCount > 0 {
		image_count = min(image_count, caps.maxImageCount)
	}

	composite_alpha := vk.CompositeAlphaFlagsKHR{.OPAQUE}

	if .OPAQUE not_in caps.supportedCompositeAlpha {
		for flag in vk.CompositeAlphaFlagKHR {
			if flag in caps.supportedCompositeAlpha {
				composite_alpha = {flag}
				break
			}
		}
	}

	if extent.width > 0 && extent.height > 0 {
		swapchain_info := vk.SwapchainCreateInfoKHR {
			sType = .SWAPCHAIN_CREATE_INFO_KHR,
			surface = s.surface,
			minImageCount = image_count,
			imageFormat = surface_format.format,
			imageColorSpace = surface_format.colorSpace,
			imageExtent = extent,
			imageArrayLayers = 1,
			imageUsage = {.TRANSFER_DST, .COLOR_ATTACHMENT},
			imageSharingMode = .EXCLUSIVE,
			preTransform = caps.currentTransform,
			compositeAlpha = composite_alpha,
			presentMode = present_mode,
			clipped = true,
		}

		if vk_check(vk.CreateSwapchainKHR(s.device, &swapchain_info, nil, &s.swapchain)) {
			count: u32
			vk.GetSwapchainImagesKHR(s.device, s.swapchain, &count, nil)
			s.swapchain_images = make([]vk.Image, count, s.allocator)
			vk.GetSwapchainImagesKHR(s.device, s.swapchain, &count, raw_data(s.swapchain_images))
		}
	}

	ok: bool
	s.offscreen_image, s.offscreen_memory, s.offscreen_view, ok = vk_create_image(
		s,
		max(s.width, 1),
		max(s.height, 1),
		VK_OFFSCREEN_FORMAT,
		1,
		{.COLOR_ATTACHMENT, .TRANSFER_SRC, .TRANSFER_DST},
	)

	if !ok {
		log.panic("Vulkan backend: cannot create offscreen image")
	}
}

vk_destroy_swapchain :: proc(s: ^VK_State) {
	vk.DeviceWaitIdle(s.device)

	if s.swapchain != 0 {
		vk.DestroySwapchainKHR(s.device, s.swapchain, nil)
		s.swapchain = 0
	}

	delete(s.swapchain_images, s.allocator)
	s.swapchain_images = {}
	vk.DestroyImageView(s.device, s.offscreen_view, nil)
	vk.DestroyImage(s.device, s.offscreen_image, nil)
	vk.FreeMemory(s.device, s.offscreen_memory, nil)
}

vk_clear :: proc(s: ^VK_State, render_target: Render_Target_Handle, color: Color) {
	image := s.offscreen_image

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		tex := hm.get(&s.textures, rt.texture)

		if tex == nil {
			log.errorf("Vulkan backend: render target %v has no texture", render_target)
			return
		}

		image = tex.image
	}

	clear_color := vk.ClearColorValue {
		float32 = f32_color_from_color(color),
	}

	clear_range := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = 1,
		layerCount = 1,
	}

	cmd := vk_begin(s)
	vk.CmdClearColorImage(cmd, image, .GENERAL, &clear_color, 1, &clear_range)
	vk_submit(s)
}

vk_present :: proc(s: ^VK_State) {
	if s.swapchain == 0 {
		return
	}

	image_index: u32
	acquire_res := vk.AcquireNextImageKHR(s.device, s.swapchain, max(u64), 0, s.acquire_fence, &image_index)

	if acquire_res == .ERROR_OUT_OF_DATE_KHR {
		vk_destroy_swapchain(s)
		vk_create_swapchain(s)
		return
	}

	if acquire_res != .SUCCESS && acquire_res != .SUBOPTIMAL_KHR {
		vk_check(acquire_res)
		return
	}

	vk.WaitForFences(s.device, 1, &s.acquire_fence, true, max(u64))
	vk.ResetFences(s.device, 1, &s.acquire_fence)

	dst := s.swapchain_images[image_index]
	cmd := vk_begin(s)
	vk_image_barrier(cmd, dst, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	blit := vk.ImageBlit {
		srcSubresource = { aspectMask = {.COLOR}, layerCount = 1 },
		srcOffsets = { {0, 0, 0}, {i32(max(s.width, 1)), i32(max(s.height, 1)), 1} },
		dstSubresource = { aspectMask = {.COLOR}, layerCount = 1 },
		dstOffsets = { {0, 0, 0}, {i32(s.swapchain_extent.width), i32(s.swapchain_extent.height), 1} },
	}

	vk.CmdBlitImage(cmd, s.offscreen_image, .GENERAL, dst, .TRANSFER_DST_OPTIMAL, 1, &blit, .NEAREST)
	vk_image_barrier(cmd, dst, .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR)
	vk_submit(s)

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		swapchainCount = 1,
		pSwapchains = &s.swapchain,
		pImageIndices = &image_index,
	}

	present_res := vk.QueuePresentKHR(s.queue, &present_info)
	recreate := acquire_res == .SUBOPTIMAL_KHR

	if present_res == .ERROR_OUT_OF_DATE_KHR {
		recreate = true
	} else if present_res == .SUBOPTIMAL_KHR {
		recreate = true
	} else {
		vk_check(present_res)
	}

	if recreate {
		vk_destroy_swapchain(s)
		vk_create_swapchain(s)
	}
}

vk_set_vsync :: proc(s: ^VK_State, enabled: bool) {
	if s.vsync == enabled {
		return
	}

	s.vsync = enabled
	vk_destroy_swapchain(s)
	vk_create_swapchain(s)
}

vk_resize_swapchain :: proc(s: ^VK_State, w, h: int) {
	vk_destroy_swapchain(s)
	s.width = w
	s.height = h
	vk_create_swapchain(s)
}

vk_get_swapchain_width :: proc(s: ^VK_State) -> int {
	return s.width
}

vk_get_swapchain_height :: proc(s: ^VK_State) -> int {
	return s.height
}

vk_begin_rendering :: proc(cmd: vk.CommandBuffer, view: vk.ImageView, width: int, height: int) {
	attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = view,
		imageLayout = .GENERAL,
		loadOp = .LOAD,
		storeOp = .STORE,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = { extent = { u32(width), u32(height) } },
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &attachment,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)
}

vk_draw :: proc(s: ^VK_State, vertex_buffer: []u8, draw_calls: []Draw_Call) {
	if len(vertex_buffer) == 0 {
		return
	}

	if len(draw_calls) == 0 {
		return
	}

	if len(vertex_buffer) > VERTEX_BUFFER_MAX {
		log.error("Vulkan backend: vertex buffer too large")
		return
	}

	copy(s.vertex_mapped[:VERTEX_BUFFER_MAX], vertex_buffer)
	vk.ResetDescriptorPool(s.device, s.descriptor_pool, {})
	cmd := vk_begin(s)
	rendering := false
	current_rt: Render_Target_Handle
	uniform_offset := 0

	for &call in draw_calls {
		shd := hm.get(&s.shaders, call.shader)

		if shd == nil {
			log.errorf("Trying to draw with invalid shader %v", call.shader)
			continue
		}

		if call.vertex_size != shd.stride {
			log.errorf("Vulkan backend: draw call vertex size %v does not match shader stride %v", call.vertex_size, shd.stride)
			continue
		}

		target_view := s.offscreen_view
		target_width := s.width
		target_height := s.height
		format_index := 0

		if rt := hm.get(&s.render_targets, call.render_target); rt != nil {
			tex := hm.get(&s.textures, rt.texture)

			if tex == nil {
				log.errorf("Vulkan backend: render target %v has no texture", call.render_target)
				continue
			}

			target_view = tex.view
			target_width = rt.width
			target_height = rt.height
			format_index = 1
		}

		if rendering && call.render_target != current_rt {
			vk.CmdEndRendering(cmd)
			vk_global_barrier(cmd)
			rendering = false
		}

		if !rendering {
			vk_begin_rendering(cmd, target_view, target_width, target_height)
			rendering = true
			current_rt = call.render_target
		}

		vk.CmdBindPipeline(cmd, .GRAPHICS, shd.pipelines[call.blend_mode][format_index])

		viewport := vk.Viewport {
			x = 0,
			y = f32(target_height),
			width = f32(target_width),
			height = -f32(target_height),
			minDepth = 0,
			maxDepth = 1,
		}

		vk.CmdSetViewport(cmd, 0, 1, &viewport)

		scissor := vk.Rect2D {
			extent = { u32(target_width), u32(target_height) },
		}

		if sciss, sciss_ok := call.scissor.?; sciss_ok {
			x0 := clamp(int(sciss.x), 0, target_width)
			y0 := clamp(int(sciss.y), 0, target_height)
			x1 := clamp(int(sciss.x + sciss.w), x0, target_width)
			y1 := clamp(int(sciss.y + sciss.h), y0, target_height)
			scissor = {
				offset = { i32(x0), i32(y0) },
				extent = { u32(x1 - x0), u32(y1 - y0) },
			}
		}

		vk.CmdSetScissor(cmd, 0, 1, &scissor)

		if shd.constants_size > 0 || shd.num_textures > 0 {
			set_alloc_info := vk.DescriptorSetAllocateInfo {
				sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool = s.descriptor_pool,
				descriptorSetCount = 1,
				pSetLayouts = &shd.set_layout,
			}

			set: vk.DescriptorSet

			if !vk_check(vk.AllocateDescriptorSets(s.device, &set_alloc_info, &set)) {
				log.error("Vulkan backend: out of descriptor sets, skipping draw call")
				continue
			}

			writes := make([]vk.WriteDescriptorSet, 1 + shd.num_textures, frame_allocator)
			image_infos := make([]vk.DescriptorImageInfo, shd.num_textures, frame_allocator)
			num_writes := 0
			buffer_info: vk.DescriptorBufferInfo

			if shd.constants_size > 0 {
				offset := mem.align_forward_int(uniform_offset, s.uniform_alignment)

				if offset + shd.constants_size > VK_UNIFORM_BUFFER_SIZE {
					log.error("Vulkan backend: out of uniform buffer space, skipping draw call")
					continue
				}

				dst := s.uniform_mapped[offset:offset + shd.constants_size]
				mem.zero_slice(dst)
				copy(dst, call.constants_data)
				uniform_offset = offset + shd.constants_size

				buffer_info = {
					buffer = s.uniform_buffer,
					offset = vk.DeviceSize(offset),
					range = vk.DeviceSize(shd.constants_size),
				}

				writes[num_writes] = {
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = set,
					dstBinding = 0,
					descriptorCount = 1,
					descriptorType = .UNIFORM_BUFFER,
					pBufferInfo = &buffer_info,
				}

				num_writes += 1
			}

			for t_idx in 0..<shd.num_textures {
				tex := hm.get(&s.textures, s.white_texture)
				sampler := Texture_Sampler{}

				if t_idx < len(call.textures) {
					if call_tex := hm.get(&s.textures, call.textures[t_idx].handle); call_tex != nil {
						tex = call_tex
					}

					sampler = call.textures[t_idx].sampler
				}

				image_infos[t_idx] = {
					sampler = vk_get_sampler(s, sampler),
					imageView = tex.view,
					imageLayout = .GENERAL,
				}

				writes[num_writes] = {
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = set,
					dstBinding = u32(1 + t_idx),
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &image_infos[t_idx],
				}

				num_writes += 1
			}

			vk.UpdateDescriptorSets(s.device, u32(num_writes), raw_data(writes), 0, nil)
			vk.CmdBindDescriptorSets(cmd, .GRAPHICS, shd.pipeline_layout, 0, 1, &set, 0, nil)
		}

		vb_offset: vk.DeviceSize
		vk.CmdBindVertexBuffers(cmd, 0, 1, &s.vertex_buffer, &vb_offset)
		vk.CmdDraw(cmd, u32(call.vertex_count), 1, u32(call.vertex_offset / call.vertex_size), 0)
	}

	if rendering {
		vk.CmdEndRendering(cmd)
	}

	vk_submit(s)
}

vk_format_from_pixel_format :: proc(f: Pixel_Format) -> vk.Format {
	switch f {
	case .Unknown: return .UNDEFINED
	case .RGBA_32_Float: return .R32G32B32A32_SFLOAT
	case .RGB_32_Float: return .R32G32B32_SFLOAT
	case .RG_32_Float: return .R32G32_SFLOAT
	case .R_32_Float: return .R32_SFLOAT
	case .RGBA_8_Norm: return .R8G8B8A8_UNORM
	case .RG_8_Norm: return .R8G8_UNORM
	case .R_8_Norm: return .R8_UNORM
	case .R_8_UInt: return .R8_UINT
	}

	return .UNDEFINED
}

vk_upload_texture_region :: proc(
	s: ^VK_State,
	tex: ^VK_Texture,
	data: []u8,
	x: int,
	y: int,
	w: int,
	h: int,
	row_length: int,
	mip_level: int,
) -> bool {
	if len(data) == 0 {
		return true
	}

	buffer, memory, mapped, ok := vk_create_host_buffer(s, len(data), {.TRANSFER_SRC})

	if !ok {
		return false
	}

	mem.copy(mapped, raw_data(data), len(data))

	region := vk.BufferImageCopy {
		bufferRowLength = u32(row_length),
		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = u32(mip_level),
			layerCount = 1,
		},
		imageOffset = { i32(x), i32(y), 0 },
		imageExtent = { u32(w), u32(h), 1 },
	}

	cmd := vk_begin(s)
	vk.CmdCopyBufferToImage(cmd, buffer, tex.image, .GENERAL, 1, &region)
	vk_submit(s)
	vk_destroy_host_buffer(s, buffer, memory)
	return true
}

vk_create_texture_internal :: proc(
	s: ^VK_State,
	width: int,
	height: int,
	format: Pixel_Format,
	data: [][]u8,
	render_target: bool,
) -> (Render_Backend_Texture, bool) {
	mip_levels := len(data)

	if mip_levels < 1 {
		log.error("Trying to create a texture with zero mip levels")
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	vk_format := vk_format_from_pixel_format(format)
	format_props: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(s.physical_device, vk_format, &format_props)

	if .SAMPLED_IMAGE not_in format_props.optimalTilingFeatures {
		log.errorf("Vulkan backend: pixel format %v is not supported for textures", format)
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	usage := vk.ImageUsageFlags{.SAMPLED, .TRANSFER_DST, .TRANSFER_SRC}

	if render_target {
		usage += {.COLOR_ATTACHMENT}
	}

	image, memory, view, ok := vk_create_image(s, width, height, vk_format, mip_levels, usage)

	if !ok {
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	tex := VK_Texture {
		image = image,
		memory = memory,
		view = view,
		width = width,
		height = height,
		mip_levels = mip_levels,
		format = format,
	}

	level_width := width
	level_height := height

	for level_data, level in data {
		vk_upload_texture_region(s, &tex, level_data, 0, 0, level_width, level_height, 0, level)
		level_width = max(level_width / 2, 1)
		level_height = max(level_height / 2, 1)
	}

	handle, add_err := hm.add(&s.textures, tex)

	if add_err != nil {
		log.errorf("Failed to add texture. Error: %v", add_err)
		vk_release_texture(s, tex)
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	return handle, true
}

vk_create_texture :: proc(
	s: ^VK_State,
	width: int,
	height: int,
	format: Pixel_Format,
	mip_levels: int,
) -> (Render_Backend_Texture, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	return vk_create_texture_internal(s, width, height, format, empty_data[:mip_levels], false)
}

vk_load_texture :: proc(
	s: ^VK_State,
	data: [][]u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Render_Backend_Texture, bool) {
	return vk_create_texture_internal(s, width, height, format, data, false)
}

vk_update_texture :: proc(
	s: ^VK_State,
	th: Render_Backend_Texture,
	data: []u8,
	rect: Rect,
	pitch: int,
	mip_level: int,
) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		log.errorf("Trying to update texture %v with new data, but it is invalid.", th)
		return false
	}

	row_length := 0

	if pitch != 0 {
		row_length = pitch / pixel_format_size(tex.format)
	}

	return vk_upload_texture_region(s, tex, data, int(rect.x), int(rect.y), int(rect.w), int(rect.h), row_length, mip_level)
}

vk_generate_mipmap :: proc(s: ^VK_State, th: Render_Backend_Texture) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		log.errorf("Trying to generate mipmap for texture %v, but it is invalid.", th)
		return false
	}

	format_props: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(s.physical_device, vk_format_from_pixel_format(tex.format), &format_props)
	required := vk.FormatFeatureFlags{.BLIT_SRC, .BLIT_DST, .SAMPLED_IMAGE_FILTER_LINEAR}

	if format_props.optimalTilingFeatures & required != required {
		log.errorf("Pixel format %v does not support generating mipmaps", tex.format)
		return false
	}

	cmd := vk_begin(s)
	src_width := tex.width
	src_height := tex.height

	for level in 1..<tex.mip_levels {
		dst_width := max(src_width / 2, 1)
		dst_height := max(src_height / 2, 1)

		blit := vk.ImageBlit {
			srcSubresource = { aspectMask = {.COLOR}, mipLevel = u32(level - 1), layerCount = 1 },
			srcOffsets = { {0, 0, 0}, {i32(src_width), i32(src_height), 1} },
			dstSubresource = { aspectMask = {.COLOR}, mipLevel = u32(level), layerCount = 1 },
			dstOffsets = { {0, 0, 0}, {i32(dst_width), i32(dst_height), 1} },
		}

		vk.CmdBlitImage(cmd, tex.image, .GENERAL, tex.image, .GENERAL, 1, &blit, .LINEAR)
		vk_global_barrier(cmd)
		src_width = dst_width
		src_height = dst_height
	}

	vk_submit(s)
	return true
}

vk_release_texture :: proc(s: ^VK_State, tex: VK_Texture) {
	vk.DestroyImageView(s.device, tex.view, nil)
	vk.DestroyImage(s.device, tex.image, nil)
	vk.FreeMemory(s.device, tex.memory, nil)
}

vk_destroy_texture :: proc(s: ^VK_State, th: Render_Backend_Texture) {
	if tex := hm.get(&s.textures, th); tex != nil {
		vk.DeviceWaitIdle(s.device)
		vk_release_texture(s, tex^)
	}

	hm.remove(&s.textures, th)
}

vk_create_render_texture :: proc(
	s: ^VK_State,
	width: int,
	height: int,
	mip_levels: int,
) -> (Render_Backend_Texture, Render_Target_Handle, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	tex, tex_ok := vk_create_texture_internal(s, width, height, .RGBA_32_Float, empty_data[:max(mip_levels, 1)], true)

	if !tex_ok {
		return RENDER_BACKEND_TEXTURE_NONE, {}, false
	}

	rt := VK_Render_Target {
		texture = tex,
		width = width,
		height = height,
	}

	rt_handle, rt_add_err := hm.add(&s.render_targets, rt)

	if rt_add_err != nil {
		log.errorf("Failed to add render target. Error: %v", rt_add_err)
		vk_destroy_texture(s, tex)
		return RENDER_BACKEND_TEXTURE_NONE, {}, false
	}

	return tex, rt_handle, true
}

vk_destroy_render_target :: proc(s: ^VK_State, render_target: Render_Target_Handle) {
	hm.remove(&s.render_targets, render_target)
}

vk_get_sampler :: proc(s: ^VK_State, sampler: Texture_Sampler) -> vk.Sampler {
	if smp, has_smp := s.samplers[sampler]; has_smp {
		return smp
	}

	vk_filter :: proc(f: Texture_Filter) -> vk.Filter {
		switch f {
		case .Point: return .NEAREST
		case .Linear: return .LINEAR
		}

		return .NEAREST
	}

	vk_wrap :: proc(w: Texture_Wrap) -> vk.SamplerAddressMode {
		switch w {
		case .Clamp: return .CLAMP_TO_EDGE
		case .Repeat: return .REPEAT
		case .Mirrored_Repeat: return .MIRRORED_REPEAT
		case .Border: return .CLAMP_TO_BORDER
		}

		return .CLAMP_TO_EDGE
	}

	border: vk.BorderColor

	switch sampler.wrap_border_color {
	case .Transparent_Black: border = .FLOAT_TRANSPARENT_BLACK
	case .Black: border = .FLOAT_OPAQUE_BLACK
	case .White: border = .FLOAT_OPAQUE_WHITE
	}

	sampler_info := vk.SamplerCreateInfo {
		sType = .SAMPLER_CREATE_INFO,
		magFilter = vk_filter(sampler.scale_up_filter),
		minFilter = vk_filter(sampler.scale_down_filter),
		mipmapMode = sampler.mip_filter == .Linear ? .LINEAR : .NEAREST,
		addressModeU = vk_wrap(sampler.wrap_x),
		addressModeV = vk_wrap(sampler.wrap_y),
		addressModeW = .CLAMP_TO_EDGE,
		maxLod = vk.LOD_CLAMP_NONE,
		borderColor = border,
	}

	smp: vk.Sampler

	if !vk_check(vk.CreateSampler(s.device, &sampler_info, nil, &smp)) {
		s.samplers[sampler] = 0
		return 0
	}

	s.samplers[sampler] = smp
	return smp
}

vk_create_shader_module :: proc(s: ^VK_State, code: []u8) -> (vk.ShaderModule, bool) {
	if len(code) == 0 {
		log.error("Vulkan backend: empty SPIR-V module")
		return 0, false
	}

	if len(code) % 4 != 0 {
		log.error("Vulkan backend: SPIR-V module size is not a multiple of 4")
		return 0, false
	}

	words := make([]u32, len(code) / 4, frame_allocator)
	mem.copy(raw_data(words), raw_data(code), len(code))

	module_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode = raw_data(words),
	}

	module: vk.ShaderModule

	if !vk_check(vk.CreateShaderModule(s.device, &module_info, nil, &module)) {
		return 0, false
	}

	return module, true
}

vk_load_shader :: proc(
	s: ^VK_State,
	compiled: sc.Compiled_Shader_View,
	inputs: []Shader_Input,
) -> (
	_handle: Shader_Handle,
	_ok: bool,
) {
	code := compiled.code[.SPIRV]
	shd := VK_Shader {
		constants_size = compiled.constants_size,
		num_textures = compiled.num_textures,
	}

	vm_ok, fm_ok: bool
	shd.vertex_module, vm_ok = vk_create_shader_module(s, code.vertex)

	if !vm_ok {
		return
	}

	shd.fragment_module, fm_ok = vk_create_shader_module(s, code.fragment)

	if !fm_ok {
		vk_release_shader(s, shd)
		return
	}

	bindings := make([]vk.DescriptorSetLayoutBinding, 1 + compiled.num_textures, frame_allocator)
	num_bindings := 0

	if compiled.constants_size > 0 {
		bindings[num_bindings] = {
			binding = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		}

		num_bindings += 1
	}

	for t_idx in 0..<compiled.num_textures {
		bindings[num_bindings] = {
			binding = u32(1 + t_idx),
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		}

		num_bindings += 1
	}

	set_layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(num_bindings),
		pBindings = raw_data(bindings),
	}

	if !vk_check(vk.CreateDescriptorSetLayout(s.device, &set_layout_info, nil, &shd.set_layout)) {
		vk_release_shader(s, shd)
		return
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts = &shd.set_layout,
	}

	if !vk_check(vk.CreatePipelineLayout(s.device, &pipeline_layout_info, nil, &shd.pipeline_layout)) {
		vk_release_shader(s, shd)
		return
	}

	attributes := make([]vk.VertexInputAttributeDescription, len(inputs), frame_allocator)
	offset := 0

	for input, idx in inputs {
		attributes[idx] = {
			location = u32(input.register),
			binding = 0,
			format = vk_format_from_pixel_format(input.format),
			offset = u32(offset),
		}

		offset += pixel_format_size(input.format)
	}

	shd.stride = offset

	vertex_binding := vk.VertexInputBindingDescription {
		binding = 0,
		stride = u32(offset),
		inputRate = .VERTEX,
	}

	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = shd.vertex_module,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = shd.fragment_module,
			pName = "main",
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = len(inputs) > 0 ? 1 : 0,
		pVertexBindingDescriptions = &vertex_binding,
		vertexAttributeDescriptionCount = u32(len(attributes)),
		pVertexAttributeDescriptions = raw_data(attributes),
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount = 1,
	}

	rasterization := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode = {},
		frontFace = .COUNTER_CLOCKWISE,
		lineWidth = 1,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	dynamic_states := [2]vk.DynamicState{ .VIEWPORT, .SCISSOR }

	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates = &dynamic_states[0],
	}

	target_formats := [2]vk.Format{ VK_OFFSCREEN_FORMAT, VK_RENDER_TEXTURE_FORMAT }

	for blend_mode in Blend_Mode {
		blend_attachment := vk.PipelineColorBlendAttachmentState {
			blendEnable = true,
			colorBlendOp = .ADD,
			alphaBlendOp = .ADD,
			colorWriteMask = {.R, .G, .B, .A},
		}

		switch blend_mode {
		case .Alpha:
			blend_attachment.srcColorBlendFactor = .SRC_ALPHA
			blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
			blend_attachment.srcAlphaBlendFactor = .SRC_ALPHA
			blend_attachment.dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA
		case .Premultiplied_Alpha:
			blend_attachment.srcColorBlendFactor = .ONE
			blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
			blend_attachment.srcAlphaBlendFactor = .ONE
			blend_attachment.dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA
		case .Additive:
			blend_attachment.srcColorBlendFactor = .SRC_ALPHA
			blend_attachment.dstColorBlendFactor = .ONE
			blend_attachment.srcAlphaBlendFactor = .SRC_ALPHA
			blend_attachment.dstAlphaBlendFactor = .ONE
		}

		color_blend := vk.PipelineColorBlendStateCreateInfo {
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			attachmentCount = 1,
			pAttachments = &blend_attachment,
		}

		for &target_format, format_index in target_formats {
			rendering_info := vk.PipelineRenderingCreateInfo {
				sType = .PIPELINE_RENDERING_CREATE_INFO,
				colorAttachmentCount = 1,
				pColorAttachmentFormats = &target_format,
			}

			pipeline_info := vk.GraphicsPipelineCreateInfo {
				sType = .GRAPHICS_PIPELINE_CREATE_INFO,
				pNext = &rendering_info,
				stageCount = len(stages),
				pStages = &stages[0],
				pVertexInputState = &vertex_input,
				pInputAssemblyState = &input_assembly,
				pViewportState = &viewport_state,
				pRasterizationState = &rasterization,
				pMultisampleState = &multisample,
				pColorBlendState = &color_blend,
				pDynamicState = &dynamic_state,
				layout = shd.pipeline_layout,
			}

			if !vk_check(vk.CreateGraphicsPipelines(s.device, 0, 1, &pipeline_info, nil, &shd.pipelines[blend_mode][format_index])) {
				vk_release_shader(s, shd)
				return
			}
		}
	}

	h, h_add_err := hm.add(&s.shaders, shd)

	if h_add_err != nil {
		log.errorf("Failed to add shader. Error: %v", h_add_err)
		vk_release_shader(s, shd)
		return
	}

	return h, true
}

vk_release_shader :: proc(s: ^VK_State, shd: VK_Shader) {
	for blend_pipelines in shd.pipelines {
		for p in blend_pipelines {
			if p != 0 {
				vk.DestroyPipeline(s.device, p, nil)
			}
		}
	}

	if shd.pipeline_layout != 0 {
		vk.DestroyPipelineLayout(s.device, shd.pipeline_layout, nil)
	}

	if shd.set_layout != 0 {
		vk.DestroyDescriptorSetLayout(s.device, shd.set_layout, nil)
	}

	if shd.vertex_module != 0 {
		vk.DestroyShaderModule(s.device, shd.vertex_module, nil)
	}

	if shd.fragment_module != 0 {
		vk.DestroyShaderModule(s.device, shd.fragment_module, nil)
	}
}

vk_destroy_shader :: proc(s: ^VK_State, h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	vk.DeviceWaitIdle(s.device)
	vk_release_shader(s, shd^)
	hm.remove(&s.shaders, h)
}

vk_read_backbuffer :: proc(s: ^VK_State, pixels: []u8) -> bool {
	if len(pixels) != s.width * s.height * 4 {
		return false
	}

	buffer, memory, mapped, ok := vk_create_host_buffer(s, len(pixels), {.TRANSFER_DST})

	if !ok {
		return false
	}

	region := vk.BufferImageCopy {
		imageSubresource = { aspectMask = {.COLOR}, layerCount = 1 },
		imageExtent = { u32(s.width), u32(s.height), 1 },
	}

	cmd := vk_begin(s)
	vk.CmdCopyImageToBuffer(cmd, s.offscreen_image, .GENERAL, buffer, 1, &region)
	vk_submit(s)
	mem.copy(raw_data(pixels), mapped, len(pixels))
	vk_destroy_host_buffer(s, buffer, memory)
	return true
}

vk_get_depth_clip_range :: proc() -> (min: f32, max: f32) {
	return 0, 1
}
