#!/usr/bin/env python3
"""
patch_ramdisk.py - Adds android_x86 compatibility links in ramdisk.img
so Android init will always find init.android_x86.rc, ueventd.android_x86.rc,
and fstab.android_x86 even if androidboot.hardware=android_x86 is passed.
"""

import os
import gzip

def patch_ramdisk(path: str):
    print(f"Reading ramdisk: {path}")
    with gzip.open(path, 'rb') as f:
        raw = f.read()

    pos = 0
    entries = []
    file_contents = {}

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

        file_contents[name] = (hdr, content)
        entries.append({
            'hdr': hdr,
            'name': name,
            'content': content
        })

        if name == 'TRAILER!!!':
            break
        pos = file_start + raw_filesize + raw_file_pad

    # Add duplicates for android_x86 aliases of android_x86_64 files
    aliases = [
        ('init.android_x86_64.rc', 'init.android_x86.rc'),
        ('ueventd.android_x86_64.rc', 'ueventd.android_x86.rc'),
        ('fstab.android_x86_64', 'fstab.android_x86.rc'),
        ('fstab.android_x86_64', 'fstab.android_x86'),
    ]

    new_entries = []
    for src_name, dst_name in aliases:
        if src_name in file_contents and dst_name not in file_contents:
            orig_hdr, content = file_contents[src_name]
            new_hdr = bytearray(orig_hdr)
            # update namesize
            namesize = len(dst_name) + 1
            new_hdr[94:102] = f'{namesize:08X}'.encode('ascii')
            new_entries.append({
                'hdr': new_hdr,
                'name': dst_name,
                'content': content
            })
            print(f"  [+] Added alias: {dst_name} -> {src_name}")

    # Insert new entries right before TRAILER!!!
    trailer = entries.pop()
    entries.extend(new_entries)
    entries.append(trailer)

    print(f"Repacking ramdisk ({len(entries)} entries)...")
    rebuilt = bytearray()
    for e in entries:
        name_bytes = e['name'].encode('latin1') + b'\x00'
        name_pad = (4 - ((110 + len(name_bytes)) % 4)) % 4
        file_pad = (4 - (len(e['content']) % 4)) % 4
        rebuilt += e['hdr'] + name_bytes + (b'\x00' * name_pad) + e['content'] + (b'\x00' * file_pad)

    pad = (512 - (len(rebuilt) % 512)) % 512
    rebuilt += b'\x00' * pad

    with gzip.open(path, 'wb', compresslevel=9) as f:
        f.write(rebuilt)
    print(f"Successfully updated {path} ({os.path.getsize(path)} bytes)")

if __name__ == '__main__':
    patch_ramdisk('D:/ANDRID/ramdisk.img')
