#!/usr/bin/env python3
"""
patch_bass_initrd.py
Patches initrd.img in iso_build/ so that when INSTALL=install.sfs is selected:
1. /etc/hosts is initialized with '127.0.0.1 localhost blisslabs' so xauth does not fail.
2. /bin/run-parts wrapper is installed so BusyBox run-parts accepts --lsbsysinit and --list,
   allowing /etc/rc2.d/ (dbus, elogind, udev) to start.
3. /usr/sbin/oem-install dummy script is created.
4. /usr/lib/xorg/Xorg is given setuid root permissions for direct KMS DRM master access.
5. /etc/X11/xorg.conf.d/20-modesetting.conf is created for Intel Cherry Trail modesetting.
6. /root/.bash_profile ensures dbus & elogind are active and launches JWM + Calamares cleanly.
"""

import os
import sys
import gzip

INITRD_PATH = r"c:\Yogabook\iso_build\initrd.img"

def patch_initrd():
    if not os.path.exists(INITRD_PATH):
        print(f"ERROR: {INITRD_PATH} not found!")
        sys.exit(1)

    print(f"Reading {INITRD_PATH}...")
    with gzip.open(INITRD_PATH, "rb") as f:
        cpio_data = f.read()

    pos = 0
    entries = []
    patched = False

    while pos < len(cpio_data) - 110:
        magic = cpio_data[pos:pos+6]
        if magic != b'070701':
            break

        header = cpio_data[pos:pos+110]
        namesize = int(header[94:102], 16)
        filesize = int(header[54:62], 16)

        name_start = pos + 110
        name = cpio_data[name_start:name_start + namesize - 1].decode('latin1')

        header_end = pos + 110 + namesize
        header_pad = (4 - (header_end % 4)) % 4
        file_start = header_end + header_pad
        file_end = file_start + filesize
        file_pad = (4 - (file_end % 4)) % 4

        content = cpio_data[file_start:file_end]

        if name == './scripts/1-install':
            print("Found ./scripts/1-install! Applying Yoga Book installer fixes...")
            txt = content.decode('latin1')

            target_hook = "ln -s /install/android/system /\n}"
            replacement_hook = """ln -s /install/android/system /

	# --- Yoga Book Calamares & X11 fixes ---
	echo "127.0.0.1 localhost blisslabs" > /install/etc/hosts
	echo "::1 localhost ip6-localhost ip6-loopback" >> /install/etc/hosts

	# Fix BusyBox run-parts rejection of --lsbsysinit and --list
	cat << 'EOFRP' > /install/bin/run-parts
#!/bin/sh
args=""
for a in "$@"; do
    case "$a" in
        --lsbsysinit|--list) ;;
        *) args="$args $a" ;;
    esac
done
exec /bin/busybox run-parts $args
EOFRP
	chmod 755 /install/bin/run-parts
	cp -f /install/bin/run-parts /install/usr/bin/run-parts 2>/dev/null || true

	# Dummy oem-install
	echo '#!/bin/sh' > /install/usr/sbin/oem-install
	echo 'exit 0' >> /install/usr/sbin/oem-install
	chmod 755 /install/usr/sbin/oem-install

	# Setuid Xorg for KMS DRM master permissions
	chmod 4755 /install/usr/lib/xorg/Xorg 2>/dev/null || true
	chmod 4755 /install/usr/bin/Xorg 2>/dev/null || true

	# Modesetting xorg config
	mkdir -p /install/etc/X11/xorg.conf.d
	cat << 'EOFXORG' > /install/etc/X11/xorg.conf.d/20-modesetting.conf
Section "Device"
    Identifier "Intel Modesetting"
    Driver "modesetting"
    Option "AccelMethod" "glamor"
EndSection
EOFXORG

	# Fix /root/.bash_profile
	cat << 'EOFBASH' > /install/root/.bash_profile
#!/bin/bash
echo "127.0.0.1 localhost blisslabs" > /etc/hosts
udevadm trigger 2>/dev/null || true

# Start dbus & elogind
/etc/init.d/dbus status >/dev/null 2>&1 || /etc/init.d/dbus start 2>/dev/null || true
/etc/init.d/elogind status >/dev/null 2>&1 || /etc/init.d/elogind start 2>/dev/null || true

export QT_QPA_PLATFORMTHEME=gtk3
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p /run/user/0
chmod 700 /run/user/0

if [ -z "$DISPLAY" ] && ! pidof Xorg >/dev/null 2>&1 && ! pidof X >/dev/null 2>&1; then
    echo "Starting Yoga Book Graphical Installer..."
    startx /usr/bin/jwm -- :0 vt1 -keeptty
fi

clear
cat /etc/bliss/message.txt 2>/dev/null || true
EOFBASH
	chmod 755 /install/root/.bash_profile
}"""
            if target_hook in txt:
                txt = txt.replace(target_hook, replacement_hook, 1)
                content = txt.encode('latin1')
                patched = True
                print("  [+] Successfully injected post-setup hooks into ./scripts/1-install")
            else:
                print("  [-] Could not locate target_hook in ./scripts/1-install!")

        entries.append((header, name, content))
        pos = file_end + file_pad

    trailer = cpio_data[pos:]

    if not patched:
        print("ERROR: Failed to patch 1-install script in initrd.img")
        sys.exit(1)

    out = bytearray()
    for header, name, content in entries:
        h = bytearray(header)
        h[54:62] = f"{len(content):08X}".encode('ascii')
        out.extend(h)
        out.extend(name.encode('latin1') + b'\x00')
        pad1 = (4 - ((110 + len(name) + 1) % 4)) % 4
        out.extend(b'\x00' * pad1)
        out.extend(content)
        pad2 = (4 - (len(content) % 4)) % 4
        out.extend(b'\x00' * pad2)

    out.extend(trailer)

    print(f"Compressing new initrd.img ({len(out):,} uncompressed bytes)...")
    with gzip.open(INITRD_PATH, "wb", compresslevel=9) as f:
        f.write(out)

    print(f"SUCCESS: Written {INITRD_PATH} ({os.path.getsize(INITRD_PATH):,} bytes)")

if __name__ == "__main__":
    patch_initrd()
