#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEBIAN_RELEASE='trixie'
DEBIAN_REPOSITORY_RELEASE=(
    "http://deb.debian.org/debian/dists/${DEBIAN_RELEASE}/Release"
    "http://deb.debian.org/debian/dists/${DEBIAN_RELEASE}-updates/Release"
    "http://security.debian.org/dists/${DEBIAN_RELEASE}-security/Release"
)

require_tools() {
  local required_tools=(
    curl
    sha256sum
  )
  local tool

  for tool in "${required_tools[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Required tool not found: ${tool}" >&2
      exit 1
    fi
  done
}

calculate_hashs() {
    local i
    local url

    for url in "${DEBIAN_REPOSITORY_RELEASE[@]}"; do
        hash="$(curl -s -L -f "$url" | sha256sum | cut -d ' ' -f1)"
        echo "$hash $url"
    done
}

main() {
    require_tools

    calculate_hashs
}

main "$@"
