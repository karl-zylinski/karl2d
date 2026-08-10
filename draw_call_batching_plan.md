# Plan: Draw_Call array for batched rendering (issue #26)

This is an implementation plan for https://github.com/karl-zylinski/karl2d/issues/26. It is written so
that an agent (or human) can execute it without having seen the discussion that produced it. Read
`agent.md` first and follow its conventions throughout.

## Background and performance verdict

Today, every batch break (`draw_current_batch()`) results in one `rb.draw()` call that redoes the
*complete* pipeline setup in the render backend: the whole vertex buffer is re-uploaded (D3D11 maps
the full 1 MB buffer with `WRITE_DISCARD`, GL orphans a full `VERTEX_BUFFER_MAX` buffer with
`BufferData` and then does `BufferSubData`), all shader constants are re-uploaded, and input layout,
shaders, rasterizer state, scissor, textures, render target, viewport and blend state are all re-set —
even when only the texture changed between batches.

A batch break happens on any change of: texture (including the shapes-drawing white texture and font
atlas textures, so interleaving text and sprites breaks constantly), shader, shader constant, camera,
scissor, blend mode, render target, or font.

Measured on the current master (Windows 11, Odin dev-2026-08, `-o:speed`, 2000 textured quads per
frame, timing the draw-issue + flush region only, vsync excluded):

| Scenario                  | D3D11    | GL       |
|---------------------------|----------|----------|
| 1 flush/frame             | 0.32 ms  | 0.28 ms  |
| 200 flushes/frame         | 1.22 ms  | 0.17 ms  |
| 2000 flushes/frame        | 5.75 ms  | 0.72 ms  |

On D3D11 (the Windows default) each batch break costs roughly 2.5–3 µs of CPU; 2000 texture switches
burn ~5.4 ms/frame over the single-batch baseline — a third of a 60 Hz frame budget. The GL numbers
look mild because GL drivers defer most work to a driver thread; the WebGL backend is expected to be
the worst of all in reality, since every GL call there crosses the JS boundary and goes through
browser validation (not measured; browsers make this awkward to isolate).

Restructuring so that the core records an array of `Draw_Call`s and the backend consumes them in one
`draw` invocation gives us:

1. **One vertex buffer upload per flush** instead of one full-buffer upload per batch break.
2. **State diffing**: consecutive draw calls that only differ by texture only need a texture bind
   between GPU draws. Shader, constants, blend, render target, viewport and scissor setup are skipped
   when unchanged.
3. **Cheap state changes**: `set_camera`/`set_scissor_rect`/`set_blend_mode`/`set_shader_constant`
   stop forcing a full upload+setup; they merely start a new (small) draw call record.

The remaining per-draw-call cost (one `Draw`/`glDrawArrays` plus a texture bind) is unavoidable
without atlasing/bindless techniques and is cheap. This is the same shape raylib uses (rlgl's
`rlDrawCall` is `{mode, vertexCount, vertexAlignment, textureId}` with a single vertex upload in
`rlDrawRenderBatch`, then a loop of texture bind + draw). Our design goes further than raylib:
raylib hard-flushes on shader/matrix/blend changes, while here those become per-draw-call state.

**Verdict: worth doing.** Main win on D3D11 and (expectedly) WebGL; GL should also gain in real
frame terms even though client-side timings look flat. The benchmark protocol below verifies this
before/after on all backends.

## Design

### The Draw_Call struct

Lives in `render_backend_interface.odin` (it is part of the backend contract, like `Shader_Desc`):

```odin
Draw_Call :: struct {
	vertex_offset: int, // in bytes, into the vertex buffer passed to `draw`
	vertex_count: int,  // number of vertices (not bytes)

	shader: Shader,

	// Snapshots taken when the draw call was opened. Owned by the core's batch arena; valid
	// until the flush completes. `shader.constants_data` must NOT be read by backends anymore;
	// read `constants_data` here instead.
	constants_data: []u8,
	bound_textures: []Texture_Handle,

	render_target: Render_Target_Handle,
	scissor: Maybe(Rect),
	blend_mode: Blend_Mode,
}
```

Differences from the sketch in issue #26, and why:

- **No `font` field.** Backends never need the font — it only matters for updating the font atlas
  texture, which the core does at flush time (see "Fonts" below).
- **No `camera` field.** Backends never compute matrices. Instead the core writes the
  view-projection matrix into the per-draw-call `constants_data` snapshot when the draw call is
  opened (the same work `draw_current_batch` does today, just earlier).
- **`constants_data` snapshot** instead of reading `shader.constants_data` at flush time. Draws are
  now deferred, so mutable state a draw call depends on must be captured when it is recorded,
  otherwise `set_shader_constant` mid-frame would retroactively change already-recorded draws.
  Bonus: `set_shader_constant` no longer needs to flush at all.
- **`bound_textures` snapshot** for the same reason (users write `shader.texture_bindpoints[...]`
  directly, see `examples/multitexture`).
- **`vertex_offset` is in bytes**, because different shaders have different `vertex_size`, so a
  shared buffer has no single stride to count vertices in.

Snapshot allocations come from a dedicated `batch_arena` (growing arena in `State`), reset after
every hard flush. Do not use the frame allocator: users running a custom frame loop control when
that resets, and the coupling would be fragile. To keep snapshots cheap and enable backend-side
skipping, only take a *new* snapshot when the source data changed (constants dirty flag set by
`set_shader_constant`; bindpoints re-snapshotted when the batch texture or shader changed);
otherwise reuse the previous draw call's slice. Backends can then skip constants upload when
`raw_data(dc.constants_data)` equals the previous draw call's pointer.

### Core state changes (`karl2d.odin`)

In `State`:

```odin
vertex_buffer_cpu: []u8,          // unchanged
vertex_buffer_cpu_used: int,      // unchanged
batch_draw_calls: [dynamic]Draw_Call,
batch_arena: // growing arena for snapshots, reset at hard flush
batch_params_dirty: bool,         // set by every set_* proc below
batch_fonts_used: // small set/array of fonts drawn since last hard flush
```

Two distinct operations replace today's single `draw_current_batch`:

**Soft break — "open a new draw call":** close the current draw call record and start a new one in
`batch_draw_calls`. No backend interaction, no upload. Cost: one struct append plus (at most) a
~100-byte constants snapshot.

**Hard flush — `draw_current_batch()` (keep the public name and its doc comment, updated):**

```odin
draw_current_batch :: proc() {
	if len(s.batch_draw_calls) == 0 && s.vertex_buffer_cpu_used == 0 {
		return
	}
	// close the open draw call record
	// update atlases of all fonts in batch_fonts_used (calls rb.update_texture)
	rb.draw(s.vertex_buffer_cpu[:s.vertex_buffer_cpu_used], s.batch_draw_calls[:])
	// clear batch_draw_calls, vertex_buffer_cpu_used = 0, reset batch_arena,
	// clear batch_fonts_used
}
```

**The invariant that keeps ordering correct:** a hard flush must happen before *any* `rb.*` call
that touches an existing resource or the swapchain — because pending draw calls may reference the
old contents. Concretely, these public procs keep (or gain) a `draw_current_batch()` call:

- `present`, `clear` (already flush today — keep)
- `update_texture`, `destroy_texture`, `set_texture_filter` / `set_texture_filter_ex`
- `destroy_shader`
- `destroy_render_texture`
- `resize` / swapchain resize paths, if any call `rb.resize_swapchain` mid-frame

Resource *creation* calls (`load_texture_*`, `load_shader_*`, `create_render_texture`) need no
flush — pending draws cannot reference a resource that doesn't exist yet.

These procs currently flush but must **stop flushing** and instead just update their `batch_*` field
and set `batch_params_dirty` (keep their existing early-outs when the value doesn't change):

- `set_camera` (also updates `proj_matrix`/`view_matrix` as today)
- `set_shader`
- `set_shader_constant` (also set a constants-dirty flag so the next opened draw call re-snapshots)
- `set_scissor_rect`
- `set_blend_mode`
- `set_render_texture` (render target becomes a per-draw-call field; `clear` still hard-flushes, so
  the common clear-after-switch pattern stays correct)
- `_set_font` (record the font in `batch_fonts_used` instead of calling `_update_font` immediately)

**Where draw calls get opened:** the prologues of the draw procs (`draw_rect`, `draw_circle*`,
`draw_line`, `draw_texture*`, text drawing internals) currently do two checks: buffer-space
(→ `draw_current_batch()`) and texture mismatch (→ `draw_current_batch()`). Replace with one helper:

```odin
// Hard-flushes if the vertex buffer can't fit `bytes_needed` more bytes. Opens a new draw
// call if none is open, if `texture` differs from the open call's texture, or if
// batch_params_dirty is set.
_prepare_batch :: proc(texture: Texture_Handle, bytes_needed: int)
```

Buffer-full still hard-flushes (upload + execute + reset). This also answers the issue's question
about backend vertex buffer limits: a draw call can never span more than `VERTEX_BUFFER_MAX` bytes,
so backends never need to split anything. Keep `VERTEX_BUFFER_MAX` as-is.

`override_shader_input` needs nothing: overrides are baked into each vertex by `batch_vertex` at
record time already.

`batch_vertex` itself is unchanged apart from where the buffer-full check lives; it must bump the
open draw call's `vertex_count` (or the count is computed when the call is closed from
`vertex_buffer_cpu_used` deltas — implementer's choice, computing on close is less per-vertex work).

### Fonts

Fontstash only ever *adds* glyphs to the atlas within a frame, so UVs recorded in earlier draw
calls stay valid; updating each used font's atlas once, at hard-flush time, right before
`rb.draw`, is correct and cheaper than today's per-batch `_update_font`. One caveat to verify
during implementation: if the fontstash atlas ever resets or resizes mid-frame (atlas full), old
UVs become invalid — that path must trigger a hard flush *before* the reset happens. Check how the
current integration handles atlas-full (look at `fs.Init` callbacks and `_update_font`) and add the
flush hook if the path exists.

### Backend interface change (`render_backend_interface.odin`)

```odin
draw: proc(vertex_buffer: []u8, draw_calls: []Draw_Call),
```

The old per-call parameters (shader, render_target, bound_textures, scissor, blend, vertex slice)
all move into `Draw_Call`.

### Backend implementation pattern (d3d11, gl, webgl; nil gets a stub)

Each backend's `draw` becomes:

1. Early-out if `draw_calls` is empty.
2. Upload `vertex_buffer` **once**. Upload only `len(vertex_buffer)` bytes, not
   `VERTEX_BUFFER_MAX` (today D3D11 maps and GL orphans the full 1 MB every call — fix that while
   here: D3D11 `Map(WRITE_DISCARD)` + copy `len(vertex_buffer)`; GL
   `BufferData(nil, len)` orphan + `BufferSubData`).
3. Loop over `draw_calls`, tracking the previous call's state *within this flush only* (no
   cross-frame caching — start the loop with everything considered dirty):
   - shader changed → set program/input layout/VS/PS (D3D11), `UseProgram`+VAO (GL)
   - `raw_data(constants_data)` changed → upload constants (reuse today's constant-upload code,
     but read from `dc.constants_data` instead of `shd.constants_data`)
   - `bound_textures` pointer or shader changed → bind textures/samplers
   - render target changed → set render target + viewport (D3D11 keeps the final
     `OMSetRenderTargets(0, nil, nil)` after the loop, as today)
   - blend mode changed → set blend state
   - scissor changed → set scissor rect; GL/WebGL must ensure `SCISSOR_TEST` ends disabled after
     the loop (do not regress the fix from PR #197)
   - vertex offset: D3D11 → `IASetVertexBuffers` with byte offset and the shader's stride whenever
     shader or offset base changes, then `Draw(vertex_count, 0)`. GL/WebGL → the attrib pointers
     live in the shader's VAO; on shader change (or at loop start) re-specify attrib pointers with
     the draw call's byte offset as base, then `glDrawArrays(TRIANGLES, (dc.vertex_offset - base)/stride, count)`
     for subsequent same-shader calls (the offset delta is always stride-aligned while the shader
     is unchanged, since vertices were appended with that stride). Simplest correct v1: re-specify
     attrib pointers per draw call and always draw with first=0; optimize only if benchmarks say so.
4. Keep `log_messages()` (D3D11) once at the end.

## Execution steps

Work on a branch. After each step the project must build with
`-vet -strict-style -vet-tabs` and the examples must run.

### Step 1: Benchmark tool (before any refactoring)

Create `tools/batch_benchmark/` (desktop) modeled on the temporary R&D benchmark below. Scenarios,
2000 quads/frame, ~45 measured frames each after ~15 warmup:

1. Single texture (1 batch break/frame) — regression guard.
2. Texture switch every 10 quads (200 breaks).
3. Texture switch every quad (2000 breaks) — worst case.
4. Interleaved `draw_texture` + `draw_text` (realistic UI/text pattern).
5. `set_camera` toggle every 10 quads, single texture (state-change cost).

Time only the draw-issue region: `t0` before issuing draws, then `k2.draw_current_batch()`, then
`t1` — this excludes vsync (D3D11 presents with `Present(1)`). Print a table. Note in the output
that GL client-side numbers under-report driver-thread cost.

Record baseline numbers on master for `d3d11` and `gl`
(`-o:speed`, `-define:KARL2D_RENDER_BACKEND=gl` for the GL run) and save them (in the PR
description and/or a comment on issue #26).

Optionally add a web variant (structure it like `examples/minimal_hello_world_web`, build with
`odin run build_web -- tools/batch_benchmark_web -o:speed`) that accumulates the same timings via
`k2.get_time` and draws the results as text on screen — WebGL is where the biggest win is expected,
so measuring it is worth the extra step.

The R&D benchmark this plan's baseline numbers came from (adapt, don't copy blindly — move
constants up, follow style):

```odin
package karl2d_batch_benchmark

import k2 "../.."
import "core:fmt"
import "core:time"

QUADS :: 2000
WARMUP_FRAMES :: 15
MEASURE_FRAMES :: 45

main :: proc() {
	k2.init(1280, 720, "batch benchmark")

	pixels_a: [64*64*4]u8
	pixels_b: [64*64*4]u8

	for i in 0..<64*64 {
		pixels_a[i*4+0] = 255
		pixels_a[i*4+3] = 255
		pixels_b[i*4+1] = 255
		pixels_b[i*4+3] = 255
	}

	tex_a := k2.load_texture_from_bytes_raw(pixels_a[:], 64, 64, .RGBA_8_Norm)
	tex_b := k2.load_texture_from_bytes_raw(pixels_b[:], 64, 64, .RGBA_8_Norm)

	// ... per scenario, per frame:
	k2.clear(k2.BLACK)
	t0 := time.tick_now()
	for i in 0..<QUADS {
		tex := tex_a
		if switch_every > 0 && (i / switch_every) % 2 == 1 {
			tex = tex_b
		}
		k2.draw_texture(tex, {f32(i % 100) * 12, f32(i / 100) * 30})
	}
	k2.draw_current_batch()
	dt := time.duration_milliseconds(time.tick_since(t0))
	k2.present()
	// accumulate dt after warmup; print averages at the end
}
```

### Step 2: Interface + nil backend

- Add `Draw_Call` to `render_backend_interface.odin`; change the `draw` proc signature.
- Update `render_backend_nil.odin`.
- The project won't fully build until steps 3–4 land; do 2–4 as one unit of work, committing when
  green.

### Step 3: Core refactor (`karl2d.odin`)

- Add `batch_draw_calls`, `batch_arena`, `batch_params_dirty`, `batch_fonts_used` to `State`;
  init in `init`, clean up in `shutdown` (remember `set_internal_state`/hot-reload keeps working —
  everything lives in `State`).
- Implement `_prepare_batch` and the draw-call open/close/snapshot logic described above.
- Convert the `set_*`/`_set_font` procs from flushing to dirty-marking.
- Rewrite `draw_current_batch` as the hard flush; update its doc comment (it is public API
  documentation, and the "what breaks a batch" comment block above it must be rewritten to describe
  the new soft-break/hard-flush split).
- Add hard-flush calls to `update_texture`, `destroy_texture`, `set_texture_filter*`,
  `destroy_shader`, `destroy_render_texture` if not already present.
- Audit every remaining `draw_current_batch()` call site against the invariant ("flush before any
  rb.* touching existing resources").

### Step 4: D3D11 backend, then GL, then WebGL

Follow the backend pattern above. D3D11 first (Windows default, easiest to verify), then GL
(`-define:KARL2D_RENDER_BACKEND=gl`), then WebGL via `build_web`.

### Step 5: Verification

- `odin run tools/test_examples` (builds every example).
- Visually run at minimum: `basics`, `fonts`, `measure_text` (text batching), `multitexture`
  (direct `texture_bindpoints` writes — must render identically), `render_texture` (render target
  switching + clear ordering), `premultiplied_alpha` (blend modes), `camera`, `ui` (scissor if
  used), `space_cat` (big real-world example), and one raylib port. On both d3d11 and gl, plus one
  web build (`minimal_hello_world_web` or the web benchmark).
- Check the scissor-disable behavior on GL/WebGL (regression guard for #197): draw with a scissor
  rect, then without, verify the second draw is unclipped.
- API surface changed (`Draw_Call`, `draw_current_batch` docs): regenerate `karl2d.doc.odin` with
  `odin run tools/api_doc_builder` and run
  `odin build tools/api_verifier -debug -vet -strict-style -vet-tabs`.

### Step 6: Benchmark comparison

Re-run `tools/batch_benchmark` on all backends, same machine, `-o:speed`. Put a before/after table
in the PR description. Success criteria:

- Scenario 1 (single batch): no regression beyond noise.
- Scenarios 2–5: clear improvement on D3D11 (expect the 2000-break case to drop from ~5.7 ms to
  low single digits; the exact floor depends on `Draw`-call cost) and on WebGL.
- If a scenario regresses, profile before merging — the most likely culprit is per-draw-call
  snapshot overhead, which the pointer-reuse scheme should prevent.

## Explicitly out of scope (possible follow-ups, keep them out of this PR)

- Indexed quads (4 verts + index buffer instead of 6 verts) — raylib does this; ~23% vertex data
  reduction, orthogonal to this change.
- Cross-frame/backend-global state caching (only diff within one flush).
- Sorting/merging draw calls by state — would break painter's-algorithm ordering; 2D requires
  submission order.
- A cap on `batch_draw_calls` (it's a dynamic array; the vertex buffer limit bounds it in
  practice).

## Behavior notes worth calling out in the PR

- `set_shader_constant` no longer flushes; constants are snapshotted per draw call. Same rendered
  output, better performance.
- Users who write `shader.texture_bindpoints[...]` directly get their values captured at the point
  the next draw call opens (previously: at the next flush, which was less predictable). Verify
  `examples/multitexture` and mention the semantics in the changelog if there is one.
- `draw_current_batch()` remains public and now means "submit everything recorded so far to the
  GPU".
