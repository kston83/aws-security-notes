#!/usr/bin/env bash
# Regenerates control-mappings/control-impact-matrix.csv from the tables in
# control-mappings/services/*.md. One row per configuration-control pair.
# Usage: scripts/build-control-matrix.sh   (run from anywhere; requires gawk)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/control-mappings/control-impact-matrix.csv"

gawk '
function clean(s) {
  s = gensub(/\[([^\]]*)\]\([^)]*\)/, "\\1", "g", s)   # markdown links -> text
  gsub(/`/, "", s)
  gsub(/\*\*/, "", s)
  gsub(/^[ \t]+|[ \t]+$/, "", s)
  return s
}
function q(s) { gsub(/"/, "\"\"", s); return "\"" s "\"" }
function types(s,   n, a, i, r, t) {
  n = split(s, a, /, */); r = ""
  for (i = 1; i <= n; i++) {
    t = a[i]
    if (t == "I") t = "Implements"; else if (t == "S") t = "Supports"; else if (t == "E") t = "Evidence"
    r = r (i > 1 ? "; " : "") t
  }
  return r
}
BEGIN {
  print "service_group,section,configuration,control_id,family,impact_type,failure_impact,evidence,automated_check"
}
FNR == 1 {
  group = FILENAME
  sub(/.*\//, "", group); sub(/\.md$/, "", group)
  section = ""
}
/^## / { section = substr($0, 4); next }
/^\| *Configuration *\|/ || /^\|-/ { next }
/^\| / {
  line = $0
  sub(/^\| */, "", line); sub(/ *\|[ \t\r]*$/, "", line)
  n = split(line, f, / *\| */)
  if (n < 6) next
  m = split(f[2], c, /, */)
  for (i = 1; i <= m; i++) {
    id = clean(c[i]); if (id == "") continue
    fam = id; sub(/[^A-Z].*$/, "", fam)
    print q(group) "," q(section) "," q(clean(f[1])) "," q(id) "," q(fam) "," q(types(clean(f[3]))) "," q(clean(f[4])) "," q(clean(f[5])) "," q(clean(f[6]))
  }
}
' "$root"/control-mappings/services/*.md > "$out"

echo "Wrote $(($(wc -l < "$out") - 1)) rows to ${out#"$root"/}"
