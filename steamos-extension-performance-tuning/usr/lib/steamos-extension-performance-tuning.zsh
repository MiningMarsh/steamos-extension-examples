#!/usr/bin/env zsh

function upsert {
	local content=$(cat)
	local target=$1

	if [[ ! -f $target ]] || [[ $(sha256sum < $target) != $(echo $content | sha256sum ) ]]; then
		echo $content | tee $target > /dev/null
	fi
}

function systune {
	local prefix=$1
	shift

	echo $@ | xargs -n2 echo | while read -r setting value; do
		echo $value | upsert $prefix/$setting
	done
}

function ioscheduler {
	if [[ 1 -eq $(cat /sys/block/$1/queue/rotational) ]]; then
		echo bfq
	elif [[ 1 -eq $(cat /sys/block/$1/removable) ]]; then
		echo mq-deadline
	else
		echo kyber
	fi
}

function on_ac {
	[[ ! -e /sys/class/power_supply/ACAD/online ]] || \
	[[ 1 == $(cat /sys/class/power_supply/ACAD/online) ]]
}

function scsipm {
	find /sys | grep link_power_management_policy | while read -r policy; do
		echo $1 | upsert $policy
	done
}

function pciepm {
        echo $1 | upsert /sys/module/pcie_aspm/parameters/policy
}

function devicepm {
	find /sys \
	| grep -E '/power/control$' \
	| while read -r control; do
		echo $1 | upsert $control
	done
}

function sndpm {
	find /sys -iname 'power_save' \
	| sort | uniq \
	| while read -r power_save; do
		if $1; then
			echo 1
		else
			echo 0
		fi | upsert $power_save
	done

	find /sys -iname 'power_save_controller' \
	| sort | uniq \
	| while read -r power_save_controller; do
		if $1; then
			echo Y
		else
			echo N
		fi | upsert $power_save_controller
	done
}

function amdgpupm {
	find /sys -iname 'power_dpm_force_performance_level' \
	| sort | uniq \
	| while read -r power_dpm_force_performance_level; do
		echo $1 | upsert $power_dpm_force_performance_level
	done
}

function hddpm {
	smartctl -s standby,$2 $1
	smartctl -s aam,$3 $1
	smartctl -s apm,$4 $1
}

function cpupm {
	if \
		[[ -e /sys/devices/system/cpu/cpufreq/policy0/scaling_driver ]] &&
		[[ intel_pstate == $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_driver) ]]
	then
		for policy in /sys/devices/system/cpu/cpufreq/policy*(N); do
			echo powersave | tee $policy/scaling_governor > /dev/null 2>&1
			if $1; then
				echo balance_performance
			else
				echo performance
			fi | tee $policy/energy_performance_preference > /dev/null 2>&1
		done
	else
		if $1; then
			cpupower frequency-set -g performance > /dev/null 2>&1
		else
			cpupower frequency-set -g schedutil > /dev/null 2>&1
		fi
	fi
}

function nvmepm {
	local base=$(grep -Eo 'nvme[0-9]+' <<< $1)
	nvme set-feature /dev/$base -f 2 -V $2
	nvme reset /dev/$base
}

function wifipm {
	iwconfig 2>/dev/null | grep -Eo '^[^ ]+' \
	| while read -r device; do
		iwconfig $device power $1
	done
}

function update-devices {
	for devtype in $@; do
		for device in /sys/block/$devtype*(N); do
			/usr/sbin/steamos-extension-performance-tuning-udev-$devtype $(basename $device)
		done
	done
}

function update-btrfs {
	for btrfs in /sys/fs/btrfs/*(N); do
		if [[ $btrfs == /sys/fs/btrfs/features ]]; then
			continue
		fi

		/usr/sbin/steamos-extension-performance-tuning-udev-btrfs $(basename $btrfs)
	done
}
