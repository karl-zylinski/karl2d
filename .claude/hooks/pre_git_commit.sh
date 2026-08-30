#!/usr/bin/env bash
# Puts the CLAUDE.md commit message rules in front of the model before it commits.

set -u

input=$(cat)

# Match the command being run, not any mention of the words. Grepping the whole payload fires on
# things like a grep for "git commit" in an unrelated command.
command=$(printf '%s' "$input" | tr -d '\r\n' |
	sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

printf '%s' "$command" | grep -qE '(^|[;&|] *)git commit' || exit 0

here=$(dirname "$0")
rules=$("$here/claude_md_section.sh" "Commit messages") || exit 0

# The rules become a JSON string, so backslashes and quotes have to survive the trip, and the
# newlines collapse to spaces because the value is a single paragraph either way.
escaped=$(printf '%s' "$rules" |
	sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
	awk '{ printf "%s ", $0 }')

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"CLAUDE.md rules for the commit message: %s"}}\n' "$escaped"
