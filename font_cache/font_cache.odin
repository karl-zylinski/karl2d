// For dynamically building fonts.
//
// The skyline rectangle packing in this file is ported from Fontstash by Mikko Mononen. Fontstash
// is licensed under the zlib license: https://github.com/memononen/fontstash
package karl2d_font_cache

import "base:runtime"
import "core:math"
import "core:slice"
import "core:unicode/utf8"
import stbtt "vendor:stb/truetype"

PAGE_START_SIZE :: 256
PAGE_MAX_SIZE :: 2048
MAX_PAGES :: 4
GLYPH_PADDING :: 1

Font :: struct {
	info: stbtt.fontinfo,
	data: []u8,
	ascent: f32,
	height_units: f32,
	glyphs: map[Glyph_Key]Glyph,
	kerning: map[[2]i32]i32,
	pages: [dynamic]Page,
	allocator: runtime.Allocator,
}

Glyph_Key :: distinct u64

Glyph :: struct {
	page: int,
	x: int,
	y: int,
	width: int,
	height: int,
	offset: [2]f32,
	advance: f32,
	index: i32,
}

// A page is a CPU-side image into which glyphs have been blitted. Use dirty_min and dirty_max to
// figure out which rectangle in it you need to upload to the GPU.
Page :: struct {
	pixels: []u8,
	width: int,
	height: int,
	nodes: [dynamic]Skyline_Node,
	glyph_keys: [dynamic]Glyph_Key,
	dirty_min: [2]int,
	dirty_max: [2]int,
	last_used: f64,
	last_reset: f64,
}

Skyline_Node :: struct {
	x: int,
	y: int,
	width: int,
}

init :: proc(font: ^Font, data: []u8, allocator: runtime.Allocator) -> bool {
	font^ = {
		data = slice.clone(data, allocator),
		glyphs = make(map[Glyph_Key]Glyph, allocator),
		kerning = make(map[[2]i32]i32, allocator),
		pages = make([dynamic]Page, allocator),
		allocator = allocator,
	}

	font_offset := stbtt.GetFontOffsetForIndex(raw_data(font.data), 0)

	if !stbtt.InitFont(&font.info, raw_data(font.data), font_offset) {
		destroy(font)
		return false
	}

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &line_gap)
	font.ascent = f32(ascent) / f32(ascent - descent)
	font.height_units = f32(ascent - descent)

	add_page(font)
	return true
}

destroy :: proc(font: ^Font) {
	for page in font.pages {
		delete(page.pixels, font.allocator)
		delete(page.nodes)
		delete(page.glyph_keys)
	}

	delete(font.pages)
	delete(font.glyphs)
	delete(font.kerning)
	delete(font.data, font.allocator)
	font^ = {}
}

get_glyph :: proc(
	font: ^Font,
	codepoint: rune,
	size: int,
	time: f64,
) -> (
	Glyph,
	bool,
) {
	key := Glyph_Key(u64(codepoint) << 32 | u64(u32(size)))

	if glyph, glyph_ok := font.glyphs[key]; glyph_ok {
		if glyph.width > 0 {
			font.pages[glyph.page].last_used = time
		}

		return glyph, true
	}

	index := stbtt.FindGlyphIndex(&font.info, codepoint)
	scale := f32(size) / font.height_units

	advance, left_side_bearing: i32
	stbtt.GetGlyphHMetrics(&font.info, index, &advance, &left_side_bearing)

	x0, y0, x1, y1: i32
	stbtt.GetGlyphBitmapBox(&font.info, index, scale, scale, &x0, &y0, &x1, &y1)

	glyph := Glyph {
		offset = {
			f32(x0 - GLYPH_PADDING),
			f32(y0 - GLYPH_PADDING) + font.ascent * f32(size),
		},
		advance = f32(advance) * scale,
		index = index,
	}

	bitmap_width := int(x1 - x0)
	bitmap_height := int(y1 - y0)
	padded_width := bitmap_width + GLYPH_PADDING * 2
	padded_height := bitmap_height + GLYPH_PADDING * 2

	if bitmap_width > 0 && bitmap_height > 0 &&
	   padded_width <= PAGE_MAX_SIZE && padded_height <= PAGE_MAX_SIZE {
		placed := false

		for &page, page_idx in font.pages {
			x, y, fits := page_add_rect(&page, padded_width, padded_height)

			if !fits {
				continue
			}

			bitmap_x := x + GLYPH_PADDING
			bitmap_y := y + GLYPH_PADDING

			stbtt.MakeGlyphBitmap(
				&font.info,
				raw_data(page.pixels[bitmap_x + bitmap_y * page.width:]),
				i32(bitmap_width),
				i32(bitmap_height),
				i32(page.width),
				scale,
				scale,
				index,
			)

			glyph.page = page_idx
			glyph.x = x
			glyph.y = y
			glyph.width = padded_width
			glyph.height = padded_height

			page.dirty_min.x = min(page.dirty_min.x, x)
			page.dirty_min.y = min(page.dirty_min.y, y)
			page.dirty_max.x = max(page.dirty_max.x, x + padded_width)
			page.dirty_max.y = max(page.dirty_max.y, y + padded_height)
			page.last_used = time
			append(&page.glyph_keys, key)
			placed = true
			break
		}

		if !placed {
			return glyph, false
		}
	}

	font.glyphs[key] = glyph
	return glyph, true
}

make_room :: proc(font: ^Font, time: f64) -> bool {
	newest := &font.pages[len(font.pages) - 1]

	if newest.width < PAGE_MAX_SIZE {
		old_width := newest.width
		old_height := newest.height
		new_width := old_width * 2
		new_height := old_height * 2
		new_pixels := make([]u8, new_width * new_height, font.allocator)

		for y in 0..<old_height {
			copy(new_pixels[y * new_width:], newest.pixels[y * old_width:(y + 1) * old_width])
		}

		delete(newest.pixels, font.allocator)
		newest.pixels = new_pixels
		newest.width = new_width
		newest.height = new_height
		newest.dirty_min = {}
		newest.dirty_max = { old_width, old_height }

		append(&newest.nodes, Skyline_Node {
			x = old_width,
			y = 0,
			width = new_width - old_width,
		})

		return true
	}

	if len(font.pages) < MAX_PAGES {
		add_page(font)
		return true
	}

	oldest := -1

	for page, page_idx in font.pages {
		if page.last_reset == time {
			continue
		}

		if oldest == -1 || page.last_used < font.pages[oldest].last_used {
			oldest = page_idx
		}
	}

	if oldest == -1 {
		return false
	}

	page := &font.pages[oldest]

	for key in page.glyph_keys {
		delete_key(&font.glyphs, key)
	}

	clear(&page.glyph_keys)
	clear(&page.nodes)
	append(&page.nodes, Skyline_Node {
		width = page.width,
	})

	slice.zero(page.pixels)
	page.dirty_min = { page.width, page.height }
	page.dirty_max = {}
	page.last_reset = time
	return true
}

add_page :: proc(font: ^Font) {
	page := Page {
		pixels = make([]u8, PAGE_START_SIZE * PAGE_START_SIZE, font.allocator),
		width = PAGE_START_SIZE,
		height = PAGE_START_SIZE,
		nodes = make([dynamic]Skyline_Node, font.allocator),
		glyph_keys = make([dynamic]Glyph_Key, font.allocator),
		dirty_min = { PAGE_START_SIZE, PAGE_START_SIZE },
	}

	append(&page.nodes, Skyline_Node {
		width = PAGE_START_SIZE,
	})

	append(&font.pages, page)
}

kern :: proc(font: ^Font, prev_index: i32, index: i32, size: int) -> f32 {
	pair := [2]i32 { prev_index, index }
	advance, advance_ok := font.kerning[pair]

	if !advance_ok {
		advance = stbtt.GetGlyphKernAdvance(&font.info, prev_index, index)
		font.kerning[pair] = advance
	}

	return f32(advance) * (f32(size) / font.height_units)
}

// ---
// ITERATOR FOR PLACING TEXT

Place_Text_Iterator :: struct {
	text: string,
	size: int,
	time: f64,
	x: f32,
	y: f32,
	prev_index: i32,
}

Place_Text_Iterator_Result :: enum {
	Placed,
	Done,
	No_Room,
}

// A glyph that has been placed by the iterator. The x and y are the top-left of the glyph, relative
// to the start of the text.
Placed_Glyph :: struct {
	glyph: Glyph,
	x: f32,
	y: f32,
}

place_text_iterator_init :: proc(text: string, size: int, time: f64) -> Place_Text_Iterator {
	return {
		text = text,
		size = size,
		time = time,
		prev_index = -1,
	}
}

place_text_iterate :: proc(
	font: ^Font,
	it: ^Place_Text_Iterator,
) -> (
	Placed_Glyph,
	Place_Text_Iterator_Result,
) {
	for len(it.text) > 0 {
		codepoint, codepoint_width := utf8.decode_rune(it.text)

		switch codepoint {
		case '\r':
			it.text = it.text[codepoint_width:]
			continue

		case '\n':
			it.text = it.text[codepoint_width:]
			it.x = 0
			it.y += f32(it.size)
			it.prev_index = -1
			continue

		case '\t':
			it.text = it.text[codepoint_width:]
			it.x += 2 * f32(it.size)
			it.prev_index = -1
			continue
		}

		glyph, glyph_ok := get_glyph(font, codepoint, it.size, it.time)

		if !glyph_ok {
			return {}, .No_Room
		}

		it.text = it.text[codepoint_width:]

		if it.prev_index != -1 {
			it.x += kern(font, it.prev_index, glyph.index, it.size)
		}

		placed := Placed_Glyph {
			glyph = glyph,
			x = math.floor(it.x + glyph.offset.x),
			y = math.floor(it.y + glyph.offset.y),
		}

		it.x += glyph.advance
		it.prev_index = glyph.index
		return placed, .Placed
	}

	return {}, .Done
}

measure :: proc(font: ^Font, text: string, size: int, time: f64) -> ([2]f32, bool) {
	it := place_text_iterator_init(text, size, time)
	width: f32

	place_res := Place_Text_Iterator_Result.Placed

	for place_res == .Placed {
		_, place_res = place_text_iterate(font, &it)
		width = max(width, it.x)
	}

	return { width, it.y + f32(size) }, place_res == .Done
}

page_add_rect :: proc(page: ^Page, width: int, height: int) -> (x: int, y: int, ok: bool) {
	best_width := page.width
	best_height := page.height
	best_idx := -1
	best_x := -1
	best_y := -1

	// Bottom left fit heuristic.
	for node, node_idx in page.nodes {
		fit_y := page_rect_fits(page^, node_idx, width, height)

		if fit_y != -1 {
			if fit_y + height < best_height ||
			   (fit_y + height == best_height && node.width < best_width) {
				best_idx = node_idx
				best_width = node.width
				best_height = fit_y + height
				best_x = node.x
				best_y = fit_y
			}
		}
	}

	if best_idx == -1 {
		return 0, 0, false
	}

	// Perform the actual packing.
	page_add_skyline_level(page, best_idx, best_x, best_y, width, height)
	return best_x, best_y, true
}

page_rect_fits :: proc(page: Page, idx: int, width: int, height: int) -> int {
	// Checks if there is enough space at the location of skyline span 'i',
	// and return the max height of all skyline spans under that at that location,
	// (think tetris block being dropped at that position). Or -1 if no space found.

	idx := idx
	x := page.nodes[idx].x
	y := page.nodes[idx].y

	if x + width > page.width {
		return -1
	}

	space_left := width

	for space_left > 0 {
		if idx == len(page.nodes) {
			return -1
		}

		y = max(y, page.nodes[idx].y)

		if y + height > page.height {
			return -1
		}

		space_left -= page.nodes[idx].width
		idx += 1
	}

	return y
}

page_add_skyline_level :: proc(page: ^Page, idx: int, x: int, y: int, width: int, height: int) {
	// insert new node
	inject_at(&page.nodes, idx, Skyline_Node {
		x = x,
		y = y + height,
		width = width,
	})

	// Delete skyline segments that fall under the shadow of the new segment.
	for i := idx + 1; i < len(page.nodes); i += 1 {
		if page.nodes[i].x >= page.nodes[i-1].x + page.nodes[i-1].width {
			break
		}

		shrink := page.nodes[i-1].x + page.nodes[i-1].width - page.nodes[i].x
		page.nodes[i].x += shrink
		page.nodes[i].width -= shrink

		if page.nodes[i].width > 0 {
			break
		}

		ordered_remove(&page.nodes, i)
		i -= 1
	}

	// Merge same height skyline segments that are next to each other.
	for i := 0; i < len(page.nodes) - 1; /**/ {
		if page.nodes[i].y == page.nodes[i+1].y {
			page.nodes[i].width += page.nodes[i+1].width
			ordered_remove(&page.nodes, i+1)
		} else {
			i += 1
		}
	}
}
