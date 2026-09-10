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

// You have one of these per font.
Font_Cache :: struct {
	info: stbtt.fontinfo,
	data: []u8,
	ascent: f32,
	glyphs: map[Glyph_Key]Glyph,
	kerning: map[[2]i32]i32,
	pages: [dynamic]Page,
	frame: int,
	allocator: runtime.Allocator,
}

Glyph_Key :: struct {
	codepoint: rune,
	size: int,
}

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

// A page will usually map to a texture. But the font cache doesn't know about textures.
Page :: struct {
	pixels: []u8,
	width: int,
	height: int,
	nodes: [dynamic]Skyline_Node,
	glyph_keys: [dynamic]Glyph_Key,
	dirty_min: [2]int,
	dirty_max: [2]int,
	last_used: int,
	reset_frame: int,
}

Skyline_Node :: struct {
	x: int,
	y: int,
	width: int,
}

Text_Iterator :: struct {
	text: string,
	size: int,
	x: f32,
	y: f32,
	prev_index: i32,
}

Placed_Glyph :: struct {
	glyph: Glyph,
	x: f32,
	y: f32,
}

Text_Iterator_Result :: enum {
	Placed,
	Done,
	No_Room,
}

init :: proc(cache: ^Font_Cache, data: []u8, allocator: runtime.Allocator) -> bool {
	info: stbtt.fontinfo
	font_offset := stbtt.GetFontOffsetForIndex(raw_data(data), 0)

	if !stbtt.InitFont(&info, raw_data(data), font_offset) {
		return false
	}

	cache^ = {
		info = info,
		data = slice.clone(data, allocator),
		glyphs = make(map[Glyph_Key]Glyph, allocator),
		kerning = make(map[[2]i32]i32, allocator),
		pages = make([dynamic]Page, allocator),
		frame = 1,
		allocator = allocator,
	}

	cache.info.data = raw_data(cache.data)

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&cache.info, &ascent, &descent, &line_gap)
	cache.ascent = f32(ascent) / f32(ascent - descent)

	add_page(cache)
	return true
}

destroy :: proc(cache: ^Font_Cache) {
	for page in cache.pages {
		delete(page.pixels, cache.allocator)
		delete(page.nodes)
		delete(page.glyph_keys)
	}

	delete(cache.pages)
	delete(cache.glyphs)
	delete(cache.kerning)
	delete(cache.data, cache.allocator)
	cache^ = {}
}

new_frame :: proc(cache: ^Font_Cache) {
	cache.frame += 1
}

get_glyph :: proc(cache: ^Font_Cache, codepoint: rune, size: int) -> (Glyph, bool) {
	key := Glyph_Key {
		codepoint = codepoint,
		size = size,
	}

	if glyph, glyph_ok := cache.glyphs[key]; glyph_ok {
		if glyph.width > 0 {
			cache.pages[glyph.page].last_used = cache.frame
		}

		return glyph, true
	}

	index := stbtt.FindGlyphIndex(&cache.info, codepoint)
	scale := stbtt.ScaleForPixelHeight(&cache.info, f32(size))

	advance, left_side_bearing: i32
	stbtt.GetGlyphHMetrics(&cache.info, index, &advance, &left_side_bearing)

	x0, y0, x1, y1: i32
	stbtt.GetGlyphBitmapBox(&cache.info, index, scale, scale, &x0, &y0, &x1, &y1)

	glyph := Glyph {
		offset = {
			f32(x0 - GLYPH_PADDING),
			f32(y0 - GLYPH_PADDING) + cache.ascent * f32(size),
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

		for &page, page_idx in cache.pages {
			x, y, fits := page_add_rect(&page, padded_width, padded_height)

			if !fits {
				continue
			}

			bitmap_x := x + GLYPH_PADDING
			bitmap_y := y + GLYPH_PADDING

			stbtt.MakeGlyphBitmap(
				&cache.info,
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
			page.last_used = cache.frame
			append(&page.glyph_keys, key)
			placed = true
			break
		}

		if !placed {
			return glyph, false
		}
	}

	cache.glyphs[key] = glyph
	return glyph, true
}

make_room :: proc(cache: ^Font_Cache) -> bool {
	newest := &cache.pages[len(cache.pages) - 1]

	if newest.width < PAGE_MAX_SIZE {
		old_width := newest.width
		old_height := newest.height
		new_width := old_width * 2
		new_height := old_height * 2
		new_pixels := make([]u8, new_width * new_height, cache.allocator)

		for y in 0..<old_height {
			copy(new_pixels[y * new_width:], newest.pixels[y * old_width:(y + 1) * old_width])
		}

		delete(newest.pixels, cache.allocator)
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

	if len(cache.pages) < MAX_PAGES {
		add_page(cache)
		return true
	}

	oldest := -1

	for page, page_idx in cache.pages {
		if page.reset_frame == cache.frame {
			continue
		}

		if oldest == -1 || page.last_used < cache.pages[oldest].last_used {
			oldest = page_idx
		}
	}

	if oldest == -1 {
		return false
	}

	page := &cache.pages[oldest]

	for key in page.glyph_keys {
		delete_key(&cache.glyphs, key)
	}

	clear(&page.glyph_keys)
	clear(&page.nodes)
	append(&page.nodes, Skyline_Node {
		width = page.width,
	})

	slice.zero(page.pixels)
	page.dirty_min = { page.width, page.height }
	page.dirty_max = {}
	page.reset_frame = cache.frame
	return true
}

add_page :: proc(cache: ^Font_Cache) {
	page := Page {
		pixels = make([]u8, PAGE_START_SIZE * PAGE_START_SIZE, cache.allocator),
		width = PAGE_START_SIZE,
		height = PAGE_START_SIZE,
		nodes = make([dynamic]Skyline_Node, cache.allocator),
		glyph_keys = make([dynamic]Glyph_Key, cache.allocator),
		dirty_min = { PAGE_START_SIZE, PAGE_START_SIZE },
	}

	append(&page.nodes, Skyline_Node {
		width = PAGE_START_SIZE,
	})

	append(&cache.pages, page)
}

kern :: proc(cache: ^Font_Cache, prev_index: i32, index: i32, size: int) -> f32 {
	pair := [2]i32 { prev_index, index }
	advance, advance_ok := cache.kerning[pair]

	if !advance_ok {
		advance = stbtt.GetGlyphKernAdvance(&cache.info, prev_index, index)
		cache.kerning[pair] = advance
	}

	return f32(advance) * stbtt.ScaleForPixelHeight(&cache.info, f32(size))
}

text_iterator_init :: proc(text: string, size: int) -> Text_Iterator {
	return {
		text = text,
		size = size,
		prev_index = -1,
	}
}

text_iterator_next :: proc(
	cache: ^Font_Cache,
	it: ^Text_Iterator,
) -> (
	Placed_Glyph,
	Text_Iterator_Result,
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

		glyph, glyph_ok := get_glyph(cache, codepoint, it.size)

		if !glyph_ok {
			return {}, .No_Room
		}

		it.text = it.text[codepoint_width:]

		if it.prev_index != -1 {
			it.x += kern(cache, it.prev_index, glyph.index, it.size)
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

measure :: proc(cache: ^Font_Cache, text: string, size: int) -> ([2]f32, bool) {
	it := text_iterator_init(text, size)
	width: f32

	placed_res := Text_Iterator_Result.Placed

	for placed_res == .Placed {
		_, placed_res = text_iterator_next(cache, &it)
		width = max(width, it.x)
	}

	return { width, it.y + f32(size) }, placed_res == .Done
}

page_add_rect :: proc(page: ^Page, width: int, height: int) -> (int, int, bool) {
	best_width := page.width
	best_height := page.height
	best_idx := -1
	best_x := -1
	best_y := -1

	// Bottom left fit heuristic.
	for node, node_idx in page.nodes {
		y := page_rect_fits(page^, node_idx, width, height)

		if y != -1 {
			if y + height < best_height || (y + height == best_height && node.width < best_width) {
				best_idx = node_idx
				best_width = node.width
				best_height = y + height
				best_x = node.x
				best_y = y
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
