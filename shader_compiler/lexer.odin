package karl2d_shader_compiler

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
	file: u16,
	line: i32,
	text: string,
}

keyword_kind :: proc(text: string) -> Token_Kind {
	switch text {
	case "const": return .Kw_Const
	case "uniform": return .Kw_Uniform
	case "in": return .Kw_In
	case "out": return .Kw_Out
	case "inout": return .Kw_Inout
	case "struct": return .Kw_Struct
	case "if": return .Kw_If
	case "else": return .Kw_Else
	case "for": return .Kw_For
	case "while": return .Kw_While
	case "do": return .Kw_Do
	case "return": return .Kw_Return
	case "break": return .Kw_Break
	case "continue": return .Kw_Continue
	case "discard": return .Kw_Discard
	case "true": return .Kw_True
	case "false": return .Kw_False
	case "layout": return .Kw_Layout
	case "flat": return .Kw_Flat
	case "smooth": return .Kw_Smooth
	case "noperspective": return .Kw_Noperspective
	case "precision": return .Kw_Precision
	case "highp": return .Kw_Highp
	case "mediump": return .Kw_Mediump
	case "lowp": return .Kw_Lowp
	case "switch": return .Kw_Switch
	case "case": return .Kw_Case
	case "default": return .Kw_Default
	}

	return .Ident
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

	for i < n {
		if c.failed {
			return
		}

		ch := src[i]

		if ch == '\n' {
			line += 1
			i += 1
			line_has_token = false
			continue
		}

		if ch == ' ' || ch == '\t' || ch == '\r' {
			i += 1
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

			switch directive {
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

			case "define", "undef", "if", "ifdef", "ifndef", "else", "elif", "endif", "pragma", "error", "line":
				compile_error(c, file, line, "#%s is not supported. Only #include, #vertex and #fragment exist, there is no preprocessor", directive)
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
			i += 1

			for i < n && (is_ident_start(src[i]) || is_digit(src[i])) {
				i += 1
			}

			text := string(src[start:i])
			append(&c.tokens, Token { kind = keyword_kind(text), file = file, line = line, text = text })
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
