# LLM agent instructions for Karl2D

This document provides guidelines for LLM agents to read. It provides conventions for writing code, writing documentation, and collaborating on this project. Please follow these instructions to ensure consistency and maintainability.

> Human can read this file too, but it might not be optimized for human consumption. Also, note that no form of vibe coded changes are allowed. You must understand each line submitted in a pull request. You can use an LLM to do code reviews and generate initial implementations, but you _must_ understand the code generated.

## Project Overview
- **Karl2D** is a 2D game development library written in the Odin programming language.
- The focus is on beginner-friendly and using a minimal set of dependencies.
- Karl2D usually requires the latest release of Odin.
- The main entry point is `karl2d.odin`, which contains the platform-independent API and core logic.
- Platform and rendering backends are implemented in separate files (e.g., `platform_windows.odin`, `render_backend_gl.odin`).
- See `karl2d.doc.odin` for a full API overview.

## Contribution Guidelines
- **Draft Pull Requests** are always welcome and do not need to follow strict rules.
- When submitting a _ready for review_ Pull Request, you must:
  1. Ensure your code is working and tested.
  2. Submit only complete, non-rudimentary code.
  3. Avoid modifying unrelated code or using auto-formatters (e.g., odinfmt).
  4. If you make unintended changes, revert them in additional commits (squash merges are used).
  5. Regenerate `karl2d.doc.odin` after API changes: `odin run tools/api_doc_builder`.
  6. Follow the code style described below.

## Code Style
- **Tabs, not spaces** for indentation.
- **Max line length:** 100 characters. Use a ruler in your editor. Always split API comment lines that start with `//` at the 100 character ruler. Do not go beyond it!
- **Procedure signatures** that are too long should be split across lines (see `init` in `karl2d.odin`).
- **Spacing:**
  - Place `:` and `=` with consistent spacing as in `karl2d.odin`.
  - Opening braces `{` should be on the same line as the declaration.
- **API Comments:**
  - Use clear, concise comments above procedures and types.
  - Document parameters and return values where appropriate.
- **File organization:**
  - Group related procedures and types together.
  - Use clear section comments (e.g., `//-------// INPUT //-------//`).

## Architecture Notes
- The core API is in `karl2d.odin`.
- Platform-specific code is in files like `platform_windows.odin`, `platform_linux.odin`, etc.
- Rendering backends are in files like `render_backend_gl.odin`, `render_backend_d3d11.odin`, etc.
- There is some audio stream-related code in `audio_stream_default.odin` and `audio_stream_web.odin`.
- No external windowing libraries (like GLFW) are used; all window/event handling is custom.
- Rendering is batch-based for performance.
- Web builds use Odin's JS runtime and a custom WebGL backend (no emscripten required).

## Testing & Documentation
- Run and test your changes with the provided examples in the `examples/` folder.
- Prefer the existing VS Code build tasks (they already include `-vet -strict-style -vet-tabs`).
- For code changes, run at least the most relevant build task(s) for what you touched.
- For API-affecting changes, also run `api_verifier` (`odin build tools/api_verifier -debug -vet -strict-style -vet-tabs`).
- `karl2d.doc.odin` is generated output and should not be edited by hand.
- Update `karl2d.doc.odin` for any API changes by running `odin run tools/api_doc_builder`.

## Web Builds
- Use the script in `build_web/` to build web versions of your game.
- When forwarding game/compiler flags, put them after `--` (example: `odin run build_web -- your_game_path -debug`).
- Your game must have `init` and `step` procedures.
- See `examples/minimal_hello_world_web/minimal_hello_world_web.odin` for a template.

## General Advice
- Keep dependencies minimal.
- Prefer clarity and simplicity over cleverness.
- Ask questions or discuss in the project's Discord or GitHub issues.

## Agent Checklist
- Keep changes focused; avoid touching unrelated code. Don't use auto-formatters. Don't modify whitespace unless you change those lines.
- Run the most relevant existing VS Code build task(s) after edits. If you do a big edit, run the `test_examples` task.
- Use `-vet -strict-style -vet-tabs` for direct Odin command checks.
- If API surface changed, regenerate docs with `odin run tools/api_doc_builder`.
- For API changes, also verify with `odin build tools/api_verifier -debug -vet -strict-style -vet-tabs`.
- Never hand-edit `karl2d.doc.odin`.
- For web builds, forward game/compiler flags after `--`.

