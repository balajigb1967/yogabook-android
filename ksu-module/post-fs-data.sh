#!/system/bin/sh
# Runs during post-fs-data (before Zygote starts)

# Ensure proper permissions on uinput for virtual keyboard injection
chmod 0660 /dev/uinput 2>/dev/null || true
chown root:input /dev/uinput 2>/dev/null || true
