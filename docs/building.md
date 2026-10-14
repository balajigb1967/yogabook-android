# Building the Yoga Book Android ROM

## 100% Automated on GitHub Actions (No Local PC Required)

The build is configured to execute completely on **standard free GitHub-hosted runners** (`ubuntu-24.04`), requiring zero local disk space, memory, or complex toolchain setups on your own machine.

### Triggering the Build

1. Push your changes to `main` or go to the **Actions** tab in your GitHub repository:
   [balajigb1967/yogabook-android](https://github.com/balajigb1967/yogabook-android)
2. Select **build-iso** in the left workflow menu.
3. Click **Run workflow**.
4. (Optional) You can provide a custom Android x86 base ISO URL if desired, or leave it blank to use the default stable base.

### What the GitHub Workflow Does

The workflow (`.github/workflows/build-iso.yml` invoking `scripts/build-github.sh`):

1. **Cleans runner disk space**: Frees up ~35 GB of space on the Ubuntu runner.
2. **Builds the Yoga Book Linux Kernel**:
   - Clones [Yoga-Book-Linux-Kernel](https://github.com/Yoga-Book/Yoga-Book-Linux-Kernel) branch `submission/yogabook-x91l-v2` (Maurizio Casciano's submitted patches).
   - Enables `CONFIG_SND_SOC_INTEL_CHT_RT5677_MACH`, TS3A227E headset detection, Goodix touch surface, DRV2604 haptics, and AtomISP camera.
   - Compiles the kernel (`bzImage`) and stripped kernel modules.
3. **Builds the Halo Keyboard Daemon**:
   - Compiles `touch_keyboard_handler` using the source code in `device/yogabook/halo-keyboard/src`.
   - Packages layout definitions (`layout.csv`, `touch-hw.csv`).
4. **Installs Sound Open Firmware (SOF)**:
   - Fetches SOF v2.15.1 firmware binaries and the tested `sof-cht-rt5677.tplg` topology.
5. **Applies Display Orientation Quirk**:
   - Configures `ro.surface_flinger.primary_display_orientation=ORIENTATION_90` for the Yoga Book's native portrait panel.
6. **Assembles the Bootable Hybrid ISO**:
   - Integrates the rEFInd touch-friendly UEFI bootloader and legacy GRUB fallback.
   - Generates `dist/YOGABOOK-x86_64-<date>-live.iso` and SHA256 checksums.
7. **Publishes Artifacts & Releases**:
   - Uploads the ISO to GitHub Actions run artifacts.
   - Automatically drafts a GitHub Release containing download links.
