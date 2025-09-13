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

# Ensure loop module is loaded
if ! lsmod | grep -q '^loop'; then
    echo "[*] loop module not loaded, attempting to load..."
    if ! modprobe loop; then
        echo "[-] Failed to load loop module. Please load it manually with: modprobe loop"
        exit 1
    fi
    echo "[+] loop module loaded successfully"
fi

# Check required tools
for cmd in truncate parted losetup e2fsck resize2fs zerofree gzip md5sum dumpe2fs; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "[-] Missing required tool: $cmd"; exit 1; }
done

cleanup() {
    if [ -n "$LOOPDEV" ] && losetup -a | grep -q "$LOOPDEV"; then
        echo "[!] Cleaning up: detaching $LOOPDEV"
        losetup -d "$LOOPDEV" || true
    fi
}
trap cleanup EXIT INT TERM

if [ ! -f "$IMAGE" ]; then
    echo "[-] Image file not found: $IMAGE"
    exit 1
fi

IMAGE_SIZE=$(stat -c%s "$IMAGE")
echo "[*] Image size: $IMAGE_SIZE bytes; target: $TARGET_SIZE bytes"

if (( IMAGE_SIZE > TARGET_SIZE )); then
    echo "[*] Image larger than target: will shrink partitions + filesystem to fit"

    # Attach image
    echo "[*] Attaching image to loop device"
    LOOPDEV=$(losetup --find --partscan --show "$IMAGE")
    echo "[*] Loop device: $LOOPDEV"

    # Make sure partitions aren't mounted
    if mount | grep -q "^${LOOPDEV}p"; then
        echo "[-] One of the image partitions is mounted. Please unmount before running."
        exit 1
    fi

    # Ensure filesystem consistent
    echo "[*] Running e2fsck on ${LOOPDEV}p2"
    e2fsck -f -y "${LOOPDEV}p2"

    # Get partition 2 start (in bytes) via parted (unit B)
    PARTED_OUT=$(parted -s --machine "$LOOPDEV" unit B print 2>/dev/null || true)
    P2_START=$(printf "%s\n" "$PARTED_OUT" | awk -F: '/^2:/{ gsub(/B$/,"",$2); gsub(/[^0-9]/,"",$2); print $2; exit }')

    if [ -z "$P2_START" ]; then
        echo "[-] Failed to determine partition 2 start with parted. Aborting."
        losetup -d "$LOOPDEV"
        LOOPDEV=""
        exit 1
    fi

    echo "[*] Partition 2 starts at byte offset: $P2_START"

    # Get the filesystem block size
    BLKSIZE=$(dumpe2fs -h "${LOOPDEV}p2" 2>/dev/null | awk -F: '/Block size:/ {gsub(/ /,"",$2); print $2; exit}')
    if [ -z "$BLKSIZE" ]; then
        echo "[-] Failed to read filesystem block size. Aborting."
        losetup -d "$LOOPDEV"
        LOOPDEV=""
        exit 1
    fi
    echo "[*] Filesystem block size: $BLKSIZE"

    # Calculate available bytes for partition 2 inside TARGET_SIZE
    # Reserve 1 byte margin to avoid boundary issues
    AVAILABLE_BYTES=$(( TARGET_SIZE - P2_START - 1 ))
    if (( AVAILABLE_BYTES <= 0 )); then
        echo "[-] No space available for partition 2 within TARGET_SIZE. Aborting."
        losetup -d "$LOOPDEV"
        LOOPDEV=""
        exit 1
    fi
    echo "[*] Available bytes for partition 2 inside target image: $AVAILABLE_BYTES"

    # Convert available bytes to filesystem blocks (floor)
    MAX_FS_BLOCKS=$(( AVAILABLE_BYTES / BLKSIZE ))
    echo "[*] Max filesystem blocks that will fit: $MAX_FS_BLOCKS"

    # Check minimum possible filesystem size
    MIN_BLOCKS=$(resize2fs -P "${LOOPDEV}p2" 2>&1 | awk '/Estimated minimum size/ {print $NF}')
    if [ -z "$MIN_BLOCKS" ]; then
        echo "[-] Could not determine filesystem minimum size. Aborting."
        losetup -d "$LOOPDEV"
        LOOPDEV=""
        exit 1
    fi
    echo "[*] Filesystem minimum blocks: $MIN_BLOCKS"

    if (( MAX_FS_BLOCKS < MIN_BLOCKS )); then
        echo "[-] Cannot shrink: required MAX_FS_BLOCKS ($MAX_FS_BLOCKS) < minimum filesystem size ($MIN_BLOCKS)."
        echo "[-] You must delete files from the filesystem first or choose a larger TARGET_SIZE."
        losetup -d "$LOOPDEV"
        LOOPDEV=""
        exit 1
    fi

    # Shrink filesystem to fit inside target
    echo "[*] Shrinking filesystem to ${MAX_FS_BLOCKS} blocks"
    resize2fs "${LOOPDEV}p2" "${MAX_FS_BLOCKS}"

    # Detach so we can safely edit the partition table on the image file
    echo "[*] Detaching loop device to update partition table on image"
    losetup -d "$LOOPDEV"
    LOOPDEV=""

    # Resize partition 2 in partition table to end at TARGET_SIZE - 1 bytes
    # parted expects an end value (we supply bytes)
    END_BYTE=$(( TARGET_SIZE - 1 ))
    echo "[*] Resizing partition 2 in partition table to end at ${END_BYTE}B"
    parted --script "$IMAGE" resizepart 2 "${END_BYTE}B"

    # Finally truncate the image to target size
    echo "[*] Truncating image to $TARGET_SIZE bytes"
    truncate -s "$TARGET_SIZE" "$IMAGE"

else
    # IMAGE_SIZE <= TARGET_SIZE: expand image to target and expand partitions
    if (( IMAGE_SIZE < TARGET_SIZE )); then
        echo "[*] Expanding image from $IMAGE_SIZE to $TARGET_SIZE bytes"
        truncate -s "$TARGET_SIZE" "$IMAGE"
    else
        echo "[*] Image already at target size"
    fi

    echo "[*] Resizing partition 2 to fill disk"
    parted --script "$IMAGE" resizepart 2 100%
fi

# Reattach loop and make fs fill partition
echo "[*] Attaching image to loop device for final resize"
LOOPDEV=$(losetup --find --partscan --show "$IMAGE")
echo "[*] Loop device: $LOOPDEV"

echo "[*] Running e2fsck on ${LOOPDEV}p2"
e2fsck -f -y "${LOOPDEV}p2"

echo "[*] Resizing ext4 filesystem on ${LOOPDEV}p2 to fill partition"
resize2fs "${LOOPDEV}p2"

echo "[*] Zeroing free space on ${LOOPDEV}p2 (slow)"
zerofree "${LOOPDEV}p2"

echo "[*] Detaching loop device"
losetup -d "$LOOPDEV"
LOOPDEV=""

echo "[*] Compressing image with gzip -9"
gzip -9 -v "$IMAGE"

echo "[*] Generating MD5 checksum"
md5sum "${IMAGE}.gz" > "${IMAGE}.gz.md5"

echo "[*] Verifying checksum"
md5sum -c "${IMAGE}.gz.md5"

echo "[+] Done. Uncompressed image resized to $TARGET_SIZE bytes."
echo "[+] Compressed image: ${IMAGE}.gz"
echo "[+] Checksum saved: ${IMAGE}.gz.md5"
