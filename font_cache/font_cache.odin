// For dynamically building fonts. The Font Cache maintains one atlas for all fonts. The atlas can
// grow up to 4096x4096. Instead of growing past 4096x4096 it will compact the atlas. Compacting
// means removing the 50% of the glyphs, where those 50% will be the least recently used glyphs.
//
// The skyline rectangle packing in this file is ported from Fontstash by Mikko Mononen. Fontstash
// is licensed under the zlib license: https://github.com/memononen/fontstash
package karl2d_font_cache

import "base:runtime"
import "core:math"
import "core:slice"
import "core:unicode/utf8"
import stbtt "../stb_truetype"

ATLAS_START_SIZE :: 256
ATLAS_MAX_SIZE :: 4096
GLYPH_PADDING :: 1

Cache :: struct {
	pixels: [][4]u8,
	width: int,
	height: int,
	nodes: [dynamic]Skyline_Node,
	glyphs: map[Glyph_Key]Glyph,
	dirty_min: [2]int,
	dirty_max: [2]int,
	last_compact: f64,
	rasterizer: stbtt.Rasterizer,
	allocator: runtime.Allocator,
}

Font :: struct {
	info: stbtt.Font_Info,
	data: []u8,
	id: u32,
	premultiply_alpha: bool,
	ascent: f32,
	height_units: f32,
	kerning: map[[2]i32]i32,
	allocator: runtime.Allocator,
}

Glyph_Key :: distinct u64

glyph_key :: proc(font_id: u32, codepoint: rune, size: int) -> Glyph_Key {
	return Glyph_Key(u64(font_id) << 48 | u64(u16(size)) << 32 | u64(u32(codepoint)))
}

glyph_key_font_id :: proc(key: Glyph_Key) -> u32 {
	return u32(key >> 48)
}

Glyph :: struct {
	x: int,
	y: int,
	width: int,
	height: int,
	offset: [2]f32,
	advance: f32,
	index: i32,
	last_used: f64,
	in_atlas: bool,
}

Skyline_Node :: struct {
	x: int,
	y: int,
	width: int,
}

Init_Error :: stbtt.Init_Error

init_cache :: proc(cache: ^Cache, allocator: runtime.Allocator) {
	cache^ = {
		pixels = make([][4]u8, ATLAS_START_SIZE * ATLAS_START_SIZE, allocator),
		width = ATLAS_START_SIZE,
		height = ATLAS_START_SIZE,
		nodes = make([dynamic]Skyline_Node, allocator),
		glyphs = make(map[Glyph_Key]Glyph, allocator),
		dirty_min = { ATLAS_START_SIZE, ATLAS_START_SIZE },
		allocator = allocator,
	}

	append(&cache.nodes, Skyline_Node {
		width = ATLAS_START_SIZE,
	})

	stbtt.init_rasterizer(&cache.rasterizer, allocator)
}

destroy_cache :: proc(cache: ^Cache) {
	stbtt.destroy_rasterizer(&cache.rasterizer)
	delete(cache.pixels, cache.allocator)
	delete(cache.nodes)
	delete(cache.glyphs)
	cache^ = {}
}

init_font :: proc(
	font: ^Font,
	data: []u8,
	font_index: int,
	id: u32,
	premultiply_alpha: bool,
	allocator: runtime.Allocator,
) -> Init_Error {
	font^ = {
		data = slice.clone(data, allocator),
		id = id,
		premultiply_alpha = premultiply_alpha,
		kerning = make(map[[2]i32]i32, allocator),
		allocator = allocator,
	}

	init_err := stbtt.init_font(&font.info, font.data, font_index)

	if init_err != .None {
		destroy_font(font)
		return init_err
	}

	height_units := font.info.ascent - font.info.descent
	font.ascent = f32(font.info.ascent) / f32(height_units)
	font.height_units = f32(height_units)
	return .None
}

destroy_font :: proc(font: ^Font) {
	delete(font.kerning)
	delete(font.data, font.allocator)
	font^ = {}
}

remove_font_glyphs :: proc(cache: ^Cache, font_id: u32) {
	keys := make([dynamic]Glyph_Key, cache.allocator)

	for key in cache.glyphs {
		if glyph_key_font_id(key) == font_id {
			append(&keys, key)
		}
	}

	for key in keys {
		delete_key(&cache.glyphs, key)
	}

	delete(keys)
}

get_glyph :: proc(
	cache: ^Cache,
	font: ^Font,
	codepoint: rune,
	size: int,
	time: f64,
	rasterize: bool,
) -> (
	Glyph,
	bool,
) {
	key := glyph_key(font.id, codepoint, size)
	glyph := &cache.glyphs[key]
	rect: stbtt.Bitmap_Rect

	if glyph == nil {
		scale := f32(size) / font.height_units
		index := stbtt.find_glyph_index(&font.info, codepoint)
		advance := stbtt.get_glyph_advance(&font.info, index)
		rect = stbtt.get_glyph_bitmap_rect(&font.info, index, scale)
		padded_width := rect.width + GLYPH_PADDING * 2
		padded_height := rect.height + GLYPH_PADDING * 2

		new_glyph := Glyph {
			offset = {
				f32(rect.x - GLYPH_PADDING),
				f32(rect.y - GLYPH_PADDING) + math.round(font.ascent * f32(size)),
			},
			advance = f32(advance) * scale,
			index = i32(index),
		}

		if rect.width > 0 && rect.height > 0 &&
		   padded_width <= ATLAS_MAX_SIZE && padded_height <= ATLAS_MAX_SIZE {
			new_glyph.width = padded_width
			new_glyph.height = padded_height
		}

		cache.glyphs[key] = new_glyph
		glyph = &cache.glyphs[key]
	}

	glyph.last_used = time

	if rasterize && !glyph.in_atlas && glyph.width > 0 {
		x, y, fits := add_rect(cache, glyph.width, glyph.height)

		if !fits {
			return glyph^, false
		}

		scale := f32(size) / font.height_units

		if rect.width == 0 {
			rect = stbtt.get_glyph_bitmap_rect(&font.info, int(glyph.index), scale)
		}

		atlas_bytes := slice.reinterpret([]u8, cache.pixels)
		bitmap_x := x + GLYPH_PADDING
		bitmap_y := y + GLYPH_PADDING
		bitmap_format := stbtt.Bitmap_Format.RGBA_White

		if font.premultiply_alpha {
			bitmap_format = .RGBA_Premultiplied
		}

		stbtt.rasterize_glyph(
			&cache.rasterizer,
			&font.info,
			int(glyph.index),
			scale,
			rect,
			atlas_bytes[(bitmap_y * cache.width + bitmap_x) * size_of([4]u8):],
			cache.width * size_of([4]u8),
			bitmap_format,
		)

		glyph.x = x
		glyph.y = y
		glyph.in_atlas = true
		cache.dirty_min.x = min(cache.dirty_min.x, x)
		cache.dirty_min.y = min(cache.dirty_min.y, y)
		cache.dirty_max.x = max(cache.dirty_max.x, x + glyph.width)
		cache.dirty_max.y = max(cache.dirty_max.y, y + glyph.height)
	}

	return glyph^, true
}

make_room :: proc(cache: ^Cache, time: f64) -> bool {
	if cache.width < ATLAS_MAX_SIZE || cache.height < ATLAS_MAX_SIZE {
		old_width := cache.width
		old_height := cache.height
		new_width := old_width
		new_height := old_height

		if old_width == old_height {
			new_width = old_width * 2
		} else {
			new_height = old_height * 2
		}

		new_pixels := make([][4]u8, new_width * new_height, cache.allocator)

		for y in 0..<old_height {
			copy(new_pixels[y * new_width:], cache.pixels[y * old_width:(y + 1) * old_width])
		}

		delete(cache.pixels, cache.allocator)
		cache.pixels = new_pixels
		cache.width = new_width
		cache.height = new_height
		cache.dirty_min = {}
		cache.dirty_max = { old_width, old_height }

		if new_width > old_width {
			append(&cache.nodes, Skyline_Node {
				x = old_width,
				y = 0,
				width = new_width - old_width,
			})
		}

		return true
	}

	if cache.last_compact == time {
		return false
	}

	Kept_Glyph :: struct {
		key: Glyph_Key,
		glyph: Glyph,
	}

	kept := make([dynamic]Kept_Glyph, cache.allocator)

	for key, glyph in cache.glyphs {
		if glyph.in_atlas {
			append(&kept, Kept_Glyph {
				key = key,
				glyph = glyph,
			})
		}
	}

	slice.sort_by(kept[:], proc(a, b: Kept_Glyph) -> bool {
		return a.glyph.last_used > b.glyph.last_used
	})

	area_budget := cache.width * cache.height / 2
	area := 0
	num_kept := 0

	for k in kept {
		glyph_area := k.glyph.width * k.glyph.height

		if k.glyph.last_used != time && area + glyph_area > area_budget {
			break
		}

		area += glyph_area
		num_kept += 1
	}

	for k in kept[num_kept:] {
		delete_key(&cache.glyphs, k.key)
	}

	resize(&kept, num_kept)

	slice.sort_by(kept[:], proc(a, b: Kept_Glyph) -> bool {
		return a.glyph.height > b.glyph.height
	})

	old_pixels := cache.pixels
	old_width := cache.width
	cache.pixels = make([][4]u8, cache.width * cache.height, cache.allocator)
	clear(&cache.nodes)
	append(&cache.nodes, Skyline_Node {
		width = cache.width,
	})

	packed_height := 0

	for k in kept {
		x, y, fits := add_rect(cache, k.glyph.width, k.glyph.height)

		if !fits {
			delete_key(&cache.glyphs, k.key)
			continue
		}

		for row in 0..<k.glyph.height {
			src_start := k.glyph.x + (k.glyph.y + row) * old_width
			dst_start := x + (y + row) * cache.width
			copy(cache.pixels[dst_start:], old_pixels[src_start:src_start + k.glyph.width])
		}

		glyph := &cache.glyphs[k.key]
		glyph.x = x
		glyph.y = y
		packed_height = max(packed_height, y + k.glyph.height)
	}

	delete(old_pixels, cache.allocator)
	delete(kept)
	cache.dirty_min = {}
	cache.dirty_max = { cache.width, packed_height }
	cache.last_compact = time
	return true
}

kern :: proc(font: ^Font, prev_index: i32, index: i32, size: int) -> f32 {
	pair := [2]i32 { prev_index, index }
	advance, advance_ok := font.kerning[pair]

	if !advance_ok {
		advance = i32(stbtt.get_glyph_kern_advance(&font.info, int(prev_index), int(index)))
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
	rasterize: bool,
}

Place_Text_Iterator_Result :: enum {
	Placed,
	Done,
	No_Room,
}

// A glyph that has been placed by the iterator. The x and y are the top-left of the glyph, relative
// to the start of the text.
Placed_Glyph :: struct {
	atlas_x: int,
	atlas_y: int,
	width: int,
	height: int,
	x: f32,
	y: f32,
}

place_text_iterator_init :: proc(
	text: string,
	size: int,
	time: f64,
	rasterize: bool,
) -> Place_Text_Iterator {
	return {
		text = text,
		size = size,
		time = time,
		prev_index = -1,
		rasterize = rasterize,
	}
}

place_text_iterate :: proc(
	cache: ^Cache,
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

		glyph, glyph_ok := get_glyph(cache, font, codepoint, it.size, it.time, it.rasterize)

		if !glyph_ok {
			return {}, .No_Room
		}

		it.text = it.text[codepoint_width:]

		if it.prev_index != -1 {
			it.x += kern(font, it.prev_index, glyph.index, it.size)
		}

		placed := Placed_Glyph {
			atlas_x = glyph.x,
			atlas_y = glyph.y,
			width = glyph.width,
			height = glyph.height,
			x = it.x + glyph.offset.x,
			y = it.y + glyph.offset.y,
		}

		it.x += glyph.advance
		it.prev_index = glyph.index
		return placed, .Placed
	}

	return {}, .Done
}

measure :: proc(
	cache: ^Cache,
	font: ^Font,
	text: string,
	size: int,
	time: f64,
) -> [2]f32 {
	it := place_text_iterator_init(text, size, time, false)
	width: f32

	place_res := Place_Text_Iterator_Result.Placed

	for place_res == .Placed {
		_, place_res = place_text_iterate(cache, font, &it)
		width = max(width, it.x)
	}

	return { width, it.y + f32(size) }
}

add_rect :: proc(cache: ^Cache, width: int, height: int) -> (x: int, y: int, ok: bool) {
	best_width := cache.width
	best_height := cache.height
	best_idx := -1
	best_x := -1
	best_y := -1

	// Bottom left fit heuristic.
	for node, node_idx in cache.nodes {
		fit_y := rect_fits(cache^, node_idx, width, height)

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
	add_skyline_level(cache, best_idx, best_x, best_y, width, height)
	return best_x, best_y, true
}

rect_fits :: proc(cache: Cache, idx: int, width: int, height: int) -> int {
	// Checks if there is enough space at the location of skyline span 'i',
	// and return the max height of all skyline spans under that at that location,
	// (think tetris block being dropped at that position). Or -1 if no space found.

	idx := idx
	x := cache.nodes[idx].x
	y := cache.nodes[idx].y

	if x + width > cache.width {
		return -1
	}

	space_left := width

	for space_left > 0 {
		if idx == len(cache.nodes) {
			return -1
		}

		y = max(y, cache.nodes[idx].y)

		if y + height > cache.height {
			return -1
		}

		space_left -= cache.nodes[idx].width
		idx += 1
	}

	return y
}

add_skyline_level :: proc(cache: ^Cache, idx: int, x: int, y: int, width: int, height: int) {
	// insert new node
	inject_at(&cache.nodes, idx, Skyline_Node {
		x = x,
		y = y + height,
		width = width,
	})

	// Delete skyline segments that fall under the shadow of the new segment.
	for i := idx + 1; i < len(cache.nodes); i += 1 {
		if cache.nodes[i].x >= cache.nodes[i-1].x + cache.nodes[i-1].width {
			break
		}

		shrink := cache.nodes[i-1].x + cache.nodes[i-1].width - cache.nodes[i].x
		cache.nodes[i].x += shrink
		cache.nodes[i].width -= shrink

		if cache.nodes[i].width > 0 {
			break
		}

		ordered_remove(&cache.nodes, i)
		i -= 1
	}

	// Merge same height skyline segments that are next to each other.
	for i := 0; i < len(cache.nodes) - 1; /**/ {
		if cache.nodes[i].y == cache.nodes[i+1].y {
			cache.nodes[i].width += cache.nodes[i+1].width
			ordered_remove(&cache.nodes, i+1)
		} else {
			i += 1
		}
	}
}
