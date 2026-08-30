# Handoff: custom client-side decorations on Wayland

This file is a briefing from a prior Claude session (2026-08-30, on Windows, research only). It carries everything needed to implement custom window decorations for GNOME/Wayland. Delete this file before the final PR is marked ready for review.

## Goal

Draw karl2d's own titlebar and resize borders on Wayland compositors that do not decorate windows (GNOME), so GNOME users get Wayland instead of the current X11 fallback. Compositors that offer server-side decorations (KDE, sway, Hyprland) keep them; the custom decorations are only the fallback. Karl approved this design.

## Decisions already made, do not relitigate

- PR #252 (libdecor) was closed. libdecor repaints the entire decoration on every hover state change, which dropped a 1280x720 window from 90 fps to 1 fps when the pointer rested on a decoration edge. SDL3 showed the same bug on the same machine. libdecor is off the table.
- PR #260 (merged) makes `wl_try_load` reject the session when the compositor lacks `zxdg_decoration_manager_v1`, so GNOME currently falls through to X11. This gate stays in place until the custom decorations work, then it is lifted.
- Decorations are drawn into `wl_subsurface`s with CPU-written `wl_shm` buffers. NOT the "bigger canvas" approach (enlarging the main surface and offsetting the game viewport) — that would leak into every render backend, mouse coordinates and screenshots. With subsurfaces the game canvas and all render backends stay untouched, and the code is self-contained in `platform_linux_window_wayland.odin`.
- Server-side decorations remain preferred when offered. Custom decor must not replace them on KDE/sway.

## How it works, protocol level

- A titlebar is a `wl_subsurface` attached to the main surface, positioned at negative y above it. Resize borders are thin subsurfaces on the other edges. `wl_subcompositor` (a core protocol, universally available) creates subsurfaces. It is NOT yet bound in `platform_bindings/linux/wayland/` — that binding is the first new code.
- Buffers for the subsurfaces are plain shared memory: `memfd_create` → `ftruncate` → `mmap` → write premultiplied ARGB pixels → `shm_create_pool` → `shm_pool_create_buffer`. `wl_create_custom_cursor` in `platform_linux_window_wayland.odin` (around line 1055) already does this exact dance, including the ARGB premultiply loop and the comment about pool lifetime. Copy its shape.
- Interactive move and resize are done BY THE COMPOSITOR on request: `xdg_toplevel_move` and `xdg_toplevel_resize` (already bound, `platform_bindings/linux/wayland/wayland_xdg.odin` lines ~261 and ~273). Our job is only hit-testing pointer events in the decor regions and issuing these requests with the seat and the pointer-button serial.
- `xdg_surface_set_window_geometry` (already bound, same file ~line 103) tells the compositor which rectangle counts as the window (for snapping, maximize sizing, shadow placement). It must cover game canvas plus decorations.
- Close is `send_close_event`-style: the close button just queues the same quit event the compositor close would. Maximize/minimize map to `xdg_toplevel` requests. Right-click on the bar can call `xdg_toplevel.show_window_menu`.
- Resize edge cursors: the codebase already handles cursor shapes via `wp_cursor_shape` with a theme fallback (`wl_load_cursor_theme`, `wl_apply_cursor`). The shape protocol has all the resize arrows.
- Title text: karl2d embeds Roboto and calls `stb_truetype` directly (`karl2d.odin` ~line 4082 uses `stbtt.InitFont` etc). Rasterize glyphs on the CPU and blit into the shm buffer. No new dependency.
- Redraw discipline is the whole reason we are doing this by hand: only repaint when something changes (title, focus, hover entering/leaving a button), and only the region that changed if convenient. Never repaint per pointer-motion event — that is the libdecor bug.
- HiDPI: the buffers need the surface scale applied. The codebase already binds `wp_viewporter` and uses viewports for cursors (`s.cursor_viewport`); the same technique sizes decoration subsurfaces in logical pixels regardless of buffer scale. Reload/redraw decor on scale change, same place the cursor theme reloads (`platform_linux_window_wayland.odin` ~line 712).

## Prior art, for calibration

- GLFW: libdecor first; its own fallback is solid-color subsurfaces with no title text and no buttons.
- SDL3 and Godot: libdecor only; without it the window is borderless. Godot has open issues about how little control libdecor gives.
- winit (Rust): the only windowing library that self-draws properly — sctk-adwaita, CPU-rendered Adwaita-look decorations into subsurfaces, title text, buttons, hover and focus states. That is the camp this work joins, but with one simple hardcoded look rather than a theme clone.

## Step-by-step plan

Each step builds on GNOME/Wayland and is tested before the next. Use the existing VS Code build tasks / `-vet -strict-style -vet-tabs`, and an example like `examples/cursors` or `examples/camera` for manual testing.

1. Bind `wl_subcompositor` in `platform_bindings/linux/wayland/` in the style of the existing bindings. Extend `KARL2D_LINUX_DECORATIONS` (name introduced in #252's design; check what actually survives in the code) or add a define so `custom` forces the custom path and lets `wl_try_load` accept a compositor without the decoration manager. Default behavior unchanged. Test: with the define, the game opens borderless on GNOME/Wayland (check the log says Wayland, not X11); without it, X11 fallback still happens.
2. One titlebar subsurface with a solid-color shm buffer, sized to the window width, repositioned/resized correctly on window resize. Test: colored bar sits above the game, survives resizing and maximize.
3. `set_window_geometry` covering canvas plus bar. Test: maximize fills the screen with no gap, half-tiling (if GNOME offers it) aligns correctly, no shadow misplacement.
4. Hit-testing: pointer events over the bar do not reach the game; drag on the bar calls `xdg_toplevel_move`. Test: window drags by the bar, game stops seeing those clicks.
5. Resize borders: thin edge/corner subsurfaces (can be fully transparent or 1px lines), `xdg_toplevel_resize` with the right edge enum, resize arrow cursors on hover. Test: resizable from all edges and corners with correct cursors.
6. Close button: drawn glyph (an X), hover state repaint of the button region only, click queues the quit/close event. Test: click closes the example; resting the pointer on the button or edges costs no fps (this is the explicit regression test against the libdecor failure).
7. Title text with stb_truetype/Roboto, plus focused/unfocused color states. Test: title shows, updates via `set_window_title`, dims when focus is lost.
8. Maximize and minimize buttons, double-click on bar maximizes, right-click calls `show_window_menu`. Test each.
9. Lift the #260 gate: `wl_try_load` accepts a missing decoration manager and picks custom decor automatically; SSD still preferred when offered. Verify on GNOME (custom) and ideally KDE or sway (still SSD, zero decor code active). Run `odin run tools/test_examples`. No public API change is expected, so `karl2d.doc.odin` should not change — verify with the api_doc_builder.
10. Delete this handoff file. PR description per the rules in `.claude/CLAUDE.md`.

## Open questions to settle with Karl along the way

- Bar height, colors, and whether minimize/maximize ship in the first PR or a follow-up (steps 1–7 are a shippable minimum).
- Whether `KARL2D_LINUX_DECORATIONS=custom` stays as a user-facing override on compositors that offer SSD.
