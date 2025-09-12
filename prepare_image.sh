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
for cmd in truncate parted losetup e2fsck resize2fs zerofree gzip md5sum; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "[-] Missing required tool: $cmd"; exit 1; }
done

# Cleanup function to detach loop device if still attached
cleanup() {
    if [ -n "$LOOPDEV" ] && losetup -a | grep -q "$LOOPDEV"; then
        echo "[!] Cleaning up: detaching $LOOPDEV"
        losetup -d "$LOOPDEV" || true
    fi
}
trap cleanup EXIT INT TERM

# Step 1: Resize the whole image file
echo "[*] Resizing image to $TARGET_SIZE bytes"
truncate -s "$TARGET_SIZE" "$IMAGE"

# Step 2: Use parted to resize partition 2 (ext4) to maximum
echo "[*] Resizing partition 2 to fill disk"
parted --script "$IMAGE" resizepart 2 100%

# Step 3: Attach image to loop device
echo "[*] Attaching image to loop device"
LOOPDEV=$(losetup --find --partscan --show "$IMAGE")

# Step 4: Resize ext4 filesystem on partition 2
echo "[*] Resizing ext4 filesystem on ${LOOPDEV}p2"
e2fsck -f -y "${LOOPDEV}p2"
resize2fs "${LOOPDEV}p2"

# Step 5: Zeroing out free space
echo "[*] Zeroing free space on ${LOOPDEV}p2"
zerofree "${LOOPDEV}p2"

# Step 6: Detach loop device
echo "[*] Detaching loop device"
losetup -d "$LOOPDEV"
LOOPDEV=""

# Step 7: Compress the image with gzip
echo "[*] Compressing image with gzip -9"
gzip -9 -v "$IMAGE"

# Step 8: Generate MD5 checksum file
echo "[*] Generating MD5 checksum"
md5sum "${IMAGE}.gz" > "${IMAGE}.gz.md5"

# Step 9: Verify the checksum right away
echo "[*] Verifying checksum"
md5sum -c "${IMAGE}.gz.md5"

echo "[+] Done. Uncompressed image resized to $TARGET_SIZE bytes."
echo "[+] Done. Compressed image: ${IMAGE}.gz"
echo "[+] Checksum saved to: ${IMAGE}.gz.md5"
echo "[+] Verify later with: md5sum -c ${IMAGE}.gz.md5"


