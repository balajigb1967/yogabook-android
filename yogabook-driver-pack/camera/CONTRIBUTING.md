# Contributing

The front OV2740 is the primary camera because it is the sensor usable for
video meetings. A transport success or a recognizable picture is not physical
acceptance: changes must be evaluated for exposure, white balance, color,
noise, motion and restart stability.

Keep subsystem ownership explicit:

- submit kernel sensor and AtomISP changes to `Yoga-Book-Linux-Kernel`;
- implement camera userspace and packaging here;
- add end-user acceptance checks to `Yoga-Book-Validator`.

Do not commit `.cpf`, `.aiqb`, extracted Windows binaries, captured images or
recorded video. Do not enable AtomISP private ioctls broadly. A prior unscoped
white-balance ioctl experiment caused an ISP division by zero and unkillable
camera tasks, requiring a cold power cycle.

Every change should pass:

```bash
make test
git diff --check
```

Runtime changes must preserve a known-good kernel boot entry and document the
exact sensor, format, frame size and application used for physical testing.
