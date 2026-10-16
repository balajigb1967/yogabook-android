#!/usr/bin/env python3
"""
patch_initrd.py - Patches initrd.img to:
1. Mount root filesystem rw directly (preventing 'Can't mount, would change RO state' error)
2. Ensure persistent /data directory is created and bind-mounted to eMMC storage
"""

import sys
import os
import gzip

def patch_initrd(initrd_path: str):
    print(f"Reading initrd: {initrd_path}")
    with gzip.open(initrd_path, "rb") as f:
        raw = f.read()

    pos = 0
    entries = []
    patched = 0

    while pos < len(raw):
        if raw[pos:pos+6] != b'070701':
            break
        hdr = bytearray(raw[pos:pos+110])
        namesize = int(hdr[94:102], 16)
        raw_filesize = int(hdr[54:62], 16)
        name_start = pos + 110
        name = raw[name_start:name_start + namesize - 1].decode('latin1')
        name_pad = (4 - ((110 + namesize) % 4)) % 4
        file_start = name_start + namesize + name_pad
        raw_file_pad = (4 - (raw_filesize % 4)) % 4
        content = raw[file_start:file_start + raw_filesize]

        if name == 'init':
            txt = content.decode('latin1')
            old_str = 'try_mount ro $dev /mnt || return 1'
            new_str = 'try_mount rw "$dev" /mnt || try_mount ro "$dev" /mnt || return 1'
            if old_str in txt:
                txt = txt.replace(old_str, new_str)
                print("  [+] Patched init: try_mount rw directly for persistent storage")
                patched += 1

            # Patch check_root to strictly require install.img if INSTALL is set (rejects eMMC)
            old_cr_end = """\tmkdir -p mnt
\techo " found at $1"
\trm /sbin/mke2fs
\thash -r
}"""

            new_cr_end = """\tif [ -n "$INSTALL" ]; then
\t\tif [ ! -f "/mnt/$SRC/install.img" ] && [ ! -f "/mnt/install.img" ] && [ ! -f "/mnt/ANDRID/install.img" ]; then
\t\t\tumount system 2>/dev/null
\t\t\tmountpoint -q /sfs && umount /sfs 2>/dev/null
\t\t\tumount /mnt 2>/dev/null
\t\t\trm -rf *
\t\t\treturn 1
\t\tfi
\tfi
\tmkdir -p mnt
\techo " found at $1"
\trm /sbin/mke2fs
\thash -r
}"""
            if old_cr_end in txt:
                txt = txt.replace(old_cr_end, new_cr_end)
                print("  [+] Patched init: check_root strictly requires install.img on installer partition")
                patched += 1

            # Ensure block scan loop checks SD card devices specifically
            old_dev_loop = 'for device in ${ROOT:-/dev/[hmnsv][dmrv][0-9a-z]*}; do'
            new_dev_loop = 'for device in ${ROOT:-/dev/mmcblk0p* /dev/mmcblk1p* /dev/sd*[0-9] /dev/[hmnsv][dmrv][0-9a-z]*}; do'
            if old_dev_loop in txt:
                txt = txt.replace(old_dev_loop, new_dev_loop)
                print("  [+] Patched init: prioritize MMC & SD card block partitions in detection loop")
                patched += 1

            content = txt.encode('latin1')
            hdr[54:62] = f'{len(content):08X}'.encode('ascii')

        elif name == 'scripts/yogabook-disk-detect.sh':
            txt = content.decode('latin1')
            if 'YOGABOOK_DETECTED' not in txt:
                txt = '#!/bin/busybox sh\n[ -n "$YOGABOOK_DETECTED" ] && return 0 2>/dev/null || true\nexport YOGABOOK_DETECTED=1\n' + txt.lstrip('#!/bin/busybox sh\n')
                content = txt.encode('latin1')
                hdr[54:62] = f'{len(content):08X}'.encode('ascii')
                print("  [+] Patched yogabook-disk-detect.sh: single run guard to prevent duplicate screen outputs")
                patched += 1

        elif name == 'scripts/2-mount':
            txt = content.decode('latin1')
            old_mdata = """mount_data()
{
	mountpoint -q data && return
	if [ -n "$DATA" ]; then"""

            new_mdata = """mount_data()
{
	mountpoint -q data && return
	remount_rw
	mkdir -p "/mnt/$SRC/data" 2>/dev/null || true
	if [ -d "/mnt/$SRC/data" ]; then
		mount --bind "/mnt/$SRC/data" data && return
	fi
	if [ -n "$DATA" ]; then"""

            if old_mdata in txt:
                txt = txt.replace(old_mdata, new_mdata)
                content = txt.encode('latin1')
                hdr[54:62] = f'{len(content):08X}'.encode('ascii')
                print("  [+] Patched scripts/2-mount: persistent /data creation and bind mount")
                patched += 1

        entries.append({
            'hdr': hdr,
            'name': name,
            'content': content
        })

        if name == 'TRAILER!!!':
            break
        pos = file_start + raw_filesize + raw_file_pad

    print(f"Repacking initrd ({len(entries)} entries, {patched} patched)...")
    rebuilt = bytearray()
    for e in entries:
        name_bytes = e['name'].encode('latin1') + b'\x00'
        name_pad = (4 - ((110 + len(name_bytes)) % 4)) % 4
        file_pad = (4 - (len(e['content']) % 4)) % 4
        rebuilt += e['hdr'] + name_bytes + (b'\x00' * name_pad) + e['content'] + (b'\x00' * file_pad)

    pad = (512 - (len(rebuilt) % 512)) % 512
    rebuilt += b'\x00' * pad

    with gzip.open(initrd_path, 'wb', compresslevel=9) as f:
        f.write(rebuilt)
    print(f"Successfully updated {initrd_path} ({os.path.getsize(initrd_path)} bytes)")

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'D:/ANDRID/initrd.img'
    patch_initrd(target)
