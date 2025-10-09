#!/usr/bin/env bash
# image_installer.sh
# HERMES Project
# License: GPLv3
#
# Usage: sudo ./image_installer.sh  raspios.img hermes-installer.tar.gz station.hermes.radio [user] [pass]

set -euo pipefail

#if [ "$EUID" -ne 0 ]; then
#  echo "Please run as root (for loop device setup)"
#  exit 1
#fi

if [ "$#" -lt 3 ]; then
  echo "Usage: sudo $0 <image> <installer.tar.gz> <FQDN> [user] [pass]"
  exit 1
fi

IMG=$1
INSTALLER=$2
FQDN=$3
USER=${4:-pi}
PASS=${5:-hermes}

WORKDIR=$(mktemp -d /tmp/piboot.XXXX)

cleanup() {
  set +e
  echo "Cleaning up..."
  umount "$WORKDIR/boot/firmware" 2>/dev/null || true
  umount "$WORKDIR" 2>/dev/null || true
  losetup -d "$LOOP" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT


LOOP=$(losetup --show -fP "$IMG")
BOOT_PART="${LOOP}p1"
ROOT_PART="${LOOP}p2"

mount "$ROOT_PART" "$WORKDIR"
mount "$BOOT_PART" "$WORKDIR/boot/firmware"

cp $INSTALLER "$WORKDIR/root/"

systemd-nspawn -D "$WORKDIR" /bin/bash -c "\
  ls -l; tar xzf /root/$(basename $INSTALLER) -C /root/ && \
  cd /root/hermes-installer && \
  ./installer.sh $FQDN && \
  rm -rf /root/hermes-installer /root/$(basename $INSTALLER)"

exit

KERNEL="$WORKDIR/kernel8.img"
DTB="$WORKDIR/bcm2711-rpi-4-b.dtb"

cp "$WORKDIR/boot/kernel8.img" "$KERNEL"
cp "$WORKDIR/boot/bcm2711-rpi-4-b.dtb" "$DTB"

# Get root UUID
ROOT_UUID=$(lsblk -no UUID "$ROOT_PART")

umount "$WORKDIR/boot"
losetup -d "$LOOP"

echo "Extracted kernel: $KERNEL"
echo "Extracted dtb:    $DTB"

# --- Boot QEMU (Raspberry Pi 4 with USB networking) ---
NET_OPTS="-netdev user,id=net0,hostfwd=tcp::2222-:22 -device usb-net,netdev=net0"


$QEMU_BIN -machine virt -cpu cortex-a72 -smp 6 -m 4G -nographic \
    -kernel kernel/vmlinuz -initrd kernel/initrd.gz -append "root=/dev/vda2 rootfstype=ext4 rw panic=0 console=ttyAMA0,115200 rootwait=1" \
    -drive format=raw,file=${IMG},if=none,id=hd0,cache=writeback \
    -accel tcg,thread=multi \
    -device virtio-blk,drive=hd0,bootindex=0 \
    -netdev user,id=mynet,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=mynet \
    -monitor telnet:127.0.0.1:5555,server,nowait


# -M raspi4b \
#  -kernel "$KERNEL" -dtb "$DTB" \
#  -m 2048 \
#  -drive file="$IMG",format=raw,if=sd \
#  -append "rw console=ttyAMA0,115200 root=/dev/mmcblk1p2 rootfstype=ext4 rootwait" \
#  -device usb-kbd \
#  $NET_OPTS \
#  -serial stdio \
#  -graphic gtk

  # -serial telnet:localhost:4321,server,nowait \
 # -monitor telnet:localhost:4322,server,nowait \
 # -nographic

#-display none &
#QEMU_PID=$!

#  -serial mon:stdio \
#    -serial telnet:localhost:4321,server,nowait \
#  -append "rw console=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" \
#  -display none &
#   -append "rw root=UUID=7c32fc47-9afe-48a1-8b32-00cf57bc60de rootfstype=ext4 rootwait" \

echo "QEMU started. Waiting for SSH on port 2222..."

# --- Wait for SSH to come up ---
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
