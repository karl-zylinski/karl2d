# Karl2D Vulkan Backend — Testing Guide & Validation Checklist

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [How to Build with the Vulkan Backend](#2-how-to-build-with-the-vulkan-backend)
3. [Example Testing Matrix](#3-example-testing-matrix)
4. [Phase-by-Phase Testing](#4-phase-by-phase-testing)
5. [Static Analysis: Potential Issues Found](#5-static-analysis-potential-issues-found)
6. [Debugging Tips](#6-debugging-tips)
7. [Phase 3 Validation Checklist](#7-phase-3-validation-checklist)

---

## 1. Prerequisites

### System Requirements
- **Vulkan SDK** installed (validation layers, `glslangValidator`)
  - Linux: Install via your distro's package manager (`vulkan-tools`, `libvulkan-dev`, `vulkan-validationlayers`)
  - Or install the [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home)
- **Odin compiler** (latest dev build recommended)
- **GPU with Vulkan support** — check with `vulkaninfo` or `vkcube`
- **Display server**: X11 or Wayland (the glue files support both)

### Verify Vulkan Installation
```bash
# Check Vulkan is working
vulkaninfo --summary
vkcube  # Should show a spinning cube
```

### SPIR-V Shaders
The pre-compiled `.spv` files are already in the repository at:
- `default_shaders/default_shader_vulkan_vertex.spv`
- `default_shaders/default_shader_vulkan_fragment.spv`

If you need to recompile them:
```bash
cd default_shaders/
glslangValidator -V default_shader_vulkan_vertex.glsl -o default_shader_vulkan_vertex.spv
glslangValidator -V default_shader_vulkan_fragment.glsl -o default_shader_vulkan_fragment.spv
```

---

## 2. How to Build with the Vulkan Backend

### Switching to Vulkan
The backend is selected at compile time via the `-define` flag:

```bash
# Build any example with Vulkan backend:
odin build examples/minimal_hello_world -define:KARL2D_RENDER_BACKEND=vulkan

# Build with debug mode (enables Vulkan validation layers + debug messenger):
odin build examples/minimal_hello_world -define:KARL2D_RENDER_BACKEND=vulkan -debug

# Run directly:
odin run examples/minimal_hello_world -define:KARL2D_RENDER_BACKEND=vulkan -debug
```

### Quick Comparison: GL vs Vulkan
```bash
# Run with GL (default):
odin run examples/basics

# Run with Vulkan:
odin run examples/basics -define:KARL2D_RENDER_BACKEND=vulkan -debug
```

### Compile-Only Check (no GPU needed)
```bash
# Just check compilation without running:
odin check examples/basics -define:KARL2D_RENDER_BACKEND=vulkan
```

---

## 3. Example Testing Matrix

Each example tests different rendering features. Test them in this order (simplest → most complex):

| Priority | Example | Key Features Tested | Phase |
|----------|---------|-------------------|-------|
| 🔴 1 | `minimal_hello_world` | Window init, clear, text rendering, present | Phase 1+2 |
| 🔴 2 | `basics` | Textures (JPG), shapes, text, input, animation | Phase 2 |
| 🔴 3 | `palette` | Color rendering accuracy | Phase 1 |
| 🟡 4 | `mouse` | Input + basic rendering | Phase 1+2 |
| 🟡 5 | `fonts` | Font atlas texture, text at various sizes | Phase 2 |
| 🟡 6 | `render_texture` | **Render-to-texture, render target switching** | **Phase 3** |
| 🟡 7 | `camera` | View matrix (push constants), zoom/pan/rotate | Phase 2 |
| 🟡 8 | `premultiplied_alpha` | Premultiplied alpha blend mode | **Phase 3** |
| 🟡 9 | `scaling_auto_window_resize` | **Swapchain resize** | **Phase 3** |
| 🟢 10 | `multitexture` | Multiple texture bindings, custom shaders | Phase 2+ |
| 🟢 11 | `bunnymark` | Performance (many draw calls, batch breaks) | Phase 2+ |
| 🟢 12 | `events` | Event handling + rendering | Phase 1 |
| 🟢 13 | `ui` | Scissor rects, complex rendering | **Phase 3** |
| 🟢 14 | `snake` | Complete game (textures, input, game logic) | Phase 2 |
| 🟢 15 | `shaders_texture_waves` | Custom shader with constants (HLSL-only, may not work) | Special |

### Important Note on `multitexture` and `shaders_texture_waves`

These examples use **custom shaders** written in GLSL/HLSL for GL/D3D11. They will **NOT** work with the Vulkan backend as-is because:
1. The Vulkan backend expects **SPIR-V bytecode**, not GLSL/HLSL source text
2. The `multitexture` example uses `when k2.RENDER_BACKEND_NAME == "gl"` / `"webgl"` / else (D3D11) — no `"vulkan"` branch exists
3. The `shaders_texture_waves` example loads HLSL data

**To make custom shader examples work with Vulkan:**
1. Write equivalent Vulkan GLSL shaders
2. Compile them to SPIR-V with `glslangValidator -V`
3. Add a `when k2.RENDER_BACKEND_NAME == "vulkan"` branch that loads the `.spv` files

---

## 4. Phase-by-Phase Testing

### Phase 1: Foundation (Clear + Window)

**What to test:**
- Window opens and displays correctly
- `k2.clear(color)` fills the window with the specified color
- `k2.present()` shows the frame without errors
- No validation layer errors in debug mode

**Test with:**
```bash
odin run examples/minimal_hello_world -define:KARL2D_RENDER_BACKEND=vulkan -debug
```

**Expected behavior:**
- Light blue window with "Hellope!" text (text requires Phase 2 textures)
- If only Phase 1 works, you should at least see a light blue window

**Common issues:**
- "Failed to create Vulkan instance" → Vulkan drivers not installed
- "Failed to find suitable GPU" → No Vulkan-capable GPU or wrong driver
- "Failed to create surface" → Window system integration issue (X11 vs Wayland)
- Black window → Present/swapchain issue
- Hang/freeze → Synchronization issue (fences/semaphores)

### Phase 2: Textures & Drawing

**What to test:**
- Textured quads render correctly
- Text renders (uses font atlas texture)
- Shapes (rectangles, circles) render
- Colors are correct (not washed out or inverted)
- Camera/view matrix transforms work

**Test with:**
```bash
odin run examples/basics -define:KARL2D_RENDER_BACKEND=vulkan -debug
odin run examples/fonts -define:KARL2D_RENDER_BACKEND=vulkan -debug
odin run examples/camera -define:KARL2D_RENDER_BACKEND=vulkan -debug
```

**Expected behavior:**
- `basics`: Spinning texture, colored shapes, FPS text, arrow key movement
- `fonts`: Text at various sizes, all readable
- `camera`: Grid with zoom/pan/rotate, stats text overlay

**Common issues:**
- Garbled textures → Pixel format mismatch or staging buffer upload issue
- Missing textures (everything white) → Texture not uploaded, descriptor not bound
- Wrong colors → Format (RGBA vs BGRA) mismatch
- Upside-down textures → Vulkan has Y-axis flipped vs GL (but `texture_needs_vertical_flip` returns false for Vulkan, which is correct — Karl2D handles this)
- Crash on texture load → Staging buffer too small, or memory type selection failed
- No text visible → Font atlas texture failed to create/upload

### Phase 3: Render Targets & Advanced Features

**What to test:**
1. **Render-to-texture** — Drawing to an offscreen target, then sampling it
2. **Render target switching** — Switching between swapchain and render targets mid-frame
3. **Blend modes** — Both Alpha and Premultiplied_Alpha
4. **Scissor rects** — Clipping draw calls to rectangular regions
5. **Swapchain resize** — Window resize without crash or visual artifacts
6. **Multiple draw calls per frame** — Batch breaks don't cause issues

**Test with:**
```bash
# Render texture (THE critical Phase 3 test)
odin run examples/render_texture -define:KARL2D_RENDER_BACKEND=vulkan -debug

# Premultiplied alpha blending
odin run examples/premultiplied_alpha -define:KARL2D_RENDER_BACKEND=vulkan -debug

# Window resize
odin run examples/scaling_auto_window_resize -define:KARL2D_RENDER_BACKEND=vulkan -debug

# Scissor + complex UI
odin run examples/ui -define:KARL2D_RENDER_BACKEND=vulkan -debug

# Performance/stress test (many batch breaks)
odin run examples/bunnymark -define:KARL2D_RENDER_BACKEND=vulkan -debug
```

**Expected behavior for `render_texture`:**
1. A small 75×48 render target is created
2. Each frame: draw orange background + spinning black rect + text to the render target
3. Switch back to swapchain
4. Clear swapchain to black
5. Draw the render target texture 3 times at different sizes/rotations
6. The render target content should appear as a small textured quad

**Common issues for Phase 3:**
- **Validation errors about image layout transitions** → The most likely issue. Check `vk_ensure_render_target`, `vk_transition_render_target_for_rendering`, and `vk_transition_render_target_for_sampling`
- **Black render target texture** → Render target not being cleared or rendered to, or not transitioned back to `SHADER_READ_ONLY_OPTIMAL` before sampling
- **Crash on render target switch** → Render pass not properly ended before starting a new one
- **Stale render target content** → Pipeline not correctly bound for render target render pass (swapchain pipeline vs RT pipeline)
- **Crash on window resize** → Swapchain recreation not properly destroying old resources
- **Blending looks wrong** → Pipeline blend state incorrect for the active blend mode
- **Scissor not working** → Dynamic scissor not set, or coords wrong

---

## 5. Static Analysis: Potential Issues Found

After careful review of `render_backend_vulkan.odin` (3212 lines), here are potential issues to watch for during testing:

### 5.1 🟡 Render Target Format: R32G32B32A32_SFLOAT May Not Be Supported

**Location:** `vk_create_render_texture()` line ~2464

The render target uses `R32G32B32A32_SFLOAT` format. While this matches the GL backend for HDR, not all GPUs support this format for color attachments. The code does **not** check `vkGetPhysicalDeviceFormatProperties()` before using it.

**Potential fix:** Add a format support check, or fall back to `R8G8B8A8_UNORM` / `B8G8R8A8_UNORM` if the float format isn't supported.

**Symptom:** `vkCreateImage` or `vkCreateFramebuffer` fails, render target creation returns empty handles.

### 5.2 🟡 Render Target Render Pass Format Mismatch

**Location:** `vk_create_render_target_render_pass()` line ~1542

The render target render pass uses `R32G32B32A32_SFLOAT` format, but if the actual render target ends up using a different format (due to fallback), the framebuffer/render pass would be incompatible.

### 5.3 🟡 `vk_begin_frame()` Does Not Set `frame_started` on Swapchain Resize Early Return

**Location:** `vk_begin_frame()` line ~1802-1804

```odin
if result == .ERROR_OUT_OF_DATE_KHR {
    vk_resize_swapchain(s.width, s.height)
    return  // Returns without setting frame_started = true!
}
```

If `AcquireNextImageKHR` returns `ERROR_OUT_OF_DATE_KHR`, the function returns early without setting `frame_started = true`. This means subsequent `vk_clear` / `vk_draw` calls in the same frame will try to call `vk_begin_frame()` again, which will re-attempt acquire. This could be a problem if the swapchain keeps being out of date (e.g., during continuous resize).

**Potential fix:** After `vk_resize_swapchain`, either retry the acquire or set a flag to skip the rest of the frame.

### 5.4 🟡 `vk_present()` Accesses Command Buffer Before Checking `frame_started`

**Location:** `vk_present()` lines 1713-1733

```odin
cmd := s.command_buffers[s.current_frame]  // Line 1713 - always executes
// ... does render pass end ...
if !s.frame_started {  // Line 1730 - early return
    return
}
vk.EndCommandBuffer(cmd)  // Only reached if frame_started
```

If `frame_started` is false, the code at lines 1717-1728 may try to end a render pass and transition render targets on a command buffer that was never begun. The `CmdEndRenderPass` and `CmdPipelineBarrier` calls would be invalid.

**Potential fix:** Move the `!s.frame_started` check to the top of `vk_present()`.

### 5.5 🟡 Vertex Buffer Overflow Not Checked

**Location:** `vk_draw()` line ~2026

```odin
mem.copy(vb_mapped, raw_data(vertex_buffer), len(vertex_buffer))
```

The vertex data is copied without checking if `len(vertex_buffer)` exceeds the allocated vertex buffer size (`VERTEX_BUFFER_MAX` from the framework side, but the Vulkan side allocates 1MB). If the framework sends more data than fits, this is a buffer overrun.

**Note:** This is likely safe because the framework's batching system limits vertex buffer size to `VERTEX_BUFFER_MAX = 1,000,000 bytes`, and the Vulkan backend allocates the same amount. But it's worth verifying the constant match.

### 5.6 🟡 Descriptor Pool Exhaustion

**Location:** `vk_draw()` line ~2115

Each draw call allocates a new descriptor set from the per-frame pool (max `MAX_DESCRIPTOR_SETS_PER_FRAME = 4096`). For `bunnymark` with thousands of bunnies, batch breaks could potentially exhaust this. The error is handled (returns early), but silently drops the draw call.

**To test:** Run `bunnymark`, click to add lots of bunnies, check for "Failed to allocate descriptor set" log messages.

### 5.7 🟢 Minor: `load_shader` Allocator Mismatch

**Location:** `vk_load_shader()` line ~2669

The default `desc_allocator` is `frame_allocator`, meaning shader descriptions are allocated from the frame arena. This is the same pattern as the GL backend, so it should be correct — the framework copies what it needs before the frame arena is reset.

### 5.8 🟡 Custom Shaders: Hardcoded Layout Assumptions

**Location:** `vk_load_shader()` lines ~2698-2703

The shader loading always assumes:
- Push constants for `view_projection` (64 bytes)
- Exactly 1 combined image sampler at binding 0
- Vertex inputs: position (vec2) + texcoord (vec2) + color (vec4 normalized u8)

This works for the **default shader** but will break for custom shaders that have different layouts (e.g., `multitexture` example needs 2 texture bindings).

**Impact:** Custom shader examples won't work correctly. This is a known Phase 2 limitation — SPIR-V reflection is not yet implemented.

### 5.9 🟢 Double-Free Prevention in Shutdown

The shutdown correctly uses `DeviceWaitIdle` and iterates handle maps to destroy resources. The `vk_destroy_render_target_resources` correctly notes that image/view/memory are owned by the texture entry, avoiding double-free.

### 5.10 🟡 `_immediate_submit_image` Global for Closures

**Location:** `vk_create_render_texture()` line ~2516 and `vk_create_texture_internal()`

The `vk_immediate_submit` pattern uses a module-level `_immediate_submit_image` variable to pass the image handle into the closure (since Odin closures can't capture local variables). This is a threading concern but since Karl2D is single-threaded, it's fine. However, it's fragile — ensure `vk_immediate_submit` is never called from multiple threads.

---

## 6. Debugging Tips

### Enable Validation Layers
Always build with `-debug` to enable Vulkan validation layers:
```bash
odin run examples/basics -define:KARL2D_RENDER_BACKEND=vulkan -debug
```

Validation messages will appear in the console via Karl2D's log system.

### Use RenderDoc for GPU Debugging
1. Install [RenderDoc](https://renderdoc.org/)
2. Launch your app through RenderDoc
3. Capture a frame (F12 by default)
4. Inspect draw calls, pipeline state, textures, render targets

### Common Validation Errors and What They Mean

| Validation Error | Likely Cause | Fix |
|-----------------|-------------|-----|
| "Image layout transition invalid" | Wrong `oldLayout` in barrier | Check the actual layout vs expected layout in transition functions |
| "Render pass not compatible with framebuffer" | Format mismatch between render pass attachment and framebuffer image | Ensure render pass format matches the image format |
| "Pipeline not compatible with render pass" | Using swapchain pipeline in RT render pass or vice versa | Check `vk_draw` pipeline selection logic |
| "Descriptor set not compatible with pipeline layout" | Wrong descriptor set layout bound | Check descriptor set allocation uses correct layout |
| "Command buffer in invalid state" | Recording commands to a buffer that wasn't begun | Check `vk_begin_frame` was called successfully |

### Log Output
The Vulkan backend logs initialization steps. Look for:
```
Vulkan: Initialized successfully
Vulkan: Created render texture 75x48
Vulkan: Swapchain resized to ...
```

If you see error messages, they'll help pinpoint the issue.

### Environment Variables
```bash
# Enable ALL validation features:
export VK_LAYER_ENABLES=VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT

# Disable validation (for performance testing):
export VK_LAYER_DISABLES=VK_LAYER_LUNARG_standard_validation

# Force X11 on a Wayland session (if Wayland glue has issues):
export GDK_BACKEND=x11
```

### If Nothing Renders (Black Screen)
1. Check validation layer output for errors
2. Verify swapchain was created (`Vulkan: Initialized successfully` in logs)
3. Check if `vk_begin_frame()` is succeeding (add log statements if needed)
4. Use RenderDoc to see if draw calls are being recorded
5. Verify the push constants (view_projection matrix) are being set correctly

### If the App Crashes
1. Run with validation layers (`-debug`)
2. Check the crash location in the backtrace
3. Common crash sites:
   - `vk_begin_frame` → Fence/semaphore issue
   - `vk_present` → Swapchain out of date
   - `vk_draw` → Invalid pipeline or descriptor set
   - `vk_create_texture_internal` → Memory allocation failure

---

## 7. Phase 3 Validation Checklist

This checklist validates the Phase 3 implementation against the requirements specified in `karl2d_vulkan_plan.md` (Section 7, Phase 3).

### Phase 3 Requirements from Plan

| # | Requirement | Status | Notes |
|---|------------|--------|-------|
| 3.1 | **Render texture creation** — `vk_create_render_texture` with framebuffer | ✅ Implemented | Creates VkImage + VkDeviceMemory + VkImageView + VkFramebuffer. Uses R32G32B32A32_SFLOAT format. Lines 2460-2632. |
| 3.2 | **Render target switching** — Handle render pass end/begin on target change | ✅ Implemented | `vk_ensure_render_target()` (lines 1825-1946) handles switching between swapchain and offscreen targets with proper barrier transitions. |
| 3.3 | **Render target destruction** — `vk_destroy_render_target` | ✅ Implemented | Lines 2634-2652. Waits for device idle, destroys framebuffer, destroys associated texture. |
| 3.4 | **Scissor support** — Dynamic scissor state in draw | ✅ Implemented | `vk_draw()` lines 2076-2088 sets dynamic scissor based on the `scissor` parameter. |
| 3.5 | **Blend mode support** — Pipeline variants for Alpha vs Premultiplied Alpha | ✅ Implemented | Pipelines created for each `Blend_Mode` variant. Lines 2925-2948 configure blend state per mode. RT pipelines created lazily. |
| 3.6 | **Swapchain resize** — `vk_resize_swapchain` with full recreation | ✅ Implemented | Lines 1642-1692. Properly destroys old framebuffers (both regular and load), recreates swapchain, image views, and framebuffers. |
| 3.7 | **Vertical flip handling** — `vk_texture_needs_vertical_flip` | ✅ Implemented | Returns `false` for all textures (line ~2429), except render target textures need special handling. Vulkan doesn't need the GL Y-flip. |
| 3.8 | **Shutdown cleanup** — `vk_shutdown` with proper resource teardown | ✅ Implemented | Lines 397-577. Comprehensive teardown in reverse creation order, including Phase 3 resources. |

### Additional Phase 3 Features Implemented (Beyond Plan)

| Feature | Status | Notes |
|---------|--------|-------|
| **Render pass variants** — CLEAR and LOAD render passes for swapchain | ✅ | `render_pass` (CLEAR) and `render_pass_load` (LOAD) prevent unnecessary clears between draw batches |
| **Pipeline cache** — `VkPipelineCache` for faster pipeline creation | ✅ | Created at init, used for all pipeline creation |
| **Lazy RT pipeline creation** — Render target pipelines created on first use | ✅ | `rt_pipelines` array in `Vulkan_Shader`, populated lazily in `vk_draw` |
| **Frame management helpers** — `vk_begin_frame`, `vk_ensure_render_target` | ✅ | Clean separation of frame start, render target switching |
| **Debug markers** — `vk_cmd_begin_label`, `vk_cmd_end_label`, `vk_set_object_name` | ✅ | Conditional on `ODIN_DEBUG`, helps with RenderDoc debugging |
| **Render target clearing via vkCmdClearColorImage** | ✅ | Uses explicit clear command before render pass for RT targets |

### Testing Verification Matrix

Run each test and mark pass/fail:

| Test | Command | Pass? | Notes |
|------|---------|-------|-------|
| **Compilation** | `odin check examples/basics -define:KARL2D_RENDER_BACKEND=vulkan` | ☐ | |
| **Debug compilation** | `odin check examples/basics -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Window + clear** | `odin run examples/minimal_hello_world -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Textures + shapes** | `odin run examples/basics -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Font rendering** | `odin run examples/fonts -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Camera (push constants)** | `odin run examples/camera -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Render texture** | `odin run examples/render_texture -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Premultiplied alpha** | `odin run examples/premultiplied_alpha -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Window resize** | `odin run examples/scaling_auto_window_resize -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Scissor/UI** | `odin run examples/ui -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Performance (bunnymark)** | `odin run examples/bunnymark -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **Complete game (snake)** | `odin run examples/snake -define:KARL2D_RENDER_BACKEND=vulkan -debug` | ☐ | |
| **No validation errors** | All above with `-debug`, check console | ☐ | |
| **Clean shutdown** | Close window, no crash or hang | ☐ | |
| **Rapid resize** | Resize window quickly multiple times | ☐ | |
| **Minimize/restore** | Minimize and restore the window | ☐ | |

### Known Limitations

1. **Custom shaders not fully supported** — `vk_load_shader` uses hardcoded layout assumptions (1 texture, push constants for view_projection). SPIR-V reflection is not implemented. Custom shader examples (`multitexture`, `shaders_texture_waves`) will not work without Vulkan-specific shader versions.

2. **R32G32B32A32_SFLOAT render target format** — May not be universally supported. If render targets fail to create, this format should be checked first.

3. **No Windows Vulkan glue yet** — Only Linux (X11 and Wayland) platform glue files exist. Windows support is planned for Phase 4.

4. **Single-threaded assumption** — The `_immediate_submit_image` global for closure state is not thread-safe.

---

*Generated: 2026-03-27*
*Branch: vulkan-phase1*
*Implementation: render_backend_vulkan.odin (3212 lines)*
