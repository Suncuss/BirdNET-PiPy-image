#!/bin/bash
# Boot a Raspberry Pi OS image in a hardware-accelerated QEMU VM (KVM on
# Linux, HVF on macOS) with the kernel from build-kernel.sh. SSH is forwarded
# to 127.0.0.1:$SSH_PORT.
#
# Usage: test/vm/boot.sh IMAGE [--background]
#   Foreground: serial console on this terminal (quit with Ctrl-A X).
#   --background: console goes to IMAGE.console.log, PID to IMAGE.pid.
# Env:   KERNEL_DIR (test/vm/.cache/kernel)  SSH_PORT (2222)  VM_CPUS (2)
#        VM_MEMORY (1536, in MB)
#
# Not covered by the VM (real hardware only): Pi firmware and config.txt, the
# first-boot root partition resize (it lives in the Pi's own initramfs), zram
# swap, EEPROM updates, audio devices.

set -euo pipefail

IMAGE="${1:?usage: boot.sh IMAGE [--background]}"
MODE="${2:-}"

KERNEL_DIR="${KERNEL_DIR:-$(dirname "$0")/.cache/kernel}"
SSH_PORT="${SSH_PORT:-2222}"
VM_CPUS="${VM_CPUS:-2}"
VM_MEMORY="${VM_MEMORY:-1536}"

if [ ! -f "$KERNEL_DIR/vmlinuz" ]; then
    echo "No kernel in $KERNEL_DIR; run test/vm/build-kernel.sh first" >&2
    exit 1
fi

case "$(uname -s)" in
    Linux) accel=kvm ;;
    Darwin) accel=hvf ;;
    *) echo "Unsupported host: $(uname -s)" >&2; exit 1 ;;
esac

# Pi OS mounts root by PARTUUID: the MBR disk signature (byte 440) + "-02"
disk_id=$(od -An -t x4 -j 440 -N 4 "$IMAGE" | tr -d ' ')

# net.ifnames=0 keeps the NIC named eth0, which Imager's network-config targets
args=(
    -M virt -accel "$accel" -cpu host -smp "$VM_CPUS" -m "$VM_MEMORY"
    -kernel "$KERNEL_DIR/vmlinuz" -initrd "$KERNEL_DIR/initrd.img"
    -append "console=ttyAMA0 root=PARTUUID=${disk_id}-02 rootfstype=ext4 fsck.repair=yes rootwait net.ifnames=0"
    -drive "file=$IMAGE,format=raw,if=virtio"
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
    -device virtio-rng-pci
)

if [ "$MODE" = "--background" ]; then
    rm -f "$IMAGE.console.log"
    qemu-system-aarch64 "${args[@]}" -display none \
        -serial "file:$IMAGE.console.log" -daemonize -pidfile "$IMAGE.pid"
    echo "VM started (PID $(cat "$IMAGE.pid")); console: $IMAGE.console.log; ssh port: $SSH_PORT"
else
    exec qemu-system-aarch64 "${args[@]}" -nographic
fi
