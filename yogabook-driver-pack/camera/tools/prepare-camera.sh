#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

product_name=$(< /sys/class/dmi/id/product_name)
case $product_name in
	*YB1-X91L*|*YB1_X91L*) ;;
	*)
		echo "ERROR: unsupported DMI product: $product_name" >&2
		exit 1
		;;
esac

if [[ ! -e /dev/video10 && ! -e /dev/video11 ]]; then
	modprobe v4l2loopback \
		devices=2 \
		video_nr=10,11 \
		card_label='Front Camera,Rear Camera' \
		exclusive_caps=1,1 \
		max_buffers=2
	udevadm settle --timeout=5 || true
fi

if command -v v4l2loopback-ctl >/dev/null; then
	if [[ ! -e /dev/video10 ]]; then
		v4l2loopback-ctl add \
			--name 'Front Camera' \
			--exclusive-caps 1 \
			--buffers 2 \
			/dev/video10
	fi
	if [[ ! -e /dev/video11 ]]; then
		v4l2loopback-ctl add \
			--name 'Rear Camera' \
			--exclusive-caps 1 \
			--buffers 2 \
			/dev/video11
	fi
	udevadm settle --timeout=5 || true
fi

for _attempt in {1..30}; do
	[[ -e /dev/video0 && -e /dev/media0 ]] && break
	sleep 1
done

[[ -e /dev/video0 && -e /dev/media0 ]] || {
	echo 'ERROR: AtomISP capture node /dev/video0 is missing' >&2
	exit 1
}
for specification in '10:Front Camera' '11:Rear Camera'; do
	device_number=${specification%%:*}
	expected_name=${specification#*:}
	device=/dev/video$device_number
	[[ -e $device ]] || {
		echo "ERROR: Yoga Book loopback node $device is missing" >&2
		exit 1
	}
	loopback_name=$(< "/sys/class/video4linux/video$device_number/name")
	if [[ $loopback_name != "$expected_name" ]]; then
		echo "ERROR: $device belongs to a different device: $loopback_name" >&2
		exit 1
	fi
done

echo 'Yoga Book camera devices prepared'
