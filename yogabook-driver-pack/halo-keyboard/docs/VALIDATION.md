# Validation

## Development host

Run:

```bash
make test
dpkg-buildpackage --build=binary --no-sign
make source
package_version=$(dpkg-parsechangelog -S Version)
package_arch=$(dpkg --print-architecture)
lintian --profile debian "../halo-keyboard_${package_version}_${package_arch}.changes"
```

Run the strict sanitizer build:

```bash
cmake -S . -B build-sanitize -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_TESTING=ON \
  -DHALO_KEYBOARD_ENABLE_SANITIZERS=ON \
  -DHALO_KEYBOARD_WARNINGS_AS_ERRORS=ON
cmake --build build-sanitize --parallel
ctest --test-dir build-sanitize --output-on-failure
shellcheck tests/*.sh debian/halo-keyboard.postinst \
  debian/halo-keyboard.postrm debian/tests/smoke
git diff --check
```

Inspect the package:

```bash
package_version=$(dpkg-parsechangelog -S Version)
package_arch=$(dpkg --print-architecture)
dpkg-deb --info "../halo-keyboard_${package_version}_${package_arch}.deb"
dpkg-deb --contents "../halo-keyboard_${package_version}_${package_arch}.deb"
```

The package must contain the handler, service, configuration, udev rule, hwdb
file, libwacom tablet definition, manual page, attribution, and license. It
must provide/conflict/replace `touch-keyboard` and must not ship the temporary
local pen-rotation rule used during diagnosis.

## Yoga Book YB1-X91L

After installation and reboot, validate:

1. `halo-keyboard.service` is active in keyboard mode.
2. Keyboard keys and the virtual touchpad work.
3. Both haptic actuators respond, including the first key press after at least
   10 seconds without touching the Halo surface.
4. Pen motion in Xournal++ maps up/down/left/right correctly in landscape.
5. The display touchscreen and accessibility keyboard still accept touch.
6. In both portrait directions, pen motion follows the rotated display axes.
7. Switching between keyboard and pen mode does not rotate the display.
8. A suspend/resume and cold boot introduce no new input or udev errors.

The dynamic Wacom mapping was physically established on a Lenovo YB1-X91L with
the Halo pen surface on the left and the display on the right. The opposite
portrait direction remains a required physical acceptance check.
