#!/usr/bin/env python3
"""
patch_installer.py - Patches Android-x86 install.img to enable 100% unattended
installation on devices without physical keyboards (such as the Lenovo Yoga Book).

Supports:
- AUTO_INSTALL=auto: Automatically targets internal OS partition (mmcblk0p2)
- AUTO_INSTALL=force_format: Cleanly formats target partition as ext4
- AUTO_INSTALL=update: Updates Android while preserving user data
- AUTO_INSTALL=mmcblk0p2: Explicit partition targeting
- Automatic 5-second countdown reboot on completion (no keyboard prompt lock)
"""

import sys
import os
import gzip

def patch_1_install_text(txt: str) -> str:
    old_hd = """install_hd()
{
	case "$AUTO_INSTALL" in
		[Uu]*)
			answer=${AUTO_UPDATE:-$(blkid | grep -v loop | grep -v iso9660 | sort | grep Android-x86 | cut -d: -f1 | head -1)}
			answer=${answer:-$(blkid | grep -v loop | sort | grep ext4 | cut -d: -f1 | head -1)}
			[ -b "$answer" -o -b /dev/$answer ] && answer=`basename $answer` || answer=
			AUTO_UPDATE=${answer:-$AUTO_UPDATE}
			;;
		*)
			[ -z "$answer" ] && set_answer_if_auto Create
			;;
	esac"""

    new_hd = """install_hd()
{
	case "$AUTO_INSTALL" in
		force_format*)
			target="${AUTO_INSTALL#force_format:}"
			[ "$target" = "$AUTO_INSTALL" ] && target="mmcblk0p2"
			answer=$(basename "$target")
			FORCE_FORMAT=ext4
			;;
		[Uu]*|auto|mmcblk*|sd*|nvme*|/dev/*)
			if [ "$AUTO_INSTALL" = "auto" ] || [ "${AUTO_INSTALL#[Uu]}" != "$AUTO_INSTALL" ]; then
				answer=${AUTO_UPDATE:-$(blkid | grep -v loop | grep -v iso9660 | sort | grep Android-x86 | cut -d: -f1 | head -1)}
				answer=${answer:-$(blkid | grep -v loop | grep -v iso9660 | sort | grep ext4 | cut -d: -f1 | head -1)}
				[ -z "$answer" ] && answer=$(ls /sys/block/mmcblk0/mmcblk0p* /sys/block/sda/sda* 2>/dev/null | grep -v -E "p1$|1$" | head -1)
			else
				answer="$AUTO_INSTALL"
			fi
			[ -b "$answer" -o -b "/dev/$answer" ] && answer=$(basename "$answer") || answer=
			AUTO_UPDATE=${answer:-$AUTO_UPDATE}
			;;
		*)
			[ -z "$answer" ] && set_answer_if_auto Create
			;;
	esac"""

    if old_hd in txt:
        txt = txt.replace(old_hd, new_hd)
        print("  [+] Patched install_hd() for robust unattended partition selection")
    else:
        print("  [!] Warning: install_hd() signature not matched, skipping")

    old_cong = """	[ -n "$VESA" ] || runit="Run $OS_TITLE"
	dialog --clear --title ' Congratulations! ' \\
		--menu "\\n $OS_TITLE is installed successfully.\\n " 11 51 13 \\
		"$runit" "" "Reboot" "" 2> $tempfile"""

    new_cong = """	[ -n "$VESA" ] || runit="Run $OS_TITLE"
	if [ -n "$AUTO_INSTALL" ]; then
		dialog --timeout 6 --clear --title ' Congratulations! ' \\
			--menu "\\n $OS_TITLE was successfully installed to /dev/$choice.\\n\\n Rebooting to Android in 5 seconds...\\n (Touch screen or wait to finish)" 12 62 13 \\
			"Reboot" "" "$runit" "" 2> $tempfile || echo "Reboot" > $tempfile
	else
		dialog --clear --title ' Congratulations! ' \\
			--menu "\\n $OS_TITLE is installed successfully.\\n " 11 51 13 \\
			"$runit" "" "Reboot" "" 2> $tempfile
	fi"""

    if old_cong in txt:
        txt = txt.replace(old_cong, new_cong)
        print("  [+] Patched Congratulations dialog for auto-reboot countdown")
    else:
        print("  [!] Warning: Congratulations dialog signature not matched, skipping")

    # Ensure default reboot on timeout
    txt = txt.replace('\t\tReboot*)\n\t\t\trebooting', '\t\tReboot*|*)\n\t\t\trebooting')

    return txt


def patch_install_img(input_img_path: str, output_img_path: str):
    print(f"Reading input image: {input_img_path}")
    if input_img_path.endswith('.gz') or input_img_path.endswith('.img'):
        try:
            with gzip.open(input_img_path, 'rb') as f:
                raw = f.read()
        except gzip.BadGzipFile:
            with open(input_img_path, 'rb') as f:
                raw = f.read()
    else:
        with open(input_img_path, 'rb') as f:
            raw = f.read()

    pos = 0
    entries = []
    patched_count = 0

    while pos < len(raw):
        if raw[pos:pos+6] != b'070701':
            break
        hdr = bytearray(raw[pos:pos+110])
        namesize = int(hdr[94:102], 16)
        filesize = int(hdr[54:62], 16)
        name_start = pos + 110
        name = raw[name_start:name_start + namesize - 1].decode('latin1')
        name_pad = (4 - ((110 + namesize) % 4)) % 4
        file_start = name_start + namesize + name_pad
        file_pad = (4 - (filesize % 4)) % 4
        content = raw[file_start:file_start + filesize]

        if name == 'scripts/1-install':
            txt = content.decode('latin1')
            patched_txt = patch_1_install_text(txt)
            content = patched_txt.encode('latin1')
            filesize = len(content)
            hdr[54:62] = f'{filesize:08X}'.encode('ascii')
            patched_count += 1

        entries.append({
            'hdr': hdr,
            'name': name,
            'content': content
        })

        if name == 'TRAILER!!!':
            break
        pos = file_start + filesize + file_pad

    print(f"Parsed {len(entries)} CPIO entries (patched {patched_count} files).")

    rebuilt = bytearray()
    for e in entries:
        name_bytes = e['name'].encode('latin1') + b'\x00'
        name_pad = (4 - ((110 + len(name_bytes)) % 4)) % 4
        file_pad = (4 - (len(e['content']) % 4)) % 4
        rebuilt += e['hdr'] + name_bytes + (b'\x00' * name_pad) + e['content'] + (b'\x00' * file_pad)

    pad = (512 - (len(rebuilt) % 512)) % 512
    rebuilt += b'\x00' * pad

    print(f"Compressing new image to: {output_img_path}")
    with gzip.open(output_img_path, 'wb', compresslevel=9) as f:
        f.write(rebuilt)

    print(f"Successfully generated {output_img_path} ({os.path.getsize(output_img_path)} bytes)")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: patch_installer.py <input install.img> <output install.img>")
        sys.exit(1)
    patch_install_img(sys.argv[1], sys.argv[2])
