#!/bin/bash
set -euo pipefail

# Force predictable output (avoid locale issues)
export LC_ALL=C

if [ $# -ne 1 ]; then
    echo "Usage: $0 <disk-image>"
    exit 1
fi

# --- Config ---
IMAGE="$1"
# optional: set target size in bytes, leave empty for "shrink to minimum"
# TARGET_SIZE=${2:-}
TARGET_SIZE=31100000256

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

LOOPDEV=""

# --- Helpers ---
cleanup() {
    if [ -n "${LOOPDEV}" ] && losetup -a | grep -q "$LOOPDEV"; then
        echo "[!] Detaching $LOOPDEV"
        losetup -d "$LOOPDEV" || true
    fi
}
trap cleanup EXIT INT TERM

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[-] Missing $1"; exit 1; }; }
for cmd in losetup sfdisk jq e2fsck resize2fs tune2fs truncate zerofree gzip md5sum e4defrag; do
    need_cmd "$cmd"
done

if [ $# -lt 1 ]; then
    echo "Usage: $0 <disk-image> [target-bytes]"
    exit 1
fi

#echo "[*] Working on $IMAGE"
#cp -v "$IMAGE" "$IMAGE.bak"  # safety backup

# --- Attach image ---
LOOPDEV=$(losetup --find --partscan --show "$IMAGE")
echo "[*] Loop attached: $LOOPDEV"

# --- Get FS block info ---
BLOCK_COUNT=$(tune2fs -l "${LOOPDEV}p2" | awk -F: '/Block count/ {gsub(/ /,"",$2); print $2}')
BLOCK_SIZE=$(tune2fs -l "${LOOPDEV}p2" | awk -F: '/Block size/ {gsub(/ /,"",$2); print $2}')
NEEDED_BYTES=$(( BLOCK_COUNT * BLOCK_SIZE ))
NEEDED_SECTORS=$(( NEEDED_BYTES / 512 ))

echo "[*] FS needs $NEEDED_BYTES bytes ($NEEDED_SECTORS sectors)"

# --- Partition info ---
START_SECTOR=$(sfdisk -J "$IMAGE" | jq '.partitiontable.partitions[1].start')
CUR_SIZE_SECTORS=$(sfdisk -J "$IMAGE" | jq '.partitiontable.partitions[1].size')
CUR_END=$(( START_SECTOR + CUR_SIZE_SECTORS - 1 ))

echo "[*] Partition 2: start=$START_SECTOR size=$CUR_SIZE_SECTORS sectors"

# --- Expand partition if FS bigger ---
REQUIRED_END=$(( START_SECTOR + NEEDED_SECTORS - 1 ))
if [ "$REQUIRED_END" -gt "$CUR_END" ]; then
    NEW_SIZE=$(( REQUIRED_END - START_SECTOR + 1 ))
    echo "[*] Expanding partition 2 -> $NEW_SIZE sectors"
    losetup -d "$LOOPDEV"
    echo "$START_SECTOR,$NEW_SIZE,L" | sfdisk -N 2 "$IMAGE"
    LOOPDEV=$(losetup --find --partscan --show "$IMAGE")
fi

# --- Repair FS ---
echo "[*] Running e2fsck"
e2fsck -f -y "${LOOPDEV}p2"

# --- Shrink FS if needed ---
MIN_BLOCKS=$(resize2fs -P "${LOOPDEV}p2" 2>/dev/null | awk '{print $7}')
echo "[*] Minimum blocks: $MIN_BLOCKS"

if [ -n "$TARGET_SIZE" ]; then
    MAX_BLOCKS=$(( TARGET_SIZE / BLOCK_SIZE - 1024 )) # margin
    if [ "$MIN_BLOCKS" -gt "$MAX_BLOCKS" ]; then
        echo "[-] Cannot shrink FS to $TARGET_SIZE bytes (min > max)"
        exit 1
    fi
    NEW_BLOCKS=$MAX_BLOCKS
    echo "[*] Resizing FS to target size: $NEW_BLOCKS blocks"
    resize2fs "${LOOPDEV}p2" $NEW_BLOCKS
else
    echo "[*] Shrinking FS to minimum: $MIN_BLOCKS blocks"
    resize2fs "${LOOPDEV}p2" $MIN_BLOCKS
fi

e2fsck -f -y "${LOOPDEV}p2"

# --- Update partition to FS size ---
BLOCK_COUNT_NOW=$(tune2fs -l "${LOOPDEV}p2" | awk -F: '/Block count/ {gsub(/ /,"",$2); print $2}')
NEEDED_BYTES_NOW=$(( BLOCK_COUNT_NOW * BLOCK_SIZE ))
NEEDED_SECTORS_NOW=$(( NEEDED_BYTES_NOW / 512 ))
NEW_END=$(( START_SECTOR + NEEDED_SECTORS_NOW - 1 ))
NEW_SIZE_SECTORS=$(( NEW_END - START_SECTOR + 1 ))

echo "[*] Final FS size: $NEEDED_BYTES_NOW bytes"
echo "[*] Shrinking partition 2 -> $NEW_SIZE_SECTORS sectors"

losetup -d "$LOOPDEV"
echo "$START_SECTOR,$NEW_SIZE_SECTORS,L" | sfdisk -N 2 "$IMAGE"
LOOPDEV=$(losetup --find --partscan --show "$IMAGE")

# --- Final checks ---
e2fsck -f -y "${LOOPDEV}p2"

# --- Truncate image to match partition ---
FINAL_BYTES=$(( (NEW_END + 1) * 512 ))
echo "[*] Truncating image to $FINAL_BYTES bytes"
losetup -d "$LOOPDEV"
LOOPDEV=""
truncate -s "$FINAL_BYTES" "$IMAGE"


LOOPDEV=$(losetup --find --partscan --show "$IMAGE")

# --- Mount partition and clean /root, /home/pi, /var ---
MNTDIR=$(mktemp -d /mnt/image.XXXX)
echo "[*] Mounting ${LOOPDEV}p2 at $MNTDIR"
mount "${LOOPDEV}p2" "$MNTDIR"

# Clean /root and /home/pi
for DIR in root home/pi; do
    TARGET="$MNTDIR/$DIR"
    if [ -d "$TARGET" ]; then
        echo "[*] Cleaning $TARGET (keeping dotfiles)"
        rm -rf "$TARGET"/*
        rm -rf "$TARGET/.cache" "$TARGET/.local"
    fi
done

# Clean old Debian packages
VAR_ARCHIVES="$MNTDIR/var/cache/apt/archives"
if [ -d "$VAR_ARCHIVES" ]; then
    echo "[*] Cleaning old Debian packages in $VAR_ARCHIVES"
    rm -rf "$VAR_ARCHIVES"/*
fi

echo "[*] Running Disk Defrag (e4defrag)"
e4defrag "${LOOPDEV}p2"

sync

umount "$MNTDIR"
rmdir "$MNTDIR"


# --- Zero free space ---
echo "[*] Zeroing free space"
zerofree "${LOOPDEV}p2"
losetup -d "$LOOPDEV"
LOOPDEV=""

# --- Compress & checksum ---
#echo "[*] Compressing with gzip -9"
#gzip -9 -v "$IMAGE"
#md5sum "${IMAGE}.gz" > "${IMAGE}.gz.md5"
#md5sum -c "${IMAGE}.gz.md5"

echo "[*] Compressing with pigz -9 (parallel gzip)"
pigz -9 -v "$IMAGE"
md5sum "${IMAGE}.gz" > "${IMAGE}.gz.md5"
md5sum -c "${IMAGE}.gz.md5"

echo "[+] Output: ${IMAGE}.gz"

#echo "[*] Compressing with plzip -9 (parallel LZMA2)"
#plzip -9 -v "$IMAGE"
#md5sum "${IMAGE}.lz" > "${IMAGE}.lz.md5"
#md5sum -c "${IMAGE}.lz.md5"
# echo "[+] Output: ${IMAGE}.lz"

echo "[+] Done. Final size: $FINAL_BYTES bytes"
