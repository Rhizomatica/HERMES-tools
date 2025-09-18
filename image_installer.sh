#!/usr/bin/env bash
# automate-pi-qemu-rpi4.sh
# Usage: sudo ./automate-pi-qemu-rpi4.sh raspios.img hermes-installer.tar.gz fqdn [user] [pass]

set -euo pipefail

IMG=$1
INSTALLER=$2
FQDN=$3
USER=${4:-pi}
PASS=${5:-raspberry}

QEMU_BIN=${QEMU_BIN:-qemu-system-aarch64}
WORKDIR=$(mktemp -d /tmp/piboot.XXXX)

cleanup() {
  set +e
  echo "Cleaning up..."
  umount "$WORKDIR/boot" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# --- Mount image and extract kernel + dtb ---
mkdir -p "$WORKDIR/boot"
# Find partitions
LOOP=$(losetup --show -fP "$IMG")
BOOT_PART="${LOOP}p1"

mount "$BOOT_PART" "$WORKDIR/boot"

KERNEL="$WORKDIR/kernel8.img"
DTB="$WORKDIR/bcm2711-rpi-4-b.dtb"

cp "$WORKDIR/boot/kernel8.img" "$KERNEL"
cp "$WORKDIR/boot/bcm2711-rpi-4-b.dtb" "$DTB"

umount "$WORKDIR/boot"
losetup -d "$LOOP"

echo "Extracted kernel: $KERNEL"
echo "Extracted dtb:    $DTB"

# --- Boot QEMU ---
NET_OPTS="-netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-device,netdev=net0"

$QEMU_BIN -M raspi4 \
  -kernel "$KERNEL" -dtb "$DTB" \
  -m 2048 \
  -drive file="$IMG",format=raw,if=sd \
  -append "rw console=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" \
  -serial stdio \
  $NET_OPTS \
  -display none &
QEMU_PID=$!

echo "QEMU started (PID $QEMU_PID). Waiting for SSH on port 2222..."

# --- Wait for SSH ---
until sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -p 2222 "$USER"@127.0.0.1 "echo ssh-up" 2>/dev/null; do
  sleep 5
done

echo "SSH is up. Copying installer..."
sshpass -p "$PASS" scp -P 2222 -o StrictHostKeyChecking=no "$INSTALLER" "$USER"@127.0.0.1:/home/$USER/

echo "Running installer inside guest..."
sshpass -p "$PASS" ssh -p 2222 -o StrictHostKeyChecking=no "$USER"@127.0.0.1 "\
  tar xzf hermes-installer.tar.gz && \
  cd hermes-installer && \
  ./installer.sh $FQDN"

echo "Rebooting guest..."
sshpass -p "$PASS" ssh -p 2222 -o StrictHostKeyChecking=no "$USER"@127.0.0.1 "sudo reboot"

echo "Done. VM is rebooting."
