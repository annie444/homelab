#!/usr/bin/env bash

echo "Zapping $1"

DISK=$1
# Zap the disk to a fresh, usable state (zap-all is important, b/c MBR has to be clean)
# You will have to run this step for all disks.
sgdisk --zap-all $DISK
# Clean hdds with dd
dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync
# Clean disks such as ssd with blkdiscard instead of dd
blkdiscard $DISK
# Inform the OS of partition table changes
partprobe $DISK
