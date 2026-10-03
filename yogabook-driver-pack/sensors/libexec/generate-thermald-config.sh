#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Yoga Book contributors

set -Eeuo pipefail

sysroot=${YBS_SYSROOT:-/}
output=${YBS_THERMAL_CONFIG:-}

sys_path() {
	if [[ $sysroot == / ]]; then
		printf '%s\n' "$1"
	else
		printf '%s%s\n' "${sysroot%/}" "$1"
	fi
}

read_value() {
	local value
	[[ -r $1 ]] || return 1
	read -r value <"$1" || return 1
	printf '%s\n' "$value"
}

read_temperature() {
	local path=$1 minimum=$2 maximum=$3 label=$4 value
	value=$(read_value "$path") || {
		echo "ERROR: $label temperature is unreadable: $path" >&2
		return 1
	}
	[[ $value =~ ^-?[0-9]+$ ]] || {
		echo "ERROR: $label temperature is not an integer: $value" >&2
		return 1
	}
	((value >= minimum && value <= maximum)) || {
		echo "ERROR: $label temperature is implausible: $value" >&2
		return 1
	}
	printf '%s\n' "$value"
}

find_hwmon() {
	local wanted=$1 hwmon name
	for hwmon in "$(sys_path /sys/class/hwmon)"/hwmon*; do
		[[ -d $hwmon ]] || continue
		name=$(read_value "$hwmon/name" 2>/dev/null || true)
		if [[ $name == "$wanted" ]]; then
			printf '%s\n' "$hwmon"
			return
		fi
	done
	return 1
}

find_thermal_zone() {
	local wanted=$1 zone type
	for zone in "$(sys_path /sys/class/thermal)"/thermal_zone*; do
		[[ -d $zone ]] || continue
		type=$(read_value "$zone/type" 2>/dev/null || true)
		if [[ $type == "$wanted" ]]; then
			printf '%s\n' "$zone"
			return
		fi
	done
	return 1
}

config_path() {
	local host_path=$1
	if [[ $sysroot == / ]]; then
		printf '%s\n' "$host_path"
	else
		printf '%s\n' "${host_path#"${sysroot%/}"}"
	fi
}

vendor=$(read_value "$(sys_path /sys/class/dmi/id/sys_vendor)" 2>/dev/null || true)
product=$(read_value "$(sys_path /sys/class/dmi/id/product_name)" 2>/dev/null || true)
if [[ $vendor != LENOVO || $product != 'Lenovo YB1-X91L' ]]; then
	echo 'ERROR: thermald policy is restricted to LENOVO / Lenovo YB1-X91L' >&2
	exit 2
fi

if [[ $sysroot == / ]]; then
	modprobe coretemp
	modprobe intel_powerclamp
fi

if [[ -n ${YBS_WAIT_SECONDS:-} ]]; then
	wait_seconds=$YBS_WAIT_SECONDS
elif [[ $sysroot == / ]]; then
	wait_seconds=45
else
	wait_seconds=0
fi
[[ $wait_seconds =~ ^[0-9]+$ ]] || {
	echo "ERROR: YBS_WAIT_SECONDS is not a non-negative integer: $wait_seconds" >&2
	exit 2
}

deadline=$((SECONDS + wait_seconds))
while :; do
	coretemp=$(find_hwmon coretemp 2>/dev/null || true)
	battery_hwmon=$(find_hwmon bq27542_0 2>/dev/null || true)
	charger_hwmon=$(find_hwmon bq25890_charger_0 2>/dev/null || true)
	pnit_zone=$(find_thermal_zone PNIT 2>/dev/null || true)
	if [[ -n $coretemp && -n $battery_hwmon && -n $charger_hwmon && -n $pnit_zone ]]; then
		break
	fi
	((SECONDS < deadline)) || break
	sleep 1
done

[[ -n $coretemp ]] || {
	echo 'ERROR: coretemp hwmon device is missing' >&2
	exit 1
}
[[ -n $battery_hwmon ]] || {
	echo 'ERROR: BQ27542 battery temperature sensor is missing' >&2
	exit 1
}
[[ -n $charger_hwmon ]] || {
	echo 'ERROR: BQ25890 charger temperature sensor is missing' >&2
	exit 1
}
[[ -n $pnit_zone ]] || {
	echo 'ERROR: PNIT platform temperature sensor is missing' >&2
	exit 1
}

declare -A core_inputs=()
for label_path in "$coretemp"/temp*_label; do
	[[ -r $label_path ]] || continue
	label=$(read_value "$label_path" 2>/dev/null || true)
	[[ $label =~ ^Core[[:space:]]([0-3])$ ]] || continue
	core=${BASH_REMATCH[1]}
	input_path=${label_path%_label}_input
	critical_path=${label_path%_label}_crit
	critical=$(read_value "$critical_path" 2>/dev/null || true)
	[[ $critical == 90000 ]] || {
		echo "ERROR: Core $core critical limit is not 90000: ${critical:-unreadable}" >&2
		exit 1
	}
	read_temperature "$input_path" -20000 110000 "Core $core" >/dev/null
	core_inputs[$core]=$input_path
done
for core in 0 1 2 3; do
	[[ -n ${core_inputs[$core]:-} ]] || {
		echo "ERROR: coretemp does not expose Core $core" >&2
		exit 1
	}
done

frequency_cdev=cpufreq
for core in 0 1 2 3; do
	driver=$(read_value "$(sys_path "/sys/devices/system/cpu/cpu$core/cpufreq/scaling_driver")" 2>/dev/null || true)
	case $driver in
	intel_cpufreq|intel_pstate)
		selected_cdev=intel_pstate
		;;
	?*)
		selected_cdev=cpufreq
		;;
	*)
		echo "ERROR: CPU $core frequency driver is unreadable" >&2
		exit 1
		;;
	esac
	if ((core == 0)); then
		frequency_cdev=$selected_cdev
	elif [[ $selected_cdev != "$frequency_cdev" ]]; then
		echo "ERROR: CPU frequency drivers require different thermald controls" >&2
		exit 1
	fi
done

pnit_input=$pnit_zone/temp
battery_input=$battery_hwmon/temp1_input
charger_input=$charger_hwmon/temp1_input
read_temperature "$pnit_input" -20000 110000 PNIT >/dev/null
read_temperature "$battery_input" -20000 80000 battery >/dev/null
read_temperature "$charger_input" -20000 100000 charger >/dev/null

processor_count=0
powerclamp_count=0
charger_cooling_count=0
for cooling in "$(sys_path /sys/class/thermal)"/cooling_device*; do
	[[ -d $cooling ]] || continue
	cooling_type=$(read_value "$cooling/type" 2>/dev/null || true)
	case $cooling_type in
	Processor) processor_count=$((processor_count + 1)) ;;
	intel_powerclamp) powerclamp_count=$((powerclamp_count + 1)) ;;
	TCHG) charger_cooling_count=$((charger_cooling_count + 1)) ;;
	esac
done
if ((processor_count != 4 || powerclamp_count != 1 || charger_cooling_count != 1)); then
	echo "ERROR: cooling devices are incomplete: Processor=$processor_count intel_powerclamp=$powerclamp_count TCHG=$charger_cooling_count" >&2
	exit 1
fi

if [[ -z $output ]]; then
	output=$(sys_path /run/thermald/yogabook-thermal-conf.xml)
fi
install -d -m 0755 "$(dirname "$output")"
temporary=$(mktemp "${output}.XXXXXX")
cleanup() { rm -f -- "$temporary"; }
trap cleanup EXIT

emit_sensor() {
	local type=$1 path=$2
	printf '      <ThermalSensor>\n'
	printf '        <Type>%s</Type>\n' "$type"
	printf '        <Path>%s</Path>\n' "$(config_path "$path")"
	printf '        <AsyncCapable>0</AsyncCapable>\n'
	printf '      </ThermalSensor>\n'
}

emit_cpu_zone() {
	local zone=$1 sensor=$2
	printf '      <ThermalZone>\n'
	printf '        <Type>%s</Type>\n' "$zone"
	printf '        <TripPoints><TripPoint>\n'
	printf '          <SensorType>%s</SensorType>\n' "$sensor"
	printf '          <Temperature>75000</Temperature>\n'
	printf '          <Hyst>3000</Hyst>\n'
	printf '          <type>max</type>\n'
	printf '          <ControlType>SEQUENTIAL</ControlType>\n'
	printf '          <CoolingDevice><type>%s</type><influence>100</influence><SamplingPeriod>4</SamplingPeriod></CoolingDevice>\n' "$frequency_cdev"
	printf '          <CoolingDevice><type>intel_powerclamp</type><influence>80</influence><SamplingPeriod>4</SamplingPeriod></CoolingDevice>\n'
	printf '          <CoolingDevice><type>Processor</type><influence>60</influence><SamplingPeriod>4</SamplingPeriod></CoolingDevice>\n'
	printf '        </TripPoint></TripPoints>\n'
	printf '      </ThermalZone>\n'
}

emit_charge_zone() {
	local zone=$1 sensor=$2 threshold=$3
	printf '      <ThermalZone>\n'
	printf '        <Type>%s</Type>\n' "$zone"
	printf '        <TripPoints><TripPoint>\n'
	printf '          <SensorType>%s</SensorType>\n' "$sensor"
	printf '          <Temperature>%s</Temperature>\n' "$threshold"
	printf '          <Hyst>3000</Hyst>\n'
	printf '          <type>max</type>\n'
	printf '          <ControlType>SEQUENTIAL</ControlType>\n'
	printf '          <CoolingDevice><type>TCHG</type><influence>100</influence><SamplingPeriod>4</SamplingPeriod></CoolingDevice>\n'
	printf '        </TripPoint></TripPoints>\n'
	printf '      </ThermalZone>\n'
}

{
	printf '%s\n' '<?xml version="1.0"?>'
	printf '%s\n' '<ThermalConfiguration>' '  <Platform>'
	printf '%s\n' '    <Name>Lenovo Yoga Book YB1-X91L thermal safety</Name>'
	printf '%s\n' '    <ProductName>Lenovo YB1-X91L</ProductName>'
	printf '%s\n' '    <Preference>QUIET</Preference>' '    <ThermalSensors>'
	for core in 0 1 2 3; do
		emit_sensor "yb_core$core" "${core_inputs[$core]}"
	done
	emit_sensor yb_pnit "$pnit_input"
	emit_sensor yb_battery "$battery_input"
	emit_sensor yb_charger "$charger_input"
	printf '%s\n' '    </ThermalSensors>' '    <ThermalZones>'
	for core in 0 1 2 3; do
		emit_cpu_zone "yb_cpu_core$core" "yb_core$core"
	done
	emit_cpu_zone yb_pnit_zone yb_pnit
	emit_charge_zone yb_battery_zone yb_battery 45000
	emit_charge_zone yb_charger_zone yb_charger 70000
	printf '%s\n' '    </ThermalZones>' '  </Platform>' '</ThermalConfiguration>'
} >"$temporary"

chmod 0644 "$temporary"
mv -f -- "$temporary" "$output"
trap - EXIT
printf 'Generated Yoga Book thermald policy: %s\n' "$output"
