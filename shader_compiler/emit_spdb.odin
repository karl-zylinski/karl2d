package karl2d_shader_compiler

import "core:slice"
import "core:strings"

SPDB_PAGE_SIZE :: 512

Spdb_Line :: struct {
	offset: u32,
	file: u16,
	line: i32,
}

Spdb_Local :: struct {
	name: string,
	type: Type_Index,
	register_kind: u16,
	register: u32,
	offset: u32,
	length: u32,
}

Spdb_Types :: struct {
	c: ^Compiler,
	records: [dynamic]u8,
	hashes: [dynamic]u32,
	ids: []u32,
}

spdb_type_begin :: proc(types: ^Spdb_Types, leaf: u16) -> int {
	start := len(types.records)
	put_u16(&types.records, 0)
	put_u16(&types.records, leaf)
	return start
}

spdb_pad :: proc(buf: ^[dynamic]u8) {
	for len(buf) % 4 != 0 {
		append(buf, u8(0xf0 + 4 - len(buf) % 4))
	}
}

spdb_numeric :: proc(buf: ^[dynamic]u8, value: int) {
	if value < 0x8000 {
		put_u16(buf, u16(value))
		return
	}

	put_u16(buf, 0x8004)
	put_u32(buf, u32(value))
}

spdb_type_end :: proc(types: ^Spdb_Types, start: int, name: string, hash_name: bool) -> u32 {
	spdb_pad(&types.records)
	length := u16(len(types.records) - start - 2)
	types.records[start] = u8(length)
	types.records[start + 1] = u8(length >> 8)
	hash: u32

	if hash_name {
		hash = pdb_hash(name)
	} else {
		for b in types.records[start:] {
			hash ~= u32(b)

			for _ in 0..<8 {
				hash = hash & 1 != 0 ? hash >> 1 ~ 0xedb88320 : hash >> 1
			}
		}
	}

	append(&types.hashes, hash % 0x3ffff)
	return u32(0x1000 + len(types.hashes) - 1)
}

spdb_type_id :: proc(types: ^Spdb_Types, t: Type_Index) -> u32 {
	if types.ids[t] != 0 {
		return types.ids[t]
	}

	c := types.c
	ty := c.types[t]
	id: u32

	switch ty.kind {
	case .Scalar:
		switch ty.scalar {
		case .Float: id = 0x40
		case .Int: id = 0x74
		case .Uint: id = 0x75
		case .Bool: id = 0x62
		case .None:
		}

	case .Vector:
		elem := spdb_type_id(types, type_vec(ty.scalar, 1))
		start := spdb_type_begin(types, 0x151b)
		put_u32(&types.records, elem)
		put_u32(&types.records, u32(ty.size))
		spdb_numeric(&types.records, int(ty.size) * 4)
		put_string(&types.records, ty.name)
		id = spdb_type_end(types, start, ty.name, false)

	case .Matrix:
		start := spdb_type_begin(types, 0x151c)
		put_u32(&types.records, 0x40)
		put_u32(&types.records, u32(ty.size))
		put_u32(&types.records, u32(ty.size))
		put_u32(&types.records, 16)
		append(&types.records, 0)
		spdb_numeric(&types.records, int(ty.size) * 16)
		put_string(&types.records, ty.name)
		id = spdb_type_end(types, start, ty.name, false)

	case .Array:
		elem := spdb_type_id(types, ty.elem)
		size, _ := type_std140_layout(c, t)
		start := spdb_type_begin(types, 0x1516)
		put_u32(&types.records, elem)
		put_u32(&types.records, 0x22)
		put_u32(&types.records, u32(size / int(ty.len)))
		spdb_numeric(&types.records, size)
		append(&types.records, 0)
		id = spdb_type_end(types, start, "", false)

	case .Struct:
		field_ids := make([]u32, len(ty.fields), c.allocator)

		for f, f_idx in ty.fields {
			field_ids[f_idx] = spdb_type_id(types, f.type)
		}

		list := spdb_type_begin(types, 0x1203)

		for f, f_idx in ty.fields {
			put_u16(&types.records, 0x150d)
			put_u16(&types.records, 3)
			put_u32(&types.records, field_ids[f_idx])
			spdb_numeric(&types.records, int(f.offset))
			put_string(&types.records, f.name)
			spdb_pad(&types.records)
		}

		list_id := spdb_type_end(types, list, "", false)
		size, _ := type_std140_layout(c, t)
		start := spdb_type_begin(types, 0x1505)
		put_u16(&types.records, u16(len(ty.fields)))
		put_u16(&types.records, 0)
		put_u32(&types.records, list_id)
		put_u32(&types.records, 0)
		put_u32(&types.records, 0)
		spdb_numeric(&types.records, size)
		put_string(&types.records, ty.name)
		id = spdb_type_end(types, start, ty.name, true)

	case .None, .Void, .Sampler_2D:
	}

	types.ids[t] = id
	return id
}

spdb_def_range :: proc(buf: ^[dynamic]u8, local: Spdb_Local, flags: u16, parent_offset: int, size: int, register_offset: u32) {
	if parent_offset > 0xffff || size > 0xffff {
		return
	}

	done := u32(0)

	for done < local.length {
		chunk := min(local.length - done, 0xfffc)
		sym := spdb_symbol_begin(buf, 0x1150)
		put_u16(buf, local.register_kind)
		put_u16(buf, flags)
		put_u16(buf, u16(parent_offset))
		put_u16(buf, u16(size))
		put_u32(buf, local.offset + done)
		put_u16(buf, 1)
		put_u16(buf, u16(chunk))
		put_u32(buf, register_offset)
		spdb_symbol_end(buf, sym)
		done += chunk
	}
}

spdb_def_ranges :: proc(c: ^Compiler, buf: ^[dynamic]u8, local: Spdb_Local, t: Type_Index, offset: int, nested: bool) {
	ty := c.types[t]

	switch ty.kind {
	case .Scalar, .Vector:
		spdb_def_range(buf, local, nested ? 5 : 1, offset, int(ty.size) * 4, local.register * 16 + u32(offset))

	case .Matrix:
		for col in 0..<int(ty.size) {
			spdb_def_range(buf, local, 5, offset + col * 16, int(ty.size) * 4, local.register * 16 + u32(offset + col * 16))
		}

	case .Array:
		size, _ := type_std140_layout(c, t)
		stride := size / int(ty.len)

		for i in 0..<int(ty.len) {
			spdb_def_ranges(c, buf, local, ty.elem, offset + i * stride, true)
		}

	case .Struct:
		for f in ty.fields {
			spdb_def_ranges(c, buf, local, f.type, offset + int(f.offset), true)
		}

	case .None, .Void, .Sampler_2D:
	}
}

put_u16 :: proc(buf: ^[dynamic]u8, value: u16) {
	append(buf, u8(value), u8(value >> 8))
}

put_string :: proc(buf: ^[dynamic]u8, str: string) {
	append(buf, str)
	append(buf, 0)
}

pad_to_4 :: proc(buf: ^[dynamic]u8) {
	for len(buf) % 4 != 0 {
		append(buf, 0)
	}
}

md5 :: proc(data: []u8) -> [16]u8 {
	state := [4]u32 { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 }
	full_blocks := len(data) / 64

	for i in 0..<full_blocks {
		dxbc_md5_transform(&state, data[i * 64:])
	}

	rest := data[full_blocks * 64:]
	tail: [128]u8
	copy(tail[:], rest)
	tail[len(rest)] = 0x80
	tail_size := len(rest) >= 56 ? 128 : 64
	bit_count := u64(len(data)) * 8
	set_u32(tail[:], tail_size - 8, u32(bit_count))
	set_u32(tail[:], tail_size - 4, u32(bit_count >> 32))
	dxbc_md5_transform(&state, tail[:])

	if tail_size == 128 {
		dxbc_md5_transform(&state, tail[64:])
	}

	result: [16]u8

	for i in 0..<4 {
		set_u32(result[:], i * 4, state[i])
	}

	return result
}

pdb_hash :: proc(str: string) -> u32 {
	result: u32
	bytes := transmute([]u8)str
	words := len(bytes) / 4

	for i in 0..<words {
		result ~= get_u32(bytes, i * 4)
	}

	rest := bytes[words * 4:]

	if len(rest) >= 2 {
		result ~= u32(rest[0]) | u32(rest[1]) << 8
		rest = rest[2:]
	}

	if len(rest) == 1 {
		result ~= u32(rest[0])
	}

	result |= 0x20202020
	result ~= result >> 11
	return result ~ (result >> 16)
}

spdb_symbol_begin :: proc(buf: ^[dynamic]u8, kind: u16) -> int {
	start := len(buf)
	put_u16(buf, 0)
	put_u16(buf, kind)
	return start
}

spdb_symbol_end :: proc(buf: ^[dynamic]u8, start: int) {
	pad_to_4(buf)
	length := u16(len(buf) - start - 2)
	buf[start] = u8(length)
	buf[start + 1] = u8(length >> 8)
}

spdb_names_stream :: proc(names: []string, offsets: []u32, allocator := context.allocator) -> []u8 {
	buf := make([dynamic]u8, 0, 256, allocator)
	put_u32(&buf, 0xeffeeffe)
	put_u32(&buf, 1)
	size_at := len(buf)
	put_u32(&buf, 0)
	strings_start := len(buf)
	append(&buf, 0)

	for name, i in names {
		offsets[i] = u32(len(buf) - strings_start)
		put_string(&buf, name)
	}

	set_u32(buf[:], size_at, u32(len(buf) - strings_start))
	bucket_count := max(len(names) * 2, 1)
	buckets := make([]u32, bucket_count, allocator)

	for name, i in names {
		slot := int(pdb_hash(name) % u32(bucket_count))

		for buckets[slot] != 0 {
			slot = (slot + 1) % bucket_count
		}

		buckets[slot] = offsets[i]
	}

	put_u32(&buf, u32(bucket_count))

	for b in buckets {
		put_u32(&buf, b)
	}

	put_u32(&buf, u32(len(names)))
	return buf[:]
}

spdb_info_stream :: proc(guid: [16]u8, names: []string, stream_indices: []u32, allocator := context.allocator) -> []u8 {
	buf := make([dynamic]u8, 0, 256, allocator)
	put_u32(&buf, 20000404)
	guid_copy := guid
	put_u32(&buf, get_u32(guid_copy[:], 0))
	put_u32(&buf, 1)
	append(&buf, ..guid_copy[:])
	size_at := len(buf)
	put_u32(&buf, 0)
	strings_start := len(buf)
	name_offsets := make([]u32, len(names), allocator)

	for name, i in names {
		name_offsets[i] = u32(len(buf) - strings_start)
		put_string(&buf, name)
	}

	set_u32(buf[:], size_at, u32(len(buf) - strings_start))
	capacity := len(names) * 2 + 2
	slots := make([]int, capacity, allocator)

	for &s in slots {
		s = -1
	}

	for name, i in names {
		slot := int((pdb_hash(name) & 0xffff) % u32(capacity))

		for slots[slot] != -1 {
			slot = (slot + 1) % capacity
		}

		slots[slot] = i
	}

	present_words := (capacity + 31) / 32
	present := make([]u32, present_words, allocator)

	for s, slot in slots {
		if s != -1 {
			present[slot / 32] |= 1 << u32(slot % 32)
		}
	}

	put_u32(&buf, u32(len(names)))
	put_u32(&buf, u32(capacity))
	put_u32(&buf, u32(present_words))

	for word in present {
		put_u32(&buf, word)
	}

	put_u32(&buf, 0)

	for s in slots {
		if s != -1 {
			put_u32(&buf, name_offsets[s])
			put_u32(&buf, stream_indices[s])
		}
	}

	put_u32(&buf, 0)
	put_u32(&buf, 20140508)
	return buf[:]
}

spdb_type_stream :: proc(hash_stream: u16, records: []u8, count: int, allocator := context.allocator) -> []u8 {
	buf := make([dynamic]u8, 0, 56 + len(records), allocator)
	put_u32(&buf, 20040203)
	put_u32(&buf, 56)
	put_u32(&buf, 0x1000)
	put_u32(&buf, u32(0x1000 + count))
	put_u32(&buf, u32(len(records)))
	put_u16(&buf, hash_stream)
	put_u16(&buf, 0xffff)
	put_u32(&buf, 4)
	put_u32(&buf, 0x3ffff)
	put_u32(&buf, 0)
	put_u32(&buf, u32(count * 4))
	put_u32(&buf, u32(count * 4))
	put_u32(&buf, count > 0 ? 8 : 0)
	put_u32(&buf, u32(count * 4 + (count > 0 ? 8 : 0)))
	put_u32(&buf, 0)
	append(&buf, ..records)
	return buf[:]
}

spdb_msf :: proc(streams: [][]u8, allocator := context.allocator) -> []u8 {
	page := SPDB_PAGE_SIZE
	total := 0

	for s in streams {
		total += len(s)
	}

	if total > 1024 * 1024 {
		page = 4096
	}

	next_page := 3
	directory := make([dynamic]u8, 0, 256, allocator)
	put_u32(&directory, u32(len(streams)))

	for s in streams {
		put_u32(&directory, u32(len(s)))
	}

	stream_first_page := make([]int, len(streams), allocator)

	for s, s_idx in streams {
		stream_first_page[s_idx] = next_page
		pages := (len(s) + page - 1) / page

		for p in 0..<pages {
			put_u32(&directory, u32(next_page + p))
		}

		next_page += pages
	}

	directory_first_page := next_page
	directory_pages := (len(directory) + page - 1) / page
	next_page += directory_pages
	block_map_page := next_page
	next_page += 1
	out := make([]u8, next_page * page, allocator)
	copy(out, "Microsoft C/C++ MSF 7.00\r\n\x1aDS\x00\x00\x00")
	set_u32(out, 32, u32(page))
	set_u32(out, 36, 1)
	set_u32(out, 40, u32(next_page))
	set_u32(out, 44, u32(len(directory)))
	set_u32(out, 48, 0)
	set_u32(out, 52, u32(block_map_page))

	for i in page..<3 * page {
		out[i] = 0xff
	}

	for p in 0..<next_page {
		out[page + p / 8] &~= 1 << u32(p % 8)
		out[2 * page + p / 8] &~= 1 << u32(p % 8)
	}

	for s, s_idx in streams {
		copy(out[stream_first_page[s_idx] * page:], s)
	}

	copy(out[directory_first_page * page:], directory[:])

	for p in 0..<directory_pages {
		set_u32(out, block_map_page * page + p * 4, u32(directory_first_page + p))
	}

	return out
}

emit_spdb :: proc(c: ^Compiler, stage: Stage, shader: []u32, body_start: int, lines: []Spdb_Line, locals: []Spdb_Local) -> []u8 {
	context.allocator = c.allocator
	shader_bytes := slice.to_bytes(shader)
	code_offset := u32(body_start * 4)
	code_length := u32(len(shader_bytes)) - code_offset
	file_name_offsets := make([]u32, len(c.files))
	file_names := make([]string, len(c.files))

	for f, f_idx in c.files {
		file_names[f_idx] = f.name == "" ? "shader.glsl" : f.name
	}

	STREAM_LINK_INFO :: 5
	STREAM_NAMES :: 6
	STREAM_TPI_HASH :: 7
	STREAM_IPI_HASH :: 8
	STREAM_MODULE :: 9
	STREAM_SECTIONS :: 10
	STREAM_GLOBALS :: 11
	STREAM_PUBLICS :: 12
	STREAM_SYMBOLS :: 13
	STREAM_FIRST_FILE :: 14
	streams := make([][]u8, STREAM_FIRST_FILE + len(c.files))
	streams[STREAM_NAMES] = spdb_names_stream(file_names, file_name_offsets)
	streams[4] = spdb_type_stream(STREAM_IPI_HASH, nil, 0)
	types := Spdb_Types { c = c, ids = make([]u32, len(c.types)) }

	for f, f_idx in c.files {
		streams[STREAM_FIRST_FILE + f_idx] = f.source
	}

	named := make([]string, 2 + len(c.files))
	named_streams := make([]u32, 2 + len(c.files))
	named[0] = "/LinkInfo"
	named_streams[0] = STREAM_LINK_INFO
	named[1] = "/names"
	named_streams[1] = STREAM_NAMES

	for name, f_idx in file_names {
		named[2 + f_idx] = strings.concatenate({ "/src/files/", name })
		named_streams[2 + f_idx] = u32(STREAM_FIRST_FILE + f_idx)
	}

	streams[1] = spdb_info_stream(md5(shader_bytes), named, named_streams)
	module := make([dynamic]u8, 0, 1024 + len(lines) * 8)
	put_u32(&module, 4)
	sym := spdb_symbol_begin(&module, 0x113c)
	put_u32(&module, 0x110)
	put_u16(&module, 0x100)

	for _ in 0..<2 {
		put_u16(&module, 1)
		put_u16(&module, 0)
		put_u16(&module, 0)
		put_u16(&module, 0)
	}

	put_string(&module, "Karl2D Shader Compiler")
	spdb_symbol_end(&module, sym)
	sym = spdb_symbol_begin(&module, 0x113d)
	append(&module, 1)
	put_string(&module, "hlslFlags")
	put_string(&module, "0x1")
	put_string(&module, "hlslTarget")
	put_string(&module, stage == .Vertex ? "vs_4_0" : "ps_4_0")
	put_string(&module, "hlslEntry")
	put_string(&module, "main")
	append(&module, 0)
	spdb_symbol_end(&module, sym)
	proc_offset := len(module)
	sym = spdb_symbol_begin(&module, 0x1110)
	put_u32(&module, 0)
	end_at := len(module)
	put_u32(&module, 0)
	put_u32(&module, 0)
	put_u32(&module, code_length)
	put_u32(&module, 0)
	put_u32(&module, code_length)
	put_u32(&module, 0)
	put_u32(&module, code_offset)
	put_u16(&module, 1)
	append(&module, 0xa0)
	put_string(&module, "main")
	spdb_symbol_end(&module, sym)

	for l in locals {
		type_id := spdb_type_id(&types, l.type)
		sym = spdb_symbol_begin(&module, 0x113e)
		put_u32(&module, type_id)
		put_u16(&module, 0)
		put_string(&module, l.name)
		spdb_symbol_end(&module, sym)

		if l.register_kind == 3 {
			size, _ := type_std140_layout(c, l.type)
			spdb_def_range(&module, l, 1, 0, min(size, 0xffff), l.register)
		} else {
			spdb_def_ranges(c, &module, l, l.type, 0, false)
		}
	}

	streams[2] = spdb_type_stream(STREAM_TPI_HASH, types.records[:], len(types.hashes))
	type_hashes := make([dynamic]u8, 0, len(types.hashes) * 4 + 8)

	for h in types.hashes {
		put_u32(&type_hashes, h)
	}

	if len(types.hashes) > 0 {
		put_u32(&type_hashes, 0x1000)
		put_u32(&type_hashes, 0)
	}

	streams[STREAM_TPI_HASH] = type_hashes[:]
	set_u32(module[:], end_at, u32(len(module)))
	sym = spdb_symbol_begin(&module, 0x0006)
	spdb_symbol_end(&module, sym)
	symbols_size := len(module)
	file_ids := make([]u32, len(c.files))
	put_u32(&module, 0xf4)
	checksums_size_at := len(module)
	put_u32(&module, 0)
	checksums_start := len(module)

	for f, f_idx in c.files {
		file_ids[f_idx] = u32(len(module) - checksums_start)
		put_u32(&module, file_name_offsets[f_idx])
		append(&module, 16, 1)
		sum := md5(f.source)
		append(&module, ..sum[:])
		pad_to_4(&module)
	}

	set_u32(module[:], checksums_size_at, u32(len(module) - checksums_start))
	put_u32(&module, 0xf2)
	lines_size_at := len(module)
	put_u32(&module, 0)
	lines_start := len(module)
	put_u32(&module, 0)
	put_u16(&module, 1)
	put_u16(&module, 0)
	put_u32(&module, u32(len(shader_bytes)))
	at := 0

	for at < len(lines) {
		run_end := at

		for run_end < len(lines) && lines[run_end].file == lines[at].file {
			run_end += 1
		}

		put_u32(&module, file_ids[lines[at].file])
		put_u32(&module, u32(run_end - at))
		put_u32(&module, u32(12 + (run_end - at) * 8))

		for l in lines[at:run_end] {
			put_u32(&module, l.offset)
			put_u32(&module, u32(l.line) & 0xffffff | 0x80000000)
		}

		at = run_end
	}

	set_u32(module[:], lines_size_at, u32(len(module) - lines_start))
	put_u32(&module, 0xf6)
	put_u32(&module, 4)
	put_u32(&module, 0)
	c13_size := len(module) - symbols_size
	put_u32(&module, 4)
	put_u32(&module, 0)
	streams[STREAM_MODULE] = module[:]
	symbols := make([dynamic]u8, 0, 32)
	sym = spdb_symbol_begin(&symbols, 0x1125)
	put_u32(&symbols, 0)
	put_u32(&symbols, u32(proc_offset))
	put_u16(&symbols, 1)
	put_string(&symbols, "main")
	spdb_symbol_end(&symbols, sym)
	streams[STREAM_SYMBOLS] = symbols[:]
	globals := make([dynamic]u8, 0, 16)
	put_u32(&globals, 0xffffffff)
	put_u32(&globals, 0xf12f091a)
	put_u32(&globals, 0)
	put_u32(&globals, 0)
	streams[STREAM_GLOBALS] = globals[:]
	publics := make([dynamic]u8, 0, 44)
	put_u32(&publics, 16)

	for _ in 0..<6 {
		put_u32(&publics, 0)
	}

	append(&publics, ..globals[:])
	streams[STREAM_PUBLICS] = publics[:]
	sections := make([dynamic]u8, 0, 40)
	append(&sections, "D3DSHDR")
	append(&sections, 0)
	put_u32(&sections, u32(len(shader_bytes)))

	for _ in 0..<6 {
		put_u32(&sections, 0)
	}

	put_u32(&sections, 0x60000020)
	streams[STREAM_SECTIONS] = sections[:]
	dbi := make([dynamic]u8, 0, 512)
	put_u32(&dbi, 0xffffffff)
	put_u32(&dbi, 19990903)
	put_u32(&dbi, 1)
	put_u16(&dbi, STREAM_GLOBALS)
	put_u16(&dbi, 0x8e00)
	put_u16(&dbi, STREAM_PUBLICS)
	put_u16(&dbi, 0)
	put_u16(&dbi, STREAM_SYMBOLS)
	put_u16(&dbi, 0)
	sizes_at := len(dbi)

	for _ in 0..<10 {
		put_u32(&dbi, 0)
	}

	modules_start := len(dbi)
	put_u32(&dbi, 0)

	put_u16(&dbi, 1)
	put_u16(&dbi, 0)
	put_u32(&dbi, 0)
	put_u32(&dbi, u32(len(shader_bytes)))
	put_u32(&dbi, 0x60000020)
	put_u16(&dbi, 0)
	put_u16(&dbi, 0)
	put_u32(&dbi, 0)
	put_u32(&dbi, 0)
	put_u16(&dbi, 0)
	put_u16(&dbi, STREAM_MODULE)
	put_u32(&dbi, u32(symbols_size))
	put_u32(&dbi, 0)
	put_u32(&dbi, u32(c13_size))
	put_u16(&dbi, u16(len(c.files)))
	put_u16(&dbi, 0)
	put_u32(&dbi, 0)
	put_u32(&dbi, 0)
	put_u32(&dbi, 0)
	put_string(&dbi, "main")
	put_string(&dbi, "none")
	pad_to_4(&dbi)
	contributions_start := len(dbi)
	put_u32(&dbi, 0xf12eba2d)
	put_u16(&dbi, 1)
	put_u16(&dbi, 0)
	put_u32(&dbi, 0)
	put_u32(&dbi, u32(len(shader_bytes)))
	put_u32(&dbi, 0x60000020)
	put_u16(&dbi, 0)
	put_u16(&dbi, 0)
	put_u32(&dbi, 0)
	put_u32(&dbi, 0)
	section_map_start := len(dbi)
	put_u16(&dbi, 2)
	put_u16(&dbi, 2)
	put_u16(&dbi, 0x0007)
	put_u16(&dbi, 0)
	put_u16(&dbi, 0)
	put_u16(&dbi, 1)
	put_u16(&dbi, 0xffff)
	put_u16(&dbi, 0xffff)
	put_u32(&dbi, 0)
	put_u32(&dbi, u32(len(shader_bytes)))
	put_u16(&dbi, 0x0208)
	put_u16(&dbi, 0)
	put_u16(&dbi, 0)
	put_u16(&dbi, 0)
	put_u16(&dbi, 0xffff)
	put_u16(&dbi, 0xffff)
	put_u32(&dbi, 0)
	put_u32(&dbi, 0xffffffff)
	source_info_start := len(dbi)
	put_u16(&dbi, 1)
	put_u16(&dbi, u16(len(c.files)))
	put_u16(&dbi, 0)
	put_u16(&dbi, u16(len(c.files)))
	name_offsets_at := len(dbi)

	for _ in c.files {
		put_u32(&dbi, 0)
	}

	names_start := len(dbi)

	for name, f_idx in file_names {
		set_u32(dbi[:], name_offsets_at + f_idx * 4, u32(len(dbi) - names_start))
		put_string(&dbi, name)
	}

	pad_to_4(&dbi)
	ec_start := len(dbi)
	put_u32(&dbi, 0xeffeeffe)
	put_u32(&dbi, 1)
	put_u32(&dbi, 1)
	append(&dbi, 0)
	put_u32(&dbi, 1)
	put_u32(&dbi, 0)
	put_u32(&dbi, 0)
	optional_start := len(dbi)

	for i in 0..<11 {
		put_u16(&dbi, i == 5 ? STREAM_SECTIONS : 0xffff)
	}

	set_u32(dbi[:], sizes_at, u32(contributions_start - modules_start))
	set_u32(dbi[:], sizes_at + 4, u32(section_map_start - contributions_start))
	set_u32(dbi[:], sizes_at + 8, u32(source_info_start - section_map_start))
	set_u32(dbi[:], sizes_at + 12, u32(ec_start - source_info_start))
	set_u32(dbi[:], sizes_at + 24, u32(len(dbi) - optional_start))
	set_u32(dbi[:], sizes_at + 28, u32(optional_start - ec_start))
	streams[3] = dbi[:]
	return spdb_msf(streams)
}
