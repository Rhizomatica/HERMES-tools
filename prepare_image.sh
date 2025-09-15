#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <disk-image>"
    exit 1
fi

IMAGE="$1"
# safe size for a 32GB SD card
TARGET_SIZE=31100000256
LOOPDEV=""

# Require root
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Must run as root"
    exit 1
fi

# Check required tools
for cmd in truncate sfdisk losetup e2fsck resize2fs zerofree gzip md5sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "[-] Missing required tool: $cmd"
        exit 1
    }
done

cleanup() {
    if [ -n "$LOOPDEV" ] && losetup -a | grep -q "$LOOPDEV"; then
        echo "[!] Cleaning up: detaching $LOOPDEV"
        losetup -d "$LOOPDEV" || true
    fi
}
trap cleanup EXIT INT TERM

echo "[*] Target image size: $TARGET_SIZE bytes"

# Step 1: Attach image to loop device
echo "[*] Attaching image to loop device"
LOOPDEV=$(losetup --find --partscan --show "$IMAGE")

# Step 2: Resize filesystem before shrinking
CUR_SIZE=$(blockdev --getsize64 "${LOOPDEV}p2")
if [ "$TARGET_SIZE" -lt "$CUR_SIZE" ]; then
    echo "[*] Shrinking filesystem on ${LOOPDEV}p2"
    e2fsck -f -y "${LOOPDEV}p2"
    resize2fs "${LOOPDEV}p2" $(( (TARGET_SIZE / 512) - 2048 ))s
fi

# Step 3: Detach loop before touching partition table
losetup -d "$LOOPDEV"
LOOPDEV=""

# Step 4: Resize partition table entry with sfdisk
echo "[*] Updating partition table for partition 2"
START_SECTOR=$(sfdisk -d "$IMAGE" | awk '/: start=/ && /, type=83/ {print $4}' | cut -d= -f2)
END_SECTOR=$(( (TARGET_SIZE / 512) - 1 ))
echo ",$((END_SECTOR - START_SECTOR + 1))" | sfdisk -N 2 "$IMAGE"

# Step 5: Truncate image file
echo "[*] Resizing raw image file"
truncate -s "$TARGET_SIZE" "$IMAGE"

# Step 6: Reattach loop and grow FS if needed
echo "[*] Reattaching loop device"
LOOPDEV=$(losetup --find --partscan --show "$IMAGE")
NEW_SIZE=$(blockdev --getsize64 "${LOOPDEV}p2")
if [ "$NEW_SIZE" -gt "$CUR_SIZE" ]; then
    echo "[*] Growing filesystem on ${LOOPDEV}p2"
    e2fsck -f -y "${LOOPDEV}p2"
    resize2fs "${LOOPDEV}p2"
fi

# Step 7: Zero free space
echo "[*] Zeroing free space on ${LOOPDEV}p2"
zerofree "${LOOPDEV}p2"

# Step 8: Detach loop
echo "[*] Detaching loop device"
losetup -d "$LOOPDEV"
LOOPDEV=""

# Step 9: Compress and checksum
echo "[*] Compressing image with gzip -9"
gzip -9 -v "$IMAGE"

echo "[*] Generating MD5 checksum"
md5sum "${IMAGE}.gz" > "${IMAGE}.gz.md5"

echo "[*] Verifying checksum"
md5sum -c "${IMAGE}.gz.md5"

echo "[+] Done. Final size: $TARGET_SIZE bytes"
echo "[+] Compressed image: ${IMAGE}.gz"
echo "[+] Checksum saved to: ${IMAGE}.gz.md5"
