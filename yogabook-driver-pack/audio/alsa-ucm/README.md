# Yoga Book ALSA UCM Config

Yoga Book ALSA UCM Config supplies the ALSA Use Case Manager (UCM2)
configuration required for working audio on the Lenovo Yoga Book YB1-X91L.
Without it, the sound card exposes no use cases and the desktop audio stack
cannot route playback and capture correctly.

The project is a fork of Yauhen Kharuzhy's
[alsa-ucm-conf-yogabook](https://github.com/jekhor/alsa-ucm-conf-yogabook),
extended with Sound Open Firmware (SOF) compatibility. The Debian package is
named `alsa-ucm-conf-yogabook`.

## Scope

This package contains only:

- the `cht-yogabook` UCM2 board configuration (Syntax 3) with the `HiFi` use
  case and the `Speaker`, `HeadsetPhones`, `DMIC1`, and `HeadsetMic` devices;
- `conf.d` aliases that match the configuration to the card:
  - `cht-yogabook` — the original Yoga Book card name;
  - `chtyogabook` — the corresponding sanitized card-name alias;
  - `cht-rt5677` — the card name used by the legacy SST path;
  - `SOF/LENOVO-LenovoYB1_X91L-X91L` — the SOF long-name alias for the
    YB1-X91L;
- Debian packaging that installs the tree under `/usr/share/alsa`.

It deliberately contains no kernel drivers, firmware binaries, or PipeWire
policy.

## SST and SOF support

The Yoga Book audio path can run under both the legacy Intel SST driver and
the SOF driver. The legacy SST topology exposes the Bay Trail media-mixer
control graph; SOF topologies do not. `HiFi.conf` therefore applies the
platform enable and disable sequences only when an SST-specific control
(`media0_in Gain 0 Switch`) exists, so the same configuration loads under
both drivers.

The SOF path additionally requires the matching SOF firmware and topology
files to be present on the system; see the
[Yoga-Book-Sound-Open-Firmware](https://github.com/Yoga-Book/Yoga-Book-Sound-Open-Firmware)
repository.

## Build and install

Build the Debian package:

```bash
dpkg-buildpackage -us -uc
sudo apt install ../alsa-ucm-conf-yogabook_1.7_all.deb
```

The package depends on `alsa-ucm-conf` and installs the UCM2 tree under
`/usr/share/alsa`. The audio stack picks the configuration up the next time
the card is opened; restarting the user audio session applies it immediately.

## License

BSD-3-Clause, see [`debian/copyright`](debian/copyright). Based on the work
of Yauhen Kharuzhy and the ALSA project's UCM configurations.
