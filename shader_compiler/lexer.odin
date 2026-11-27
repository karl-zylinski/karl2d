package karl2d_shader_compiler

import "core:slice"
import "core:strings"

Token_Kind :: enum u8 {
	EOF,
	Ident,
	Int_Lit,
	Uint_Lit,
	Float_Lit,
	LParen,
	RParen,
	LBrace,
	RBrace,
	LBracket,
	RBracket,
	Dot,
	Comma,
	Semicolon,
	Colon,
	Question,
	Plus,
	Minus,
	Star,
	Slash,
	Percent,
	Inc,
	Dec,
	Lt,
	Gt,
	Le,
	Ge,
	Eq_Eq,
	Not_Eq,
	And_And,
	Or_Or,
	Xor_Xor,
	Not,
	Amp,
	Pipe,
	Caret,
	Tilde,
	Shl,
	Shr,
	Assign,
	Add_Assign,
	Sub_Assign,
	Mul_Assign,
	Div_Assign,
	Mod_Assign,
	And_Assign,
	Or_Assign,
	Xor_Assign,
	Shl_Assign,
	Shr_Assign,
	Kw_Const,
	Kw_Uniform,
	Kw_In,
	Kw_Out,
	Kw_Inout,
	Kw_Struct,
	Kw_If,
	Kw_Else,
	Kw_For,
	Kw_While,
	Kw_Do,
	Kw_Return,
	Kw_Break,
	Kw_Continue,
	Kw_Discard,
	Kw_True,
	Kw_False,
	Kw_Layout,
	Kw_Flat,
	Kw_Smooth,
	Kw_Noperspective,
	Kw_Precision,
	Kw_Highp,
	Kw_Mediump,
	Kw_Lowp,
	Kw_Switch,
	Kw_Case,
	Kw_Default,
	Stage_Vertex,
	Stage_Fragment,
}

Token :: struct {
	kind: Token_Kind,
	known: u8,
	file: u16,
	line: i32,
	text: string,
}

Macro :: struct {
	name: string,
	params: []string,
	is_function: bool,
	ready: bool,
	body: []Token,
}

Macro_Call :: struct {
	macro: Macro,
	start: int,
	depth: int,
}

find_macro :: proc(c: ^Compiler, name: string) -> int {
	for m, m_idx in c.macros {
		if m.ready && m.name == name {
			return m_idx
		}
	}

	return -1
}

substitute_macro :: proc(c: ^Compiler, macro: Macro, args: []Token, at: Token) -> []Token {
	arg_starts := make([dynamic]int, 0, 8, c.allocator)
	arg_ends := make([dynamic]int, 0, 8, c.allocator)
	depth := 0
	start := 0

	for t, t_idx in args {
		if t.kind == .LParen {
			depth += 1
		} else if t.kind == .RParen {
			depth -= 1
		} else if t.kind == .Comma && depth == 0 {
			append(&arg_starts, start)
			append(&arg_ends, t_idx)
			start = t_idx + 1
		}
	}

	if len(args) > 0 || len(macro.params) > 0 {
		append(&arg_starts, start)
		append(&arg_ends, len(args))
	}

	if len(arg_starts) != len(macro.params) {
		compile_error(c, at.file, at.line, "The macro '%s' takes %d arguments but got %d", macro.name, len(macro.params), len(arg_starts))
		return nil
	}

	result := make([dynamic]Token, 0, len(macro.body) + len(args), c.allocator)

	for t in macro.body {
		param := -1

		if t.kind == .Ident {
			for p, p_idx in macro.params {
				if p == t.text {
					param = p_idx
					break
				}
			}
		}

		if param == -1 {
			append(&result, t)
		} else {
			append(&result, ..args[arg_starts[param]:arg_ends[param]])
		}
	}

	return result[:]
}

expand_tokens :: proc(c: ^Compiler, tokens: []Token, at: Token, depth: int) {
	if depth > 32 {
		compile_error(c, at.file, at.line, "A macro expands to itself without end")
		return
	}

	i := 0

	for i < len(tokens) && !c.failed {
		t := tokens[i]
		m := t.kind == .Ident ? find_macro(c, t.text) : -1

		if m != -1 && !c.macros[m].is_function {
			expand_tokens(c, c.macros[m].body, at, depth + 1)
			i += 1
			continue
		}

		if m != -1 && i + 1 < len(tokens) && tokens[i + 1].kind == .LParen {
			end := i + 2
			open := 1

			for end < len(tokens) && open > 0 {
				if tokens[end].kind == .LParen {
					open += 1
				} else if tokens[end].kind == .RParen {
					open -= 1
				}

				end += 1
			}

			if open == 0 {
				expand_tokens(c, substitute_macro(c, c.macros[m], tokens[i + 2:end - 1], at), at, depth + 1)
				i = end
				continue
			}
		}

		t.file = at.file
		t.line = at.line
		append(&c.tokens, t)
		i += 1
	}
}

Known_Name :: struct {
	name: string,
	kind: Token_Kind,
	type: Type_Index,
	builtin: Builtin,
	builtin_var: Builtin_Var,
}

known_names: [256]Known_Name

name_hash_step :: proc "contextless" (hash: u32, ch: u8) -> u32 {
	return (hash ~ u32(ch)) * 16777619
}

find_known_name :: proc "contextless" (name: string, hash: u32) -> u8 {
	slot := hash % 255 + 1

	for known_names[slot].name != "" {
		if known_names[slot].name == name {
			return u8(slot)
		}

		slot = slot % 255 + 1
	}

	return 0
}

@(init)
init_known_names :: proc "contextless" () {
	add :: proc "contextless" (entry: Known_Name) {
		hash := u32(2166136261)

		for i in 0..<len(entry.name) {
			hash = name_hash_step(hash, entry.name[i])
		}

		slot := hash % 255 + 1

		for known_names[slot].name != "" {
			slot = slot % 255 + 1
		}

		known_names[slot] = entry
	}

	add({ name = "const", kind = .Kw_Const })
	add({ name = "uniform", kind = .Kw_Uniform })
	add({ name = "in", kind = .Kw_In })
	add({ name = "out", kind = .Kw_Out })
	add({ name = "inout", kind = .Kw_Inout })
	add({ name = "struct", kind = .Kw_Struct })
	add({ name = "if", kind = .Kw_If })
	add({ name = "else", kind = .Kw_Else })
	add({ name = "for", kind = .Kw_For })
	add({ name = "while", kind = .Kw_While })
	add({ name = "do", kind = .Kw_Do })
	add({ name = "return", kind = .Kw_Return })
	add({ name = "break", kind = .Kw_Break })
	add({ name = "continue", kind = .Kw_Continue })
	add({ name = "discard", kind = .Kw_Discard })
	add({ name = "true", kind = .Kw_True })
	add({ name = "false", kind = .Kw_False })
	add({ name = "layout", kind = .Kw_Layout })
	add({ name = "flat", kind = .Kw_Flat })
	add({ name = "smooth", kind = .Kw_Smooth })
	add({ name = "noperspective", kind = .Kw_Noperspective })
	add({ name = "precision", kind = .Kw_Precision })
	add({ name = "highp", kind = .Kw_Highp })
	add({ name = "mediump", kind = .Kw_Mediump })
	add({ name = "lowp", kind = .Kw_Lowp })
	add({ name = "switch", kind = .Kw_Switch })
	add({ name = "case", kind = .Kw_Case })
	add({ name = "default", kind = .Kw_Default })
	add({ name = "void", kind = .Ident, type = T_VOID })
	add({ name = "bool", kind = .Ident, type = T_BOOL })
	add({ name = "int", kind = .Ident, type = T_INT })
	add({ name = "uint", kind = .Ident, type = T_UINT })
	add({ name = "float", kind = .Ident, type = T_FLOAT })
	add({ name = "bvec2", kind = .Ident, type = T_BVEC2 })
	add({ name = "bvec3", kind = .Ident, type = T_BVEC3 })
	add({ name = "bvec4", kind = .Ident, type = T_BVEC4 })
	add({ name = "ivec2", kind = .Ident, type = T_IVEC2 })
	add({ name = "ivec3", kind = .Ident, type = T_IVEC3 })
	add({ name = "ivec4", kind = .Ident, type = T_IVEC4 })
	add({ name = "uvec2", kind = .Ident, type = T_UVEC2 })
	add({ name = "uvec3", kind = .Ident, type = T_UVEC3 })
	add({ name = "uvec4", kind = .Ident, type = T_UVEC4 })
	add({ name = "vec2", kind = .Ident, type = T_VEC2 })
	add({ name = "vec3", kind = .Ident, type = T_VEC3 })
	add({ name = "vec4", kind = .Ident, type = T_VEC4 })
	add({ name = "mat2", kind = .Ident, type = T_MAT2 })
	add({ name = "mat3", kind = .Ident, type = T_MAT3 })
	add({ name = "mat4", kind = .Ident, type = T_MAT4 })
	add({ name = "sampler2D", kind = .Ident, type = T_SAMPLER_2D })
	add({ name = "gl_Position", kind = .Ident, builtin_var = .Position })
	add({ name = "gl_FragCoord", kind = .Ident, builtin_var = .Frag_Coord })
	add({ name = "gl_VertexID", kind = .Ident, builtin_var = .Vertex_ID })
	add({ name = "gl_InstanceID", kind = .Ident, builtin_var = .Instance_ID })
	add({ name = "gl_FrontFacing", kind = .Ident, builtin_var = .Front_Facing })
	add({ name = "gl_FragDepth", kind = .Ident, builtin_var = .Frag_Depth })

	for name, builtin in builtin_names {
		if builtin != .None {
			add({ name = name, kind = .Ident, builtin = builtin })
		}
	}
}


is_ident_start :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

is_digit :: proc(ch: u8) -> bool {
	return ch >= '0' && ch <= '9'
}

is_hex_digit :: proc(ch: u8) -> bool {
	return is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

lex_file :: proc(c: ^Compiler, file_idx: int) {
	src := c.files[file_idx].source
	file := u16(file_idx)
	line := i32(1)
	i := 0
	n := len(src)
	line_has_token := false
	calls := make([dynamic]Macro_Call, 0, 4, c.allocator)
	define_macro := -1
	define_start := 0
	open_conditions := 0
	skip_depth := 0
	skip_can_resume := false

	for i <= n {
		if c.failed {
			return
		}

		ch := i < n ? src[i] : '\n'

		if ch == '\n' {
			line += 1
			i += 1
			line_has_token = false

			if define_macro != -1 {
				c.macros[define_macro].body = slice.clone(c.tokens[define_start:], c.allocator)
				c.macros[define_macro].ready = true
				resize(&c.tokens, define_start)
				define_macro = -1
			}

			continue
		}

		if ch == ' ' || ch == '\t' || ch == '\r' {
			i += 1
			continue
		}

		if ch == '\\' && i + 1 < n && src[i + 1] == '\n' {
			i += 2
			line += 1
			continue
		}

		if ch == '\\' && i + 2 < n && src[i + 1] == '\r' && src[i + 2] == '\n' {
			i += 3
			line += 1
			continue
		}

		if skip_depth > 0 && (ch != '#' || line_has_token) {
			for i < n && src[i] != '\n' {
				i += 1
			}

			continue
		}

		if ch == '/' && i + 1 < n && src[i + 1] == '/' {
			for i < n && src[i] != '\n' {
				i += 1
			}

			continue
		}

		if ch == '/' && i + 1 < n && src[i + 1] == '*' {
			i += 2

			for i < n {
				if src[i] == '*' && i + 1 < n && src[i + 1] == '/' {
					i += 2
					break
				}

				if src[i] == '\n' {
					line += 1
				}

				i += 1
			}

			continue
		}

		if ch == '#' && !line_has_token {
			i += 1

			for i < n && (src[i] == ' ' || src[i] == '\t') {
				i += 1
			}

			start := i

			for i < n && is_ident_start(src[i]) {
				i += 1
			}

			directive := string(src[start:i])

			if skip_depth > 0 {
				switch directive {
				case "ifdef", "ifndef":
					skip_depth += 1

				case "else":
					if skip_depth == 1 && skip_can_resume {
						skip_depth = 0
						open_conditions += 1
					}

				case "endif":
					skip_depth -= 1
				}

				for i < n && src[i] != '\n' {
					i += 1
				}

				continue
			}

			switch directive {
			case "define", "undef", "ifdef", "ifndef":
				for i < n && (src[i] == ' ' || src[i] == '\t') {
					i += 1
				}

				name_start := i

				for i < n && (is_ident_start(src[i]) || is_digit(src[i])) {
					i += 1
				}

				name := string(src[name_start:i])

				if name == "" {
					compile_error(c, file, line, "Expected a name after #%s", directive)
					return
				}

				existing := find_macro(c, name)

				if directive == "ifdef" || directive == "ifndef" {
					if (existing != -1) == (directive == "ifdef") {
						open_conditions += 1
					} else {
						skip_depth = 1
						skip_can_resume = true
					}

					break
				}

				if existing != -1 {
					ordered_remove(&c.macros, existing)
				}

				if directive == "undef" {
					break
				}

				macro := Macro { name = name }

				if i < n && src[i] == '(' {
					macro.is_function = true
					params := make([dynamic]string, 0, 4, c.allocator)
					i += 1

					for i < n && src[i] != ')' && src[i] != '\n' {
						if src[i] == ' ' || src[i] == '\t' || src[i] == ',' {
							i += 1
							continue
						}

						param_start := i

						for i < n && (is_ident_start(src[i]) || is_digit(src[i])) {
							i += 1
						}

						if i == param_start {
							compile_error(c, file, line, "The parameters of the macro '%s' are not valid", name)
							return
						}

						append(&params, string(src[param_start:i]))
					}

					if i >= n || src[i] != ')' {
						compile_error(c, file, line, "The parameters of the macro '%s' are missing a ')'", name)
						return
					}

					i += 1
					macro.params = params[:]
				}

				append(&c.macros, macro)
				define_macro = len(c.macros) - 1
				define_start = len(c.tokens)
				line_has_token = true
				continue

			case "else":
				if open_conditions == 0 {
					compile_error(c, file, line, "#else without #ifdef")
					return
				}

				open_conditions -= 1
				skip_depth = 1
				skip_can_resume = false

			case "endif":
				if open_conditions == 0 {
					compile_error(c, file, line, "#endif without #ifdef")
					return
				}

				open_conditions -= 1

			case "vertex":
				if file_idx != 0 {
					compile_error(c, file, line, "#vertex is not allowed in an included file")
					return
				}

				append(&c.tokens, Token { kind = .Stage_Vertex, file = file, line = line })

			case "fragment":
				if file_idx != 0 {
					compile_error(c, file, line, "#fragment is not allowed in an included file")
					return
				}

				append(&c.tokens, Token { kind = .Stage_Fragment, file = file, line = line })

			case "include":
				for i < n && (src[i] == ' ' || src[i] == '\t') {
					i += 1
				}

				if i >= n || src[i] != '"' {
					compile_error(c, file, line, "Expected a quoted path after #include")
					return
				}

				i += 1
				path_start := i

				for i < n && src[i] != '"' && src[i] != '\n' {
					i += 1
				}

				if i >= n || src[i] != '"' {
					compile_error(c, file, line, "Unterminated #include path")
					return
				}

				lex_include(c, file_idx, line, string(src[path_start:i]))
				i += 1

			case "version", "extension":

			case "if", "elif", "pragma", "error", "line":
				compile_error(c, file, line, "#%s is not supported. The directives are #include, #vertex, #fragment, #define, #undef, #ifdef, #ifndef, #else and #endif", directive)
				return

			case:
				compile_error(c, file, line, "Unknown directive #%s", directive)
				return
			}

			for i < n && src[i] != '\n' {
				i += 1
			}

			continue
		}

		line_has_token = true

		if is_ident_start(ch) {
			start := i
			hash := u32(2166136261)

			for i < n && (is_ident_start(src[i]) || is_digit(src[i])) {
				hash = name_hash_step(hash, src[i])
				i += 1
			}

			text := string(src[start:i])
			known := find_known_name(text, hash)
			token := Token { kind = known == 0 ? .Ident : known_names[known].kind, known = known, file = file, line = line, text = text }
			macro := len(c.macros) > 0 && token.kind == .Ident ? find_macro(c, text) : -1

			if macro == -1 {
				append(&c.tokens, token)
				continue
			}

			if !c.macros[macro].is_function {
				expand_tokens(c, c.macros[macro].body, token, 0)
				continue
			}

			after := i

			for after < n && (src[after] == ' ' || src[after] == '\t' || src[after] == '\r' || src[after] == '\n') {
				after += 1
			}

			append(&c.tokens, token)

			if after < n && src[after] == '(' {
				append(&calls, Macro_Call { macro = c.macros[macro], start = len(c.tokens) - 1 })
			}

			continue
		}

		if is_digit(ch) || (ch == '.' && i + 1 < n && is_digit(src[i + 1])) {
			start := i
			kind := Token_Kind.Int_Lit

			if ch == '0' && i + 1 < n && (src[i + 1] == 'x' || src[i + 1] == 'X') {
				i += 2

				for i < n && is_hex_digit(src[i]) {
					i += 1
				}
			} else {
				for i < n && is_digit(src[i]) {
					i += 1
				}

				if i < n && src[i] == '.' {
					kind = .Float_Lit
					i += 1

					for i < n && is_digit(src[i]) {
						i += 1
					}
				}

				if i < n && (src[i] == 'e' || src[i] == 'E') {
					kind = .Float_Lit
					i += 1

					if i < n && (src[i] == '+' || src[i] == '-') {
						i += 1
					}

					for i < n && is_digit(src[i]) {
						i += 1
					}
				}
			}

			text := string(src[start:i])

			if kind == .Float_Lit {
				if i < n && (src[i] == 'f' || src[i] == 'F') {
					i += 1
				}
			} else if i < n && (src[i] == 'u' || src[i] == 'U') {
				kind = .Uint_Lit
				i += 1
			}

			append(&c.tokens, Token { kind = kind, file = file, line = line, text = text })
			continue
		}

		next := i + 1 < n ? src[i + 1] : 0
		next2 := i + 2 < n ? src[i + 2] : 0
		kind := Token_Kind.EOF
		length := 1

		switch ch {
		case '(': kind = .LParen
		case ')': kind = .RParen
		case '{': kind = .LBrace
		case '}': kind = .RBrace
		case '[': kind = .LBracket
		case ']': kind = .RBracket
		case '.': kind = .Dot
		case ',': kind = .Comma
		case ';': kind = .Semicolon
		case ':': kind = .Colon
		case '?': kind = .Question
		case '~': kind = .Tilde

		case '+':
			if next == '+' {
				kind = .Inc
				length = 2
			} else if next == '=' {
				kind = .Add_Assign
				length = 2
			} else {
				kind = .Plus
			}

		case '-':
			if next == '-' {
				kind = .Dec
				length = 2
			} else if next == '=' {
				kind = .Sub_Assign
				length = 2
			} else {
				kind = .Minus
			}

		case '*':
			if next == '=' {
				kind = .Mul_Assign
				length = 2
			} else {
				kind = .Star
			}

		case '/':
			if next == '=' {
				kind = .Div_Assign
				length = 2
			} else {
				kind = .Slash
			}

		case '%':
			if next == '=' {
				kind = .Mod_Assign
				length = 2
			} else {
				kind = .Percent
			}

		case '<':
			if next == '<' && next2 == '=' {
				kind = .Shl_Assign
				length = 3
			} else if next == '<' {
				kind = .Shl
				length = 2
			} else if next == '=' {
				kind = .Le
				length = 2
			} else {
				kind = .Lt
			}

		case '>':
			if next == '>' && next2 == '=' {
				kind = .Shr_Assign
				length = 3
			} else if next == '>' {
				kind = .Shr
				length = 2
			} else if next == '=' {
				kind = .Ge
				length = 2
			} else {
				kind = .Gt
			}

		case '=':
			if next == '=' {
				kind = .Eq_Eq
				length = 2
			} else {
				kind = .Assign
			}

		case '!':
			if next == '=' {
				kind = .Not_Eq
				length = 2
			} else {
				kind = .Not
			}

		case '&':
			if next == '&' {
				kind = .And_And
				length = 2
			} else if next == '=' {
				kind = .And_Assign
				length = 2
			} else {
				kind = .Amp
			}

		case '|':
			if next == '|' {
				kind = .Or_Or
				length = 2
			} else if next == '=' {
				kind = .Or_Assign
				length = 2
			} else {
				kind = .Pipe
			}

		case '^':
			if next == '^' {
				kind = .Xor_Xor
				length = 2
			} else if next == '=' {
				kind = .Xor_Assign
				length = 2
			} else {
				kind = .Caret
			}

		case:
			compile_error(c, file, line, "Unexpected character '%c'", rune(ch))
			return
		}

		append(&c.tokens, Token { kind = kind, file = file, line = line, text = string(src[i:i + length]) })
		i += length

		if len(calls) == 0 {
			continue
		}

		call := &calls[len(calls) - 1]

		if kind == .LParen {
			call.depth += 1
		} else if kind == .RParen {
			call.depth -= 1
		}

		if call.depth > 0 {
			continue
		}

		name := c.tokens[call.start]
		args := slice.clone(c.tokens[call.start + 2:len(c.tokens) - 1], c.allocator)
		resize(&c.tokens, call.start)
		expand_tokens(c, substitute_macro(c, call.macro, args, name), name, 0)
		pop(&calls)
	}

	if open_conditions > 0 || skip_depth > 0 {
		compile_error(c, file, line, "An #ifdef or #ifndef is missing its #endif")
	}
}

lex_include :: proc(c: ^Compiler, from_file: int, line: i32, path: string) {
	from_name := c.files[from_file].name
	dir_end := strings.last_index_any(from_name, "/\\")
	joined := path

	if dir_end >= 0 {
		joined = strings.concatenate({ from_name[:dir_end + 1], path }, c.allocator)
	}

	parts := make([dynamic]string, 0, 16, c.allocator)
	part_start := 0

	for i in 0..=len(joined) {
		if i < len(joined) && joined[i] != '/' && joined[i] != '\\' {
			continue
		}

		part := joined[part_start:i]
		part_start = i + 1

		if part == "." {
			continue
		}

		if part == ".." && len(parts) > 0 && parts[len(parts) - 1] != ".." && parts[len(parts) - 1] != "" {
			pop(&parts)
			continue
		}

		append(&parts, part)
	}

	full_path := strings.join(parts[:], "/", c.allocator)

	for f in c.files {
		if f.name == full_path {
			return
		}
	}

	if c.options.read_file == nil {
		compile_error(c, u16(from_file), line, "Cannot #include \"%s\": no file reader was supplied", path)
		return
	}

	data, data_ok := c.options.read_file(full_path, c.options.read_file_user_data, c.allocator)

	if !data_ok {
		compile_error(c, u16(from_file), line, "Cannot read included file \"%s\"", full_path)
		return
	}

	if len(c.files) >= 65535 {
		compile_error(c, u16(from_file), line, "Too many included files")
		return
	}

	append(&c.files, Source_File { name = full_path, source = data })
	lex_file(c, len(c.files) - 1)
}
