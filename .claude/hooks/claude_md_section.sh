#!/usr/bin/env bash
# Prints one "## <name>" section of CLAUDE.md, without its heading. Every hook gets its text this
# way so that CLAUDE.md stays the only place the rules are written down.

set -u

name=$1
root=${CLAUDE_PROJECT_DIR:-.}
file="$root/.claude/CLAUDE.md"

[ -f "$file" ] || exit 1

body=$(awk -v want="## $name" '
	$0 == want { found = 1; next }
	found && /^## / { exit }
	found { print }
' "$file" | sed -e '/^[[:space:]]*$/d')

[ -n "$body" ] || exit 1

printf '%s\n' "$body"
