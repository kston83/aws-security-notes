#!/usr/bin/env bash
# Checks every relative Markdown link in the repo: the target file must exist,
# and if the link has a #fragment, the target must contain a matching heading.
# External (http/https/mailto) links are not checked, nor is anything inside
# fenced code blocks or inline code spans.
# Usage: scripts/check-links.sh   (exit status 1 if any link is broken)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2

# GitHub-style heading slugs for a file, one per line.
slugs() {
  grep -E '^#{1,6} ' "$1" \
    | sed -E 's/^#{1,6} +//; s/[[:space:]]+$//' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}

broken=0
checked=0

while IFS= read -r file; do
  dir="$(dirname "$file")"
  # Pull out link targets: ](target)
  while IFS= read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|'') continue ;;
    esac
    path="${target%%#*}"
    frag=""
    [[ "$target" == *"#"* ]] && frag="${target#*#}"

    if [[ -z "$path" ]]; then
      dest="$file"
    else
      dest="$dir/$path"
    fi
    checked=$((checked + 1))

    if [[ ! -e "$dest" ]]; then
      echo "BROKEN  $file -> $target  (no such file)"
      broken=$((broken + 1))
      continue
    fi
    if [[ -n "$frag" && -f "$dest" ]]; then
      if ! slugs "$dest" | grep -qxF -- "$frag"; then
        echo "BROKEN  $file -> $target  (no such heading)"
        broken=$((broken + 1))
      fi
    fi
  # Skip fenced code blocks and inline code spans: GitHub renders neither as links.
  done < <(awk '/^[[:space:]]*(```|~~~)/ { fence = !fence; next } !fence' "$file" \
             | sed -E 's/`[^`]*`//g' \
             | grep -oE '\]\([^)[:space:]]+\)' | sed -E 's/^\]\(//; s/\)$//')
done < <(find . -name '*.md' -not -path './.git/*' | sed 's|^\./||' | sort)

echo "Checked $checked relative links; $broken broken."
[[ "$broken" -eq 0 ]]
