#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
kit=Sources/HyperpointKit
bad=0

fail() { print -u2 "layer violation: $1"; print -u2 -- "$2"; bad=1 }

code() { grep -rEn --include='*.swift' "$2" "$1" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true }

forbid_imports() {
  local hits; hits=$(code "$1" "^(public |internal |package |@preconcurrency )?import ($2)\$")
  [[ -z "$hits" ]] || fail "$1 imports a framework it must not ($3)" "$hits"
}

declared() { [[ -d $1 ]] || return 0; { grep -rhoE --include='*.swift' '(class|struct|enum|actor|protocol|typealias) [A-Z][A-Za-z0-9]*' "$1" || true } | awk '{print $2}' | sort -u }

forbid_symbols() {
  local names hits; names=$(declared "$2" | paste -sd'|' -)
  [[ -n "$names" ]] || return 0
  hits=$(code "$1" "\\b($names)\\b")
  [[ -z "$hits" ]] || fail "$1 uses symbols from $2" "$hits"
}

forbid_imports $kit/Model 'AppKit|SwiftUI|IOKit(\..*)?|CoreGraphics|ApplicationServices|CoreServices|Carbon|os|Dispatch' "Model is Foundation only"
forbid_imports $kit/Core 'AppKit|SwiftUI|IOKit(\..*)?|ApplicationServices|CoreServices|Carbon|os|Dispatch' "Core is pure"
forbid_imports Sources/Hyperpoint 'IOKit(\..*)?|CoreGraphics|ApplicationServices|Carbon' "the app talks to Engine, never to devices"

effects=$(code $kit/Core 'Thread\b|DispatchQueue|CFRunLoop|Date\(\)|\.now\b|Process\(|FileManager|UserDefaults|Task *[({]|\.sleep\(')
[[ -z "$effects" ]] || fail "$kit/Core has effects: threads, clocks, processes and files belong in Runtime" "$effects"

forbid_symbols $kit/Core $kit/Runtime
forbid_symbols $kit/Model $kit/Runtime
forbid_symbols $kit/Model $kit/Core

exit $bad
