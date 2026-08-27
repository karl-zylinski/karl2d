# LLM agent instructions for Karl2D

Conventions for writing code, writing documentation, and collaborating on this project.

> Human can read this file too, but it might not be optimized for human consumption. Also, note that no form of vibe coded changes are allowed. You can use an LLM to do code reviews and generate code, but you _must_ understand the code generated.

## Project Overview
- **Karl2D** is a 2D game development library written in the Odin programming language, licensed under Zlib license.
- The focus is on being beginner-friendly, using a minimal set of dependencies and minimizing issues when you actually want to ship the game.
- Karl2D usually requires the latest release of Odin.
- The main entry point is `karl2d.odin`, which contains the platform-independent API and core logic. Platform, render and audio backends live in separate files.
- See `karl2d.doc.odin` for a full API overview. It is generated output: never edit it by hand.

## Workflow
- If the work is on an existing pull request, start with `gh pr checkout <number>` rather than a branch or worktree that merely looks like the right one. It checks out the PR head (including from forks) and sets up tracking, so `git push` updates the PR instead of creating a disconnected branch.
- Keep changes focused. Don't touch unrelated code, don't use auto-formatters (e.g. odinfmt), and don't modify whitespace on lines you aren't otherwise changing.
- If you make unintended changes, revert them in additional commits (squash merges are used).
- If you break backwards compatbility, introduce @(deprecated) procedures or somehow try to do it gracefully. If you cannot help it, then so be, but flag about it in the review.
- Keep dependencies minimal. Prefer clarity and simplicity over cleverness.
- Draft Pull Requests are always welcome and do not need to follow strict rules. A _ready for review_ PR must contain working, tested, complete code that follows the style below.

## Commit messages

Write them like a tweet, max 180 characters. Only simple sentences. Only allowed punctuation is the period. If possible, keep them to 3-4 words. Use more words if really needed.

## Verifying Your Work
- Build and test through the examples in `examples/`. Prefer the existing VS Code build tasks; they already include `-vet -strict-style -vet-tabs` and come in three variants: default (D3D11 on Windows), `(GL)`, and `(web)`. Use the same `-vet -strict-style -vet-tabs` flags when running `odin` directly.
- After edits, run the most relevant build task(s) for what you touched. After a large change, run `odin run tools/test_examples`, the CI script that builds every example (some are excluded from web builds, e.g. `minimal_hello_world`, `custom_frame_update`).
- `tests/coordinate_system` holds the coordinate system checks. Run it both ways: once plain and once with `-define:KARL2D_TEST_Y_UP=true`, both with `-define:KARL2D_RENDER_BACKEND=nil -define:KARL2D_AUDIO_BACKEND=nil -define:ODIN_TEST_THREADS=1`. They open a window, so they only run where one can be created.
- Regenerate `karl2d.doc.odin`: `odin run tools/api_doc_builder`. Any change in `karl2d.doc.odin` is a user-facing API change. Make sure you want that change to actually happen. Think about what happens if you break backwards compatibility.
- Web builds use the script in `build_web/`. Forward game/compiler flags after `--`: `odin run build_web -- your_game_path -debug`. A web game must have `init` and `step` procedures; `examples/minimal_hello_world_web/` is the template.
- `tools/make_sublime_projects`, `tools/make_vscode_project/` and `tools/make_zed_project/` generate editor project configurations.

## Code Style

### Paradigm
- Write procedural imperative code. This is the most important code idea. None of that functional or OOP stuff. Prefer long procedures over compositing everything to tiny procedures. Just seeing the code that does something is easier than hopping into some othe procedure.

### Formatting
- Tabs, not spaces, for indentation.
- Max line length in `.odin` files: 100 characters. Use a ruler in your editor, split `//` comment lines at the ruler, and never go beyond it. Markdown files can and should use longer lines, since they will be viewed with line wrapping on.
- Anything that does not fit on one line is split with one item per line. That goes for procedure calls, procedure signatures, struct definitions and struct literals. The item list is indented one tab, each item ends with a comma including the last one, and the closing bracket sits on its own line at the indentation of the line that opened it. Do not pack several items onto a continuation line to save space. See `init` in `karl2d.odin` for a signature and `draw_text_static`'s call to `draw_texture_fit` for a call.

  ```
  s.proj_matrix = make_default_projection(
  	pf.get_screen_width(),
  	pf.get_screen_height(),
  	_camera_flip_y(),
  )
  ```
- The return values get split over several lines too, not just the parameters. When a signature does not fit, `-> (` opens the list, each return value sits on its own line ending with a comma, and `)` closes it with any tag and the opening brace after it. Splitting both lists reads better than keeping the return values packed on the closing line. This is only about where the line breaks go: it says nothing about naming the return values, which is a separate decision covered further down. See `create_texture` in `render_backend_d3d11.odin`.

  ```
  create_texture :: proc(
  	width: int,
  	height: int,
  	format: Pixel_Format,
  	data: rawptr,
  ) -> (
  	Texture_Handle,
  	bool,
  ) {
  ```
- Place `:` and `=` with consistent spacing as in `karl2d.odin`. Opening braces `{` go on the same line as the declaration.
- Ranges are written without spaces: `for i in 0..<len(pixels)`, not `0 ..< len(pixels)`. Attributes too: `@(private="package")`, not `@(private = "package")`.
- No single-line `if` bodies: the body goes on its own line, even when it is one statement. (One older example does this; don't copy it.)
- Struct field alignment follows the file: some files column-align field values (`platform_mac.odin`), most use a single space after `:`. Match the file you are in, and keep structs you add consistent with each other.

### Naming
- Multi-return result names use suffixes: `img, img_err := ...` and `data, data_ok := ...`. Always `thing_err`/`thing_ok`, never `err_thing`.
- A number that appears in more than one place gets a file-level constant, with a unit comment when the unit isn't obvious: `CAMERA_KEY_MOVE_SPEED :: 300 // in screen pixels/sec`.
- Procs that implement the platform interface carry the platform prefix (`mac_set_cursor`). Internal helpers may skip the prefix when the file is `#+private file` (`apply_cursor_state`).
- Log messages follow "Failed <doing> <thing>. Error: %v" or "Cannot <verb>, <thing> does not exist.". In platform backends it is also fine to name the failing OS call: "CreateIconIndirect failed with %v".

### Comments
- Use short sentences. Prefer a period over all other forms of punctuation
- Never write about how something used to work, or about what a change improved. The reader has only ever seen the current version.
- Don't duplicate information on a procedure and on a struct that the procedure uses. Put it on the procedure if unsure where to put it.

### File organization
- Group related procedures and types together.
- Separate the groups with section comments as in `karl2d.odin`: a dash line, a centered text line, and another dash line, with the dashes matching the width of the text:
  ```
  //-------//
  // INPUT //
  //-------//
  ```
- Long procedures can be split up with short ALL-CAPS section comments: `// CAMERA PANNING`, `// DRAW WORLD` (see `examples/camera/camera.odin`).

### Handles use a zero value, not `Maybe`
- Every handle type has a `<TYPE>_NONE` constant that is just its zero value (`TEXTURE_NONE`, `SOUND_NONE`, `CUSTOM_CURSOR_NONE`, ...). Declare one next to the type. Do not wrap handles in `Maybe` to express "none", and do not add a separate `bool` for whether a handle is set.
- A zero-value handle is already invalid, so `Maybe` adds a second way to say the same thing.
- It keeps handles assignable and comparable as-is. A `Custom_Cursor` goes straight into a `Cursor` union, so `selected = gauntlet` and `selected == gauntlet` just work. Wrapped in a `Maybe` both sides need unwrapping first, and the comparison needs an explicit `Cursor(...)` conversion. There is nothing to unwrap, so no `x, ok := h.?` before every use, and no temporary to carry the unwrapped value around.
- Passing a zero handle is safe: procedures that take handles log and carry on rather than misbehaving. They log on every call though, so guard with `!= <TYPE>_NONE` in code that runs each frame.
- See `examples/cursors/cursors.odin` for how this reads in practice.

### Named return values are for naked returns, and start with `_`
- A long procedure that can fail in many places ends up repeating `return SOMETHING_NONE, false` a dozen times. Naming the return values turns each of those into a naked `return`, which is shorter and keeps the failure value in one place. `load_audio_clip_from_bytes`, `load_audio_stream_from_file` and `load_static_font_from_bytes` do this.
- Whether a procedure is long enough to want this is a judgement call, done by feel. Short procedures, and ones with only a couple of failure paths, keep writing the values out: `create_custom_cursor` still returns `CUSTOM_CURSOR_NONE, false`. Do not convert a procedure just to match a neighbour, and do not convert every procedure in a file at once.
- Name them with a leading underscore: `_clip`, `_stream`, `_font`, `_ok`.
- The only two things such a procedure does with them is a naked `return` on every failure path and one real `return value, true` at the end. Never assign to `_clip` or `_ok` themselves.
- That is what the underscore is for. Assigning to a named return part way through is how they turn into bugs: a later naked `return` then hands back whatever was assigned instead of the zero value, and the reader has to track every assignment to know what actually comes out. A name that starts with `_` does not read like a variable you were meant to write to, so it doesn't happen by accident.
- This works because every `<TYPE>_NONE` is the zero value of its type, so a naked `return` gives back exactly what the explicit `return SOMETHING_NONE, false` did.

### Avoid `defer`; write the cleanup where it happens
- `defer` moves work away from the point it runs, so the reader has to reconstruct the order instead of reading top to bottom. Free, release or destroy a thing on the line after it stops being needed.
- Usually the resource dies long before the procedure does, and releasing it right there is both linear and a tighter lifetime. In `x11_create_custom_cursor` the Xcursor image is finished with the moment `cursorImageLoadCursor` has copied it, well before any of the error returns.
- If a value is still needed by the `return` expression, put the result in a local, clean up, then return the local.
- `defer` is fine when a scope really does exit many ways and each would otherwise repeat the same cleanup. `wl_create_custom_cursor` keeps `defer linux.close(fd)` because three separate paths would each have to close it.

### Take a parameter by pointer only to mutate it
- Odin already passes anything bigger than 16 bytes by implicit reference, so `^T` does not save you a copy. Passing a big struct by value is free.
- What `^T` does is tell the reader that the procedure may write to what they handed it. Spend that on read-only parameters and a pointer stops meaning anything, so nobody can tell the mutating procedures from the rest at a glance.
- `_draw_call_changes` compares two draw calls and returns what differs between them, so it takes `Draw_Call`, not `^Draw_Call`, even though they are 128 bytes each. The platform interface's `get_events` fills the array you hand it, so that one takes a pointer.
- Pointers are also right when the value is optional, or when you need the thing itself rather than its value, which is why `hm.get` hands one back.
- Don't reach for a pointer because you think it will be faster. If you believe a signature costs something, measure it. The compiler is already doing the thing you are about to do by hand.

## Architecture Notes

### Layout
- The core API is in `karl2d.odin`.
- Platform-specific code is in files like `platform_windows.odin`, `platform_linux.odin`, `platform_mac.odin`, `platform_web.odin`.
- Rendering backends are in files like `render_backend_gl.odin`, `render_backend_d3d11.odin`, `render_backend_webgl.odin`.
- Audio backends: `audio_backend_waveout.odin` (Windows), `audio_backend_core_audio.odin` (macOS), `audio_backend_alsa.odin` (Linux), `audio_backend_web_audio.odin` (web), `audio_backend_nil.odin` (fallback).
- Audio streaming has platform-split files: `audio_stream_default.odin` (non-web) and `audio_stream_web.odin`.
- File system access is split: `file_system_default.odin` (non-web, uses `core:os`) and `file_system_web.odin` (stub — file reading not yet supported on web).
- `log/log.odin` provides the internal logging utility (`karl2d_logger` package) with `debugf`, `infof`, `warnf`, `errorf`, `fatalf`.
- `default_fonts/` contains `roboto.ttf` (the default embedded font). `default_shaders/` contains HLSL, GLSL, and WebGL GLSL shaders used by render backends. Avoid modifying these unless you are changing rendering behavior.
- `platform_bindings/` contains supplementary platform-specific bindings (subdirs: `linux/`, `mac/`).

### Patterns
- The project uses an **interface/chooser pattern** for extensible subsystems: `*_interface.odin` defines a struct of function pointers (the contract), and `*_chooser.odin` selects the implementation at compile time based on platform/config. Used for platforms (`platform_interface.odin`), render backends (`render_backend_interface.odin`, `render_backend_chooser.odin`), and audio backends (`audio_backend_interface.odin`, `audio_backend_chooser.odin`).
- **Render backend selection:** On Windows the default backend is **D3D11**. On Linux/macOS it's **GL**. On web it's **WebGL**. Override with `-define:KARL2D_RENDER_BACKEND=gl` (or `d3d11`, `webgl`, `nil`). The `(GL)` VS Code build tasks use this flag.
- **GL glue files** (e.g. `platform_windows_glue_gl.odin`, `platform_linux_glue_gl_x11.odin`) handle platform-specific OpenGL context setup. These exist alongside the platform files.
- No external windowing libraries (like GLFW) are used; all window/event handling is custom.
- Rendering is batch-based for performance.
- Web builds use Odin's JS runtime and a custom WebGL backend (no emscripten required).

## Checklist Before You Are Done
- Ran the relevant build task(s), and `odin run tools/test_examples` if the change was large.
- If the API surface changed: regenerated `karl2d.doc.odin` and ran `api_verifier` (see Verifying Your Work).
- No unrelated code touched, no auto-formatter output, no whitespace changes on untouched lines.
- New code follows the Code Style section, including the comment voice and the handle/defer patterns.
