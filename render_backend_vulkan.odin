// Vulkan render backend for Karl2D.
// Phase 1: Foundation & Initialization — instance, device, swapchain, command buffers, synchronization.
// Phase 2: Textures, shaders, pipelines, vertex buffers, draw calls.
#+build linux, windows
#+private file

package karl2d

import "base:runtime"
import vk "vendor:vulkan"
import hm "core:container/handle_map"
import "log"
import "core:mem"
import "core:strings"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

MAX_FRAMES_IN_FLIGHT :: 2

// Maximum number of descriptor sets we can allocate per frame.
// This limits how many draw calls (batch breaks) we can have per frame.
MAX_DESCRIPTOR_SETS_PER_FRAME :: 4096

// Staging buffer size for texture uploads (16 MB)
STAGING_BUFFER_SIZE :: 16 * 1024 * 1024

// ---------------------------------------------------------------------------
// Vulkan glue state types are in render_backend_vulkan_types.odin (package-visible).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Sub-structures
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

Vulkan_Shader_Constant :: struct {
        offset: u32,
        size:   u32,
}

Vulkan_Shader :: struct {
        handle:                Shader_Handle,
        vertex_module:         vk.ShaderModule,
        fragment_module:       vk.ShaderModule,

        // Pipeline cache: one pipeline per blend mode
        pipelines:             [Blend_Mode]vk.Pipeline,
        pipeline_layout:       vk.PipelineLayout,
        descriptor_set_layout: vk.DescriptorSetLayout,

        // Whether this shader uses push constants for view_projection
        uses_push_constants:   bool,

        // Uniform buffer info
        ubo_size:              int,
        ubo_binding:           u32,

        // Texture binding count
        texture_binding_count: int,

        // Vertex stride
        vertex_stride:         int,
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

        // Dynamic vertex buffers (one per frame-in-flight to avoid write-after-read hazards)
        vertex_buffers:        [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
        vertex_buffer_memories: [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
        vertex_buffer_mapped:  [MAX_FRAMES_IN_FLIGHT]rawptr,

        // Staging buffer for texture uploads
        staging_buffer:        vk.Buffer,
        staging_buffer_memory: vk.DeviceMemory,
        staging_buffer_mapped: rawptr,
        staging_buffer_size:   int,

        // Descriptor pool (reset each frame)
        descriptor_pools: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorPool,

        // Default sampler (nearest-neighbor)
        default_sampler:       vk.Sampler,
        default_linear_sampler: vk.Sampler,

        // A 1x1 white texture used when no texture is bound
        white_texture_image:   vk.Image,
        white_texture_memory:  vk.DeviceMemory,
        white_texture_view:    vk.ImageView,

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

        // 11. Create vertex buffers (Phase 2)
        if !vk_create_vertex_buffers() {
                log.error("Vulkan: Failed to create vertex buffers")
                return
        }

        // 12. Create staging buffer (Phase 2)
        if !vk_create_staging_buffer() {
                log.error("Vulkan: Failed to create staging buffer")
                return
        }

        // 13. Create descriptor pools (Phase 2)
        if !vk_create_descriptor_pools() {
                log.error("Vulkan: Failed to create descriptor pools")
                return
        }

        // 14. Create default samplers (Phase 2)
        if !vk_create_default_samplers() {
                log.error("Vulkan: Failed to create default samplers")
                return
        }

        // 15. Create 1x1 white texture for untextured draws (Phase 2)
        if !vk_create_white_texture() {
                log.error("Vulkan: Failed to create white texture")
                return
        }

        log.info("Vulkan: Initialization complete (Phase 2)")
}

// ---------------------------------------------------------------------------
// Shutdown
// ---------------------------------------------------------------------------

vk_shutdown :: proc() {
        if s == nil { return }
        if s.device != nil {
                vk.DeviceWaitIdle(s.device)
        }

        // Destroy white texture
        if s.white_texture_view != 0 {
                vk.DestroyImageView(s.device, s.white_texture_view, nil)
        }
        if s.white_texture_image != 0 {
                vk.DestroyImage(s.device, s.white_texture_image, nil)
        }
        if s.white_texture_memory != 0 {
                vk.FreeMemory(s.device, s.white_texture_memory, nil)
        }

        // Destroy default samplers
        if s.default_sampler != 0 {
                vk.DestroySampler(s.device, s.default_sampler, nil)
        }
        if s.default_linear_sampler != 0 {
                vk.DestroySampler(s.device, s.default_linear_sampler, nil)
        }

        // Destroy descriptor pools
        for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
                if s.descriptor_pools[i] != 0 {
                        vk.DestroyDescriptorPool(s.device, s.descriptor_pools[i], nil)
                }
        }

        // Destroy staging buffer
        if s.staging_buffer_mapped != nil && s.staging_buffer_memory != 0 {
                vk.UnmapMemory(s.device, s.staging_buffer_memory)
        }
        if s.staging_buffer != 0 {
                vk.DestroyBuffer(s.device, s.staging_buffer, nil)
        }
        if s.staging_buffer_memory != 0 {
                vk.FreeMemory(s.device, s.staging_buffer_memory, nil)
        }

        // Destroy vertex buffers
        for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
                if s.vertex_buffer_mapped[i] != nil && s.vertex_buffer_memories[i] != 0 {
                        vk.UnmapMemory(s.device, s.vertex_buffer_memories[i])
                }
                if s.vertex_buffers[i] != 0 {
                        vk.DestroyBuffer(s.device, s.vertex_buffers[i], nil)
                }
                if s.vertex_buffer_memories[i] != 0 {
                        vk.FreeMemory(s.device, s.vertex_buffer_memories[i], nil)
                }
        }

        // Destroy all managed textures
        {
                tex_iter := hm.dynamic_iterator_make(&s.textures)
                for {
                        tex, _, ok := hm.dynamic_iterate(&tex_iter)
                        if !ok { break }
                        vk_destroy_texture_resources(tex)
                }
        }

        // Destroy all managed shaders
        {
                shd_iter := hm.dynamic_iterator_make(&s.shaders)
                for {
                        shd, _, ok := hm.dynamic_iterate(&shd_iter)
                        if !ok { break }
                        vk_destroy_shader_resources(shd)
                }
        }

        // Destroy all managed render targets
        {
                rt_iter := hm.dynamic_iterator_make(&s.render_targets)
                for {
                        rt, _, ok := hm.dynamic_iterate(&rt_iter)
                        if !ok { break }
                        vk_destroy_render_target_resources(rt)
                }
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
        append(&extensions, cstring("VK_KHR_surface"))

        when ODIN_OS == .Linux {
                append(&extensions, cstring("VK_KHR_wayland_surface"))
                append(&extensions, cstring("VK_KHR_xlib_surface"))
        } else when ODIN_OS == .Windows {
                append(&extensions, cstring("VK_KHR_win32_surface"))
        }

        when ODIN_DEBUG {
                append(&extensions, cstring("VK_EXT_debug_utils"))
        }

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
                return false
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

        return vk_find_queue_families(s.physical_device)
}

vk_rate_physical_device :: proc(device: vk.PhysicalDevice) -> int {
        props: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(device, &props)

        if !vk_device_supports_extensions(device) {
                return -1
        }

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

        device_features: vk.PhysicalDeviceFeatures

        swapchain_ext: cstring = "VK_KHR_swapchain"
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
        for f in formats {
                if f.format == .B8G8R8A8_UNORM && f.colorSpace == .SRGB_NONLINEAR {
                        return f
                }
        }
        return formats[0]
}

vk_choose_swap_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
        return .FIFO
}

vk_choose_swap_extent :: proc(capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
        if capabilities.currentExtent.width != max(u32) {
                return capabilities.currentExtent
        }
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

        actual_count: u32
        vk.GetSwapchainImagesKHR(s.device, s.swapchain, &actual_count, nil)
        s.swapchain_images = make([]vk.Image, actual_count, s.allocator)
        vk.GetSwapchainImagesKHR(s.device, s.swapchain, &actual_count, raw_data(s.swapchain_images))

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
                flags = {.SIGNALED},
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
// Vertex buffer management (Phase 2)
// ---------------------------------------------------------------------------

vk_create_vertex_buffers :: proc() -> bool {
        for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
                buf, buf_mem, mapped := vk_create_buffer(
                        VERTEX_BUFFER_MAX,
                        {.VERTEX_BUFFER},
                        {.HOST_VISIBLE, .HOST_COHERENT},
                        map_memory = true,
                )
                if buf == 0 {
                        log.error("Vulkan: Failed to create vertex buffer")
                        return false
                }
                s.vertex_buffers[i] = buf
                s.vertex_buffer_memories[i] = buf_mem
                s.vertex_buffer_mapped[i] = mapped
        }
        return true
}

// ---------------------------------------------------------------------------
// Staging buffer for texture uploads (Phase 2)
// ---------------------------------------------------------------------------

vk_create_staging_buffer :: proc() -> bool {
        s.staging_buffer_size = STAGING_BUFFER_SIZE
        buf, buf_mem, mapped := vk_create_buffer(
                s.staging_buffer_size,
                {.TRANSFER_SRC},
                {.HOST_VISIBLE, .HOST_COHERENT},
                map_memory = true,
        )
        if buf == 0 {
                log.error("Vulkan: Failed to create staging buffer")
                return false
        }
        s.staging_buffer = buf
        s.staging_buffer_memory = buf_mem
        s.staging_buffer_mapped = mapped
        return true
}

// ---------------------------------------------------------------------------
// Descriptor pools (Phase 2)
// ---------------------------------------------------------------------------

vk_create_descriptor_pools :: proc() -> bool {
        pool_sizes := [2]vk.DescriptorPoolSize {
                {
                        type            = .COMBINED_IMAGE_SAMPLER,
                        descriptorCount = MAX_DESCRIPTOR_SETS_PER_FRAME * 4, // up to 4 textures per draw
                },
                {
                        type            = .UNIFORM_BUFFER,
                        descriptorCount = MAX_DESCRIPTOR_SETS_PER_FRAME,
                },
        }

        for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
                pool_info := vk.DescriptorPoolCreateInfo {
                        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
                        maxSets       = MAX_DESCRIPTOR_SETS_PER_FRAME,
                        poolSizeCount = len(pool_sizes),
                        pPoolSizes    = &pool_sizes[0],
                }

                result := vk.CreateDescriptorPool(s.device, &pool_info, nil, &s.descriptor_pools[i])
                if result != .SUCCESS {
                        log.errorf("Vulkan: Failed to create descriptor pool %d (%v)", i, result)
                        return false
                }
        }
        return true
}

// ---------------------------------------------------------------------------
// Default samplers (Phase 2)
// ---------------------------------------------------------------------------

vk_create_default_samplers :: proc() -> bool {
        // Nearest-neighbor sampler (default for 2D pixel art)
        sampler_info := vk.SamplerCreateInfo {
                sType        = .SAMPLER_CREATE_INFO,
                magFilter    = .NEAREST,
                minFilter    = .NEAREST,
                addressModeU = .REPEAT,
                addressModeV = .REPEAT,
                addressModeW = .REPEAT,
                mipmapMode   = .NEAREST,
                maxLod       = 0,
        }

        result := vk.CreateSampler(s.device, &sampler_info, nil, &s.default_sampler)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create default sampler (%v)", result)
                return false
        }

        // Linear sampler
        sampler_info.magFilter = .LINEAR
        sampler_info.minFilter = .LINEAR

        result = vk.CreateSampler(s.device, &sampler_info, nil, &s.default_linear_sampler)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create linear sampler (%v)", result)
                return false
        }

        return true
}

// ---------------------------------------------------------------------------
// 1x1 white texture (used for untextured/shape draws) (Phase 2)
// ---------------------------------------------------------------------------

vk_create_white_texture :: proc() -> bool {
        // Create a 1x1 RGBA white pixel
        white_pixel := [4]u8{255, 255, 255, 255}

        // Create the image
        img_info := vk.ImageCreateInfo {
                sType       = .IMAGE_CREATE_INFO,
                imageType   = .D2,
                format      = .R8G8B8A8_UNORM,
                extent      = {width = 1, height = 1, depth = 1},
                mipLevels   = 1,
                arrayLayers = 1,
                samples     = {._1},
                tiling      = .OPTIMAL,
                usage       = {.SAMPLED, .TRANSFER_DST},
                initialLayout = .UNDEFINED,
        }

        result := vk.CreateImage(s.device, &img_info, nil, &s.white_texture_image)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create white texture image (%v)", result)
                return false
        }

        // Allocate memory
        mem_req: vk.MemoryRequirements
        vk.GetImageMemoryRequirements(s.device, s.white_texture_image, &mem_req)

        mem_type_idx := vk_find_memory_type(mem_req.memoryTypeBits, {.DEVICE_LOCAL})
        if mem_type_idx < 0 {
                log.error("Vulkan: Failed to find memory type for white texture")
                return false
        }

        alloc_info := vk.MemoryAllocateInfo {
                sType           = .MEMORY_ALLOCATE_INFO,
                allocationSize  = mem_req.size,
                memoryTypeIndex = u32(mem_type_idx),
        }

        result = vk.AllocateMemory(s.device, &alloc_info, nil, &s.white_texture_memory)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to allocate white texture memory (%v)", result)
                return false
        }

        vk.BindImageMemory(s.device, s.white_texture_image, s.white_texture_memory, 0)

        // Upload pixel data via staging buffer
        dst := ([^]u8)(s.staging_buffer_mapped)
        mem.copy(dst, &white_pixel[0], 4)

        // Transition + copy + transition
        vk_immediate_submit(proc(cmd: vk.CommandBuffer) {
                // Transition to TRANSFER_DST_OPTIMAL
                barrier := vk.ImageMemoryBarrier {
                        sType               = .IMAGE_MEMORY_BARRIER,
                        srcAccessMask       = {},
                        dstAccessMask       = {.TRANSFER_WRITE},
                        oldLayout           = .UNDEFINED,
                        newLayout           = .TRANSFER_DST_OPTIMAL,
                        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                        image               = s.white_texture_image,
                        subresourceRange    = {
                                aspectMask     = {.COLOR},
                                baseMipLevel   = 0,
                                levelCount     = 1,
                                baseArrayLayer = 0,
                                layerCount     = 1,
                        },
                }
                vk.CmdPipelineBarrier(cmd, {.TOP_OF_PIPE}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

                // Copy from staging buffer
                region := vk.BufferImageCopy {
                        bufferOffset      = 0,
                        bufferRowLength   = 0,
                        bufferImageHeight = 0,
                        imageSubresource  = {
                                aspectMask     = {.COLOR},
                                mipLevel       = 0,
                                baseArrayLayer = 0,
                                layerCount     = 1,
                        },
                        imageOffset = {0, 0, 0},
                        imageExtent = {1, 1, 1},
                }
                vk.CmdCopyBufferToImage(cmd, s.staging_buffer, s.white_texture_image, .TRANSFER_DST_OPTIMAL, 1, &region)

                // Transition to SHADER_READ_ONLY_OPTIMAL
                barrier.srcAccessMask = {.TRANSFER_WRITE}
                barrier.dstAccessMask = {.SHADER_READ}
                barrier.oldLayout = .TRANSFER_DST_OPTIMAL
                barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
                vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
        })

        // Create image view
        view_info := vk.ImageViewCreateInfo {
                sType    = .IMAGE_VIEW_CREATE_INFO,
                image    = s.white_texture_image,
                viewType = .D2,
                format   = .R8G8B8A8_UNORM,
                components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
                subresourceRange = {
                        aspectMask     = {.COLOR},
                        baseMipLevel   = 0,
                        levelCount     = 1,
                        baseArrayLayer = 0,
                        layerCount     = 1,
                },
        }

        result = vk.CreateImageView(s.device, &view_info, nil, &s.white_texture_view)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create white texture image view (%v)", result)
                return false
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

        vk_destroy_swapchain_framebuffers()
        vk_destroy_swapchain_resources()

        old_swapchain := s.swapchain
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
// Clear / Present / Draw
// ---------------------------------------------------------------------------

vk_clear :: proc(render_target: Render_Target_Handle, color: Color) {
        if s == nil { return }

        // Wait for the previous frame using this slot to finish
        vk.WaitForFences(s.device, 1, &s.in_flight_fences[s.current_frame], true, max(u64))
        vk.ResetFences(s.device, 1, &s.in_flight_fences[s.current_frame])

        // Reset the descriptor pool for this frame
        vk.ResetDescriptorPool(s.device, s.descriptor_pools[s.current_frame], {})

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
        if s == nil { return }
        if len(vertex_buffer) == 0 { return }

        vk_shd := hm.get(&s.shaders, shd.handle)
        if vk_shd == nil { return }

        cmd := s.command_buffers[s.current_frame]

        // Ensure we are in a render pass
        if !s.in_render_pass { return }

        // 1. Copy vertex data to the mapped vertex buffer for this frame
        vb_mapped := s.vertex_buffer_mapped[s.current_frame]
        if vb_mapped != nil {
                mem.copy(vb_mapped, raw_data(vertex_buffer), len(vertex_buffer))
        }

        // 2. Bind the pipeline for this shader + blend mode
        pipeline := vk_shd.pipelines[blend_mode]
        if pipeline == 0 { return }
        vk.CmdBindPipeline(cmd, .GRAPHICS, pipeline)

        // 3. Set dynamic viewport
        viewport_width:  f32
        viewport_height: f32
        rt := hm.get(&s.render_targets, render_target)
        if rt != nil {
                viewport_width  = f32(rt.width)
                viewport_height = f32(rt.height)
        } else {
                viewport_width  = f32(s.swapchain_extent.width)
                viewport_height = f32(s.swapchain_extent.height)
        }

        viewport := vk.Viewport {
                x        = 0,
                y        = 0,
                width    = viewport_width,
                height   = viewport_height,
                minDepth = 0,
                maxDepth = 1,
        }
        vk.CmdSetViewport(cmd, 0, 1, &viewport)

        // 4. Set dynamic scissor
        if scissor_rect, has_scissor := scissor.(Rect); has_scissor {
                sc := vk.Rect2D {
                        offset = {i32(scissor_rect.x), i32(scissor_rect.y)},
                        extent = {u32(scissor_rect.w), u32(scissor_rect.h)},
                }
                vk.CmdSetScissor(cmd, 0, 1, &sc)
        } else {
                sc := vk.Rect2D {
                        offset = {0, 0},
                        extent = {u32(viewport_width), u32(viewport_height)},
                }
                vk.CmdSetScissor(cmd, 0, 1, &sc)
        }

        // 5. Push constants (view_projection matrix)
        if vk_shd.uses_push_constants && len(shd.constants) > 0 {
                // Push all constants data as push constants (up to 128 bytes minimum guaranteed)
                push_size := min(len(shd.constants_data), 128)
                if push_size > 0 {
                        vk.CmdPushConstants(
                                cmd,
                                vk_shd.pipeline_layout,
                                {.VERTEX},
                                0,
                                u32(push_size),
                                raw_data(shd.constants_data),
                        )
                }
        }

        // 6. Allocate and update descriptor set for texture bindings
        desc_set: vk.DescriptorSet
        alloc_info := vk.DescriptorSetAllocateInfo {
                sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
                descriptorPool     = s.descriptor_pools[s.current_frame],
                descriptorSetCount = 1,
                pSetLayouts        = &vk_shd.descriptor_set_layout,
        }

        result := vk.AllocateDescriptorSets(s.device, &alloc_info, &desc_set)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to allocate descriptor set (%v)", result)
                return
        }

        // Write texture descriptors
        // We support up to 4 texture bindings; use white texture as fallback
        MAX_TEX_BINDINGS :: 4
        image_infos: [MAX_TEX_BINDINGS]vk.DescriptorImageInfo
        writes := make([dynamic]vk.WriteDescriptorSet, 0, MAX_TEX_BINDINGS, context.temp_allocator)

        tex_count := min(vk_shd.texture_binding_count, len(bound_textures), MAX_TEX_BINDINGS)
        if tex_count == 0 { tex_count = 1 } // Always bind at least one texture (the white tex)

        for i in 0 ..< tex_count {
                tex_view := s.white_texture_view
                tex_sampler := s.default_sampler

                if i < len(bound_textures) {
                        if vk_tex := hm.get(&s.textures, bound_textures[i]); vk_tex != nil {
                                tex_view = vk_tex.view
                                tex_sampler = vk_tex.sampler
                        }
                }

                image_infos[i] = vk.DescriptorImageInfo {
                        sampler     = tex_sampler,
                        imageView   = tex_view,
                        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
                }

                append(&writes, vk.WriteDescriptorSet {
                        sType           = .WRITE_DESCRIPTOR_SET,
                        dstSet          = desc_set,
                        dstBinding      = u32(i),
                        dstArrayElement = 0,
                        descriptorCount = 1,
                        descriptorType  = .COMBINED_IMAGE_SAMPLER,
                        pImageInfo      = &image_infos[i],
                })
        }

        if len(writes) > 0 {
                vk.UpdateDescriptorSets(s.device, u32(len(writes)), raw_data(writes[:]), 0, nil)
        }

        vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vk_shd.pipeline_layout, 0, 1, &desc_set, 0, nil)

        // 7. Bind vertex buffer
        vb := s.vertex_buffers[s.current_frame]
        offset := vk.DeviceSize(0)
        vk.CmdBindVertexBuffers(cmd, 0, 1, &vb, &offset)

        // 8. Draw
        vertex_count := u32(len(vertex_buffer) / shd.vertex_size) if shd.vertex_size > 0 else 0
        if vertex_count > 0 {
                vk.CmdDraw(cmd, vertex_count, 1, 0, 0)
        }
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
// Texture implementation (Phase 2)
// ---------------------------------------------------------------------------

vk_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
        tex := vk_create_texture_internal(width, height, format, nil)
        if tex.image == 0 { return {} }

        handle, err := hm.add(&s.textures, tex)
        if err != nil {
                log.errorf("Vulkan: Failed to add texture to handle map: %v", err)
                vk_destroy_texture_resources(&tex)
                return {}
        }
        return handle
}

vk_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
        tex := vk_create_texture_internal(width, height, format, data)
        if tex.image == 0 { return {} }

        handle, err := hm.add(&s.textures, tex)
        if err != nil {
                log.errorf("Vulkan: Failed to add texture to handle map: %v", err)
                vk_destroy_texture_resources(&tex)
                return {}
        }
        return handle
}

vk_create_texture_internal :: proc(width: int, height: int, format: Pixel_Format, data: []u8) -> Vulkan_Texture {
        tex: Vulkan_Texture
        tex.width = width
        tex.height = height
        tex.format = format
        tex.sampler = s.default_sampler

        vk_format := vk_translate_pixel_format(format)

        // Create image
        img_info := vk.ImageCreateInfo {
                sType       = .IMAGE_CREATE_INFO,
                imageType   = .D2,
                format      = vk_format,
                extent      = {width = u32(width), height = u32(height), depth = 1},
                mipLevels   = 1,
                arrayLayers = 1,
                samples     = {._1},
                tiling      = .OPTIMAL,
                usage       = {.SAMPLED, .TRANSFER_DST},
                initialLayout = .UNDEFINED,
        }

        result := vk.CreateImage(s.device, &img_info, nil, &tex.image)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create image (%v)", result)
                return tex
        }

        // Allocate device-local memory
        mem_req: vk.MemoryRequirements
        vk.GetImageMemoryRequirements(s.device, tex.image, &mem_req)

        mem_type_idx := vk_find_memory_type(mem_req.memoryTypeBits, {.DEVICE_LOCAL})
        if mem_type_idx < 0 {
                log.error("Vulkan: Failed to find device-local memory type for texture")
                vk.DestroyImage(s.device, tex.image, nil)
                tex.image = 0
                return tex
        }

        alloc_info := vk.MemoryAllocateInfo {
                sType           = .MEMORY_ALLOCATE_INFO,
                allocationSize  = mem_req.size,
                memoryTypeIndex = u32(mem_type_idx),
        }

        result = vk.AllocateMemory(s.device, &alloc_info, nil, &tex.memory)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to allocate texture memory (%v)", result)
                vk.DestroyImage(s.device, tex.image, nil)
                tex.image = 0
                return tex
        }

        vk.BindImageMemory(s.device, tex.image, tex.memory, 0)

        // If data provided, upload via staging buffer
        if data != nil && len(data) > 0 {
                vk_upload_texture_data(&tex, data, 0, 0, width, height)
        } else {
                // Just transition layout to SHADER_READ_ONLY
                tex_image := tex.image
                vk_immediate_submit(proc(cmd: vk.CommandBuffer) {
                        barrier := vk.ImageMemoryBarrier {
                                sType               = .IMAGE_MEMORY_BARRIER,
                                srcAccessMask       = {},
                                dstAccessMask       = {.SHADER_READ},
                                oldLayout           = .UNDEFINED,
                                newLayout           = .SHADER_READ_ONLY_OPTIMAL,
                                srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                                dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                                image               = _immediate_submit_image,
                                subresourceRange    = {
                                        aspectMask     = {.COLOR},
                                        baseMipLevel   = 0,
                                        levelCount     = 1,
                                        baseArrayLayer = 0,
                                        layerCount     = 1,
                                },
                        }
                        vk.CmdPipelineBarrier(cmd, {.TOP_OF_PIPE}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
                }, tex.image)
        }
        tex.layout = .SHADER_READ_ONLY_OPTIMAL

        // Create image view
        view_info := vk.ImageViewCreateInfo {
                sType    = .IMAGE_VIEW_CREATE_INFO,
                image    = tex.image,
                viewType = .D2,
                format   = vk_format,
                components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
                subresourceRange = {
                        aspectMask     = {.COLOR},
                        baseMipLevel   = 0,
                        levelCount     = 1,
                        baseArrayLayer = 0,
                        layerCount     = 1,
                },
        }

        result = vk.CreateImageView(s.device, &view_info, nil, &tex.view)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create image view (%v)", result)
                vk.FreeMemory(s.device, tex.memory, nil)
                vk.DestroyImage(s.device, tex.image, nil)
                tex.image = 0
                return tex
        }

        return tex
}

vk_upload_texture_data :: proc(tex: ^Vulkan_Texture, data: []u8, x, y, w, h: int) {
        data_size := len(data)
        if data_size > s.staging_buffer_size {
                log.errorf("Vulkan: Texture data (%d bytes) exceeds staging buffer size (%d)", data_size, s.staging_buffer_size)
                return
        }

        // Copy to staging buffer
        dst := ([^]u8)(s.staging_buffer_mapped)
        mem.copy(dst, raw_data(data), data_size)

        // Record and submit transfer commands
        img := tex.image
        bx := i32(x)
        by := i32(y)
        bw := u32(w)
        bh := u32(h)

        vk_immediate_submit(proc(cmd: vk.CommandBuffer) {
                // Transition to TRANSFER_DST_OPTIMAL
                barrier := vk.ImageMemoryBarrier {
                        sType               = .IMAGE_MEMORY_BARRIER,
                        srcAccessMask       = {.SHADER_READ},
                        dstAccessMask       = {.TRANSFER_WRITE},
                        oldLayout           = .UNDEFINED,
                        newLayout           = .TRANSFER_DST_OPTIMAL,
                        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                        image               = _immediate_submit_image,
                        subresourceRange    = {
                                aspectMask     = {.COLOR},
                                baseMipLevel   = 0,
                                levelCount     = 1,
                                baseArrayLayer = 0,
                                layerCount     = 1,
                        },
                }
                vk.CmdPipelineBarrier(cmd, {.FRAGMENT_SHADER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

                // Copy buffer to image
                region := vk.BufferImageCopy {
                        bufferOffset      = 0,
                        bufferRowLength   = 0,
                        bufferImageHeight = 0,
                        imageSubresource  = {
                                aspectMask     = {.COLOR},
                                mipLevel       = 0,
                                baseArrayLayer = 0,
                                layerCount     = 1,
                        },
                        imageOffset = {_immediate_submit_offset_x, _immediate_submit_offset_y, 0},
                        imageExtent = {_immediate_submit_width, _immediate_submit_height, 1},
                }
                vk.CmdCopyBufferToImage(cmd, s.staging_buffer, _immediate_submit_image, .TRANSFER_DST_OPTIMAL, 1, &region)

                // Transition to SHADER_READ_ONLY_OPTIMAL
                barrier.srcAccessMask = {.TRANSFER_WRITE}
                barrier.dstAccessMask = {.SHADER_READ}
                barrier.oldLayout = .TRANSFER_DST_OPTIMAL
                barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
                vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
        }, img, bx, by, bw, bh)
}

vk_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
        tex := hm.get(&s.textures, th)
        if tex == nil { return false }

        vk_upload_texture_data(tex, data, int(rect.x), int(rect.y), int(rect.w), int(rect.h))
        return true
}

vk_destroy_texture :: proc(th: Texture_Handle) {
        tex := hm.get(&s.textures, th)
        if tex == nil { return }

        // Wait for any in-flight commands to complete before destroying
        vk.DeviceWaitIdle(s.device)

        vk_destroy_texture_resources(tex)
        hm.remove(&s.textures, th)
}

vk_destroy_texture_resources :: proc(tex: ^Vulkan_Texture) {
        if tex.view != 0 {
                vk.DestroyImageView(s.device, tex.view, nil)
        }
        if tex.image != 0 {
                vk.DestroyImage(s.device, tex.image, nil)
        }
        if tex.memory != 0 {
                vk.FreeMemory(s.device, tex.memory, nil)
        }
        // Don't destroy sampler here - it's shared (default_sampler)
        // Custom samplers are handled separately
}

vk_texture_needs_vertical_flip :: proc(th: Texture_Handle) -> bool {
        // Vulkan does not need the GL vertical flip hack
        tex := hm.get(&s.textures, th)
        if tex == nil { return false }
        return tex.needs_vertical_flip
}

vk_set_texture_filter :: proc(
        th: Texture_Handle,
        scale_down_filter: Texture_Filter,
        scale_up_filter: Texture_Filter,
        mip_filter: Texture_Filter,
) {
        tex := hm.get(&s.textures, th)
        if tex == nil {
                log.error("Vulkan: Trying to set texture filter for invalid texture")
                return
        }

        // Use the pre-created samplers
        if scale_down_filter == .Linear || scale_up_filter == .Linear {
                tex.sampler = s.default_linear_sampler
        } else {
                tex.sampler = s.default_sampler
        }
}

// ---------------------------------------------------------------------------
// Render texture (Phase 3 stub — minimal implementation)
// ---------------------------------------------------------------------------

vk_create_render_texture :: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle) {
        log.warn("Vulkan: create_render_texture not yet fully implemented (Phase 3)")
        return {}, {}
}

vk_destroy_render_target :: proc(render_target: Render_Target_Handle) {
        rt := hm.get(&s.render_targets, render_target)
        if rt == nil { return }

        vk.DeviceWaitIdle(s.device)
        vk_destroy_render_target_resources(rt)
        hm.remove(&s.render_targets, render_target)
}

vk_destroy_render_target_resources :: proc(rt: ^Vulkan_Render_Target) {
        if rt.framebuffer != 0 {
                vk.DestroyFramebuffer(s.device, rt.framebuffer, nil)
        }
        if rt.render_pass != 0 {
                vk.DestroyRenderPass(s.device, rt.render_pass, nil)
        }
        if rt.view != 0 {
                vk.DestroyImageView(s.device, rt.view, nil)
        }
        if rt.image != 0 {
                vk.DestroyImage(s.device, rt.image, nil)
        }
        if rt.memory != 0 {
                vk.FreeMemory(s.device, rt.memory, nil)
        }
}

// ---------------------------------------------------------------------------
// Shader implementation (Phase 2)
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
        if len(vs_source) == 0 || len(fs_source) == 0 {
                log.error("Vulkan: Shader source is empty")
                return {}, {}
        }

        vk_shd: Vulkan_Shader

        // Create shader modules from SPIR-V bytecode
        vs_ok: bool
        vk_shd.vertex_module, vs_ok = vk_create_shader_module(vs_source)
        if !vs_ok {
                log.error("Vulkan: Failed to create vertex shader module")
                return {}, {}
        }

        fs_ok: bool
        vk_shd.fragment_module, fs_ok = vk_create_shader_module(fs_source)
        if !fs_ok {
                log.error("Vulkan: Failed to create fragment shader module")
                vk.DestroyShaderModule(s.device, vk_shd.vertex_module, nil)
                return {}, {}
        }

        // For the default shader, we use a hardcoded layout:
        // - Push constants: mat4 view_projection (64 bytes) at vertex stage
        // - Descriptor set 0, binding 0: sampler2D tex
        // - Vertex inputs: position (vec2), texcoord (vec2), color (vec4 normalized u8)
        vk_shd.uses_push_constants = true
        vk_shd.texture_binding_count = 1

        // Build descriptor set layout: one combined image sampler at binding 0
        sampler_binding := vk.DescriptorSetLayoutBinding {
                binding         = 0,
                descriptorType  = .COMBINED_IMAGE_SAMPLER,
                descriptorCount = 1,
                stageFlags      = {.FRAGMENT},
        }

        ds_layout_info := vk.DescriptorSetLayoutCreateInfo {
                sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                bindingCount = 1,
                pBindings    = &sampler_binding,
        }

        result := vk.CreateDescriptorSetLayout(s.device, &ds_layout_info, nil, &vk_shd.descriptor_set_layout)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create descriptor set layout (%v)", result)
                vk.DestroyShaderModule(s.device, vk_shd.vertex_module, nil)
                vk.DestroyShaderModule(s.device, vk_shd.fragment_module, nil)
                return {}, {}
        }

        // Push constant range: 64 bytes for mat4 view_projection
        push_constant_range := vk.PushConstantRange {
                stageFlags = {.VERTEX},
                offset     = 0,
                size       = 64, // size_of(mat4)
        }

        pipeline_layout_info := vk.PipelineLayoutCreateInfo {
                sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
                setLayoutCount         = 1,
                pSetLayouts            = &vk_shd.descriptor_set_layout,
                pushConstantRangeCount = 1,
                pPushConstantRanges    = &push_constant_range,
        }

        result = vk.CreatePipelineLayout(s.device, &pipeline_layout_info, nil, &vk_shd.pipeline_layout)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create pipeline layout (%v)", result)
                vk.DestroyDescriptorSetLayout(s.device, vk_shd.descriptor_set_layout, nil)
                vk.DestroyShaderModule(s.device, vk_shd.vertex_module, nil)
                vk.DestroyShaderModule(s.device, vk_shd.fragment_module, nil)
                return {}, {}
        }

        // Set up vertex input description
        // Default vertex format: position (vec2, RG_32_Float) + texcoord (vec2, RG_32_Float) + color (vec4, RGBA_8_Norm)
        // Stride: 8 + 8 + 4 = 20 bytes
        desc.inputs = make([]Shader_Input, 3, desc_allocator)
        desc.inputs[0] = {name = strings.clone("position", desc_allocator), register = 0, type = .Vec2, format = .RG_32_Float}
        desc.inputs[1] = {name = strings.clone("texcoord", desc_allocator), register = 1, type = .Vec2, format = .RG_32_Float}
        desc.inputs[2] = {name = strings.clone("color", desc_allocator), register = 2, type = .Vec4, format = .RGBA_8_Norm}

        if len(layout_formats) >= 3 {
                desc.inputs[0].format = layout_formats[0]
                desc.inputs[1].format = layout_formats[1]
                desc.inputs[2].format = layout_formats[2]
        }

        stride: int
        for input in desc.inputs {
                stride += pixel_format_size(input.format)
        }
        vk_shd.vertex_stride = stride

        // Build Vulkan vertex input attribute descriptions
        binding_desc := vk.VertexInputBindingDescription {
                binding   = 0,
                stride    = u32(stride),
                inputRate = .VERTEX,
        }

        attr_descs: [3]vk.VertexInputAttributeDescription
        offset: u32 = 0
        for input, i in desc.inputs {
                attr_descs[i] = vk.VertexInputAttributeDescription {
                        location = u32(input.register),
                        binding  = 0,
                        format   = vk_translate_shader_input_format(input.format),
                        offset   = offset,
                }
                offset += u32(pixel_format_size(input.format))
        }

        // Create graphics pipelines for each blend mode
        for blend_mode in Blend_Mode {
                pipeline := vk_create_graphics_pipeline(
                        &vk_shd,
                        &binding_desc,
                        attr_descs[:len(desc.inputs)],
                        blend_mode,
                )
                vk_shd.pipelines[blend_mode] = pipeline
        }

        // Set up shader desc constants (push constants exposed as "view_projection")
        desc.constants = make([]Shader_Constant_Desc, 1, desc_allocator)
        desc.constants[0] = {
                name = strings.clone("view_projection", desc_allocator),
                size = 64, // mat4
        }

        // Set up texture bindpoints
        desc.texture_bindpoints = make([]Shader_Texture_Bindpoint_Desc, 1, desc_allocator)
        desc.texture_bindpoints[0] = {
                name = strings.clone("tex", desc_allocator),
        }

        // Add to handle map
        shader_handle, add_err := hm.add(&s.shaders, vk_shd)
        if add_err != nil {
                log.errorf("Vulkan: Failed to add shader to handle map: %v", add_err)
                vk_destroy_shader_resources(&vk_shd)
                return SHADER_NONE, {}
        }

        return shader_handle, desc
}

vk_create_shader_module :: proc(code: []byte) -> (vk.ShaderModule, bool) {
        // SPIR-V must be aligned to 4 bytes and length must be multiple of 4
        if len(code) % 4 != 0 {
                log.error("Vulkan: SPIR-V code size is not a multiple of 4")
                return 0, false
        }

        create_info := vk.ShaderModuleCreateInfo {
                sType    = .SHADER_MODULE_CREATE_INFO,
                codeSize = len(code),
                pCode    = (^u32)(raw_data(code)),
        }

        mod: vk.ShaderModule
        result := vk.CreateShaderModule(s.device, &create_info, nil, &mod)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create shader module (%v)", result)
                return 0, false
        }

        return mod, true
}

vk_create_graphics_pipeline :: proc(
        shd: ^Vulkan_Shader,
        binding_desc: ^vk.VertexInputBindingDescription,
        attr_descs: []vk.VertexInputAttributeDescription,
        blend_mode: Blend_Mode,
) -> vk.Pipeline {
        // Shader stages
        shader_stages := [2]vk.PipelineShaderStageCreateInfo {
                {
                        sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
                        stage  = {.VERTEX},
                        module = shd.vertex_module,
                        pName  = "main",
                },
                {
                        sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
                        stage  = {.FRAGMENT},
                        module = shd.fragment_module,
                        pName  = "main",
                },
        }

        // Vertex input state
        vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
                sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                vertexBindingDescriptionCount   = 1,
                pVertexBindingDescriptions      = binding_desc,
                vertexAttributeDescriptionCount = u32(len(attr_descs)),
                pVertexAttributeDescriptions    = raw_data(attr_descs),
        }

        // Input assembly
        input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
                sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                topology = .TRIANGLE_LIST,
        }

        // Viewport state (dynamic)
        viewport_state := vk.PipelineViewportStateCreateInfo {
                sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                viewportCount = 1,
                scissorCount  = 1,
        }

        // Rasterization
        rasterizer := vk.PipelineRasterizationStateCreateInfo {
                sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                polygonMode = .FILL,
                cullMode    = {},    // No culling for 2D
                frontFace   = .COUNTER_CLOCKWISE,
                lineWidth   = 1.0,
        }

        // Multisampling (no MSAA)
        multisampling := vk.PipelineMultisampleStateCreateInfo {
                sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                rasterizationSamples = {._1},
        }

        // Color blending
        color_blend_attachment: vk.PipelineColorBlendAttachmentState

        switch blend_mode {
        case .Alpha:
                color_blend_attachment = vk.PipelineColorBlendAttachmentState {
                        blendEnable         = true,
                        srcColorBlendFactor = .SRC_ALPHA,
                        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
                        colorBlendOp        = .ADD,
                        srcAlphaBlendFactor = .ONE,
                        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
                        alphaBlendOp        = .ADD,
                        colorWriteMask      = {.R, .G, .B, .A},
                }
        case .Premultiplied_Alpha:
                color_blend_attachment = vk.PipelineColorBlendAttachmentState {
                        blendEnable         = true,
                        srcColorBlendFactor = .ONE,
                        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
                        colorBlendOp        = .ADD,
                        srcAlphaBlendFactor = .ONE,
                        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
                        alphaBlendOp        = .ADD,
                        colorWriteMask      = {.R, .G, .B, .A},
                }
        }

        color_blending := vk.PipelineColorBlendStateCreateInfo {
                sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                attachmentCount = 1,
                pAttachments    = &color_blend_attachment,
        }

        // Dynamic state
        dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
        dynamic_state := vk.PipelineDynamicStateCreateInfo {
                sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                dynamicStateCount = len(dynamic_states),
                pDynamicStates    = &dynamic_states[0],
        }

        pipeline_info := vk.GraphicsPipelineCreateInfo {
                sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
                stageCount          = len(shader_stages),
                pStages             = &shader_stages[0],
                pVertexInputState   = &vertex_input_info,
                pInputAssemblyState = &input_assembly,
                pViewportState      = &viewport_state,
                pRasterizationState = &rasterizer,
                pMultisampleState   = &multisampling,
                pColorBlendState    = &color_blending,
                pDynamicState       = &dynamic_state,
                layout              = shd.pipeline_layout,
                renderPass          = s.render_pass,
                subpass             = 0,
        }

        pipeline: vk.Pipeline
        result := vk.CreateGraphicsPipelines(s.device, 0, 1, &pipeline_info, nil, &pipeline)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create graphics pipeline for blend mode %v (%v)", blend_mode, result)
                return 0
        }

        return pipeline
}

vk_destroy_shader :: proc(h: Shader_Handle) {
        shd := hm.get(&s.shaders, h)
        if shd == nil {
                log.errorf("Vulkan: Invalid shader: %v", h)
                return
        }

        vk.DeviceWaitIdle(s.device)
        vk_destroy_shader_resources(shd)
        hm.remove(&s.shaders, h)
}

vk_destroy_shader_resources :: proc(shd: ^Vulkan_Shader) {
        for &pipeline in shd.pipelines {
                if pipeline != 0 {
                        vk.DestroyPipeline(s.device, pipeline, nil)
                        pipeline = 0
                }
        }
        if shd.pipeline_layout != 0 {
                vk.DestroyPipelineLayout(s.device, shd.pipeline_layout, nil)
        }
        if shd.descriptor_set_layout != 0 {
                vk.DestroyDescriptorSetLayout(s.device, shd.descriptor_set_layout, nil)
        }
        if shd.vertex_module != 0 {
                vk.DestroyShaderModule(s.device, shd.vertex_module, nil)
        }
        if shd.fragment_module != 0 {
                vk.DestroyShaderModule(s.device, shd.fragment_module, nil)
        }
}

vk_default_shader_vertex_source :: proc() -> []byte {
        vertex_source := #load("default_shaders/default_shader_vulkan_vertex.spv")
        return vertex_source
}

vk_default_shader_fragment_source :: proc() -> []byte {
        fragment_source := #load("default_shaders/default_shader_vulkan_fragment.spv")
        return fragment_source
}

// ---------------------------------------------------------------------------
// Helper: Buffer creation
// ---------------------------------------------------------------------------

vk_create_buffer :: proc(
        size: int,
        usage: vk.BufferUsageFlags,
        properties: vk.MemoryPropertyFlags,
        map_memory := false,
) -> (vk.Buffer, vk.DeviceMemory, rawptr) {
        buf_info := vk.BufferCreateInfo {
                sType = .BUFFER_CREATE_INFO,
                size  = vk.DeviceSize(size),
                usage = usage,
                sharingMode = .EXCLUSIVE,
        }

        buf: vk.Buffer
        result := vk.CreateBuffer(s.device, &buf_info, nil, &buf)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to create buffer (%v)", result)
                return 0, 0, nil
        }

        mem_req: vk.MemoryRequirements
        vk.GetBufferMemoryRequirements(s.device, buf, &mem_req)

        mem_type_idx := vk_find_memory_type(mem_req.memoryTypeBits, properties)
        if mem_type_idx < 0 {
                log.error("Vulkan: Failed to find suitable memory type for buffer")
                vk.DestroyBuffer(s.device, buf, nil)
                return 0, 0, nil
        }

        alloc_info := vk.MemoryAllocateInfo {
                sType           = .MEMORY_ALLOCATE_INFO,
                allocationSize  = mem_req.size,
                memoryTypeIndex = u32(mem_type_idx),
        }

        buf_mem: vk.DeviceMemory
        result = vk.AllocateMemory(s.device, &alloc_info, nil, &buf_mem)
        if result != .SUCCESS {
                log.errorf("Vulkan: Failed to allocate buffer memory (%v)", result)
                vk.DestroyBuffer(s.device, buf, nil)
                return 0, 0, nil
        }

        vk.BindBufferMemory(s.device, buf, buf_mem, 0)

        mapped: rawptr = nil
        if map_memory {
                result = vk.MapMemory(s.device, buf_mem, 0, vk.DeviceSize(size), {}, &mapped)
                if result != .SUCCESS {
                        log.errorf("Vulkan: Failed to map buffer memory (%v)", result)
                        // Still return the buffer, just without mapping
                        mapped = nil
                }
        }

        return buf, buf_mem, mapped
}

// ---------------------------------------------------------------------------
// Helper: Find memory type
// ---------------------------------------------------------------------------

vk_find_memory_type :: proc(type_filter: u32, properties: vk.MemoryPropertyFlags) -> int {
        mem_props: vk.PhysicalDeviceMemoryProperties
        vk.GetPhysicalDeviceMemoryProperties(s.physical_device, &mem_props)

        for i in 0 ..< mem_props.memoryTypeCount {
                if (type_filter & (1 << i)) != 0 {
                        if properties <= mem_props.memoryTypes[i].propertyFlags {
                                return int(i)
                        }
                }
        }

        return -1
}

// ---------------------------------------------------------------------------
// Helper: Immediate command buffer submission (for texture uploads, etc.)
// We store temporary state in module-level variables since Odin closures
// don't capture local variables.
// ---------------------------------------------------------------------------

// Temporary state for immediate submit callbacks.
// Odin procs cannot capture locals, so we use module-level variables.
_immediate_submit_image: vk.Image
_immediate_submit_offset_x: i32
_immediate_submit_offset_y: i32
_immediate_submit_width: u32
_immediate_submit_height: u32

vk_immediate_submit :: proc(record_fn: proc(cmd: vk.CommandBuffer), image: vk.Image = {}, ox: i32 = 0, oy: i32 = 0, w: u32 = 0, h: u32 = 0) {
        // Store parameters for the callback
        _immediate_submit_image = image
        _immediate_submit_offset_x = ox
        _immediate_submit_offset_y = oy
        _immediate_submit_width = w
        _immediate_submit_height = h

        alloc_info := vk.CommandBufferAllocateInfo {
                sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
                commandPool        = s.command_pool,
                level              = .PRIMARY,
                commandBufferCount = 1,
        }

        cmd: vk.CommandBuffer
        vk.AllocateCommandBuffers(s.device, &alloc_info, &cmd)

        begin_info := vk.CommandBufferBeginInfo {
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = {.ONE_TIME_SUBMIT},
        }
        vk.BeginCommandBuffer(cmd, &begin_info)

        record_fn(cmd)

        vk.EndCommandBuffer(cmd)

        submit_info := vk.SubmitInfo {
                sType              = .SUBMIT_INFO,
                commandBufferCount = 1,
                pCommandBuffers    = &cmd,
        }

        vk.QueueSubmit(s.graphics_queue, 1, &submit_info, 0)
        vk.QueueWaitIdle(s.graphics_queue)

        vk.FreeCommandBuffers(s.device, s.command_pool, 1, &cmd)
}

// ---------------------------------------------------------------------------
// Helper: Pixel format translation
// ---------------------------------------------------------------------------

vk_translate_pixel_format :: proc(f: Pixel_Format) -> vk.Format {
        switch f {
        case .RGBA_32_Float: return .R32G32B32A32_SFLOAT
        case .RGB_32_Float:  return .R32G32B32_SFLOAT
        case .RG_32_Float:   return .R32G32_SFLOAT
        case .R_32_Float:    return .R32_SFLOAT
        case .RGBA_8_Norm:   return .R8G8B8A8_UNORM
        case .RG_8_Norm:     return .R8G8_UNORM
        case .R_8_Norm:      return .R8_UNORM
        case .R_8_UInt:      return .R8_UINT
        case .Unknown:       return .R8G8B8A8_UNORM
        }
        return .R8G8B8A8_UNORM
}

vk_translate_shader_input_format :: proc(f: Pixel_Format) -> vk.Format {
        switch f {
        case .RGBA_32_Float: return .R32G32B32A32_SFLOAT
        case .RGB_32_Float:  return .R32G32B32_SFLOAT
        case .RG_32_Float:   return .R32G32_SFLOAT
        case .R_32_Float:    return .R32_SFLOAT
        case .RGBA_8_Norm:   return .R8G8B8A8_UNORM
        case .RG_8_Norm:     return .R8G8_UNORM
        case .R_8_Norm:      return .R8_UNORM
        case .R_8_UInt:      return .R8_UINT
        case .Unknown:       return .R32G32B32A32_SFLOAT
        }
        return .R32G32B32A32_SFLOAT
}

// ---------------------------------------------------------------------------
// Vulkan proc address loader — see render_backend_vulkan_linux.odin /
// render_backend_vulkan_windows.odin for vk_get_proc_address().
// ---------------------------------------------------------------------------
