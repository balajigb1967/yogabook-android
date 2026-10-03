#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
temporary_root=${TMPDIR:-/tmp}
temporary_directory=$(mktemp -d "$temporary_root/yogabook-camera-test.XXXXXX")

cleanup() {
	rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

required_files=(
	ATTRIBUTION.md
	CONTRIBUTING.md
	LICENSE
	Makefile
	README.md
	config/cameras.json
	debian/changelog
	debian/control
	debian/docs
	debian/install
	debian/postinst
	debian/preinst
	debian/prerm
	debian/rules
	docs/ACCEPTANCE.md
	docs/ARCHITECTURE.md
	docs/CALIBRATION.md
	docs/KERNEL-CONTRACT.md
	docs/STATUS.md
	docs/WINDOWS-DRIVER-EVIDENCE.md
	metadata/OV2740_CJAE533_CHT.cpf.sha256
	metadata/lenovo-driver-manifest.sha256
	modprobe.d/yogabook-camera.conf
	modules-load.d/yogabook-camera.conf
	src/yogabook_camera.py
	src/yogabook_camera_capture.py
	src/yogabook_camera_control.py
	systemd/yogabook-camera-prepare.service
	systemd/yogabook-camera-sleep.service
	systemd/yogabook-camera.service
	tools/camera-sleep.sh
	tests/check-camera-config.py
	tests/check-package.sh
	tests/test-camera-python.py
	tools/inspect-aiqb.sh
	tools/prepare-camera.sh
	tools/stage-lenovo-tuning.sh
	udev/72-yogabook-camera-private.rules
)

for required_file in "${required_files[@]}"; do
	test -f "$root/$required_file"
done

for executable_file in \
	debian/postinst \
	debian/preinst \
	debian/prerm \
	debian/rules \
	src/yogabook_camera.py \
	src/yogabook_camera_capture.py \
	src/yogabook_camera_control.py \
	tests/check-project.sh \
	tests/check-package.sh \
	tools/camera-sleep.sh \
	tools/inspect-aiqb.sh \
	tools/prepare-camera.sh \
	tools/stage-lenovo-tuning.sh; do
	test -x "$root/$executable_file"
done

grep -Fq 'GNU GENERAL PUBLIC LICENSE' "$root/LICENSE"
grep -Fq 'Copyright (c) 2017 Intel Corporation.' \
	"$root/docs/KERNEL-CONTRACT.md"
grep -Fq 'WV517S actuator remains separate' "$root/docs/KERNEL-CONTRACT.md"
grep -Fqx 'b6a240c4e47ed1187987f9f68d8e68d392b758467914aa7bcc73993fe7952a55  OV2740_CJAE533_CHT.cpf' \
	"$root/metadata/OV2740_CJAE533_CHT.cpf.sha256"

if git -C "$root" ls-files '*.cpf' '*.aiqb' | grep -q .; then
	echo 'ERROR: proprietary camera tuning is tracked by Git' >&2
	exit 1
fi

printf 'AIQBnot-a-valid-file' >"$temporary_directory/invalid.cpf"
if "$root/tools/inspect-aiqb.sh" --structure-only \
	"$temporary_directory/invalid.cpf" >/dev/null 2>&1; then
	echo 'ERROR: invalid AIQB fixture was accepted' >&2
	exit 1
fi

printf 'AIQB\0OV2740 V11 tuning on 2015/02/02.\0' \
	>"$temporary_directory/structure.cpf"
"$root/tools/inspect-aiqb.sh" --structure-only \
	"$temporary_directory/structure.cpf" | grep -Fq 'AIQB_VALIDATION: STRUCTURE_ONLY'

python3 -m json.tool "$root/config/cameras.json" >/dev/null
python3 "$root/tests/check-camera-config.py" "$root/config/cameras.json"
PYTHONPATH="$root/src" python3 "$root/tests/test-camera-python.py"
PYTHONPYCACHEPREFIX="$temporary_directory/pycache" \
	python3 -m py_compile "$root"/src/*.py "$root"/tests/*.py

bash -n \
	"$root"/tools/*.sh \
	"$root"/tests/*.sh \
	"$root/debian/postinst" \
	"$root/debian/preinst" \
	"$root/debian/prerm"

dpkg-parsechangelog -l"$root/debian/changelog" -S Version | \
	grep -Ex '[0-9]+\.[0-9]+\.[0-9]+'
grep -Eq '^ acl,$' "$root/debian/control"
grep -Fq 'ConditionPathExists=/sys/class/dmi/id/product_name' \
	"$root/systemd/yogabook-camera-prepare.service"
grep -Fq 'ExecCondition=/usr/bin/grep -Eq YB1[-_]X91L' \
	"$root/systemd/yogabook-camera-prepare.service"
grep -Fq 'Before=sleep.target' "$root/systemd/yogabook-camera-sleep.service"
grep -Fq 'ExecStart=/usr/libexec/yogabook-camera/camera-sleep.sh pre' \
	"$root/systemd/yogabook-camera-sleep.service"
grep -Fq 'ExecStop=/usr/libexec/yogabook-camera/camera-sleep.sh post' \
	"$root/systemd/yogabook-camera-sleep.service"
grep -Fq 'Type=notify' "$root/systemd/yogabook-camera.service"
grep -Fq 'User=1000' "$root/systemd/yogabook-camera.service"
grep -Fq 'SupplementaryGroups=video render' "$root/systemd/yogabook-camera.service"
grep -Fq 'Before=display-manager.service' "$root/systemd/yogabook-camera.service"
grep -Fq 'CPUQuota=175%' "$root/systemd/yogabook-camera.service"
grep -Fq 'MemoryMax=384M' "$root/systemd/yogabook-camera.service"
grep -Fq 'TasksMax=64' "$root/systemd/yogabook-camera.service"
grep -Fq 'ExecStop=-/usr/bin/v4l2-ctl -d /dev/video10 --set-ctrl=keep_format=0' \
	"$root/systemd/yogabook-camera.service"
grep -Fq 'ExecStop=-/usr/bin/v4l2-ctl -d /dev/video11 --set-ctrl=keep_format=0' \
	"$root/systemd/yogabook-camera.service"
grep -Fq 'ExecStartPre=-/usr/bin/v4l2-ctl -d /dev/video10 --set-ctrl=keep_format=0' \
	"$root/systemd/yogabook-camera.service"
grep -Fq 'ExecStartPre=-/usr/bin/v4l2-ctl -d /dev/video11 --set-ctrl=keep_format=0' \
	"$root/systemd/yogabook-camera.service"
grep -Fq 'os.kill(service_pid(), signal.SIGUSR2)' "$root/src/yogabook_camera_control.py"
grep -Fq 'os.kill(current_pid, signal.SIGHUP)' "$root/src/yogabook_camera_control.py"
grep -Fq 'CameraSelectionMonitor(arguments.switch_dwell)' "$root/src/yogabook_camera.py"
grep -Fq 'CameraActivityMonitor(' "$root/src/yogabook_camera.py"
grep -Fq 'temperature=hottest_temperature_celsius()' "$root/src/yogabook_camera.py"
grep -Fq 'self._pause_streaming(reason)' "$root/src/yogabook_camera.py"
grep -Fq 'intervideosink name=browser_bridge channel=yogabook-camera sync=false' \
	"$root/src/yogabook_camera.py"
grep -Fq 'intervideosrc channel=yogabook-camera' "$root/src/yogabook_camera.py"
grep -Fq 'framerate=30/1,colorimetry=2:4:7:1' "$root/src/yogabook_camera.py"
grep -Fq 'card_label="Front Camera,Rear Camera"' \
	"$root/modprobe.d/yogabook-camera.conf"
grep -Fq "for specification in '10:Front Camera' '11:Rear Camera'" \
	"$root/tools/prepare-camera.sh"
grep -Fq 'v4l2sink device={arguments.front_output_device}' "$root/src/yogabook_camera.py"
grep -Fq 'v4l2sink device={arguments.rear_output_device}' "$root/src/yogabook_camera.py"
grep -Fq 'keep_format=1,sustain_framerate=1,timeout=0' \
	"$root/src/yogabook_camera.py"
grep -Fq 'INTERVIDEO_LAST_FRAME_TIMEOUT_NS = 365 * 24 * 60 * 60 * 1_000_000_000' \
	"$root/src/yogabook_camera.py"
grep -Fq 'self._wait_for_fresh_processed_frame(previous_timestamp)' \
	"$root/src/yogabook_camera.py"
grep -Fq 'pixelformat=YUYV,field=none,colorspace=rec709,xfer=srgb' \
	"$root/src/yogabook_camera.py"
grep -Fq 'return int(self.pipeline_failed)' "$root/src/yogabook_camera.py"
grep -Fq 'Restart=on-failure' "$root/systemd/yogabook-camera.service"
if grep -Fq '0.824705 + 1.105571 * x + 0.423998 * y' \
	"$root/src/yogabook_camera.py"; then
	echo 'ERROR: physically rejected quadratic color surface is still enabled' >&2
	exit 1
fi
grep -Fq 'pixel.rgb + 0.16 * (pixel.rgb - 0.25 * neighbours)' \
	"$root/src/yogabook_camera.py"
grep -Fq 'return 24 <= level <= 235' "$root/src/yogabook_camera.py"
grep -Fq "user=\$(id -nu \"\$uid\" 2>/dev/null) || continue" "$root/debian/preinst"
grep -Fq "setfacl -b \"\$device\"" "$root/debian/postinst"
grep -Fq 'ATTR{name}=="ATOMISP video output"' \
	"$root/udev/72-yogabook-camera-private.rules"
if grep -Fq 'Yoga Book Camera' "$root/udev/72-yogabook-camera-private.rules"; then
	echo 'ERROR: private-device rule must not match the corrected loopback' >&2
	exit 1
fi
if grep -Fq 'allow_raw_output' \
	"$root/modprobe.d/yogabook-camera.conf" \
	"$root/tools/prepare-camera.sh"; then
	echo 'ERROR: obsolete AtomISP raw-output gate is still referenced' >&2
	exit 1
fi
grep -Fq 'YB1-X91L' "$root/tools/prepare-camera.sh"
grep -Fq 'devices=2 video_nr=10,11' \
	"$root/modprobe.d/yogabook-camera.conf"
grep -Fq 'exclusive_caps=1,1 max_buffers=2' \
	"$root/modprobe.d/yogabook-camera.conf"
grep -Fq 'dh_installsystemd --no-stop-on-upgrade yogabook-camera.service' \
	"$root/debian/rules"

if command -v shellcheck >/dev/null; then
	shellcheck \
		"$root"/tools/*.sh \
		"$root"/tests/*.sh \
		"$root/debian/postinst" \
		"$root/debian/preinst" \
		"$root/debian/prerm"
else
	echo 'WARN: shellcheck is not installed; static shell validation skipped' >&2
fi

echo 'Yoga Book Camera project: PASS'
