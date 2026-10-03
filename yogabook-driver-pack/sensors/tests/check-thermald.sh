#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Yoga Book contributors

set -Eeuo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
generator=$root/libexec/generate-thermald-config.sh
drop_in=$root/systemd/thermald.service.d/10-yogabook-policy.conf
fixture=$(mktemp -d /tmp/yogabook-thermald-test.XXXXXX)

cleanup() {
	rm -rf -- "$fixture"
}
trap cleanup EXIT

write_file() {
	local path=$1 value=$2
	install -d -m 0755 "$(dirname "$fixture$path")"
	printf '%s\n' "$value" >"$fixture$path"
}

make_valid_fixture() {
	local core cooling

	write_file /sys/class/dmi/id/sys_vendor LENOVO
	write_file /sys/class/dmi/id/product_name 'Lenovo YB1-X91L'
	write_file /sys/class/hwmon/hwmon0/name coretemp
	for core in 0 1 2 3; do
		write_file "/sys/class/hwmon/hwmon0/temp$((core + 1))_label" "Core $core"
		write_file "/sys/class/hwmon/hwmon0/temp$((core + 1))_input" "$((61000 + core * 1000))"
		write_file "/sys/class/hwmon/hwmon0/temp$((core + 1))_crit" 90000
		write_file "/sys/devices/system/cpu/cpu$core/cpufreq/scaling_driver" intel_cpufreq
	done
	write_file /sys/class/hwmon/hwmon1/name bq27542_0
	write_file /sys/class/hwmon/hwmon1/temp1_input 42000
	write_file /sys/class/hwmon/hwmon2/name bq25890_charger_0
	write_file /sys/class/hwmon/hwmon2/temp1_input 41000
	write_file /sys/class/thermal/thermal_zone0/type PNIT
	write_file /sys/class/thermal/thermal_zone0/temp 65000
	for cooling in 0 1 2 3; do
		write_file "/sys/class/thermal/cooling_device$cooling/type" Processor
	done
	write_file /sys/class/thermal/cooling_device4/type intel_powerclamp
	write_file /sys/class/thermal/cooling_device5/type TCHG
}

assert_xpath() {
	local expression=$1 expected=$2 actual
	actual=$(xmllint --xpath "string($expression)" "$output")
	[[ $actual == "$expected" ]] || {
		printf 'XPath assertion failed: %s: expected %s, got %s\n' \
			"$expression" "$expected" "$actual" >&2
		exit 1
	}
}

assert_rejected_without_replacement() {
	local expected_status=$1 status
	printf '%s\n' preserved >"$output"
	set +e
	YBS_SYSROOT=$fixture YBS_THERMAL_CONFIG=$output "$generator" >/dev/null 2>&1
	status=$?
	set -e
	[[ $status == "$expected_status" ]]
	[[ $(<"$output") == preserved ]]
}

test -x "$generator"
test -f "$drop_in"
make_valid_fixture
output=$fixture/run/thermald/yogabook-thermal-conf.xml
YBS_SYSROOT=$fixture YBS_THERMAL_CONFIG=$output "$generator" >/dev/null
xmllint --noout "$output"

assert_xpath 'count(/ThermalConfiguration/Platform/ThermalSensors/ThermalSensor)' 7
assert_xpath 'count(/ThermalConfiguration/Platform/ThermalZones/ThermalZone)' 7
assert_xpath 'count(//ThermalZone[TripPoints/TripPoint/Temperature="75000"])' 5
assert_xpath 'count(//ThermalZone[TripPoints/TripPoint/Temperature="45000"])' 1
assert_xpath 'count(//ThermalZone[TripPoints/TripPoint/Temperature="70000"])' 1
assert_xpath 'count(//TripPoint[Hyst="3000"])' 7
assert_xpath 'count(//ThermalZone[starts-with(Type,"yb_cpu_core")]/TripPoints/TripPoint/CoolingDevice[type="intel_pstate"])' 4
assert_xpath 'count(//ThermalZone[starts-with(Type,"yb_cpu_core")]/TripPoints/TripPoint/CoolingDevice[type="intel_powerclamp"])' 4
assert_xpath 'count(//ThermalZone[starts-with(Type,"yb_cpu_core")]/TripPoints/TripPoint/CoolingDevice[type="Processor"])' 4
assert_xpath 'count(//ThermalZone[Type="yb_pnit_zone"]/TripPoints/TripPoint/CoolingDevice)' 3
assert_xpath 'count(//ThermalZone[Type="yb_battery_zone" or Type="yb_charger_zone"]/TripPoints/TripPoint/CoolingDevice[type="TCHG"])' 2
assert_xpath 'count(//CoolingDevice[SamplingPeriod="4"])' 17
assert_xpath 'count(//TripPoint[type="max"])' 7
assert_xpath 'count(//*[contains(translate(local-name(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"), "shutdown")])' 0
assert_xpath 'count(//ThermalSensor[starts-with(Path,"/sys/class/")])' 7

for core in 0 1 2 3; do
	assert_xpath "count(//ThermalSensor[Type=\"yb_core$core\" and Path=\"/sys/class/hwmon/hwmon0/temp$((core + 1))_input\"])" 1
done

grep -Fqx 'ExecStartPre=/usr/libexec/yogabook-sensors/generate-thermald-config.sh' "$drop_in"
grep -Fqx 'ExecStart=' "$drop_in"
grep -Fqx 'ExecStart=/usr/sbin/thermald --systemd --dbus-enable --ignore-default-control --config-file=/run/thermald/yogabook-thermal-conf.xml --poll-interval=4' "$drop_in"
grep -Fqx 'RestartSec=10s' "$drop_in"
grep -Fqx 'TimeoutStartSec=70s' "$drop_in"
if grep -Eq -- '--ignore-critical-trip|shutdown|poweroff' "$drop_in"; then
	echo 'thermald drop-in contains a forbidden shutdown override' >&2
	exit 1
fi

# Exercise activation and recovery semantics without manipulating real cooling
# devices. The policy recovers only after its 3 C hysteresis margin.
policy_state() {
	local temperature=$1 threshold=$2 hysteresis=$3 active=${4:-0}
	if ((temperature >= threshold)); then
		printf 'cooling\n'
	elif ((active && temperature > threshold - hysteresis)); then
		printf 'cooling\n'
	else
		printf 'normal\n'
	fi
}
[[ $(policy_state 74999 75000 3000) == normal ]]
[[ $(policy_state 75000 75000 3000) == cooling ]]
[[ $(policy_state 73000 75000 3000 1) == cooling ]]
[[ $(policy_state 72000 75000 3000 1) == normal ]]
[[ $(policy_state 45000 45000 3000) == cooling ]]
[[ $(policy_state 42000 45000 3000 1) == normal ]]

rm -f "$fixture/sys/class/hwmon/hwmon2/name" "$fixture/sys/class/hwmon/hwmon2/temp1_input"
(
	sleep 1
	write_file /sys/class/hwmon/hwmon2/name bq25890_charger_0
	write_file /sys/class/hwmon/hwmon2/temp1_input 41000
) &
delayed_sensor=$!
YBS_SYSROOT=$fixture YBS_WAIT_SECONDS=3 YBS_THERMAL_CONFIG=$output "$generator" >/dev/null
wait "$delayed_sensor"
assert_xpath 'count(//ThermalSensor[Type="yb_charger"])' 1

for core in 0 1 2 3; do
	write_file "/sys/devices/system/cpu/cpu$core/cpufreq/scaling_driver" acpi-cpufreq
done
YBS_SYSROOT=$fixture YBS_THERMAL_CONFIG=$output "$generator" >/dev/null
assert_xpath 'count(//ThermalZone[starts-with(Type,"yb_cpu_core")]/TripPoints/TripPoint/CoolingDevice[type="cpufreq"])' 4
for core in 0 1 2 3; do
	write_file "/sys/devices/system/cpu/cpu$core/cpufreq/scaling_driver" intel_cpufreq
done

write_file /sys/class/dmi/id/sys_vendor NOT-LENOVO
assert_rejected_without_replacement 2
write_file /sys/class/dmi/id/sys_vendor LENOVO

rm -f "$fixture/sys/class/thermal/thermal_zone0/temp"
assert_rejected_without_replacement 1
write_file /sys/class/thermal/thermal_zone0/temp 65000

write_file /sys/class/hwmon/hwmon1/temp1_input -273150
assert_rejected_without_replacement 1

echo 'Yoga Book thermald policy: PASS'
