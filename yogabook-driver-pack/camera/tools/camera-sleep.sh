#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

action=${1:?usage: camera-sleep.sh pre|post}
state_directory=/run/yogabook-camera-sleep
service=yogabook-camera.service

case $action in
	pre)
		install -d -m 0755 "$state_directory"
		rm -f -- "$state_directory/resume-service"
		if systemctl is-active --quiet "$service"; then
			systemctl stop "$service"
			install -m 0644 /dev/null "$state_directory/resume-service"
		fi
		;;
	post)
		if [[ -f $state_directory/resume-service ]]; then
			systemctl start "$service"
			rm -f -- "$state_directory/resume-service"
		fi
		;;
	*)
		echo "ERROR: unsupported sleep action: $action" >&2
		exit 2
		;;
esac
