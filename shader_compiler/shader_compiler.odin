package karl2d_shader_compiler

import "base:runtime"
import "core:fmt"

Target :: enum u8 {
	GLSL_330,
	GLSL_ES_300,
	SPIRV,
	DXBC,
}

Stage :: enum u8 {
	Shared,
	Vertex,
	Fragment,
}

Read_File_Proc :: proc(path: string, user_data: rawptr, allocator: runtime.Allocator) -> (data: []u8, ok: bool)

Compile_Options :: struct {
	targets: bit_set[Target],
	read_file: Read_File_Proc,
	read_file_user_data: rawptr,
	no_debug_info: bool,
	no_optimization: bool,
}

Source_File :: struct {
	name: string,
	source: []u8,
}

Expr_Index :: distinct i32
Stmt_Index :: distinct i32
Var_Index :: distinct i32
Func_Index :: distinct i32
Type_Index :: distinct i32

Expr_Kind :: enum u8 {
	None,
	Literal,
	Var,
	Binary,
	Unary,
	Assign,
	Ternary,
	Call,
	Builtin_Call,
	Construct,
	Index,
	Field,
	Swizzle,
	Comma,
}

Expr :: struct {
	kind: Expr_Kind,
	op: Token_Kind,
	postfix: bool,
	swizzle_count: u8,
	swizzle: [4]u8,
	builtin: Builtin,
	file: u16,
	line: i32,
	type: Type_Index,
	a: Expr_Index,
	b: Expr_Index,
	c: Expr_Index,
	args_start: i32,
	args_count: i32,
	var: Var_Index,
	func: Func_Index,
	field: i32,
	ival: i64,
	fval: f64,
}

Stmt_Kind :: enum u8 {
	None,
	Block,
	Decl,
	Expr,
	If,
	For,
	While,
	Do_While,
	Return,
	Break,
	Continue,
	Discard,
	Switch,
	Case,
	Default,
}

Stmt :: struct {
	kind: Stmt_Kind,
	file: u16,
	line: i32,
	next: Stmt_Index,
	first: Stmt_Index,
	expr: Expr_Index,
	post: Expr_Index,
	body: Stmt_Index,
	else_body: Stmt_Index,
	var: Var_Index,
}

Var_Kind :: enum u8 {
	Local,
	Param,
	Global,
	Uniform,
	Input,
	Output,
	Builtin,
}

Param_Qualifier :: enum u8 {
	In,
	Out,
	Inout,
}

Interpolation :: enum u8 {
	Smooth,
	Flat,
}

Builtin_Var :: enum u8 {
	None,
	Position,
	Frag_Coord,
	Vertex_ID,
	Instance_ID,
	Front_Facing,
	Frag_Depth,
}

Var :: struct {
	name: string,
	type: Type_Index,
	kind: Var_Kind,
	stage: Stage,
	is_const: bool,
	has_const_value: bool,
	dynamic_index: bool,
	written: bool,
	keep_decl: bool,
	param_qualifier: Param_Qualifier,
	interpolation: Interpolation,
	builtin: Builtin_Var,
	used: bit_set[Stage],
	used_init: bit_set[Stage],
	file: u16,
	line: i32,
	location: i32,
	offset: i32,
	init: Expr_Index,
	ival: i64,
	fval: f64,
}

Func :: struct {
	name: string,
	return_type: Type_Index,
	params: []Var_Index,
	body: Stmt_Index,
	stage: Stage,
	has_body: bool,
	fragment_only: bool,
	fragment_only_file: u16,
	fragment_only_line: i32,
	fragment_only_what: string,
	used: bit_set[Stage],
	visiting: bit_set[Stage],
	file: u16,
	line: i32,
}

Decl_Kind :: enum u8 {
	Struct,
	Var,
	Func,
}

Decl :: struct {
	kind: Decl_Kind,
	index: i32,
}

Compiler :: struct {
	allocator: runtime.Allocator,
	options: Compile_Options,
	files: [dynamic]Source_File,
	tokens: [dynamic]Token,
	macros: [dynamic]Macro,
	tok: int,
	types: [dynamic]Type,
	exprs: [dynamic]Expr,
	expr_args: [dynamic]Expr_Index,
	stmts: [dynamic]Stmt,
	vars: [dynamic]Var,
	funcs: [dynamic]Func,
	decls: [dynamic]Decl,
	scope: [dynamic]Var_Index,
	scope_marks: [dynamic]int,
	stage: Stage,
	stage_scope_start: int,
	seen_stages: bit_set[Stage],
	cur_func: Func_Index,
	loop_depth: int,
	switch_depth: int,
	uses_frag_coord_flip: bool,
	main_funcs: [Stage]Func_Index,
	uniforms: [dynamic]Var_Index,
	textures: [dynamic]Var_Index,
	inputs: [dynamic]Var_Index,
	varyings: [dynamic]Varying,
	frag_output: Var_Index,
	constants_size: int,
	failed: bool,
	error: string,
}

Varying :: struct {
	vertex_var: Var_Index,
	fragment_var: Var_Index,
}

compile_error :: proc(c: ^Compiler, file: u16, line: i32, format: string, args: ..any) {
	if c.failed {
		return
	}

	c.failed = true
	name := ""

	if int(file) < len(c.files) {
		name = c.files[file].name
	}

	msg := fmt.aprintf(format, ..args, allocator = c.allocator)
	c.error = fmt.aprintf("%s(%d): %s", name, line, msg, allocator = c.allocator)

	if len(c.tokens) > 0 {
		c.tok = len(c.tokens) - 1
	}
}

compile :: proc(
	source: []u8,
	filename: string,
	options: Compile_Options,
	allocator := context.allocator,
	scratch_allocator := context.temp_allocator,
) -> (compiled: Compiled_Shader, error: string, ok: bool) {
	c := new(Compiler, scratch_allocator)
	c.allocator = scratch_allocator
	c.options = options
	context.allocator = scratch_allocator

	c.files = make([dynamic]Source_File, 0, 4)
	c.tokens = make([dynamic]Token, 0, len(source) / 3 + 16)
	c.types = make([dynamic]Type, 0, 64)
	c.exprs = make([dynamic]Expr, 1, len(source) / 6 + 64)
	c.expr_args = make([dynamic]Expr_Index, 0, 256)
	c.stmts = make([dynamic]Stmt, 1, 256)
	c.vars = make([dynamic]Var, 1, 128)
	c.funcs = make([dynamic]Func, 1, 32)
	c.decls = make([dynamic]Decl, 0, 64)
	c.scope = make([dynamic]Var_Index, 0, 128)
	c.scope_marks = make([dynamic]int, 0, 32)
	c.uniforms = make([dynamic]Var_Index, 0, 16)
	c.textures = make([dynamic]Var_Index, 0, 8)
	c.inputs = make([dynamic]Var_Index, 0, 8)
	c.varyings = make([dynamic]Varying, 0, 8)

	init_types(c)
	append(&c.files, Source_File { name = filename, source = source })
	lex_file(c, 0)
	last_line := i32(1)

	for ch in source {
		if ch == '\n' {
			last_line += 1
		}
	}

	append(&c.tokens, Token { kind = .EOF, file = 0, line = last_line })

	if !c.failed {
		parse_program(c)
	}

	if !c.failed && !options.no_optimization {
		optimize_program(c)
	}

	if !c.failed {
		finish_program(c)
	}

	if c.failed {
		return {}, fmt.aprint(c.error, allocator = allocator), false
	}

	code: [Target]Target_Code

	if .GLSL_330 in options.targets {
		code[.GLSL_330].vertex = emit_glsl(c, .Vertex, false)
		code[.GLSL_330].fragment = emit_glsl(c, .Fragment, false)
	}

	if .GLSL_ES_300 in options.targets {
		code[.GLSL_ES_300].vertex = emit_glsl(c, .Vertex, true)
		code[.GLSL_ES_300].fragment = emit_glsl(c, .Fragment, true)
	}

	if .DXBC in options.targets {
		code[.DXBC].vertex = emit_dxbc(c, .Vertex)
		code[.DXBC].fragment = emit_dxbc(c, .Fragment)
	}

	if .SPIRV in options.targets {
		code[.SPIRV].vertex = emit_spirv(c, .Vertex)
		code[.SPIRV].fragment = emit_spirv(c, .Fragment)
	}

	if c.failed {
		return {}, fmt.aprint(c.error, allocator = allocator), false
	}

	bytes := serialize_compiled_shader(c, code, allocator)
	compiled, ok = compiled_shader_from_bytes(bytes)
	return compiled, "", ok
}
