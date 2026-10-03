# Contributing

Keep changes within the keyboard-half input boundary. Kernel, audio, sensor,
and general desktop-policy changes belong in their owning projects.

Before submitting a change:

```bash
make test
dpkg-buildpackage --build=binary --no-sign
```

For changes to event handling or device lifetime, also run the sanitizer and
warnings-as-errors build documented in `docs/VALIDATION.md`, plus ShellCheck on
the project and Debian scripts.

Hardware quirks must use the narrowest identity supported by their database.
Keep hwdb rules DMI-scoped where possible, and keep libwacom definitions scoped
to physically verified bus, vendor, and product identifiers. The YB1-X91L pen
must retain a neutral libinput matrix so Mutter can apply the current display
transform without rotating coordinates twice. Always test landscape, both
portrait directions, display touch, and the accessibility keyboard when
changing pen or touch integration. Do not broaden the Wacom definition without
physical evidence from the additional hardware.

Retain copyright and license notices in code derived from the reference
projects. New contributions are accepted under BSD-3-Clause.
