# Building the ROM

## Why not free GitHub-hosted runners?

A LineageOS source build needs **~120 GB** of disk and **16 GB** RAM.
GitHub-hosted runners provide ~15–30 GB of free disk — the build cannot run
there. The two supported ways:

1. **Your own machine (recommended, free)** — Ubuntu 22.04/24.04 or WSL2,
   ≥140 GB free disk, ≥16 GB RAM, decent broadband (~60 GB download).
2. **Self-hosted GitHub runner** — same requirements, register the machine to
   your repo and run the `build-iso` workflow.

## One-command local build

```bash
./scripts/build-local.sh
```

The script:

1. checks disk/RAM,
2. `repo init/sync` LineageOS 23.2 (shallow, x86-focused) with the Yoga Book
   local manifest (`manifest/local_manifests/yogabook.xml`),
3. overlays this repository onto `device/yogabook`,
4. applies the Yoga Book kernel patches (RT5677 machine driver, AtomISP
   sensors, platform quirks) to the Debian mainline kernel source,
5. builds `lineage_YOGABOOK_x86_64` + the custom `yogabook-liveiso` target,
6. builds the extra kernel versions (multi-kernel menu) and injects them into
   the ISO,
7. drops `dist/YOGABOOK-x86_64-<version>-live.iso` (+ `.sha256`).

Useful flags: `--skip-sync` (reuse an existing tree), `--clean`, `--jobs N`,
`--only-kernel-<n>`.

## CI

`.github/workflows/build-iso.yml` runs the same script on a self-hosted runner
(labels `[self-hosted, linux, x64]`) and uploads `dist/*.iso` to a draft
release. Register a runner:

Repo → Settings → Actions → Runners → New self-hosted runner (Linux x64),
then on your build box:

```bash
./config.sh --url https://github.com/balajigb1967/yogabook-android --token <TOKEN> --labels yogabook-build
sudo ./svc.sh install && sudo ./svc.sh start
```
