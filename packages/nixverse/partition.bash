set -euo pipefail

#shellcheck disable=SC2153
boot_type=$BOOT_TYPE
#shellcheck disable=SC2153
boot_device=$BOOT_DEVICE
#shellcheck disable=SC2153
root_format=$ROOT_FORMAT

mem_size=$(awk '$1 == "MemTotal:" {print $2; exit}' /proc/meminfo)
# < 1GB
if [ "$mem_size" -lt $((2 ** 20)) ]; then
	swap_size=1G
else
	swap_size=$((mem_size))K
fi

if mountpoint --quiet /mnt; then
	umount --recursive /mnt
fi
awk 'NR > 1 {print $1}' /proc/swaps | {
	while read -r dev; do
		swapoff "$dev"
	done
}
echo "Partitioning disk"
case $boot_type in
efi)
	sgdisk \
		--zap-all \
		--new "0:0:100M" \
		--change-name '1:boot' \
		--typecode 1:EF00 \
		--new "0:0:-$swap_size" \
		--change-name '2:root' \
		--typecode 2:8300 \
		--new "0:0:0" \
		--change-name '3:swap' \
		--typecode 3:8200 \
		"$boot_device"
	;;
bios)
	sgdisk \
		--zap-all \
		--new '0:0:+1M' \
		--change-name '1:boot' \
		--typecode 1:EF02 \
		--new "0:0:-$swap_size" \
		--change-name '2:root' \
		--typecode 2:8300 \
		--new "0:0:0" \
		--change-name '3:swap' \
		--typecode 3:8200 \
		"$boot_device"
	;;
esac

# Without this, lsblk reports empty PARTLABEL
udevadm trigger
lsblk \
	--noheadings \
	--list \
	--output PARTLABEL,PATH \
	"$boot_device" |
	awk '
		$1 == "boot" {boot = $2}
		$1 == "root" {root = $2}
		$1 == "swap" {swap = $2}
		END {print boot, root, swap}
	' | (
	read -r boot root swap

	if [[ $boot_type = efi ]]; then
		mkfs.fat -F 32 "$boot"
	fi

	case $root_format in
	xfs) mkfs.xfs -f "$root" ;;
	ext4) mkfs.ext4 "$root" ;;
	btrfs) mkfs.btrfs --force "$root" ;;
	esac
	mount "$root" /mnt
	if [[ $boot_type = efi ]]; then
		mkdir /mnt/boot
		mount "$boot" /mnt/boot
	fi
	mkswap "$swap"
	swapon "$swap"
)
