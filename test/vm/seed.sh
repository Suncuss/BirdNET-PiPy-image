#!/bin/bash
# Write the first-boot settings Raspberry Pi Imager would write (user,
# password, SSH key, hostname, timezone, wired network) into an image's boot
# partition, so a VM boot exercises the same cloud-init path a real flash does.
#
# The files mirror what Imager 2.0.6 generates for these settings
# (rpi-imager src/customization_generator.cpp). Uses mtools, so no mounting,
# loop devices or sudo — the same script works on Linux and macOS.
#
# Usage: test/vm/seed.sh IMAGE SSH_PUBKEY_FILE
# Env:   VM_USER (birder)  VM_PASSWORD (birdnet-test)  VM_HOSTNAME (birdnet-vm)
#        VM_TIMEZONE (America/New_York)
# Needs: mtools, openssl with `passwd -6` (macOS: brew install mtools openssl@3)

set -euo pipefail

IMAGE="${1:?usage: seed.sh IMAGE SSH_PUBKEY_FILE}"
PUBKEY_FILE="${2:?usage: seed.sh IMAGE SSH_PUBKEY_FILE}"

VM_USER="${VM_USER:-birder}"
VM_PASSWORD="${VM_PASSWORD:-birdnet-test}"
VM_HOSTNAME="${VM_HOSTNAME:-birdnet-vm}"
VM_TIMEZONE="${VM_TIMEZONE:-America/New_York}"

# Boot partition = MBR entry 1; its start LBA is at byte 454 (446 + 8)
start_lba=$(od -An -t u4 -j 454 -N 4 "$IMAGE" | tr -d ' ')
offset=$((start_lba * 512))

password_hash=$(openssl passwd -6 "$VM_PASSWORD")
pubkey=$(cat "$PUBKEY_FILE")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/user-data" <<EOF
#cloud-config
manage_resolv_conf: false

hostname: $VM_HOSTNAME
manage_etc_hosts: true
packages:
- avahi-daemon

apt:
  preserve_sources_list: true
  conf: |
    Acquire {
      Check-Date "false";
    };

timezone: $VM_TIMEZONE
keyboard:
  model: pc105
  layout: "us"
users:
- name: $VM_USER
  groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
  shell: /bin/bash
  lock_passwd: false
  passwd: "$password_hash"
  ssh_authorized_keys:
    - $pubkey
  sudo: ALL=(ALL) NOPASSWD:ALL

enable_ssh: true
ssh_pwauth: true
EOF

cat > "$work/network-config" <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: true
      optional: true
EOF

mcopy -o -i "$IMAGE@@$offset" "$work/user-data" "$work/network-config" ::/
echo "Seeded $IMAGE: user $VM_USER, hostname $VM_HOSTNAME"
