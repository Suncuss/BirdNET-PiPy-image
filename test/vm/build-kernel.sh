#!/bin/bash
# Build a generic arm64 kernel + initrd that boots a Raspberry Pi OS image
# under QEMU's "virt" machine.
#
# The Pi's own kernel targets Pi hardware and can't drive QEMU's virtio disk
# and network, so we borrow Debian's and force those drivers into the initrd.
# Modules loaded in the initrd stay loaded after the switch to the image's own
# root filesystem, so the image under test is never modified.
#
# Usage: test/vm/build-kernel.sh [OUT_DIR]    (default: test/vm/.cache/kernel)
# Needs: docker on an arm64 host (Pi 5, Apple Silicon)

set -euo pipefail

OUT="${1:-$(dirname "$0")/.cache/kernel}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

docker run --rm --platform linux/arm64 -v "$OUT:/out" debian:trixie bash -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq initramfs-tools >/dev/null
    printf "%s\n" virtio_pci virtio_blk virtio_net virtio_rng ext4 vfat \
        nls_cp437 nls_ascii nls_utf8 nls_iso8859_1 >> /etc/initramfs-tools/modules
    apt-get install -y -qq linux-image-arm64 >/dev/null
    version=$(ls /lib/modules)
    cp "/boot/vmlinuz-$version" /out/vmlinuz
    cp "/boot/initrd.img-$version" /out/initrd.img
    echo "$version" > /out/version
    chown -R '"$(id -u):$(id -g)"' /out
'

echo "Kernel $(cat "$OUT/version") written to $OUT"
