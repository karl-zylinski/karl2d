# Karl2D AI Coding Agent Instructions

## Project Overview

**Karl2D** is a minimal-dependency 2D game creation library written in Odin. The library prioritizes shipping games with few external dependencies by implementing platform/rendering backends directly rather than using abstractions like GLFW.

### Core Architecture

Karl2D uses an **interface-based architecture** with compile-time selection:

1. **Platform Layer** (`platform_*.odin`): Handles window creation, input, and OS interaction
   - Windows, macOS, Linux (X11/Wayland), Web (via Odin's WASM runtime)
   - Interface: `Platform_Interface` defines what a platform backend must implement

2. **Rendering Layer** (`render_backend_*.odin`): GPU communication
   - D3D11 (Windows default), OpenGL (macOS/Linux default), WebGL (Web), NIL (test/headless)
   - Interface: `Render_Backend_Interface` with vertex batching, shader management, texture handling

3. **Audio Layer** (`audio_backend_*.odin`): Sound playback
   - WaveOut (Windows), Web Audio API (Web), NIL (default)
   - Architecture in beta; not fully featured yet

4. **Main API** (`karl2d.odin`): Platform/rendering-agnostic game loop and drawing commands
   - Uses `State` struct containing batching buffers, input maps, and frame allocator
   - Frame lifecycle: `reset_frame_allocator() → calculate_frame_time() → process_events() → user code → present()` (these procedures are all called by `update()`)

### Backend Selection

Backends are chosen at **compile-time** using `-define` flags:

```bash
# Render backend (defaults: Windows=d3d11, macOS/Linux=gl, Web=webgl)
odin run . -define:KARL2D_RENDER_BACKEND=gl

# Audio backend (defaults: Windows=waveout, others=nil)
odin run . -define:KARL2D_AUDIO_BACKEND=waveout
```

Backend selection is in `render_backend_chooser.odin` and `audio_backend_chooser.odin`. When choosing a backend, ensure it's available on the target platform—check available options or you'll get a compile-time panic.

## Code Style & Standards

Strictly enforced in contributions:

1. **Indentation**: Use **tabs**, not spaces
2. **Line Length**: Max **100 characters** (enforced with a visual ruler in editor)
3. **Spacing**: Follow the exact style in [karl2d.odin](karl2d.odin)
   - Space around operators: `x : = 5` (except in tuples)
   - Colons, equals, parentheses placement—review [karl2d.odin](karl2d.odin) as reference
4. **No Auto-formatters**: Do NOT use odinfmt or similar; manually match style
5. **API Comments**: Use Odin doc format (e.g., [init proc](karl2d.odin#L37))

## Key Workflows & Build System

### Running Examples

Use VS Code tasks (defined in workspace) or direct Odin commands:

```bash
# Desktop (default backend for platform)
odin run examples/basics -vet -strict-style -keep-executable -debug

# Explicit backend selection
odin run examples/basics -vet -strict-style -keep-executable -debug -define:KARL2D_RENDER_BACKEND=gl

# OpenGL on Windows
odin run examples/basics -vet -strict-style -keep-executable -debug -define:KARL2D_RENDER_BACKEND=gl
```

### Building for Web

Web builds require a custom build tool that generates wrapper code:

```bash
odin run build_web -- examples/minimal_hello_world
odin run build_web -- examples/basics -debug  # Add flags after --
```

Process:
1. `build_web.odin` reads the example directory
2. Generates `build/web/*_web_entry.odin` wrapper that calls your `init()` and `step()` procs
3. Copies `odin.js` from Odin's core libraries
4. Builds to WebAssembly (js_wasm32 target)
5. Output: `bin/web/main.wasm` + `index.html`
6. Launch via browser or local HTTP server (avoid CORS issues with file://)

Web examples must export `init :: proc()` and `step :: proc() -> bool` procedures.

### Testing & API Documentation

- **Comprehensive Tests**: Run the `run_tests` build task (default task) or execute:
  ```bash
  odin run tools/test_examples -vet -strict-style -vet-tabs
  ```
  This validates all examples across backends and is what CI runs on GitHub.

- **API Doc**: Run `odin run tools/api_doc_builder` to regenerate `karl2d.doc.odin`
  - CI enforces this—do NOT commit changes to doc file without rebuilding
  - Doc file is generated from comments in [karl2d.odin](karl2d.odin)

## Important Patterns & Conventions

### Frame Allocator & Lifetime Management

The global frame allocator (`s.frame_allocator`) resets each frame. Use it for temporary allocations:

```odin
// Valid for this frame only
vertices := make([dynamic]Vertex, frame_allocator)
```

For persistent data, use `context.allocator` (the main allocator).

These allocators are internal to the library. Games that use the library should use their own allocators.

### Platform & Rendering Backend Pattern

Both backends follow similar initialization:

1. `*_Interface` struct defines the vtable (required procs)
2. `*_State` struct holds backend-specific state (platform-dependent details)
3. Runtime expects raw pointers to state; backends cast to their own types
4. Example: [Platform_Interface](platform_interface.odin) → implemented by Windows/Mac/Linux/Web

When adding a new backend feature, add to the interface definition **first**, then implement in each backend.

### Batch-Based Rendering

Karl2D batches draw commands by (shader, texture, scissor, blend mode). State transitions flush the batch:

```odin
draw_text()  // Defers to frame allocator
draw_rect()  // Different texture? Flushes current batch
draw_present()  // Submits accumulated vertex buffer to render backend
```

### Texture Loading & WASM Constraints

Desktop uses filesystem; WASM cannot. Use `#load()` to bake textures into the binary:

```odin
// Desktop: file path works
tex := k2.load_texture_from_bytes(#load("assets/image.png"))

// Both: embedded works everywhere
tex := k2.load_texture_from_bytes(#load("assets/image.png"))
```

## Cross-Component Communication

- **Input**: Events from platform → stored in `State.events` → user queries via `k2.key_is_held()`, etc.
- **Rendering**: User calls `k2.draw_*()` → deferred to frame allocator → `present()` batches & flushes to backend
- **Allocators**: Global `frame_allocator` (cleared per frame) vs `context.allocator` (persistent)

## Pull Request Standards

Before submitting:

1. ✅ Code compiles and runs: `odin run . -vet -strict-style -keep-executable -debug`
2. ✅ Style matches [karl2d.odin](karl2d.odin) exactly (tabs, line length, spacing)
3. ✅ No unrelated code changes (makes review harder)
4. ✅ If API changes: regenerate `karl2d.doc.odin` via `odin run tools/api_doc_builder`
5. ✅ Test on target platform (Windows/Mac/Linux/Web as relevant)

Do not use auto-formatters. Do not modify auto-generated files manually.
