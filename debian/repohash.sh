#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

DEBIAN_RELEASE='trixie'
DEBIAN_REPOSITORY_RELEASE=(
    "http://deb.debian.org/debian/dists/${DEBIAN_RELEASE}/Release"
    "http://deb.debian.org/debian/dists/${DEBIAN_RELEASE}-updates/Release"
    "http://security.debian.org/dists/${DEBIAN_RELEASE}-security/Release"
    "${SCRIPT_DIR}/make.sh"
    "${SCRIPT_DIR}/repohash.sh"
)

require_tools() {
  local required_tools=(
    sha256sum
    curl
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
    local source
    local source_name
    local hash

    for source in "${DEBIAN_REPOSITORY_RELEASE[@]}"; do
        if [[ "$source" =~ ^https?:// ]]; then
            hash="$(curl -s -L -f "$source" | sha256sum | cut -d ' ' -f1)"
            source_name="$source"
        else
            hash="$(cat "$source" | sha256sum | cut -d ' ' -f1)"
            source_name="${source#${ROOT_DIR}/}"
        fi

        echo "$hash $source_name"
    done
}

main() {
    require_tools

    calculate_hashs
}

main "$@"
