#!/usr/bin/env bash
# Holds the model to the CLAUDE.md checklist once per distinct set of Odin changes. The hash in the
# git directory keeps it from asking again about work it has already asked about.

set -u

input=$(cat)

printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0

changes=$(git diff HEAD -- '*.odin' 2>/dev/null)
untracked=$(git ls-files --others --exclude-standard -- '*.odin' 2>/dev/null)

if [ -z "$changes" ] && [ -z "$untracked" ]; then
	exit 0
fi

current=$(printf '%s\n%s' "$changes" "$untracked" | git hash-object --stdin)
seen_file="$git_dir/karl2d-checklist-seen"

if [ -f "$seen_file" ] && [ "$(cat "$seen_file")" = "$current" ]; then
	exit 0
fi

here=$(dirname "$0")
checklist=$("$here/claude_md_section.sh" "Checklist") || {
	echo "CLAUDE.md has no Checklist section. The Stop hook reads it from there." >&2
	exit 2
}

printf '%s' "$current" > "$seen_file"

{
	echo "Odin files changed. Go through the CLAUDE.md checklist and say which of these you did."
	echo
	printf '%s\n' "$checklist"
} >&2

exit 2
