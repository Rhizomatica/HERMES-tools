#!/usr/bin/env bash
# image_installer.sh
# HERMES Project
# License: GPLv3
#
# Usage: sudo ./image_installer.sh raspios.img hermes-installer.tar.gz station.hermes.radio

set -euo pipefail

DEFAULT_IMG_NAME="2025-10-01-raspios-bookworm-arm64-lite.img"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (for loop device setup)"
  exit 1
fi

if [ "$#" -lt 3 ]; then
  echo "Usage: sudo $0 <image> <installer.tar.gz>"
  echo "<image> - path to Raspberry Pi OS image or \"auto\" to download automatically"
  exit 1
fi

IMG=$1
INSTALLER=$2
FQDN=$3
USER=${4:-pi}
PASS=${5:-hermes}

INTERMEDIATE_SIZE=17179869184
TARGET_SIZE=30000000000

WORKDIR=$(mktemp -d /tmp/piboot.XXXX)

cleanup() {
  set +e
  echo "Cleaning up..."
  umount "$WORKDIR/boot/firmware" 2>/dev/null || true
  umount "$WORKDIR" 2>/dev/null || true
  rm -rf "$WORKDIR"
  losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

if [ "$IMG" == "auto" ]; then
    echo "[*] Downloading latest Raspberry Pi OS Lite image..."
    if [ -f "${DEFAULT_IMG_NAME}.xz" ]; then
        rm -f "${DEFAULT_IMG_NAME}"
        unxz -k "${DEFAULT_IMG_NAME}.xz"
        echo "[*] Using cached image at ${DEFAULT_IMG_NAME}.xz"
    else
        wget https://downloads.raspberrypi.com/raspios_oldstable_lite_arm64/images/raspios_oldstable_lite_arm64-2025-10-02/${DEFAULT_IMG_NAME}.xz
        rm -f "${DEFAULT_IMG_NAME}"
        unxz -k "${DEFAULT_IMG_NAME}.xz"
        echo "[*] Downloaded image to $IMG.xz"
    fi
    IMG="${FQDN}.img"
    mv "${DEFAULT_IMG_NAME}" "${IMG}"
fi

# check if image size is less than 16GB
IMG_SIZE=$(stat -c%s "$IMG")
if [ "$IMG_SIZE" -lt "$INTERMEDIATE_SIZE" ]; then
    echo "[*] Resizing image to 16GB..."
    qemu-img resize "${IMG}" "$INTERMEDIATE_SIZE"

    LOOP=$(losetup --show -fP "$IMG")
    BOOT_PART="${LOOP}p1"
    ROOT_PART="${LOOP}p2"

    parted --script "$LOOP" resizepart 2 100%
    e2fsck -f "${ROOT_PART}"
    resize2fs "${ROOT_PART}"
else
    LOOP=$(losetup --show -fP "$IMG")
    BOOT_PART="${LOOP}p1"
    ROOT_PART="${LOOP}p2"
    echo "[*] Image size is already 16GB or larger, skipping resize."
fi

mount "$ROOT_PART" "$WORKDIR"
mount "$BOOT_PART" "$WORKDIR/boot/firmware"

cp $INSTALLER "$WORKDIR/root/"

systemd-nspawn -D "$WORKDIR" /bin/bash -c "\
  ls -l; tar xzf /root/$(basename $INSTALLER) -C /root/ && \
  cd /root/hermes-installer && \
  ./installer.sh -v $FQDN"

echo "[*] Done. systemd-spawn is off."

MNT_BOOT="$WORKDIR/boot/firmware"

echo "[*] Copying kernel and DTB..."
mkdir -p boot
cp "$MNT_BOOT/kernel8.img" boot/
cp "$MNT_BOOT/bcm2711-rpi-4-b.dtb" boot/

echo "[*] Unmounting image..."
sudo umount "$MNT_BOOT"
sudo umount "$WORKDIR"
sudo losetup -d "$LOOP"

echo "[*] Booting QEMU for last step setup..."
qemu-system-aarch64 \
    -M raspi4b \
    -m 2G \
    -smp 4 \
    -kernel "boot/kernel8.img" \
    -dtb "boot/bcm2711-rpi-4-b.dtb" \
    -append "rw earlyprintk loglevel=8 root=/dev/mmcblk1p2 rootwait" \
    -drive "file=$IMG,if=sd,format=raw" \
    -display gtk


echo "[*] Adjusting to 30GB final image size..."
IMG_SIZE=$(stat -c%s "$IMG")
if [ "$IMG_SIZE" -lt "$TARGET_SIZE" ]; then
    echo "[*] Resizing image to 30GB..."
    qemu-img resize "${IMG}" $TARGET_SIZE

    LOOP=$(losetup --show -fP "$IMG")
    BOOT_PART="${LOOP}p1"
    ROOT_PART="${LOOP}p2"

    parted --script "$LOOP" resizepart 2 100%
    e2fsck -f "${ROOT_PART}"
    resize2fs "${ROOT_PART}"

else
    echo "[*] Image size is already 30GB or larger, skipping resize."
    LOOP=$(losetup --show -fP "$IMG")
    BOOT_PART="${LOOP}p1"
    ROOT_PART="${LOOP}p2"
fi

echo "[*] Running Disk Defrag (e4defrag)"
mount "$ROOT_PART" "$WORKDIR"
e4defrag "${ROOT_PART}"
umount "$WORKDIR"

echo "[*] Zeroing free space for better compression"
zerofree "${LOOPDEV}p2"

echo "[*] Compressing with pigz -9 (parallel gzip)"
pigz -9 -v "$IMG"
md5sum "${IMG}.gz" > "${IMG}.gz.md5"
md5sum -c "${IMG}.gz.md5"

echo "[*] Final compressed image size: $(du -m "${IMG}.gz" | cut -f1) MB"
echo "[*] Done. Image ready: $IMG"
