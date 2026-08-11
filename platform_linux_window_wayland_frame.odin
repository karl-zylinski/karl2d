#+build linux
package karl2d

// Draws our own window decorations for Wayland compositors that won't do it for us (GNOME/Mutter,
// primarily -- see decorations_are_client_side in platform_linux_window_wayland.odin). No external
// dependencies: four wl_subsurfaces (a painted titlebar, three 1x1-pixel-stretched border strips)
// sit outside the content surface and never overlap it, so this is purely additive.
//
// Every procedure here is safe to call unconditionally, on any Wayland compositor, at any point:
// they all check `s.frame.titlebar_surface == nil` (or, for wl_frame_insets, the same condition)
// and return immediately if there's no frame. That's what keeps this additive instead of a second
// window implementation living inside platform_linux_window_wayland.odin -- see that file's
// toplevel_listener.configure and wl_set_window_mode for the two call sites that use insets.

import "core:c"
import "core:math"
import "core:strings"
import "core:time"
import stbtt "vendor:stb/truetype"

import "log"
import wl "platform_bindings/linux/wayland"

// Logical pixels.
FRAME_TITLEBAR_HEIGHT :: 32
FRAME_BORDER          :: 4  // also the resize grab margin -- see wl_frame_hit_test
FRAME_CORNER_RADIUS   :: 9  // only the top corners are rounded

FRAME_BUTTON_HIT_SIZE  :: 28 // logical px, the square area a button occupies
FRAME_BUTTON_ICON_SIZE :: 10 // logical px, the glyph drawn inside that area
FRAME_BUTTON_GAP       :: 2
FRAME_BUTTON_MARGIN    :: 6  // gap from the titlebar's right edge to the first button

FRAME_TEXT_SIZE   :: 14 // logical px
FRAME_TEXT_MARGIN :: 8  // gap from the titlebar's left edge to the title text

FRAME_COLOR_TITLEBAR_ACTIVE   :: Color{50, 50, 54, 255}
FRAME_COLOR_TITLEBAR_INACTIVE :: Color{38, 38, 41, 255}
FRAME_COLOR_BORDER            :: Color{20, 20, 22, 255}
FRAME_COLOR_TEXT_ACTIVE       :: Color{235, 235, 235, 255}
FRAME_COLOR_TEXT_INACTIVE     :: Color{140, 140, 140, 255}
FRAME_COLOR_BUTTON_HOVER      :: Color{255, 255, 255, 35}
FRAME_COLOR_CLOSE_HOVER       :: Color{196, 43, 28, 255}

FRAME_DOUBLE_CLICK_INTERVAL :: 400 * time.Millisecond

// .None is the zero value, meaning "no button" -- see the handle-like-zero-value convention this
// codebase uses instead of Maybe (agent.md). Used both for "nothing hovered/pressed" and as
// WL_Frame_Hit.button when the hit isn't a button at all.
WL_Frame_Button :: enum {
	None,
	Minimize,
	Maximize,
	Close,
}

// Which of the frame's own surfaces (if any) a wl_surface pointer refers to.
WL_Frame_Surface :: enum {
	None,
	Titlebar,
	Left,
	Right,
	Bottom,
}

WL_Frame_Resize_Edge :: enum {
	None,
	Top,
	Bottom,
	Left,
	Right,
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
}

WL_Frame_Hit_Kind :: enum {
	None,
	Move,   // titlebar, not over a button -- drag to move, double-click to maximize, right-click menu
	Button,
	Resize,
}

WL_Frame_Hit :: struct {
	kind:        WL_Frame_Hit_Kind,
	button:      WL_Frame_Button,        // valid when kind == .Button
	resize_edge: WL_Frame_Resize_Edge,   // valid when kind == .Resize
}

// One border strip: a 1x1-pixel shm buffer stretched over its whole area by a viewport, so it
// never needs repainting, only repositioning and resizing.
WL_Frame_Strip :: struct {
	surface:    ^wl.Surface,
	subsurface: ^wl.Subsurface,
	viewport:   ^wl.WP_Viewport,
	shm_buf:    WL_SHM_Buffer,
}

WL_Frame :: struct {
	titlebar_surface:    ^wl.Surface,
	titlebar_subsurface: ^wl.Subsurface,
	titlebar_viewport:   ^wl.WP_Viewport,
	titlebar_buffer:     WL_SHM_Buffer,

	// The compositor may still be reading this one when a repaint replaces it -- see
	// titlebar_buffer_listener. Freed once its `release` event fires.
	titlebar_buffer_old: WL_SHM_Buffer,

	left:   WL_Frame_Strip,
	right:  WL_Frame_Strip,
	bottom: WL_Frame_Strip,

	// Owned copy of the window title, for the titlebar to paint. title_version is bumped whenever
	// it changes; wl_frame_repaint_titlebar compares it against painted_title_version.
	title:         string,
	title_version: int,

	// What's currently painted into titlebar_buffer, so repaints can be skipped when nothing that
	// would change the result has changed.
	painted_width:          int,
	painted_scale:          f32,
	painted_activated:      bool,
	painted_maximized:      bool,
	painted_title_version:  int,
	painted_hovered_button: WL_Frame_Button,

	// Input state -- see pointer_listener in platform_linux_window_wayland.odin.
	hovered_button:  WL_Frame_Button,
	pressed_button:  WL_Frame_Button,
	last_click_tick: time.Tick,
	has_last_click:  bool,

	font:    stbtt.fontinfo,
	font_ok: bool,
}

//---------------//
// FRAME EXTENTS //
//---------------//

// Logical-pixel insets the frame adds around the content surface. All zero when there's no frame
// (or it's hidden for fullscreen), so callers can use this unconditionally.
wl_frame_insets :: proc() -> (left, top, right, bottom: int) {
	if s.frame.titlebar_surface == nil || s.fullscreen {
		return
	}

	top = FRAME_TITLEBAR_HEIGHT + wl_frame_top_border()

	if !s.maximized {
		// A maximized window has no resize edges, so GNOME (and we) drop the borders. The
		// titlebar stays.
		left = FRAME_BORDER
		right = FRAME_BORDER
		bottom = FRAME_BORDER
	}

	return
}

// Thickness of the border strip drawn above the titlebar, in logical pixels. Zero when maximized,
// for the same reason the side borders go away: there is no resize edge up there to grab, and a
// dark line pinned to the top of the screen just looks like a mistake.
wl_frame_top_border :: proc() -> int {
	return s.maximized ? 0 : FRAME_BORDER
}

//--------------------//
// CREATE AND DESTROY //
//--------------------//

wl_frame_create :: proc() {
	if !s.decorations_are_client_side || s.subcompositor == nil {
		return
	}

	font_offset := stbtt.GetFontOffsetForIndex(raw_data(DEFAULT_FONT_DATA), 0)
	s.frame.font_ok = bool(stbtt.InitFont(&s.frame.font, raw_data(DEFAULT_FONT_DATA), font_offset))

	if !s.frame.font_ok {
		log.error("Failed loading the default font for window decorations; titlebar will have no text")
	}

	s.frame.titlebar_surface = wl.compositor_create_surface(s.compositor)
	s.frame.titlebar_subsurface = wl.subcompositor_get_subsurface(
		s.subcompositor,
		s.frame.titlebar_surface,
		s.surface,
	)
	s.frame.titlebar_viewport = wl.wp_viewporter_get_viewport(s.viewporter, s.frame.titlebar_surface)
	wl.subsurface_place_below(s.frame.titlebar_subsurface, s.surface)

	wl_frame_create_strip(&s.frame.left, s.surface)
	wl_frame_create_strip(&s.frame.right, s.surface)
	wl_frame_create_strip(&s.frame.bottom, s.surface)
}

wl_frame_create_strip :: proc(strip: ^WL_Frame_Strip, parent: ^wl.Surface) {
	strip.surface = wl.compositor_create_surface(s.compositor)
	strip.subsurface = wl.subcompositor_get_subsurface(s.subcompositor, strip.surface, parent)
	strip.viewport = wl.wp_viewporter_get_viewport(s.viewporter, strip.surface)
	wl.subsurface_place_below(strip.subsurface, s.surface)

	shm_buf, shm_buf_ok := wl_create_shm_buffer(1, 1)
	if !shm_buf_ok {
		return
	}

	strip.shm_buf = shm_buf
	pixel_data := ([^]u32)(strip.shm_buf.data)
	pixel_data[0] = wl_frame_pack_color(FRAME_COLOR_BORDER, 1)

	wl.surface_attach(strip.surface, strip.shm_buf.buffer, 0, 0)
	wl.surface_commit(strip.surface)
}

wl_frame_destroy :: proc() {
	// Freed before the guard below: wl_frame_set_title keeps the title whether or not a frame was
	// ever created, so on a server-side-decorated compositor this is the only thing to clean up.
	if s.frame.title != "" {
		delete(s.frame.title, s.allocator)
		s.frame.title = ""
	}

	if s.frame.titlebar_surface == nil {
		return
	}

	if s.frame.titlebar_buffer.buffer != nil {
		wl.buffer_destroy(s.frame.titlebar_buffer.buffer)
		wl_destroy_shm_buffer(s.frame.titlebar_buffer)
	}
	if s.frame.titlebar_buffer_old.buffer != nil {
		wl.buffer_destroy(s.frame.titlebar_buffer_old.buffer)
		wl_destroy_shm_buffer(s.frame.titlebar_buffer_old)
	}

	wl.wp_viewport_destroy(s.frame.titlebar_viewport)
	wl.subsurface_destroy(s.frame.titlebar_subsurface)
	wl.surface_destroy(s.frame.titlebar_surface)

	wl_frame_destroy_strip(&s.frame.left)
	wl_frame_destroy_strip(&s.frame.right)
	wl_frame_destroy_strip(&s.frame.bottom)

	s.frame = {}
}

wl_frame_destroy_strip :: proc(strip: ^WL_Frame_Strip) {
	if strip.shm_buf.buffer != nil {
		wl.buffer_destroy(strip.shm_buf.buffer)
		wl_destroy_shm_buffer(strip.shm_buf)
	}

	wl.wp_viewport_destroy(strip.viewport)
	wl.subsurface_destroy(strip.subsurface)
	wl.surface_destroy(strip.surface)
}

// Updates the owned copy of the title. Safe to call before the frame exists (e.g. from wl_init,
// before wl_frame_create has run) -- it just won't have anything to paint yet.
wl_frame_set_title :: proc(title: string) {
	if s.frame.title != "" {
		delete(s.frame.title, s.allocator)
	}

	s.frame.title = strings.clone(title, s.allocator)
	s.frame.title_version += 1
}

//--------//
// LAYOUT //
//--------//

// Repositions and resizes the frame's subsurfaces for a `content_width` x `content_height`
// content area, hides the border strips when maximized, hides everything when fullscreen, and
// repaints the titlebar if anything that would change its look has changed.
//
// Subsurfaces are synchronized, so none of this is visible until the *parent* surface commits.
// `flush` decides who does that. Pass false from the configure handler: the game's next render
// commits the parent along with a content buffer at the new size, so the frame and the content
// resize in the same compositor frame. Committing here instead would move the frame immediately
// while the content buffer is still the old size, which tears visibly during a resize drag.
// Everything else (title, hover, focus, scale) has no render to piggyback on and needs flush.
wl_frame_layout :: proc(content_width: int, content_height: int, flush := true) {
	if s.frame.titlebar_surface == nil {
		return
	}

	if s.fullscreen {
		wl.surface_attach(s.frame.titlebar_surface, nil, 0, 0)
		wl.surface_commit(s.frame.titlebar_surface)
		wl_frame_set_strip_visible(&s.frame.left, false)
		wl_frame_set_strip_visible(&s.frame.right, false)
		wl_frame_set_strip_visible(&s.frame.bottom, false)

		if flush {
			wl.surface_commit(s.surface)
		}
		return
	}

	left, top, right, bottom := wl_frame_insets()
	window_width := content_width + left + right

	wl.subsurface_set_position(s.frame.titlebar_subsurface, i32(-left), i32(-top))
	wl.wp_viewport_set_destination(s.frame.titlebar_viewport, i32(window_width), i32(top))
	wl_frame_repaint_titlebar(window_width)

	borders_visible := !s.maximized
	wl_frame_set_strip_visible(&s.frame.left, borders_visible)
	wl_frame_set_strip_visible(&s.frame.right, borders_visible)
	wl_frame_set_strip_visible(&s.frame.bottom, borders_visible)

	if borders_visible {
		wl.subsurface_set_position(s.frame.left.subsurface, i32(-left), 0)
		wl.wp_viewport_set_destination(s.frame.left.viewport, i32(left), i32(content_height))

		wl.subsurface_set_position(s.frame.right.subsurface, i32(content_width), 0)
		wl.wp_viewport_set_destination(s.frame.right.viewport, i32(right), i32(content_height))

		wl.subsurface_set_position(s.frame.bottom.subsurface, i32(-left), i32(content_height))
		wl.wp_viewport_set_destination(s.frame.bottom.viewport, i32(window_width), i32(bottom))
	}

	if flush {
		wl.surface_commit(s.surface)
	}
}

wl_frame_set_strip_visible :: proc(strip: ^WL_Frame_Strip, visible: bool) {
	if visible {
		if strip.shm_buf.buffer != nil {
			wl.surface_attach(strip.surface, strip.shm_buf.buffer, 0, 0)
			wl.surface_commit(strip.surface)
		}
	} else {
		// Attaching no buffer unmaps a wl_surface -- there's no dedicated "hide" request.
		wl.surface_attach(strip.surface, nil, 0, 0)
		wl.surface_commit(strip.surface)
	}
}

//--------------------//
// TITLEBAR REPAINTING //
//--------------------//

wl_frame_repaint_titlebar :: proc(window_width: int) {
	needs_repaint :=
		window_width != s.frame.painted_width ||
		s.scale != s.frame.painted_scale ||
		s.activated != s.frame.painted_activated ||
		s.maximized != s.frame.painted_maximized ||
		s.frame.title_version != s.frame.painted_title_version ||
		s.frame.hovered_button != s.frame.painted_hovered_button

	if !needs_repaint {
		return
	}

	// Only record what we painted if we actually painted it, so a failed buffer allocation gets
	// retried on the next layout instead of being remembered as done.
	if !wl_frame_paint_titlebar(window_width) {
		return
	}

	s.frame.painted_width = window_width
	s.frame.painted_scale = s.scale
	s.frame.painted_activated = s.activated
	s.frame.painted_maximized = s.maximized
	s.frame.painted_title_version = s.frame.title_version
	s.frame.painted_hovered_button = s.frame.hovered_button
}

wl_frame_paint_titlebar :: proc(window_width: int) -> bool {
	top_border := wl_frame_top_border()

	physical_w := max(1, int(math.round(f32(window_width) * s.scale)))
	physical_h := max(1, int(math.round(f32(FRAME_TITLEBAR_HEIGHT + top_border) * s.scale)))

	shm_buf, shm_buf_ok := wl_create_shm_buffer(physical_w, physical_h)
	if !shm_buf_ok {
		return false
	}

	colors := make([]Color, physical_w * physical_h, frame_allocator)

	bg := s.activated ? FRAME_COLOR_TITLEBAR_ACTIVE : FRAME_COLOR_TITLEBAR_INACTIVE
	for &col in colors {
		col = bg
	}

	border_px := min(int(math.round(f32(top_border) * s.scale)), physical_h)
	for y in 0..<border_px {
		for x in 0..<physical_w {
			colors[y * physical_w + x] = FRAME_COLOR_BORDER
		}
	}

	text_color := s.activated ? FRAME_COLOR_TEXT_ACTIVE : FRAME_COLOR_TEXT_INACTIVE

	buttons, button_count := wl_frame_visible_buttons()
	leftmost_button_px := physical_w

	for button in buttons[:button_count] {
		bx, by, bw, bh := wl_frame_button_rect(button, window_width)

		px := int(math.round(f32(bx) * s.scale))
		py := int(math.round(f32(by) * s.scale))
		pw := int(math.round(f32(bw) * s.scale))
		ph := int(math.round(f32(bh) * s.scale))

		leftmost_button_px = min(leftmost_button_px, px)

		icon_color := text_color

		if s.frame.hovered_button == button {
			if button == .Close {
				wl_frame_fill_rect(colors, physical_w, physical_h, px, py, pw, ph, FRAME_COLOR_CLOSE_HOVER, 1)
				icon_color = FRAME_COLOR_TEXT_ACTIVE
			} else {
				wl_frame_fill_rect(colors, physical_w, physical_h, px, py, pw, ph, FRAME_COLOR_BUTTON_HOVER, 1)
			}
		}

		center_x := f32(px) + f32(pw) / 2
		center_y := f32(py) + f32(ph) / 2
		icon_half := f32(FRAME_BUTTON_ICON_SIZE) * s.scale / 2

		wl_frame_paint_button_icon(
			colors, physical_w, physical_h, button, center_x, center_y, icon_half, icon_color,
		)
	}

	wl_frame_draw_text(colors, physical_w, physical_h, s.frame.title, leftmost_button_px, text_color)

	corner_radius_px := int(math.round(f32(FRAME_CORNER_RADIUS) * s.scale))

	pixel_data := ([^]u32)(shm_buf.data)
	for y in 0..<physical_h {
		for x in 0..<physical_w {
			coverage := wl_frame_corner_coverage(x, y, physical_w, corner_radius_px)
			pixel_data[y * physical_w + x] = wl_frame_pack_color(colors[y * physical_w + x], coverage)
		}
	}

	if s.frame.titlebar_buffer_old.buffer != nil {
		// A repaint landed again before the previous one's release event fired (a fast resize
		// drag). Free it immediately rather than queue it -- worst case a single frame tears,
		// which is preferable to an unbounded queue of pending buffers.
		wl.buffer_destroy(s.frame.titlebar_buffer_old.buffer)
		wl_destroy_shm_buffer(s.frame.titlebar_buffer_old)
	}

	s.frame.titlebar_buffer_old = s.frame.titlebar_buffer
	s.frame.titlebar_buffer = shm_buf

	wl.add_listener(s.frame.titlebar_buffer.buffer, &titlebar_buffer_listener, nil)
	wl.surface_attach(s.frame.titlebar_surface, s.frame.titlebar_buffer.buffer, 0, 0)
	wl.surface_commit(s.frame.titlebar_surface)
	return true
}

// The previous titlebar buffer stays alive until the compositor confirms it's done reading from
// it, since we can't safely free memory it might still be compositing from.
titlebar_buffer_listener := wl.Buffer_Listener {
	release = proc "c" (data: rawptr, buffer: ^wl.Buffer) {
		context = s.odin_ctx

		if buffer == s.frame.titlebar_buffer_old.buffer {
			wl.buffer_destroy(buffer)
			wl_destroy_shm_buffer(s.frame.titlebar_buffer_old)
			s.frame.titlebar_buffer_old = {}
		}
	},
}

//---------//
// BUTTONS //
//---------//

wl_frame_visible_buttons :: proc() -> (buttons: [3]WL_Frame_Button, count: int) {
	if s.wm_can_minimize {
		buttons[count] = .Minimize
		count += 1
	}
	if s.wm_can_maximize {
		buttons[count] = .Maximize
		count += 1
	}
	buttons[count] = .Close
	count += 1
	return
}

// Logical-pixel hit rect for `button`, relative to the titlebar surface's own top-left (so `y`
// already accounts for the top border strip). Shared between painting and wl_frame_hit_test below,
// so the two can never disagree about where a button actually is.
wl_frame_button_rect :: proc(button: WL_Frame_Button, window_width: int) -> (x, y, w, h: int) {
	buttons, count := wl_frame_visible_buttons()

	index := -1
	for b, i in buttons[:count] {
		if b == button {
			index = i
		}
	}

	if index == -1 {
		return
	}

	from_right := count - index
	step := FRAME_BUTTON_HIT_SIZE + FRAME_BUTTON_GAP
	right_edge := window_width - FRAME_BUTTON_MARGIN - (from_right - 1) * step

	x = right_edge - FRAME_BUTTON_HIT_SIZE
	y = wl_frame_top_border() + (FRAME_TITLEBAR_HEIGHT - FRAME_BUTTON_HIT_SIZE) / 2
	w = FRAME_BUTTON_HIT_SIZE
	h = FRAME_BUTTON_HIT_SIZE
	return
}

//-------//
// INPUT //
//-------//

// Which frame surface (if any) `surface` is. Used to route pointer events -- see pointer_listener
// in platform_linux_window_wayland.odin.
wl_frame_surface_role :: proc(surface: ^wl.Surface) -> WL_Frame_Surface {
	if surface == nil {
		return .None
	}

	switch surface {
	case s.frame.titlebar_surface: return .Titlebar
	case s.frame.left.surface:     return .Left
	case s.frame.right.surface:    return .Right
	case s.frame.bottom.surface:   return .Bottom
	}

	return .None
}

// The full window's logical-pixel width (content plus left/right insets), which is what frame
// hit-testing and cursor decisions are expressed in.
wl_frame_window_width :: proc() -> int {
	left, _, right, _ := wl_frame_insets()
	return s.last_configure_width + left + right
}

// What's under `local` (logical pixels, relative to whichever frame surface `role` names) --
// a button, a resize edge (with corners near the ends of the titlebar and bottom strips), or the
// titlebar's plain move/menu area. wl_frame_button_rect is the single source of truth for where
// buttons are, so this and the painting code can never disagree.
wl_frame_hit_test :: proc(role: WL_Frame_Surface, local: Vec2, window_width: int) -> WL_Frame_Hit {
	switch role {
	case .Titlebar:
		buttons, count := wl_frame_visible_buttons()

		for button in buttons[:count] {
			bx, by, bw, bh := wl_frame_button_rect(button, window_width)
			if local.x >= f32(bx) && local.x < f32(bx + bw) && local.y >= f32(by) && local.y < f32(by + bh) {
				return {kind = .Button, button = button}
			}
		}

		// Zero-height when maximized, so this whole block falls through to .Move there.
		if local.y < f32(wl_frame_top_border()) {
			if local.x < FRAME_BORDER {
				return {kind = .Resize, resize_edge = .Top_Left}
			}
			if local.x >= f32(window_width - FRAME_BORDER) {
				return {kind = .Resize, resize_edge = .Top_Right}
			}
			return {kind = .Resize, resize_edge = .Top}
		}

		return {kind = .Move}

	case .Left:
		return {kind = .Resize, resize_edge = .Left}

	case .Right:
		return {kind = .Resize, resize_edge = .Right}

	case .Bottom:
		if local.x < FRAME_BORDER {
			return {kind = .Resize, resize_edge = .Bottom_Left}
		}
		if local.x >= f32(window_width - FRAME_BORDER) {
			return {kind = .Resize, resize_edge = .Bottom_Right}
		}
		return {kind = .Resize, resize_edge = .Bottom}

	case .None:
	}

	return {}
}

wl_frame_resize_edge_wire :: proc(edge: WL_Frame_Resize_Edge) -> c.uint32_t {
	switch edge {
	case .Top:          return wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP
	case .Bottom:       return wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM
	case .Left:         return wl.XDG_TOPLEVEL_RESIZE_EDGE_LEFT
	case .Right:        return wl.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT
	case .Top_Left:     return wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT
	case .Top_Right:    return wl.XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT
	case .Bottom_Left:  return wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT
	case .Bottom_Right: return wl.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT
	case .None:
	}
	return wl.XDG_TOPLEVEL_RESIZE_EDGE_NONE
}

wl_frame_resize_edge_cursor :: proc(edge: WL_Frame_Resize_Edge) -> Standard_Cursor {
	switch edge {
	case .Top, .Bottom:            return .Resize_NS
	case .Left, .Right:            return .Resize_EW
	case .Top_Left, .Bottom_Right: return .Resize_NWSE
	case .Top_Right, .Bottom_Left: return .Resize_NESW
	case .None:
	}
	return .Default
}

// What cursor to show for the pointer's current position over a frame surface.
wl_frame_cursor :: proc(role: WL_Frame_Surface) -> Standard_Cursor {
	hit := wl_frame_hit_test(role, s.pointer_local, wl_frame_window_width())

	if hit.kind != .Resize {
		return .Default
	}

	return wl_frame_resize_edge_cursor(hit.resize_edge)
}

// Updates which button (if any) is hovered, and repaints the titlebar if that changed. Called
// from pointer_listener.motion while over the titlebar.
wl_frame_update_hover :: proc(role: WL_Frame_Surface) {
	hit := wl_frame_hit_test(role, s.pointer_local, wl_frame_window_width())

	new_hover := WL_Frame_Button.None
	if hit.kind == .Button {
		new_hover = hit.button
	}

	if new_hover == s.frame.hovered_button {
		return
	}

	s.frame.hovered_button = new_hover
	wl_frame_layout(s.last_configure_width, s.last_configure_height)
}

// Runs the effect of clicking `button` -- called on release, once pointer_listener has confirmed
// the press and release both landed on the same button.
wl_frame_click_button :: proc(button: WL_Frame_Button) {
	switch button {
	case .Close:
		append(&s.events, Event_Close_Window_Requested{})

	case .Maximize:
		if s.maximized {
			wl.xdg_toplevel_unset_maximized(s.toplevel)
		} else {
			wl.xdg_toplevel_set_maximized(s.toplevel)
		}

	case .Minimize:
		wl.xdg_toplevel_set_minimized(s.toplevel)

	case .None:
	}
}

// Paints a button's icon (an X, a square outline, or a bar) as anti-aliased strokes centered at
// (center_x, center_y), all in physical pixels.
wl_frame_paint_button_icon :: proc(
	colors: []Color,
	buf_w: int,
	buf_h: int,
	button: WL_Frame_Button,
	center_x: f32,
	center_y: f32,
	icon_half: f32,
	color: Color,
) {
	segments: [4][4]f32
	seg_count := 0

	switch button {
	case .Close:
		segments[0] = {-icon_half, -icon_half, icon_half, icon_half}
		segments[1] = {-icon_half, icon_half, icon_half, -icon_half}
		seg_count = 2
	case .Maximize:
		segments[0] = {-icon_half, -icon_half, icon_half, -icon_half}
		segments[1] = {icon_half, -icon_half, icon_half, icon_half}
		segments[2] = {icon_half, icon_half, -icon_half, icon_half}
		segments[3] = {-icon_half, icon_half, -icon_half, -icon_half}
		seg_count = 4
	case .Minimize:
		segments[0] = {-icon_half, icon_half, icon_half, icon_half}
		seg_count = 1
	case .None:
		return
	}

	stroke := max(f32(1), s.scale)

	min_x := max(0, int(center_x - icon_half - stroke))
	max_x := min(buf_w - 1, int(center_x + icon_half + stroke))
	min_y := max(0, int(center_y - icon_half - stroke))
	max_y := min(buf_h - 1, int(center_y + icon_half + stroke))

	for y in min_y..=max_y {
		for x in min_x..=max_x {
			coverage: f32 = 0

			for i in 0..<seg_count {
				seg := segments[i]
				seg_coverage := wl_frame_line_coverage(
					f32(x) - center_x, f32(y) - center_y,
					seg[0], seg[1], seg[2], seg[3],
					stroke,
				)
				coverage = max(coverage, seg_coverage)
			}

			if coverage > 0 {
				idx := y * buf_w + x
				colors[idx] = wl_frame_blend(colors[idx], color, coverage)
			}
		}
	}
}

//------//
// TEXT //
//------//

wl_frame_draw_text :: proc(
	colors: []Color,
	buf_w: int,
	buf_h: int,
	title: string,
	right_limit_px: int,
	color: Color,
) {
	if !s.frame.font_ok || right_limit_px <= 0 {
		return
	}

	pixel_height := f32(FRAME_TEXT_SIZE) * s.scale
	scale := stbtt.ScaleForPixelHeight(&s.frame.font, pixel_height)

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&s.frame.font, &ascent, &descent, &line_gap)

	total_width: f32 = 0
	for r in title {
		idx := stbtt.FindGlyphIndex(&s.frame.font, r)
		if idx <= 0 {
			continue
		}
		advance: i32
		stbtt.GetGlyphHMetrics(&s.frame.font, idx, &advance, nil)
		total_width += f32(advance) * scale
	}

	available_left := f32(int(math.round(f32(FRAME_TEXT_MARGIN) * s.scale)))
	available_width := f32(right_limit_px) - available_left

	if available_width <= 0 {
		return
	}

	pen_x := available_left + max(0, (available_width - total_width) / 2)
	titlebar_top_px := f32(int(math.round(f32(FRAME_BORDER) * s.scale)))
	baseline_y :=
		titlebar_top_px + f32(FRAME_TITLEBAR_HEIGHT) * s.scale / 2 + f32(ascent + descent) * scale / 2

	for r in title {
		if pen_x >= f32(right_limit_px) {
			break // Out of room -- simplest form of clipping a too-long title.
		}

		idx := stbtt.FindGlyphIndex(&s.frame.font, r)
		if idx <= 0 {
			continue
		}

		advance: i32
		stbtt.GetGlyphHMetrics(&s.frame.font, idx, &advance, nil)

		w, h, xoff, yoff: c.int
		bitmap := stbtt.GetGlyphBitmap(&s.frame.font, scale, scale, idx, &w, &h, &xoff, &yoff)

		if bitmap != nil {
			for by in 0..<int(h) {
				for bx in 0..<int(w) {
					dst_x := int(pen_x) + int(xoff) + bx
					dst_y := int(baseline_y) + int(yoff) + by

					if dst_x < 0 || dst_x >= buf_w || dst_y < 0 || dst_y >= buf_h || dst_x >= right_limit_px {
						continue
					}

					coverage := f32(bitmap[by * int(w) + bx]) / 255
					if coverage <= 0 {
						continue
					}

					dst_idx := dst_y * buf_w + dst_x
					colors[dst_idx] = wl_frame_blend(colors[dst_idx], color, coverage)
				}
			}

			stbtt.FreeBitmap(bitmap, nil)
		}

		pen_x += f32(advance) * scale
	}
}

//----------------//
// PIXEL HELPERS //
//----------------//

// Blends `color` at `coverage` over every pixel in the `w` x `h` rect at (x,y), clipped to the
// buffer. Used for button hover backgrounds.
wl_frame_fill_rect :: proc(
	colors: []Color,
	buf_w: int,
	buf_h: int,
	x, y, w, h: int,
	color: Color,
	coverage: f32,
) {
	min_x := max(0, x)
	max_x := min(buf_w - 1, x + w - 1)
	min_y := max(0, y)
	max_y := min(buf_h - 1, y + h - 1)

	for py in min_y..=max_y {
		for px in min_x..=max_x {
			idx := py * buf_w + px
			colors[idx] = wl_frame_blend(colors[idx], color, coverage)
		}
	}
}

// Anti-aliased coverage (0..1) for how much a stroke of `thickness` along the segment
// (x0,y0)-(x1,y1) covers the point (px,py). All in the same space (physical pixels here).
wl_frame_line_coverage :: proc(px, py, x0, y0, x1, y1, thickness: f32) -> f32 {
	dx := x1 - x0
	dy := y1 - y0
	len_sq := dx*dx + dy*dy

	t: f32 = 0
	if len_sq > 0 {
		t = clamp(((px - x0) * dx + (py - y0) * dy) / len_sq, 0, 1)
	}

	cx := x0 + t*dx
	cy := y0 + t*dy
	dist := math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))

	half := thickness / 2
	if dist <= half - 0.5 {
		return 1
	}
	if dist >= half + 0.5 {
		return 0
	}
	return half + 0.5 - dist
}

// Anti-aliased coverage (0..1) for whether the pixel at (px,py) in a buffer `w` wide falls inside
// a rounded top corner. 1 (fully opaque) everywhere except within `radius` physical pixels of a
// top corner; only the top corners round, matching GNOME's own windows.
wl_frame_corner_coverage :: proc(px, py, w, radius: int) -> f32 {
	if radius <= 0 {
		return 1
	}

	cx, cy: int
	corner := false

	if px < radius && py < radius {
		cx, cy = radius, radius
		corner = true
	} else if px >= w - radius && py < radius {
		cx, cy = w - radius - 1, radius
		corner = true
	}

	if !corner {
		return 1
	}

	dx := f32(px - cx)
	dy := f32(py - cy)
	dist := math.sqrt(dx*dx + dy*dy)
	r := f32(radius)

	if dist <= r - 0.5 {
		return 1
	}
	if dist >= r + 0.5 {
		return 0
	}
	return r + 0.5 - dist
}

// Blends `fg` over the opaque `bg` at `coverage` (0..1), scaled by fg's own alpha. Every frame
// color is fully opaque, so this always returns a fully opaque result -- true transparency (the
// rounded corners) is applied once, separately, in wl_frame_pack_color.
wl_frame_blend :: proc(bg: Color, fg: Color, coverage: f32) -> Color {
	t := coverage * f32(fg.a) / 255
	return {
		u8(f32(bg.r) + (f32(fg.r) - f32(bg.r)) * t),
		u8(f32(bg.g) + (f32(fg.g) - f32(bg.g)) * t),
		u8(f32(bg.b) + (f32(fg.b) - f32(bg.b)) * t),
		255,
	}
}

// Packs a straight color into a premultiplied ARGB8888 u32, with its own alpha additionally
// scaled by `coverage` -- used to carve the transparent rounded corners out of an otherwise
// opaque buffer.
wl_frame_pack_color :: proc(col: Color, coverage: f32) -> u32 {
	a := f32(col.a) * coverage
	r := f32(col.r) * a / 255
	g := f32(col.g) * a / 255
	b := f32(col.b) * a / 255
	return u32(a) << 24 | u32(r) << 16 | u32(g) << 8 | u32(b)
}
