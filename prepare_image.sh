#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <disk-image>"
    exit 1
fi

IMAGE="$1"
# Safe size for a 32GB SD card (example)
TARGET_SIZE=31100000256
LOOPDEV=""

# Require root
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Must run as root"
    exit 1
fi

# Check required tools
for cmd in truncate sfdisk losetup e2fsck resize2fs zerofree gzip md5sum jq fdisk; do
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

# Step 2: Shrink filesystem if needed
CUR_SIZE=$(blockdev --getsize64 "${LOOPDEV}p2")
if [ "$TARGET_SIZE" -lt "$CUR_SIZE" ]; then
    echo "[*] Shrinking filesystem on ${LOOPDEV}p2"
    e2fsck -f -y "${LOOPDEV}p2"

    # Query minimum size (in 4K blocks)
    MIN_BLOCKS=$(resize2fs -P "${LOOPDEV}p2" 2>/dev/null | awk '{print $7}')

    # Compute max blocks that fit inside target size
    MAX_BLOCKS=$(( (TARGET_SIZE / 4096) - 1024 ))  # leave ~4MB margin

    if [ "$MIN_BLOCKS" -gt "$MAX_BLOCKS" ]; then
        echo "[-] Filesystem cannot shrink to fit target size ($TARGET_SIZE bytes)"
        exit 1
    fi

    echo "[*] Resizing filesystem to $MAX_BLOCKS blocks (~$((MAX_BLOCKS*4096/1024/1024)) MiB)"
    resize2fs "${LOOPDEV}p2" $MAX_BLOCKS
fi

# Step 3: Detach loop before changing partition table
losetup -d "$LOOPDEV"
LOOPDEV=""

# Step 4: Update partition table with sfdisk
echo "[*] Updating partition table for partition 2"

START_SECTOR=$(sfdisk -J "$IMAGE" | jq '.partitiontable.partitions[1].start')
if ! [[ "$START_SECTOR" =~ ^[0-9]+$ ]]; then
    echo "[-] Failed to determine start sector for partition 2"
    exit 1
fi

END_SECTOR=$(( (TARGET_SIZE / 512) - 1 ))
SIZE_SECTORS=$((END_SECTOR - START_SECTOR + 1))

echo "[DEBUG] START=$START_SECTOR END=$END_SECTOR SIZE=$SIZE_SECTORS"
echo "$START_SECTOR,$SIZE_SECTORS,L" | sfdisk -N 2 "$IMAGE"

# Step 5: Resize raw image file
echo "[*] Truncating image file to $TARGET_SIZE bytes"
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
