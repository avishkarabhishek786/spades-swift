#!/usr/bin/env bash
# Enforces the purity rules in CLAUDE.md §4 mechanically.
#
# SpadesEngine and SpadesEconomy import only Foundation, take time and
# randomness as injected values, and never let an unordered collection decide
# output. Every one of those is easy to break by accident, which is why this is
# a build step and not a code-review convention.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="$ROOT/Packages/SpadesEngine/Sources"
status=0

# Comments are stripped before matching. The rules are about what the code
# does, and a doc comment explaining why `Calendar` is absent must not read as
# `Calendar` being present. Line numbers survive because the comment text is
# blanked in place rather than the line being removed.
code_only() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r file; do
    sed 's|//.*||' "$file" | grep -n . | sed "s|^|${file#"$ROOT/"}:|"
  done < <(find "$dir" -name '*.swift' | sort)
}

# scan <label> <dir> <pattern> [exclude...]
#
# The directory is always explicit. An earlier version defaulted it and took
# excludes in the same position, so the RNG rule silently scanned a directory
# named "using:" and could never fire.
scan() {
  local label="$1" dir="$2" pattern="$3"
  shift 3
  local matches
  matches="$(code_only "$dir" | grep -E "$pattern" || true)"
  for filter in "$@"; do
    matches="$(grep -v -- "$filter" <<<"$matches" || true)"
  done
  if [[ -n "$matches" ]]; then
    echo "PURITY VIOLATION — $label"
    sed 's/^/  /' <<<"$matches"
    status=1
  fi
}

# Reading the current time. `Date` as a stored type is fine; constructing one
# is not, because that is the clock entering the module.
scan "reads the clock — time must be injected" "$SOURCES" \
  '\bDate\(\)|\bDate\.now\b|\.timeIntervalSinceNow\b'

# Calendar arithmetic. Day-keys arrive as strings already resolved by the app
# layer; see the calendar boundary in §4.
scan "uses Calendar / TimeZone / DateFormatter — see the calendar boundary in §4" "$SOURCES" \
  '\b(Calendar|TimeZone|DateFormatter|DateComponents)\b'

# Foundation only.
scan "imports an Apple framework — these targets are Foundation-only" "$SOURCES" \
  '^[^:]*:[0-9]+:[[:space:]]*(@[a-zA-Z]+[[:space:]]+)?import[[:space:]]+(UIKit|SwiftUI|AVFoundation|GameKit|AppKit|CoreGraphics|Combine)\b'

# Pacing is a presentation concern and belongs in GameSession.
scan "sleeps — pacing belongs in the app layer" "$SOURCES" \
  '\bTask\.sleep\b|\bThread\.sleep\b|\busleep\('

# Randomness must come from an injected generator, never the system source.
scan "uses the system RNG — randomness enters through an injected generator" "$SOURCES" \
  '\.(random|randomElement|shuffled|shuffle)\(' 'using:'

# No singletons in the pure targets.
scan "reaches for a singleton" "$SOURCES" '\.shared\b'

# The target split is compiler-enforced, but an import is caught here first and
# reads more clearly than a link error.
scan "SpadesEconomy imports SpadesEngine — the targets are independent by design" \
  "$SOURCES/SpadesEconomy" 'import[[:space:]]+SpadesEngine\b'
scan "SpadesEngine imports SpadesEconomy — the targets are independent by design" \
  "$SOURCES/SpadesEngine" 'import[[:space:]]+SpadesEconomy\b'

if [[ $status -eq 0 ]]; then
  echo "purity check passed"
fi
exit $status
