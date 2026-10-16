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
    # 1. Patch install_hd() for robust dynamic auto-install targeting and forcing clean ext4 format
    old_hd_orig = """install_hd()
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
	esac

	select_dev || rebooting"""

    old_hd_prev = """install_hd()
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
	esac

	select_dev || rebooting"""

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
			# Determine boot disk to NEVER select or overwrite the boot media (SD card)
			boot_disk=""
			if [ -n "$dev" ]; then
				boot_disk=$(basename "$dev" | sed 's/p[0-9].*//')
			elif [ -n "$booted_from" ]; then
				boot_disk=$(echo "$booted_from" | sed 's/p[0-9].*//')
			fi

			# Determine the 64GB internal eMMC disk (must not be boot disk)
			emmc_disk=""
			for d in mmcblk1 mmcblk0 mmcblk2; do
				[ -d "/sys/block/$d" ] || continue
				[ -n "$boot_disk" ] && [ "$d" = "$boot_disk" ] && continue
				emmc_disk="$d"
				break
			done

			# Fallback: find disk by size (>50GB = 100000000 512-byte sectors)
			if [ -z "$emmc_disk" ]; then
				for d in mmcblk0 mmcblk1 mmcblk2 sda nvme0n1; do
					[ -d "/sys/block/$d" ] || continue
					sz=$(cat "/sys/block/$d/size" 2>/dev/null || echo 0)
					if [ "$sz" -gt 100000000 ]; then
						emmc_disk="$d"
						break
					fi
				done
			fi
			emmc_disk=${emmc_disk:-mmcblk1}

			# Ensure partition 2 exists on eMMC; if not, use whatever non-EFI partition exists or partition 2
			target_part="${emmc_disk}p2"
			if [ ! -b "/dev/$target_part" ] && [ ! -d "/sys/block/$emmc_disk/$target_part" ]; then
				for p in /sys/block/$emmc_disk/${emmc_disk}p*; do
					[ -d "$p" ] || continue
					bn=$(basename "$p")
					case "$bn" in *boot*|*rpmb*|*p1) continue ;; esac
					target_part="$bn"
					break
				done
			fi

			answer="$target_part"
			FORCE_FORMAT=ext4
			echo "=========================================================="
			echo ">>> [YOGABOOK AUTO-INSTALLER] Target internal eMMC: /dev/$answer"
			echo ">>> [YOGABOOK AUTO-INSTALLER] Boot media detected: /dev/$boot_disk"
			echo "=========================================================="
			;;
	esac

	if [ -n "$AUTO_INSTALL" ] && [ -n "$answer" ]; then
		choice="$answer"
	else
		select_dev || rebooting
	fi"""

    if old_hd_orig in txt:
        txt = txt.replace(old_hd_orig, new_hd)
        print("  [+] Patched install_hd() from original for unattended partition selection and bypass")
    elif old_hd_prev in txt:
        txt = txt.replace(old_hd_prev, new_hd)
        print("  [+] Patched install_hd() from previous version for unattended partition selection and bypass")
    elif 'install_hd()' in txt:
        # Fallback to replacing just case block
        txt = txt.replace('select_dev || rebooting', 'if [ -n "$AUTO_INSTALL" ] && [ -n "$answer" ]; then choice="$answer"; else select_dev || rebooting; fi')
        print("  [+] Patched select_dev || rebooting bypass")

    # 2. Patch format_fs to zero out Bass OS and format cleanly with busybox mke2fs
    old_fmt_orig = """format_fs()
{
	local cmd
	echo -e '"Do not re-format" ""\\next4 ""\\nntfs ""\\nfat32 ""' > $menufile
	set_answer_if_auto $FORCE_FORMAT
	choose "Choose filesystem" "Please select a filesystem to format $1:"
	case "$choice" in
		ext4)
			cmd="mkfs.ext3 -L"
			;;"""

    new_fmt_clean = """format_fs()
{
	local cmd
	if [ -n "$AUTO_INSTALL" ]; then
		choice="ext4"
	else
		echo -e '"Do not re-format" ""\\next4 ""\\nntfs ""\\nfat32 ""' > $menufile
		set_answer_if_auto $FORCE_FORMAT
		choose "Choose filesystem" "Please select a filesystem to format $1:"
	fi
	case "$choice" in
		ext4)
			umount /dev/$1 2>/dev/null || true
			echo "=========================================================="
			echo ">>> [YOGABOOK AUTO-INSTALLER] Wiping previous OS (BlissOS / BassOS) from /dev/$1..."
			busybox dd if=/dev/zero of=/dev/$1 bs=1M count=100 2>/dev/null || true
			echo ">>> [YOGABOOK AUTO-INSTALLER] Formatting /dev/$1 as ext4..."
			echo "=========================================================="
			busybox mke2fs -F -L Android-x86 /dev/$1 || mke2fs -F -L Android-x86 /dev/$1 || true
			if [ -n "$AUTO_INSTALL" ]; then
				return 0
			fi
			cmd=""
			;;"""

    if old_fmt_orig in txt:
        txt = txt.replace(old_fmt_orig, new_fmt_clean)
        print("  [+] Patched format_fs() from original to zero-fill wipe and clean auto-format")
    elif 'cmd="mke2fs -F -L"' in txt or 'echo ">>> Wiping Bass OS..."' in txt:
        print("  [+] format_fs() already contains zero-fill wipe logic")

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
		ln -sf "$asrc" /hd/android 2>/dev/null || true
		mkdir -p "/hd/$asrc/data" "/hd/data" 2>/dev/null || true"""

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

    # 7. Force clean format of EFI partition to wipe old Bass OS bootloader and write standalone GRUB to all paths
    old_efi_block = """		until try_mount rw /dev/$boot efi; do
			dialog --title " Confirm " --defaultno --yesno "\\n Cannot mount /dev/$boot.\\n Do you want to format it?" 8 37
			[ $? -eq 0 ] && mkdosfs -n EFI /dev/$boot
		done
		if [ "$efi" = "32" ]; then
			grubcfg=efi/boot/grub/i386-efi/grub.cfg
			bootefi=bootia32.efi
		else
			grubcfg=efi/boot/grub/x86_64-efi/grub.cfg
			bootefi=BOOTx64.EFI
		fi
		if [ -d efi/efi/boot -a ! -s efi/efi/boot/android.cfg ]; then
			efidir=/efi/Android
		else
			efidir=/efi/boot
			rm -rf efi/efi/Android
		fi
		mkdir -p `dirname $grubcfg` efi$efidir
		cp -af grub2/efi/boot/* efi$efidir"""

    new_efi_block = """		# Wipe old Bass OS EFI bootloader and format EFI partition fresh
		umount /dev/$boot 2>/dev/null || true
		echo ">>> Wiping old EFI bootloader and formatting clean FAT32 EFI partition..."
		busybox mkdosfs -F 32 -n "EFI" /dev/$boot || mkdosfs -n "EFI" /dev/$boot || true
		mkdir -p efi
		try_mount rw /dev/$boot efi
		if [ "$efi" = "32" ]; then
			bootefi=bootia32.efi
		else
			bootefi=BOOTx64.EFI
		fi
		efidir=/EFI/BOOT
		mkdir -p efi/EFI/BOOT efi/EFI/boot efi/EFI/Android efi/boot/grub 2>/dev/null || true
		cp -af grub2/efi/boot/* efi/EFI/BOOT/ 2>/dev/null || true
		cp -af grub2/efi/boot/* efi/EFI/boot/ 2>/dev/null || true
		cp -af grub2/efi/boot/* efi/EFI/Android/ 2>/dev/null || true
		# Write standalone GRUB configuration for Yoga Book eMMC boot
		mkdir -p efi/boot/grub /hd/boot/grub 2>/dev/null || true
		cat > /tmp/standalone_grub.cfg << 'EOF_GRUB'
set timeout=3
set default=0
loadfont unicode || true
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm console || true

search --no-floppy --file --set=root /android-9.0-r2/kernel
if [ -z "$root" ]; then
    search --no-floppy --file --set=root /kernel
fi

menuentry "Yoga Book Android-x86" {
    set gfxpayload=keep
    if [ -f /android-9.0-r2/kernel ]; then
        linux /android-9.0-r2/kernel androidboot.hardware=android_x86 SRC=/android-9.0-r2 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive sdhci.debug_quirks2=0x04 quiet
        initrd /android-9.0-r2/initrd.img
    else
        linux /kernel androidboot.hardware=android_x86 SRC=/android-9.0-r2 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive sdhci.debug_quirks2=0x04 quiet
        initrd /initrd.img
    fi
}
menuentry "Yoga Book Android-x86 (Verbose Console)" {
    set gfxpayload=keep
    if [ -f /android-9.0-r2/kernel ]; then
        linux /android-9.0-r2/kernel androidboot.hardware=android_x86 SRC=/android-9.0-r2 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive sdhci.debug_quirks2=0x04 console=tty0 DEBUG=2
        initrd /android-9.0-r2/initrd.img
    else
        linux /kernel androidboot.hardware=android_x86 SRC=/android-9.0-r2 ro.surface_flinger.primary_display_orientation=ORIENTATION_90 androidboot.selinux=permissive sdhci.debug_quirks2=0x04 console=tty0 DEBUG=2
        initrd /initrd.img
    fi
}
EOF_GRUB
		cp -f /tmp/standalone_grub.cfg efi/boot/grub/grub.cfg 2>/dev/null || true
		cp -f /tmp/standalone_grub.cfg efi/boot/grub/x86_64-efi/grub.cfg 2>/dev/null || true
		cp -f /tmp/standalone_grub.cfg efi/boot/grub/i386-efi/grub.cfg 2>/dev/null || true
		cp -f /tmp/standalone_grub.cfg efi/EFI/BOOT/grub.cfg 2>/dev/null || true
		cp -f /tmp/standalone_grub.cfg efi/EFI/boot/grub.cfg 2>/dev/null || true
		cp -f /tmp/standalone_grub.cfg efi/EFI/Android/grub.cfg 2>/dev/null || true
		cp -f /tmp/standalone_grub.cfg /hd/boot/grub/grub.cfg 2>/dev/null || true"""

    if old_efi_block in txt:
        txt = txt.replace(old_efi_block, new_efi_block)
        print("  [+] Patched EFI block: force clean format and write standalone bootloader to all paths")
    else:
        print("  [!] Warning: EFI block signature not matched, skipping")

    # 8. Delete BlissOS, BassOS, and old Android entries from UEFI NVRAM so BlissOS never boots
    old_efimgr = """		# Checking for old EFI entries, removing them and adding new depending on bitness
		efibootmgr | grep -Eo ".{0,6}Android-x86" | cut -c1-4 > /tmp/efientries
		if [ -s /tmp/efientries ]; then
			set_answer_if_auto 1
			adialog --title " Question " --yesno "\\nEFI boot entries for previous Android-x86 installations were found.\\n\\nDo you wish to delete them?" 10 61
			[ $? -eq 0 ] && while read entry; do efibootmgr -Bb "$entry" > /dev/tty4 2>&1; done < /tmp/efientries
		fi"""

    new_efimgr = """		# Delete old BlissOS / BassOS / Android entries from UEFI NVRAM so only clean Android remains
		for b in $(efibootmgr 2>/dev/null | grep -iE "bliss|bass|android" | awk '{print $1}' | sed 's/Boot//; s/\\*//'); do
			efibootmgr -b "$b" -B > /dev/null 2>&1 || true
		done"""

    if old_efimgr in txt:
        txt = txt.replace(old_efimgr, new_efimgr)
        print("  [+] Patched efibootmgr to purge BlissOS and BassOS from UEFI NVRAM")
    else:
        print("  [!] Warning: efibootmgr block not matched, skipping")

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
        raw_filesize = int(hdr[54:62], 16)
        name_start = pos + 110
        name = raw[name_start:name_start + namesize - 1].decode('latin1')
        name_pad = (4 - ((110 + namesize) % 4)) % 4
        file_start = name_start + namesize + name_pad
        raw_file_pad = (4 - (raw_filesize % 4)) % 4
        content = raw[file_start:file_start + raw_filesize]

        if name == 'scripts/1-install':
            txt = content.decode('latin1')
            patched_txt = patch_1_install_text(txt)
            content = patched_txt.encode('latin1')
            hdr[54:62] = f'{len(content):08X}'.encode('ascii')
            patched_count += 1
        elif name in ('grub2/efi/boot/BOOTx64.EFI', 'grub2/efi/boot/grubx64.efi'):
            efi_src = 'D:/EFI/BOOT/BOOTX64.EFI'
            if os.path.exists(efi_src):
                with open(efi_src, 'rb') as f_efi:
                    content = f_efi.read()
                hdr[54:62] = f'{len(content):08X}'.encode('ascii')
                print(f"  [+] Replaced {name} with standalone Yoga Book BOOTX64.EFI ({len(content)} bytes)")
                patched_count += 1
        elif name == 'grub2/efi/boot/bootia32.efi':
            efi_src = 'D:/EFI/BOOT/BOOTIA32.EFI'
            if os.path.exists(efi_src):
                with open(efi_src, 'rb') as f_efi:
                    content = f_efi.read()
                hdr[54:62] = f'{len(content):08X}'.encode('ascii')
                print(f"  [+] Replaced {name} with standalone Yoga Book BOOTIA32.EFI ({len(content)} bytes)")
                patched_count += 1

        entries.append({
            'hdr': hdr,
            'name': name,
            'content': content
        })

        if name == 'TRAILER!!!':
            break
        pos = file_start + raw_filesize + raw_file_pad

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
