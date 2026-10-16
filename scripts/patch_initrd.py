#!/usr/bin/env python3
"""
patch_initrd.py - Patches Android-x86 initrd.img to strictly require the specified
SRC directory (e.g. ANDRID) and prioritize external SD card / USB block devices
over internal eMMC storage.
"""

import sys
import os
import gzip

def patch_init_content(txt: str) -> str:
    # 1. Require SRC strictly when SRC is provided so we never hijack internal eMMC OS (Bass OS)
    old_candidate = """	if [ -z "$SRC" ] || [ ! -e "/mnt/$SRC/$RAMDISK" ]; then
		for candidate in ANDRID andrid android Android ANDROID ""; do
			if [ -n "$candidate" ] && [ -e "/mnt/$candidate/$RAMDISK" ]; then
				SRC="$candidate"
				break
			elif [ -z "$candidate" ] && [ -e "/mnt/$RAMDISK" ]; then
				SRC=""
				break
			fi
		done
	fi"""

    new_candidate = """	if [ -n "$SRC" ]; then
		if [ ! -e "/mnt/$SRC/$RAMDISK" ]; then
			return 1
		fi
	else
		for candidate in ANDRID andrid android Android ANDROID ""; do
			if [ -n "$candidate" ] && [ -e "/mnt/$candidate/$RAMDISK" ]; then
				SRC="$candidate"
				break
			elif [ -z "$candidate" ] && [ -e "/mnt/$RAMDISK" ]; then
				SRC=""
				break
			fi
		done
	fi"""

    if old_candidate in txt:
        txt = txt.replace(old_candidate, new_candidate)
        print("  [+] Patched candidate loop to strictly require SRC and reject eMMC OS hijacking")
    else:
        print("  [!] Warning: candidate loop not matched")

    # 2. Prioritize external MicroSD slot (mmcblk1p*) and USB (sd*[0-9]) before internal eMMC
    old_loop = "for device in ${ROOT:-/dev/[hmnsv][dmrv][0-9a-z]*}; do"
    new_loop = "for device in ${ROOT:-/dev/mmcblk1p* /dev/sd*[0-9] /dev/[hmnsv][dmrv][0-9a-z]*}; do"

    if old_loop in txt:
        txt = txt.replace(old_loop, new_loop)
        print("  [+] Patched device detection loop to prioritize external SD card and USB media")
    else:
        print("  [!] Warning: device loop not matched")

    return txt

def patch_initrd(input_path: str, output_path: str):
    print(f"Reading initrd: {input_path}")
    try:
        with gzip.open(input_path, 'rb') as f:
            raw = f.read()
    except Exception:
        with open(input_path, 'rb') as f:
            raw = f.read()

    pos = 0
    entries = []
    patched = False

    while pos < len(raw):
        if raw[pos:pos+6] != b'070701':
            break
        hdr = bytearray(raw[pos:pos+110])
        namesize = int(hdr[94:102], 16)
        filesize = int(hdr[54:62], 16)
        name_start = pos + 110
        fn = raw[name_start:name_start + namesize - 1].decode('latin1')
        name_pad = (4 - ((110 + namesize) % 4)) % 4
        file_start = name_start + namesize + name_pad
        file_pad = (4 - (filesize % 4)) % 4
        content = raw[file_start:file_start + filesize]

        if fn == 'init':
            txt = content.decode('latin1')
            patched_txt = patch_init_content(txt)
            content = patched_txt.encode('latin1')
            filesize = len(content)
            hdr[54:62] = f'{filesize:08X}'.encode('ascii')
            patched = True

        entries.append({
            'hdr': hdr,
            'name': fn,
            'content': content
        })
        if fn == 'TRAILER!!!':
            break
        pos = file_start + filesize + file_pad

    assert patched, "Failed to patch init inside initrd"

    rebuilt = bytearray()
    for e in entries:
        name_bytes = e['name'].encode('latin1') + b'\x00'
        name_pad = (4 - ((110 + len(name_bytes)) % 4)) % 4
        file_pad = (4 - (len(e['content']) % 4)) % 4
        rebuilt += e['hdr'] + name_bytes + (b'\x00' * name_pad) + e['content'] + (b'\x00' * file_pad)

    pad = (512 - (len(rebuilt) % 512)) % 512
    rebuilt += b'\x00' * pad

    print(f"Compressing new initrd to: {output_path}")
    with gzip.open(output_path, 'wb', compresslevel=9) as f:
        f.write(rebuilt)

    print(f"Successfully generated {output_path} ({os.path.getsize(output_path)} bytes)")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: patch_initrd.py <input initrd.img> <output initrd.img>")
        sys.exit(1)
    patch_initrd(sys.argv[1], sys.argv[2])
