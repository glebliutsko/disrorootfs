#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEBIAN_RELEASE='trixie'
DEBIAN_ARCH='amd64'
DEBIAN_MIRROR='http://deb.debian.org/debian'
ROOTFS_DIR="${ROOTFS_DIR:-${SCRIPT_DIR}/rootfs}"
DEBOOTSTRAP_VARIANT='minbase'

APT_REPOSITORY="
Types: deb
URIs: http://deb.debian.org/debian
Suites: $DEBIAN_RELEASE $DEBIAN_RELEASE-updates
Components: contrib main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org
Suites: $DEBIAN_RELEASE-security
Components: contrib main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
"

DEBOOTSTRAP_PACKAGES=(
  dialog
  locales
)

CHROOT_PACKAGES=(
  systemd-sysv
  dbus

  ifupdown
  iproute2
  iputils-ping
  bind9-dnsutils
  traceroute
  netcat-openbsd

  tree
  less
  wget
  curl

  vim
  htop

  tar
  gzip
  zip
  unzip
  xz-utils

  python3
)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

require_tools() {
  local required_tools=(
    debootstrap
    mount
    mountpoint
    umount
    chroot
  )
  local tool

  for tool in "${required_tools[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Required tool not found: ${tool}" >&2
      exit 1
    fi
  done
}

unmount_all() {
  local mounts=(
    "/dev/full"
    "/dev/null"
    "/dev/random"
    "/dev/tty"
    "/dev/urandom"
    "/dev/zero"
    "/dev/ptmx"
    "/proc"
    "/run"
    "/dev/pts"
    "/dev"
    "/sys"
  )

  local i
  for i in "${mounts[@]}"; do
    if mountpoint -q "${ROOTFS_DIR}/$i"; then
      umount -v "${ROOTFS_DIR}/$i"
    fi
  done
}

mount_chroot_fs() {
  local mounts_dev=(
    "/dev/full"
    "/dev/null"
    "/dev/random"
    "/dev/tty"
    "/dev/urandom"
    "/dev/zero"
  )

  local i

  mount -v -t tmpfs tmpfs "${ROOTFS_DIR}/dev" -o mode=755
  for i in "${mounts_dev[@]}"; do
    touch "${ROOTFS_DIR}/$i"
    mount -v --bind "$i" "${ROOTFS_DIR}/$i"
  done

  mkdir -p "${ROOTFS_DIR}/dev/pts"
  mount -v -t devpts devpts "${ROOTFS_DIR}/dev/pts" -o ptmxmode=666

  touch "${ROOTFS_DIR}/dev/ptmx"
  mount -v --bind "${ROOTFS_DIR}/dev/pts/ptmx" "${ROOTFS_DIR}/dev/ptmx"

  mount -v -t proc proc "${ROOTFS_DIR}/proc"
  mount -v -t tmpfs tmpfs "${ROOTFS_DIR}/run" -o mode=755
  mount -v -t tmpfs tmpfs "${ROOTFS_DIR}/sys" -o mode=755
}

run_debootstrap() {
  local packages
  packages="$(printf '%q,' "${DEBOOTSTRAP_PACKAGES[@]}" | sed 's/,$//')"

  mkdir -p "${ROOTFS_DIR}"

  debootstrap \
    --arch="${DEBIAN_ARCH}" \
    --variant="${DEBOOTSTRAP_VARIANT}" \
    --include="${packages}" \
    "${DEBIAN_RELEASE}" \
    "${ROOTFS_DIR}" \
    "${DEBIAN_MIRROR}"

  rm -v -rf "${ROOTFS_DIR:?}"/dev/*
  rm -v -rf "${ROOTFS_DIR:?}"/run/*
}

configure_repository() {
  rm -v -f "${ROOTFS_DIR}/etc/apt/sources.list"
  echo "$APT_REPOSITORY" > "${ROOTFS_DIR}"/etc/apt/sources.list.d/debian.sources
}

disable_systemd_units() {
  local units=(
    'sys-kernel-config.mount'
    'sys-kernel-debug.mount'
    'systemd-modules-load.service'
  )
  
  local i
  for i in "${units[@]}"; do
    ln -v -s '/dev/null' "${ROOTFS_DIR:?}/etc/systemd/system/$i"
  done
}

install_chroot_packages() {
  local packages
  packages="$(printf '%q ' "${CHROOT_PACKAGES[@]}")"

  DEBIAN_FRONTEND=noninteractive \
  LANG=en_US.UTF-8 \
  PATH=/sbin:/bin:/usr/sbin:/usr/bin \
  chroot "${ROOTFS_DIR}" /bin/bash -euxc "
    sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    locale-gen
    update-locale LANG=en_US.UTF-8

    apt update
    apt upgrade -y
    apt install -y ${packages}
    apt clean
    rm -v -rf /var/lib/apt/lists/*

    rm -v -rf /etc/cron.daily/
    echo -n '' > /etc/motd
  "
}

rootfs_pack() {
  local current_date
  local image_name

  current_date="$(date +"%Y-%m-%dT%H-%M-%S")"
  image_name="debian_${DEBIAN_RELEASE}-${DEBIAN_ARCH}-${current_date}.tar.zst"
  (
    cd "${ROOTFS_DIR:?}"
    tar --numeric-owner --zstd -cvf "../$image_name" .
  )
}

main() {
  require_root
  require_tools

  trap unmount_all EXIT

  run_debootstrap
  configure_repository
  disable_systemd_units
  mount_chroot_fs
  install_chroot_packages
  unmount_all

  rootfs_pack
}

main "$@"
