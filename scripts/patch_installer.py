#!/usr/bin/env python3
"""
patch_installer.py - Patches Android-x86 install.img to enable 100% unattended
installation on devices without physical keyboards (such as the Lenovo Yoga Book).

Supports:
- AUTO_INSTALL=auto: Automatically targets internal eMMC partition (mmcblk0p2)
- Erases previous OS (Bass OS) cleanly by formatting mmcblk0p2 with ext4
- Directly copies kernel, initrd.img, ramdisk.img, and system.sfs into /hd/$asrc/
- Creates compatibility symlinks so GRUB search finds /kernel and /$asrc/kernel
- Automatic 5-second countdown reboot on completion
"""

import sys
import os
import gzip

def patch_1_install_text(txt: str) -> str:
    # 1. Patch install_hd() for robust auto-install targeting and forcing clean ext4 format
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
		[Uu]pdate)
			answer=${AUTO_UPDATE:-$(blkid | grep -v loop | grep -v iso9660 | sort | grep Android-x86 | cut -d: -f1 | head -1)}
			answer=${answer:-$(blkid | grep -v loop | grep -v iso9660 | sort | grep ext4 | cut -d: -f1 | head -1)}
			[ -b "$answer" -o -b "/dev/$answer" ] && answer=$(basename "$answer") || answer=
			AUTO_UPDATE=${answer:-$AUTO_UPDATE}
			FORCE_FORMAT=no
			;;
		*)
			# Default unattended install: Cleanly ERASE and install to internal eMMC partition 2
			target="${AUTO_INSTALL#force_format:}"
			[ "$target" = "auto" -o "$target" = "1" -o -z "$target" ] && target=""
			if [ -n "$target" ] && [ -b "/dev/$(basename $target)" ]; then
				answer=$(basename "$target")
			elif [ -b /dev/mmcblk0p2 ]; then
				answer="mmcblk0p2"
			else
				answer=$(blkid | grep -v loop | grep -v iso9660 | sort | grep ext4 | cut -d: -f1 | head -1)
				[ -z "$answer" ] && answer=$(ls /sys/block/mmcblk0/mmcblk0p* /sys/block/sda/sda* 2>/dev/null | grep -v -E "p1$|1$" | head -1)
				[ -n "$answer" ] && answer=$(basename "$answer")
			fi
			FORCE_FORMAT=ext4
			;;
	esac"""

    if old_hd in txt:
        txt = txt.replace(old_hd, new_hd)
        print("  [+] Patched install_hd() for unattended partition selection and ext4 clean format")
    else:
        print("  [!] Warning: install_hd() signature not matched, skipping")

    # 2. Patch format_fs to use mke2fs -F -L (force format to wipe Bass OS without prompt)
    old_fmt = """	case "$choice" in
		ext4)
			cmd="mkfs.ext3 -L"
			;;"""

    new_fmt = """	case "$choice" in
		ext4)
			umount /dev/$1 2>/dev/null || true
			cmd="mke2fs -F -L"
			;;"""

    if old_fmt in txt:
        txt = txt.replace(old_fmt, new_fmt)
        print("  [+] Patched format_fs() to use mke2fs -F -L for forced partition wipe")
    else:
        print("  [!] Warning: format_fs() signature not matched, skipping")

    # 3. Patch install_to() to prevent AUTO_UPDATE from disabling ext4 format on auto-install
    old_force = '[ -n "$AUTO_UPDATE" ] && FORCE_FORMAT=no || FORCE_FORMAT=ext4'
    new_force = 'if [ "$AUTO_INSTALL" = "update" ]; then FORCE_FORMAT=no; else FORCE_FORMAT=ext4; fi'
    if old_force in txt:
        txt = txt.replace(old_force, new_force)
        print("  [+] Patched FORCE_FORMAT check in install_to()")
    else:
        print("  [!] Warning: FORCE_FORMAT signature not matched, skipping")

    # 4. Patch file copy in install_to() to guarantee direct copying to /hd/$asrc/
    old_copy = """	try_upgrade hd/$asrc
	mkdir -p hd/$asrc
	cd hd/$asrc
	rm -rf system*
	( ( cd /; find $files | $CPIO -H newc -o ) | pv -ns ${size}k | ( $CPIO -iud > /dev/null; echo $? > /tmp/result )) 2>&1 \\
		| progress_bar "Installing $OS_TITLE to $1" "Expect to write $size KB..."
	result=$((`cat /tmp/result`*255))"""

    new_copy = """	try_upgrade hd/$asrc
	mkdir -p hd/$asrc
	cd hd/$asrc
	rm -rf system*

	# Direct copy from source media to guarantee kernel and system files land directly in hd/$asrc
	src_media=""
	for sm in /src "/mnt/$SRC" "/mnt/${SRC#/}" /mnt/ANDRID /mnt/andrid /mnt; do
		if [ -f "$sm/kernel" ] && [ -f "$sm/initrd.img" ]; then
			src_media="$sm"
			break
		fi
	done

	if [ -n "$src_media" ]; then
		echo "Copying Yoga Book Android files directly from $src_media to /hd/$asrc..."
		cp -vf "$src_media/kernel" "/hd/$asrc/kernel"
		cp -vf "$src_media/initrd.img" "/hd/$asrc/initrd.img"
		[ -f "$src_media/$RAMDISK" ] && cp -vf "$src_media/$RAMDISK" "/hd/$asrc/$RAMDISK"
		[ -f "$src_media/ramdisk.img" ] && cp -vf "$src_media/ramdisk.img" "/hd/$asrc/ramdisk.img"
		if [ -f "$src_media/system.sfs" ]; then
			cp -vf "$src_media/system.sfs" "/hd/$asrc/system.sfs"
		elif [ -f "$src_media/system.img" ]; then
			cp -vf "$src_media/system.img" "/hd/$asrc/system.img"
		fi
		echo 0 > /tmp/result
	else
		( ( cd /; find $files | $CPIO -H newc -o ) | pv -ns ${size}k | ( $CPIO -iud > /dev/null; echo $? > /tmp/result )) 2>&1 \\
			| progress_bar "Installing $OS_TITLE to $1" "Expect to write $size KB..."
	fi
	result=$((`cat /tmp/result`*255))"""

    if old_copy in txt:
        txt = txt.replace(old_copy, new_copy)
        print("  [+] Patched file copying to use direct robust copy to /hd/$asrc")
    else:
        print("  [!] Warning: file copy signature not matched, skipping")

    # 5. Flatten any subdirectories and create root symlinks for GRUB compatibility
    old_flatten = """		for d in android mnt sfs ./$SRC; do
			[ -d $d ] && mv $d/* . && rmdir $d
		done"""

    new_flatten = """		for d in android mnt sfs ./$SRC ANDRID andrid; do
			[ -d "$d" ] && mv "$d"/* . 2>/dev/null && rmdir "$d" 2>/dev/null
		done
		for sub in /hd/$asrc/ANDRID /hd/$asrc/andrid /hd/$asrc/mnt/* /hd/$asrc/mnt; do
			if [ -d "$sub" ]; then
				mv -f "$sub"/* /hd/$asrc/ 2>/dev/null || true
				rm -rf "$sub" 2>/dev/null || true
			fi
		done
		# Root compatibility links so GRUB finds /kernel or /$asrc/kernel
		ln -sf "$asrc/kernel" /hd/kernel 2>/dev/null || true
		ln -sf "$asrc/initrd.img" /hd/initrd.img 2>/dev/null || true
		ln -sf "$asrc/ramdisk.img" /hd/ramdisk.img 2>/dev/null || true
		ln -sf "$asrc/system.sfs" /hd/system.sfs 2>/dev/null || true
		ln -sf "$asrc" /hd/android 2>/dev/null || true"""

    if old_flatten in txt:
        txt = txt.replace(old_flatten, new_flatten)
        print("  [+] Patched folder flattening and root compatibility symlinks")
    else:
        print("  [!] Warning: folder flattening signature not matched, skipping")

    # 6. Patch Congratulations dialog for auto-reboot countdown
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

    txt = txt.replace('\t\tReboot*)\n\t\t\trebooting', '\t\tReboot*|*)\n\t\t\trebooting')

    return txt


def patch_install_img(input_img_path: str, output_img_path: str):
    print(f"Reading input image: {input_img_path}")
    try:
        with gzip.open(input_img_path, 'rb') as f:
            raw = f.read()
    except Exception:
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
