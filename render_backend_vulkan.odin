// Vulkan render backend for Karl2D.
// Phase 1: Foundation & Initialization — instance, device, swapchain, command buffers, synchronization.
// Later phases will add textures, shaders, pipelines, render targets, etc.
#+build linux, windows
#+private file

package karl2d

import "base:runtime"
import vk "vendor:vulkan"
import hm "core:container/handle_map"
import "log"

when ODIN_OS == .Linux {
        import wl "platform_bindings/linux/wayland"
        import X "vendor:x11/xlib"
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

MAX_FRAMES_IN_FLIGHT :: 2

// ---------------------------------------------------------------------------
// Vulkan glue state — common header for platform-specific glue structs.
// The concrete types (Vulkan_Wayland_Glue_State, Vulkan_X11_Glue_State) place
// these two fields first so the render backend can safely cast the glue state
// pointer and read platform_type / vk_surface regardless of which platform
// glue was actually created.
// ---------------------------------------------------------------------------

Vulkan_Glue_Platform_Type :: enum {
        Unknown,
        Wayland,
        X11,
        Win32,
}

Vulkan_Glue_State :: struct {
        platform_type: Vulkan_Glue_Platform_Type,
        vk_surface:    vk.SurfaceKHR,
}

// ---------------------------------------------------------------------------
// Sub-structures (textures, shaders, render targets — stubs for Phase 1)
// ---------------------------------------------------------------------------

Vulkan_Texture :: struct {
        handle:              Texture_Handle,
        image:               vk.Image,
        memory:              vk.DeviceMemory,
        view:                vk.ImageView,
        sampler:             vk.Sampler,
        format:              Pixel_Format,
        width:               int,
        height:              int,
        layout:              vk.ImageLayout,
        needs_vertical_flip: bool,
}

Vulkan_Shader :: struct {
        handle:          Shader_Handle,
        vertex_module:   vk.ShaderModule,
        fragment_module: vk.ShaderModule,
}

Vulkan_Render_Target :: struct {
        handle:      Render_Target_Handle,
        image:       vk.Image,
        memory:      vk.DeviceMemory,
        view:        vk.ImageView,
        framebuffer: vk.Framebuffer,
        render_pass: vk.RenderPass,
        width:       int,
        height:      int,
}

// ---------------------------------------------------------------------------
// Vulkan_State — module-level state, following the same pattern as GL / D3D11
// ---------------------------------------------------------------------------

Vulkan_State :: struct {
        allocator: runtime.Allocator,
        width:     int,
        height:    int,

        // Core Vulkan objects
        instance:        vk.Instance,
        physical_device: vk.PhysicalDevice,
        device:          vk.Device,
        surface:         vk.SurfaceKHR,

        // Debug
        debug_messenger: vk.DebugUtilsMessengerEXT,

        // Queues
        graphics_queue:        vk.Queue,
        present_queue:         vk.Queue,
        graphics_queue_family: u32,
        present_queue_family:  u32,

        // Swapchain
        swapchain:             vk.SwapchainKHR,
        swapchain_images:      []vk.Image,
        swapchain_image_views: []vk.ImageView,
        swapchain_format:      vk.Format,
        swapchain_extent:      vk.Extent2D,

        // Per-frame synchronization (double-buffered)
        image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
        render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
        in_flight_fences:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,
        current_frame:              u32,
        current_image_index:        u32,

        // Command pool and buffers
        command_pool:    vk.CommandPool,
        command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

        // Default render pass and framebuffers for the swapchain
        render_pass:  vk.RenderPass,
        framebuffers: []vk.Framebuffer,

        // Whether we are currently inside a render pass recording
        in_render_pass: bool,

        // Resource handle maps (same pattern as GL / D3D11)
        textures:       hm.Dynamic_Handle_Map(Vulkan_Texture, Texture_Handle),
        shaders:        hm.Dynamic_Handle_Map(Vulkan_Shader, Shader_Handle),
        render_targets: hm.Dynamic_Handle_Map(Vulkan_Render_Target, Render_Target_Handle),

        // Platform glue
        glue: Window_Render_Glue,
}

// Module-level state pointer (same pattern as GL_State / D3D11_State).
s: ^Vulkan_State

// ---------------------------------------------------------------------------
// Render_Backend_Interface vtable
// ---------------------------------------------------------------------------

@(private = "package")
RENDER_BACKEND_VULKAN :: Render_Backend_Interface {
        state_size                    = vk_state_size,
        init                          = vk_init,
        shutdown                      = vk_shutdown,
        clear                         = vk_clear,
        present                       = vk_present,
        draw                          = vk_draw,
        resize_swapchain              = vk_resize_swapchain,
        get_swapchain_width           = vk_get_swapchain_width,
        get_swapchain_height          = vk_get_swapchain_height,
        set_internal_state            = vk_set_internal_state,
        create_texture                = vk_create_texture,
        load_texture                  = vk_load_texture,
        update_texture                = vk_update_texture,
        destroy_texture               = vk_destroy_texture,
        texture_needs_vertical_flip   = vk_texture_needs_vertical_flip,
        create_render_texture         = vk_create_render_texture,
        destroy_render_target         = vk_destroy_render_target,
        set_texture_filter            = vk_set_texture_filter,
        load_shader                   = vk_load_shader,
        destroy_shader                = vk_destroy_shader,
        default_shader_vertex_source  = vk_default_shader_vertex_source,
        default_shader_fragment_source = vk_default_shader_fragment_source,
}

// ---------------------------------------------------------------------------
// State size / internal state (hot-reload support)
// ---------------------------------------------------------------------------

vk_state_size :: proc() -> int {
        return size_of(Vulkan_State)
}

vk_set_internal_state :: proc(state: rawptr) {
        s = (^Vulkan_State)(state)
}

// ---------------------------------------------------------------------------
// Initialization
// ---------------------------------------------------------------------------

vk_init :: proc(
        state: rawptr,
        glue: Window_Render_Glue,
        swapchain_width, swapchain_height: int,
        allocator := context.allocator,
) {
        s = (^Vulkan_State)(state)
        s.allocator = allocator
        s.width = swapchain_width
        s.height = swapchain_height
        s.glue = glue

        hm.dynamic_init(&s.textures, allocator)
        hm.dynamic_init(&s.shaders, allocator)
        hm.dynamic_init(&s.render_targets, allocator)

        // Load global Vulkan function pointers (vkGetInstanceProcAddr, etc.)
        vk.load_proc_addresses_global(rawptr(vk_get_proc_address()))

        // 1. Create Vulkan instance
        if !vk_create_instance() {
                log.error("Vulkan: Failed to create instance")
                return
        }

        // Load instance-level function pointers
        vk.load_proc_addresses_instance(s.instance)

        // 2. Set up debug messenger (debug builds only)
        when ODIN_DEBUG {
                vk_setup_debug_messenger()
        }

        // 3. Create surface via the platform glue handles.
        //    The glue's make_context signals the glue is ready. The actual VkSurfaceKHR is
        //    created here by the render backend using the platform handles stored in the glue state.
        if glue.make_context != nil {
                if !glue.make_context(glue.state) {
                        log.error("Vulkan: Platform glue make_context failed")
                        return
                }
        }

        if !vk_create_surface_from_glue(glue) {
                log.error("Vulkan: Failed to create VkSurfaceKHR")
                return
        }

        // 4. Pick physical device
        if !vk_pick_physical_device() {
                log.error("Vulkan: Failed to find a suitable GPU")
                return
        }

        // 5. Create logical device and queues
        if !vk_create_logical_device() {
                log.error("Vulkan: Failed to create logical device")
                return
        }

        // Load device-level function pointers
        vk.load_proc_addresses_device(s.device)

        // 6. Create swapchain
        if !vk_create_swapchain() {
                log.error("Vulkan: Failed to create swapchain")
                return
        }

        // 7. Create default render pass
        if !vk_create_render_pass() {
                log.error("Vulkan: Failed to create render pass")
                return
        }

        // 8. Create framebuffers for swapchain images
        if !vk_create_framebuffers() {
                log.error("Vulkan: Failed to create framebuffers")
                return
        }

        // 9. Create command pool and allocate command buffers
        if !vk_create_command_pool() {
                log.error("Vulkan: Failed to create command pool")
                return
        }

        if !vk_allocate_command_buffers() {
                log.error("Vulkan: Failed to allocate command buffers")
                return
        }

        // 10. Create synchronization primitives
        if !vk_create_sync_objects() {
                log.error("Vulkan: Failed to create synchronization objects")
                return
        }

        log.info("Vulkan: Initialization complete")
}

// ---------------------------------------------------------------------------
// Shutdown
// ---------------------------------------------------------------------------

vk_shutdown :: proc() {
        if s == nil { return }
        if s.device != nil {
                vk.DeviceWaitIdle(s.device)
        }

        // Destroy sync objects
        for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
                if s.image_available_semaphores[i] != 0 {
                        vk.DestroySemaphore(s.device, s.image_available_semaphores[i], nil)
                }
                if s.render_finished_semaphores[i] != 0 {
                        vk.DestroySemaphore(s.device, s.render_finished_semaphores[i], nil)
                }
                if s.in_flight_fences[i] != 0 {
                        vk.DestroyFence(s.device, s.in_flight_fences[i], nil)
                }
        }

        // Destroy command pool (frees command buffers implicitly)
        if s.command_pool != 0 {
                vk.DestroyCommandPool(s.device, s.command_pool, nil)
        }

        // Destroy framebuffers
        vk_destroy_swapchain_framebuffers()

        // Destroy render pass
        if s.render_pass != 0 {
                vk.DestroyRenderPass(s.device, s.render_pass, nil)
        }

        // Destroy swapchain image views and swapchain
        vk_destroy_swapchain_resources()

        if s.swapchain != 0 {
                vk.DestroySwapchainKHR(s.device, s.swapchain, nil)
        }

        // Destroy surface
        if s.surface != 0 {
                vk.DestroySurfaceKHR(s.instance, s.surface, nil)
        }

        // Destroy logical device
        if s.device != nil {
                vk.DestroyDevice(s.device, nil)
        }

        // Destroy debug messenger
        when ODIN_DEBUG {
                if s.debug_messenger != 0 {
                        vk.DestroyDebugUtilsMessengerEXT(s.instance, s.debug_messenger, nil)
                }
        }

        // Destroy instance
        if s.instance != nil {
                vk.DestroyInstance(s.instance, nil)
        }

        // Clean up handle maps
        hm.dynamic_destroy(&s.textures)
        hm.dynamic_destroy(&s.shaders)
        hm.dynamic_destroy(&s.render_targets)

        // Free swapchain image arrays
        if s.swapchain_images != nil {
                delete(s.swapchain_images, s.allocator)
        }
        if s.swapchain_image_views != nil {
                delete(s.swapchain_image_views, s.allocator)
        }
        if s.framebuffers != nil {
                delete(s.framebuffers, s.allocator)
        }

        // Destroy the glue
        if s.glue.destroy != nil {
                s.glue.destroy(s.glue.state)
        }

        log.info("Vulkan: Shutdown complete")
}

// ---------------------------------------------------------------------------
// Instance creation
// ---------------------------------------------------------------------------

vk_create_instance :: proc() -> bool {
        app_info := vk.ApplicationInfo {
                sType              = .APPLICATION_INFO,
                pApplicationName   = "Karl2D Application",
                applicationVersion = vk.MAKE_VERSION(1, 0, 0),
                pEngineName        = "Karl2D",
                engineVersion      = vk.MAKE_VERSION(1, 0, 0),
                apiVersion         = vk.API_VERSION_1_0,
        }

        // Required extensions
        extensions := make([dynamic]cstring, 0, 8, context.temp_allocator)
        append(&extensions, vk.KHR_SURFACE_EXTENSION_NAME)

        // Platform-specific surface extension
        when ODIN_OS == .Linux {
                // We add both — only the one matching the active windowing system will be used at runtime.
                // The instance extension just needs to be available.
                append(&extensions, vk.KHR_WAYLAND_SURFACE_EXTENSION_NAME)
                append(&extensions, vk.KHR_XLIB_SURFACE_EXTENSION_NAME)
        } else when ODIN_OS == .Windows {
                append(&extensions, vk.KHR_WIN32_SURFACE_EXTENSION_NAME)
        }

        when ODIN_DEBUG {
                append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
        }

        // Validation layers (debug only)
        layer_count: u32 = 0
        layer_names: [^]cstring = nil
        validation_layer := cstring("VK_LAYER_KHRONOS_validation")

        when ODIN_DEBUG {
                layer_count = 1
                layer_names = &validation_layer
        }

        create_info := vk.InstanceCreateInfo {
                sType                   = .INSTANCE_CREATE_INFO,
                pApplicationInfo        = &app_info,
                enabledExtensionCount   = u32(len(extensions)),
                ppEnabledExtensionNames = raw_data(extensions[:]),
                enabledLayerCount       = layer_count,
                ppEnabledLayerNames     = layer_names,
        }

        result := vk.CreateInstance(&create_info, nil, &s.instance)
        if result != .SUCCESS {
                log.errorf("Vulkan: vkCreateInstance failed with %v", result)
                return false
        }
        return true
}

// ---------------------------------------------------------------------------
// Debug messenger (debug builds)
// ---------------------------------------------------------------------------

when ODIN_DEBUG {
        vk_debug_callback :: proc "system" (
                message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
                message_types: vk.DebugUtilsMessageTypeFlagsEXT,
                p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
                p_user_data: rawptr,
        ) -> b32 {
                context = runtime.default_context()
                if p_callback_data != nil && p_callback_data.pMessage != nil {
                        if .ERROR in message_severity {
                                log.errorf("Vulkan Validation: %s", p_callback_data.pMessage)
                        } else if .WARNING in message_severity {
                                log.warnf("Vulkan Validation: %s", p_callback_data.pMessage)
                        } else {
                                log.infof("Vulkan Validation: %s", p_callback_data.pMessage)
                        }
                }
                return false // Don't abort the Vulkan call
        }

        vk_setup_debug_messenger :: proc() {
                create_info := vk.DebugUtilsMessengerCreateInfoEXT {
                        sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                        messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
                        messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
                        pfnUserCallback = vk_debug_callback,
                }
                result := vk.CreateDebugUtilsMessengerEXT(s.instance, &create_info, nil, &s.debug_messenger)
                if result != .SUCCESS {
                        log.warnf("Vulkan: Failed to set up debug messenger (%v)", result)
                }
        }
}

// ---------------------------------------------------------------------------
// Surface creation from platform glue handles
// ---------------------------------------------------------------------------

vk_create_surface_from_glue :: proc(glue: Window_Render_Glue) -> bool {
        if glue.state == nil {
                log.error("Vulkan: Glue state is nil, cannot create surface")
                return false
        }

        // Read the common header to determine which platform we are on
        vk_glue := (^Vulkan_Glue_State)(glue.state)

        when ODIN_OS == .Linux {
                switch vk_glue.platform_type {
                case .Wayland:
                        wl_glue := (^Vulkan_Wayland_Glue_State)(glue.state)
                        create_info := vk.WaylandSurfaceCreateInfoKHR {
                                sType   = .WAYLAND_SURFACE_CREATE_INFO_KHR,
                                display = auto_cast wl_glue.wl_display,
                                surface = auto_cast wl_glue.wl_surface,
                        }
                        result := vk.CreateWaylandSurfaceKHR(s.instance, &create_info, nil, &s.surface)
                        if result != .SUCCESS {
                                log.errorf("Vulkan: vkCreateWaylandSurfaceKHR failed with %v", result)
                                return false
                        }
                        // Store the surface in the glue state so cleanup can find it if needed
                        wl_glue.vk_surface = s.surface
                        return true

                case .X11:
                        x11_glue := (^Vulkan_X11_Glue_State)(glue.state)
                        create_info := vk.XlibSurfaceCreateInfoKHR {
                                sType  = .XLIB_SURFACE_CREATE_INFO_KHR,
                                dpy    = auto_cast x11_glue.x11_display,
                                window = auto_cast x11_glue.x11_window,
                        }
                        result := vk.CreateXlibSurfaceKHR(s.instance, &create_info, nil, &s.surface)
                        if result != .SUCCESS {
                                log.errorf("Vulkan: vkCreateXlibSurfaceKHR failed with %v", result)
                                return false
                        }
                        x11_glue.vk_surface = s.surface
                        return true

                case .Win32, .Unknown:
                        log.error("Vulkan: Unexpected platform type for Linux surface creation")
                        return false
                }
        } else when ODIN_OS == .Windows {
                // Windows surface creation will be added in Phase 4
                log.error("Vulkan: Windows surface creation not yet implemented (Phase 4)")
                return false
        }

        return false
}

// ---------------------------------------------------------------------------
// Physical device selection
// ---------------------------------------------------------------------------

vk_pick_physical_device :: proc() -> bool {
        device_count: u32
        vk.EnumeratePhysicalDevices(s.instance, &device_count, nil)
        if device_count == 0 {
                log.error("Vulkan: No physical devices found")
                return false
        }

        devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
        vk.EnumeratePhysicalDevices(s.instance, &device_count, raw_data(devices))

        // Score devices: prefer discrete GPU, require graphics + present queue, require swapchain ext
        best_score := -1
        for dev in devices {
                score := vk_rate_physical_device(dev)
                if score > best_score {
                        best_score = score
                        s.physical_device = dev
                }
        }

        if best_score < 0 || s.physical_device == nil {
                return false
        }

        // Find queue families for the chosen device
        return vk_find_queue_families(s.physical_device)
}

vk_rate_physical_device :: proc(device: vk.PhysicalDevice) -> int {
        props: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(device, &props)

        // Check required extensions
        if !vk_device_supports_extensions(device) {
                return -1
        }

        // Check queue family support
        if !vk_has_required_queue_families(device) {
                return -1
        }

        score := 0
        if props.deviceType == .DISCRETE_GPU {
                score += 1000
        } else if props.deviceType == .INTEGRATED_GPU {
                score += 100
        }

        return score
}

vk_device_supports_extensions :: proc(device: vk.PhysicalDevice) -> bool {
        ext_count: u32
        vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)

        if ext_count == 0 { return false }

        extensions := make([]vk.ExtensionProperties, ext_count, context.temp_allocator)
        vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, raw_data(extensions))

        // Require VK_KHR_swapchain
        swapchain_found := false
        for &ext in extensions {
                name := cstring(raw_data(&ext.extensionName))
                if name == vk.KHR_SWAPCHAIN_EXTENSION_NAME {
                        swapchain_found = true
                        break
                }
        }

        return swapchain_found
}

vk_has_required_queue_families :: proc(device: vk.PhysicalDevice) -> bool {
        family_count: u32
        vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
        if family_count == 0 { return false }

        families := make([]vk.QueueFamilyProperties, family_count, context.temp_allocator)
        vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))

        found_graphics := false
        found_present := false

        for family, i in families {
                if .GRAPHICS in family.queueFlags {
                        found_graphics = true
                }

                present_support: b32
                vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), s.surface, &present_support)
                if present_support {
                        found_present = true
                }

                if found_graphics && found_present { return true }
        }

        return false
}

vk_find_queue_families :: proc(device: vk.PhysicalDevice) -> bool {
        family_count: u32
        vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, nil)
        families := make([]vk.QueueFamilyProperties, family_count, context.temp_allocator)
        vk.GetPhysicalDeviceQueueFamilyProperties(device, &family_count, raw_data(families))

        graphics_found := false
        present_found := false

        for family, i in families {
                if .GRAPHICS in family.queueFlags && !graphics_found {
                        s.graphics_queue_family = u32(i)
                        graphics_found = true
                }

                present_support: b32
                vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), s.surface, &present_support)
                if present_support && !present_found {
                        s.present_queue_family = u32(i)
                        present_found = true
                }

                if graphics_found && present_found { break }
        }

        return graphics_found && present_found
}

// ---------------------------------------------------------------------------
// Logical device + queues
// ---------------------------------------------------------------------------

vk_create_logical_device :: proc() -> bool {
        // Unique queue family indices
        unique_families: [2]u32
        unique_count: int = 1
        unique_families[0] = s.graphics_queue_family
        if s.present_queue_family != s.graphics_queue_family {
                unique_families[1] = s.present_queue_family
                unique_count = 2
        }

        queue_priority: f32 = 1.0
        queue_create_infos: [2]vk.DeviceQueueCreateInfo
        for i in 0 ..< unique_count {
                queue_create_infos[i] = vk.DeviceQueueCreateInfo {
                        sType            = .DEVICE_QUEUE_CREATE_INFO,
                        queueFamilyIndex = unique_families[i],
                        queueCount       = 1,
                        pQueuePriorities = &queue_priority,
                }
        }

        device_features: vk.PhysicalDeviceFeatures // All zeroed = no special features needed for 2D

        swapchain_ext := vk.KHR_SWAPCHAIN_EXTENSION_NAME
        device_create_info := vk.DeviceCreateInfo {
                sType                   = .DEVICE_CREATE_INFO,
                queueCreateInfoCount    = u32(unique_count),
                pQueueCreateInfos       = &queue_create_infos[0],
                pEnabledFeatures        = &device_features,
                enabledExtensionCount   = 1,
                ppEnabledExtensionNames = &swapchain_ext,
        }

        result := vk.CreateDevice(s.physical_device, &device_create_info, nil, &s.device)
        if result != .SUCCESS {
                log.errorf("Vulkan: vkCreateDevice failed with %v", result)
                return false
        }

        vk.GetDeviceQueue(s.device, s.graphics_queue_family, 0, &s.graphics_queue)
        vk.GetDeviceQueue(s.device, s.present_queue_family, 0, &s.present_queue)

        return true
}

// ---------------------------------------------------------------------------
// Swapchain
// ---------------------------------------------------------------------------

Swapchain_Support_Details :: struct {
        capabilities: vk.SurfaceCapabilitiesKHR,
        formats:      []vk.SurfaceFormatKHR,
        present_modes: []vk.PresentModeKHR,
}

vk_query_swapchain_support :: proc(device: vk.PhysicalDevice) -> Swapchain_Support_Details {
        details: Swapchain_Support_Details
        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, s.surface, &details.capabilities)

        format_count: u32
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device, s.surface, &format_count, nil)
        if format_count > 0 {
                details.formats = make([]vk.SurfaceFormatKHR, format_count, context.temp_allocator)
                vk.GetPhysicalDeviceSurfaceFormatsKHR(device, s.surface, &format_count, raw_data(details.formats))
        }

        mode_count: u32
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device, s.surface, &mode_count, nil)
        if mode_count > 0 {
                details.present_modes = make([]vk.PresentModeKHR, mode_count, context.temp_allocator)
                vk.GetPhysicalDeviceSurfacePresentModesKHR(device, s.surface, &mode_count, raw_data(details.present_modes))
        }

        return details
}

vk_choose_swap_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
        // Prefer B8G8R8A8_UNORM with SRGB_NONLINEAR color space (matches D3D11 choice)
        for f in formats {
                if f.format == .B8G8R8A8_UNORM && f.colorSpace == .SRGB_NONLINEAR {
                        return f
                }
        }
        // Fallback to first available
        return formats[0]
}

vk_choose_swap_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
        // FIFO is guaranteed available and gives vsync behaviour (matches existing GL/D3D11)
        return .FIFO
}

vk_choose_swap_extent :: proc(capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
        if capabilities.currentExtent.width != max(u32) {
                return capabilities.currentExtent
        }
        // Pick the extent that matches our desired window size, clamped to surface capabilities
        extent := vk.Extent2D {
                width  = clamp(u32(s.width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
                height = clamp(u32(s.height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        }
        return extent
}

vk_create_swapchain :: proc() -> bool {
        support := vk_query_swapchain_support(s.physical_device)
        if len(support.formats) == 0 || len(support.present_modes) == 0 {
                log.error("Vulkan: Swapchain not adequately supported")
                return false
        }

        surface_format := vk_choose_swap_surface_format(support.formats)
        present_mode := vk_choose_swap_present_mode(support.present_modes)
        extent := vk_choose_swap_extent(&support.capabilities)

        // Request one more image than the minimum for triple-/double-buffering headroom
        image_count := support.capabilities.minImageCount + 1
        if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
                image_count = support.capabilities.maxImageCount
        }

        create_info := vk.SwapchainCreateInfoKHR {
                sType            = .SWAPCHAIN_CREATE_INFO_KHR,
                surface          = s.surface,
                minImageCount    = image_count,
                imageFormat      = surface_format.format,
                imageColorSpace  = surface_format.colorSpace,
                imageExtent      = extent,
                imageArrayLayers = 1,
                imageUsage       = {.COLOR_ATTACHMENT},
                preTransform     = support.capabilities.currentTransform,
                compositeAlpha   = {.OPAQUE},
                presentMode      = present_mode,
                clipped          = true,
        }

        queue_family_indices := [2]u32{s.graphics_queue_family, s.present_queue_family}
        if s.graphics_queue_family != s.present_queue_family {
                create_info.imageSharingMode = .CONCURRENT
                create_info.queueFamilyIndexCount = 2
                create_info.pQueueFamilyIndices = &queue_family_indices[0]
        } else {
                create_info.imageSharingMode = .EXCLUSIVE
        }

        result := vk.CreateSwapchainKHR(s.device, &create_info, nil, &s.swapchain)
        if result != .SUCCESS {
                log.errorf("Vulkan: vkCreateSwapchainKHR failed with %v", result)
                return false
        }

        s.swapchain_format = surface_format.format
        s.swapchain_extent = extent

        // Retrieve swapchain images
        actual_count: u32
        vk.GetSwapchainImagesKHR(s.device, s.swapchain, &actual_count, nil)
        s.swapchain_images = make([]vk.Image, actual_count, s.allocator)
        vk.GetSwapchainImagesKHR(s.device, s.swapchain, &actual_count, raw_data(s.swapchain_images))

        // Create image views
        s.swapchain_image_views = make([]vk.ImageView, len(s.swapchain_images), s.allocator)
        for img, i in s.swapchain_images {
                view_info := vk.ImageViewCreateInfo {
                        sType    = .IMAGE_VIEW_CREATE_INFO,
                        image    = img,
                        viewType = .D2,
                        format   = s.swapchain_format,
                        components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
                        subresourceRange = {
                                aspectMask     = {.COLOR},
                                baseMipLevel   = 0,
                                levelCount     = 1,
                                baseArrayLayer = 0,
                                layerCount     = 1,
                        },
                }
                result := vk.CreateImageView(s.device, &view_info, nil, &s.swapchain_image_views[i])
                if result != .SUCCESS {
                        log.errorf("Vulkan: Failed to create image view %d (%v)", i, result)
                        return false
                }
        }

        return true
}

vk_destroy_swapchain_resources :: proc() {
        if s.swapchain_image_views != nil {
                for view in s.swapchain_image_views {
                        if view != 0 {
                                vk.DestroyImageView(s.device, view, nil)
                        }
                }
        }
        // swapchain_images are owned by the swapchain; no need to destroy individually
}

// ---------------------------------------------------------------------------
// Render pass
// ---------------------------------------------------------------------------

vk_create_render_pass :: proc() -> bool {
        color_attachment := vk.AttachmentDescription {
                format         = s.swapchain_format,
                samples        = {._1},
                loadOp         = .CLEAR,
                storeOp        = .STORE,
                stencilLoadOp  = .DONT_CARE,
                stencilStoreOp = .DONT_CARE,
                initialLayout  = .UNDEFINED,
                finalLayout    = .PRESENT_SRC_KHR,
        }

        color_attachment_ref := vk.AttachmentReference {
                attachment = 0,
                layout     = .COLOR_ATTACHMENT_OPTIMAL,
        }

        subpass := vk.SubpassDescription {
                pipelineBindPoint    = .GRAPHICS,
                colorAttachmentCount = 1,
                pColorAttachments    = &color_attachment_ref,
        }

        // Subpass dependency to synchronise the image layout transition
        dependency := vk.SubpassDependency {
                srcSubpass    = vk.SUBPASS_EXTERNAL,
                dstSubpass    = 0,
                srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
                srcAccessMask = {},
                dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
                dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
        }

        render_pass_info := vk.RenderPassCreateInfo {
                sType           = .RENDER_PASS_CREATE_INFO,
                attachmentCount = 1,
                pAttachments    = &color_attachment,
                subpassCount    = 1,
                pSubpasses      = &subpass,
                dependencyCount = 1,
                pDependencies   = &dependency,
        }

        result := vk.CreateRenderPass(s.device, &render_pass_info, nil, &s.render_pass)
        if result != .SUCCESS {
                log.errorf("Vulkan: vkCreateRenderPass failed with %v", result)
                return false
        }

        return true
}

// ---------------------------------------------------------------------------
// Framebuffers
// ---------------------------------------------------------------------------

vk_create_framebuffers :: proc() -> bool {
        s.framebuffers = make([]vk.Framebuffer, len(s.swapchain_image_views), s.allocator)

        for view, i in s.swapchain_image_views {
                attachments := [1]vk.ImageView{view}
                fb_info := vk.FramebufferCreateInfo {
                        sType           = .FRAMEBUFFER_CREATE_INFO,
                        renderPass      = s.render_pass,
                        attachmentCount = 1,
                        pAttachments    = &attachments[0],
                        width           = s.swapchain_extent.width,
                        height          = s.swapchain_extent.height,
                        layers          = 1,
                }

                result := vk.CreateFramebuffer(s.device, &fb_info, nil, &s.framebuffers[i])
                if result != .SUCCESS {
                        log.errorf("Vulkan: Failed to create framebuffer %d (%v)", i, result)
                        return false
                }
        }
        return true
}

vk_destroy_swapchain_framebuffers :: proc() {
        if s.framebuffers != nil {
                for fb in s.framebuffers {
                        if fb != 0 {
                                vk.DestroyFramebuffer(s.device, fb, nil)
                        }
                }
        }
}

// ---------------------------------------------------------------------------
// Command pool & buffers
// ---------------------------------------------------------------------------

vk_create_command_pool :: proc() -> bool {
        pool_info := vk.CommandPoolCreateInfo {
                sType            = .COMMAND_POOL_CREATE_INFO,
                flags            = {.RESET_COMMAND_BUFFER},
                queueFamilyIndex = s.graphics_queue_family,
        }

        result := vk.CreateCommandPool(s.device, &pool_info, nil, &s.command_pool)
        if result != .SUCCESS {
                log.errorf("Vulkan: vkCreateCommandPool failed with %v", result)
                return false
        }
        return true
}

vk_allocate_command_buffers :: proc() -> bool {
        alloc_info := vk.CommandBufferAllocateInfo {
                sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
                commandPool        = s.command_pool,
                level              = .PRIMARY,
                commandBufferCount = MAX_FRAMES_IN_FLIGHT,
        }

        result := vk.AllocateCommandBuffers(s.device, &alloc_info, &s.command_buffers[0])
        if result != .SUCCESS {
                log.errorf("Vulkan: vkAllocateCommandBuffers failed with %v", result)
                return false
        }
        return true
}

// ---------------------------------------------------------------------------
// Synchronization
// ---------------------------------------------------------------------------

vk_create_sync_objects :: proc() -> bool {
        sem_info := vk.SemaphoreCreateInfo {
                sType = .SEMAPHORE_CREATE_INFO,
        }
        fence_info := vk.FenceCreateInfo {
                sType = .FENCE_CREATE_INFO,
                flags = {.SIGNALED}, // Start signaled so first frame doesn't block
        }

        for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
                if vk.CreateSemaphore(s.device, &sem_info, nil, &s.image_available_semaphores[i]) != .SUCCESS ||
                   vk.CreateSemaphore(s.device, &sem_info, nil, &s.render_finished_semaphores[i]) != .SUCCESS ||
                   vk.CreateFence(s.device, &fence_info, nil, &s.in_flight_fences[i]) != .SUCCESS {
                        log.error("Vulkan: Failed to create sync objects for a frame")
                        return false
                }
        }
        return true
}

// ---------------------------------------------------------------------------
// Swapchain resize
// ---------------------------------------------------------------------------

vk_resize_swapchain :: proc(width, height: int) {
        if s == nil { return }
        if width == 0 || height == 0 { return }

        vk.DeviceWaitIdle(s.device)

        s.width = width
        s.height = height

        // Destroy old framebuffers, image views, swapchain — then recreate
        vk_destroy_swapchain_framebuffers()
        vk_destroy_swapchain_resources()

        old_swapchain := s.swapchain
        // Free old arrays
        if s.swapchain_images != nil {
                delete(s.swapchain_images, s.allocator)
                s.swapchain_images = nil
        }
        if s.swapchain_image_views != nil {
                delete(s.swapchain_image_views, s.allocator)
                s.swapchain_image_views = nil
        }
        if s.framebuffers != nil {
                delete(s.framebuffers, s.allocator)
                s.framebuffers = nil
        }

        // Destroy old swapchain after creating a new one would be ideal, but we destroy first here
        if old_swapchain != 0 {
                vk.DestroySwapchainKHR(s.device, old_swapchain, nil)
                s.swapchain = {}
        }

        if !vk_create_swapchain() {
                log.error("Vulkan: Failed to recreate swapchain on resize")
                return
        }
        if !vk_create_framebuffers() {
                log.error("Vulkan: Failed to recreate framebuffers on resize")
                return
        }

        log.infof("Vulkan: Swapchain resized to %dx%d", width, height)
}

// ---------------------------------------------------------------------------
// Clear / Present / Draw  (Phase 1 minimal implementations)
// ---------------------------------------------------------------------------

vk_clear :: proc(render_target: Render_Target_Handle, color: Color) {
        if s == nil { return }

        // Wait for the previous frame using this slot to finish
        vk.WaitForFences(s.device, 1, &s.in_flight_fences[s.current_frame], true, max(u64))
        vk.ResetFences(s.device, 1, &s.in_flight_fences[s.current_frame])

        // Acquire the next swapchain image
        result := vk.AcquireNextImageKHR(
                s.device,
                s.swapchain,
                max(u64),
                s.image_available_semaphores[s.current_frame],
                0,
                &s.current_image_index,
        )

        if result == .ERROR_OUT_OF_DATE_KHR {
                vk_resize_swapchain(s.width, s.height)
                return
        }

        // Reset and begin the command buffer
        cmd := s.command_buffers[s.current_frame]
        vk.ResetCommandBuffer(cmd, {})

        begin_info := vk.CommandBufferBeginInfo {
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = {.ONE_TIME_SUBMIT},
        }
        vk.BeginCommandBuffer(cmd, &begin_info)

        // Begin render pass with clear colour
        clear_color := vk.ClearValue{}
        clear_color.color.float32 = {
                f32(color[0]) / 255.0,
                f32(color[1]) / 255.0,
                f32(color[2]) / 255.0,
                f32(color[3]) / 255.0,
        }

        render_pass_info := vk.RenderPassBeginInfo {
                sType       = .RENDER_PASS_BEGIN_INFO,
                renderPass  = s.render_pass,
                framebuffer = s.framebuffers[s.current_image_index],
                renderArea  = {
                        offset = {0, 0},
                        extent = s.swapchain_extent,
                },
                clearValueCount = 1,
                pClearValues    = &clear_color,
        }
        vk.CmdBeginRenderPass(cmd, &render_pass_info, .INLINE)
        s.in_render_pass = true
}

vk_present :: proc() {
        if s == nil { return }

        cmd := s.command_buffers[s.current_frame]

        // End the render pass if one is active
        if s.in_render_pass {
                vk.CmdEndRenderPass(cmd)
                s.in_render_pass = false
        }

        vk.EndCommandBuffer(cmd)

        // Submit
        wait_semaphores := [1]vk.Semaphore{s.image_available_semaphores[s.current_frame]}
        wait_stages := [1]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
        signal_semaphores := [1]vk.Semaphore{s.render_finished_semaphores[s.current_frame]}

        submit_info := vk.SubmitInfo {
                sType                = .SUBMIT_INFO,
                waitSemaphoreCount   = 1,
                pWaitSemaphores      = &wait_semaphores[0],
                pWaitDstStageMask    = &wait_stages[0],
                commandBufferCount   = 1,
                pCommandBuffers      = &cmd,
                signalSemaphoreCount = 1,
                pSignalSemaphores    = &signal_semaphores[0],
        }

        vk.QueueSubmit(s.graphics_queue, 1, &submit_info, s.in_flight_fences[s.current_frame])

        // Present
        swapchains := [1]vk.SwapchainKHR{s.swapchain}
        image_indices := [1]u32{s.current_image_index}
        present_info := vk.PresentInfoKHR {
                sType              = .PRESENT_INFO_KHR,
                waitSemaphoreCount = 1,
                pWaitSemaphores    = &signal_semaphores[0],
                swapchainCount     = 1,
                pSwapchains        = &swapchains[0],
                pImageIndices      = &image_indices[0],
        }

        result := vk.QueuePresentKHR(s.present_queue, &present_info)
        if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
                vk_resize_swapchain(s.width, s.height)
        }

        s.current_frame = (s.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}

vk_draw :: proc(
        shd: Shader,
        render_target: Render_Target_Handle,
        bound_textures: []Texture_Handle,
        scissor: Maybe(Rect),
        blend_mode: Blend_Mode,
        vertex_buffer: []u8,
) {
        // Phase 1 stub — draw calls will be implemented in Phase 2 (pipelines + shaders + vertex upload)
        // For now this is intentionally empty so the backend compiles and clears work.
}

// ---------------------------------------------------------------------------
// Swapchain dimension queries
// ---------------------------------------------------------------------------

vk_get_swapchain_width :: proc() -> int {
        return s.width if s != nil else 0
}

vk_get_swapchain_height :: proc() -> int {
        return s.height if s != nil else 0
}

// ---------------------------------------------------------------------------
// Texture stubs (Phase 2)
// ---------------------------------------------------------------------------

vk_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
        log.warn("Vulkan: create_texture not yet implemented (Phase 2)")
        return {}
}

vk_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
        log.warn("Vulkan: load_texture not yet implemented (Phase 2)")
        return {}
}

vk_update_texture :: proc(handle: Texture_Handle, data: []u8, rect: Rect) -> bool {
        log.warn("Vulkan: update_texture not yet implemented (Phase 2)")
        return false
}

vk_destroy_texture :: proc(handle: Texture_Handle) {
}

vk_texture_needs_vertical_flip :: proc(handle: Texture_Handle) -> bool {
        // Vulkan does not need the GL vertical flip hack
        return false
}

vk_create_render_texture :: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle) {
        log.warn("Vulkan: create_render_texture not yet implemented (Phase 3)")
        return {}, {}
}

vk_destroy_render_target :: proc(render_target: Render_Target_Handle) {
}

vk_set_texture_filter :: proc(
        handle: Texture_Handle,
        scale_down_filter: Texture_Filter,
        scale_up_filter: Texture_Filter,
        mip_filter: Texture_Filter,
) {
        log.warn("Vulkan: set_texture_filter not yet implemented (Phase 2)")
}

// ---------------------------------------------------------------------------
// Shader stubs (Phase 2)
// ---------------------------------------------------------------------------

vk_load_shader :: proc(
        vs_source: []byte,
        fs_source: []byte,
        desc_allocator := frame_allocator,
        layout_formats: []Pixel_Format = {},
) -> (
        handle: Shader_Handle,
        desc: Shader_Desc,
) {
        log.warn("Vulkan: load_shader not yet implemented (Phase 2)")
        return {}, {}
}

vk_destroy_shader :: proc(handle: Shader_Handle) {
}

vk_default_shader_vertex_source :: proc() -> []byte {
        // Phase 2 will embed pre-compiled SPIR-V via #load
        return {}
}

vk_default_shader_fragment_source :: proc() -> []byte {
        return {}
}

// ---------------------------------------------------------------------------
// Vulkan proc address loader (platform-specific)
// ---------------------------------------------------------------------------

when ODIN_OS == .Linux {
        import "core:dynlib"

        vk_get_proc_address :: proc() -> rawptr {
                lib, ok := dynlib.load_library("libvulkan.so.1", {})
                if !ok {
                        lib, ok = dynlib.load_library("libvulkan.so", {})
                }
                if !ok {
                        log.error("Vulkan: Failed to load libvulkan.so")
                        return nil
                }
                addr, _ := dynlib.symbol_address(lib, "vkGetInstanceProcAddr")
                return addr
        }
} else when ODIN_OS == .Windows {
        import "core:sys/windows"

        vk_get_proc_address :: proc() -> rawptr {
                lib := windows.LoadLibraryW(windows.L("vulkan-1.dll"))
                if lib == nil {
                        log.error("Vulkan: Failed to load vulkan-1.dll")
                        return nil
                }
                return rawptr(windows.GetProcAddress(lib, "vkGetInstanceProcAddr"))
        }
}
