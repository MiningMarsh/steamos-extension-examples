#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

echo "==========================================="
echo "Hibernate After Sleep - Uninstall Script"
echo "==========================================="
echo ""
echo "This will:"
echo "  - Remove suspend-then-hibernate configuration"
echo "  - Remove systemd sleep configuration"
echo "  - Remove systemd-logind hibernation bypass"
echo "  - Remove GRUB resume parameters"
echo "  - Optionally resize swapfile to 1GB"
echo "  - Remove the extension"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo "Aborted."
	exit 0
fi

echo ""
echo "Step 1: Removing and disabling hibernate-after-sleep service, helpers, and suspend link..."
systemctl disable --now steamos-extension-hibernate-after-sleep-install.service
systemctl disable --now steamos-extension-hibernate-after-sleep-fix-bluetooth.service
systemctl disable --now steamos-extension-hibernate-after-sleep-mark-boot-good.service

echo "Removing suspend link..."
if [[ -L "/etc/systemd/system/steamos-extension-hibernate-after-sleep-install.service" ]]; then
    rm -f /etc/systemd/system/systemd-suspend.service
	echo "  Removed"
else
	echo "  Not found (skipping)"
fi


echo ""
echo "Step 2: Removing sleep configuration..."
if [[ -f "/etc/systemd/sleep.conf" ]]; then
	rm -f /etc/systemd/sleep.conf
	echo "  Removed"
else
	echo "  Not found (skipping)"
fi

echo ""
echo "Step 3: Removing systemd-logind hibernation bypass..."
override_file="/etc/systemd/system/systemd-logind.service.d/override.conf"
if [[ -f "$override_file" ]]; then
	if grep -q "SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK" "$override_file"; then
		temp_file=$(mktemp)
		in_service_section=0

		while IFS= read -r line; do
			if [[ "$line" =~ ^\[Service\] ]]; then
				in_service_section=1
				echo "$line" >> "$temp_file"
			elif [[ "$line" =~ ^\[.*\] ]]; then
				in_service_section=0
				echo "$line" >> "$temp_file"
			elif [[ $in_service_section -eq 1 ]] && [[ "$line" =~ ^Environment=SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK ]]; then
				: # Skip this line
			else
				echo "$line" >> "$temp_file"
			fi
		done < "$override_file"

		if [[ -s "$temp_file" ]] && grep -q "[^[:space:]]" "$temp_file"; then
			mv "$temp_file" "$override_file"
			echo "  Removed hibernation bypass (preserved other settings)"
		else
			rm -f "$override_file"
			rmdir /etc/systemd/system/systemd-logind.service.d 2>/dev/null || true
			rm -f "$temp_file"
			echo "  Removed override file (was empty)"
		fi
	else
		echo "  Bypass not found in override file (skipping)"
	fi
else
	echo "  Override file not found (skipping)"
fi

echo ""
echo "Step 4: Removing GRUB resume parameters..."
starter=steamenv_boot
cfg=/boot/efi/EFI/steamos/grub.cfg
remount=false

# HoloISO
if [[ -f /boot/grub/grub.cfg ]]; then
	starter=linux
	cfg=/boot/grub/grub.cfg
	remount=true
fi

if [[ ! -e $cfg ]]; then
	echo "  Warning: GRUB config file not found at $cfg (skipping)"
elif grep -q "resume=/dev/disk/by-uuid" "$cfg"; then
	# HoloISO keeps boot on the readonly partition.
	if $remount; then
		steamos-readonly disable
	fi

	sed -i -E 's/ resume=[^ ]*//g' "$cfg"
	sed -i -E 's/ resume_offset=[0-9]*//g' "$cfg"

	if $remount; then
		steamos-readonly enable
	fi

	echo "  Removed from GRUB (will take effect on next boot)"
else
	echo "  Not found in GRUB (skipping)"
fi

echo ""
echo "Step 5: Swapfile management..."
function is_btrfs {
	local fstype=$(findmnt -no FSTYPE -T /home)
	[[ "$fstype" == "btrfs" ]]
}

if is_btrfs; then
	swapfile_path="/home/@swapfile/swapfile"
else
	swapfile_path="/home/swapfile"
fi

if [[ -f "$swapfile_path" ]]; then
	current_size=$(stat -c %s "$swapfile_path" 2>/dev/null || echo 0)
	current_size_gb=$((current_size / 1073741824))

	echo "  Current swapfile: $swapfile_path (${current_size_gb}GB)"
	echo ""
	read -p "  Resize swapfile to 1GB? [y/N] " -n 1 -r
	echo

	if [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "  Resizing swapfile to 1GB..."
		swapoff "$swapfile_path" 2>/dev/null || true

		if is_btrfs; then
			rm -f "$swapfile_path"
			truncate -s 0 "$swapfile_path"
			chattr +C "$swapfile_path"
			fallocate -l 1G "$swapfile_path"
			chmod 600 "$swapfile_path"
			mkswap "$swapfile_path"
			swapon "$swapfile_path"
		else
			dd if=/dev/zero of="$swapfile_path" bs=1G count=1
			chmod 600 "$swapfile_path"
			mkswap "$swapfile_path"
			swapon "$swapfile_path"
		fi

		echo "  Swapfile resized to 1GB"
	else
		echo "  Swapfile kept at current size"
		swapon "$swapfile_path" 2>/dev/null || true
	fi
else
	echo "  Swapfile not found (skipping)"
fi

echo ""
echo "Step 6: Reloading systemd..."
systemctl daemon-reload
echo "  Reloaded"

echo ""
echo "Step 7: Removing extension..."
extension_file="/var/lib/extensions/steamos-extension-hibernate-after-sleep.raw"
if [[ -f "$extension_file" ]]; then
	rm -f "$extension_file"
	echo "  Removed extension file"
	systemd-sysext refresh
	echo "  Extension unmerged"
else
	echo "  Extension file not found at $extension_file"
fi

echo ""
read -p "Remove uninstall script? [y/N] " -n 1 -r

if [[ $REPLY =~ ^[Yy]$ ]]; then
	
    echo "Cleaning up uninstall script..."
    if [[ -f "/home/deck/.bin/steamos-extension-hibernate-after-sleep-uninstall.sh" ]]; then
        rm -f /home/deck/.bin/steamos-extension-hibernate-after-sleep-uninstall.sh
        echo "  Removed uninstall script"
    fi
fi

echo ""
echo "==========================================="
echo "Uninstall complete!"
echo "==========================================="
echo ""
echo "Changes made:"
echo "  - Removed hibernate-after-sleep extension"
echo "  - Removed systemd configurations"
echo "  - Removed GRUB resume parameters"
echo ""
echo "Please reboot for all changes to take effect."
