{
  lib,
  config,
  nodeName,
}:
let
  cfg = config.install.partitions;
in
assert lib.assertMsg (
  config.install.partitions.device != null
) "install.partitions.device must be specified for node ${nodeName}";
assert lib.assertMsg (
  config.install.partitions.boot.type != null
) "install.partitions.boot.type must be specified for node ${nodeName}";
assert lib.assertMsg (
  config.install.partitions.root.format != null
) "install.partitions.root.format must be specified for node ${nodeName}";
''
  set -euo pipefail

  if mountpoint --quiet /mnt; then
    umount --recursive /mnt
  fi
  awk 'NR > 1 {print $1}' /proc/swaps | {
    while read -r dev; do
      swapoff "$dev"
    done
  }

  ${lib.optionalString cfg.swap.enable (
    if cfg.swap.size != "" then
      "swap_size=${cfg.swap.size}"
    else
      ''
        mem_size=$(awk '$1 == "MemTotal:" {print $2; exit}' /proc/meminfo)
        # < 1GB
        if [[ "$mem_size" -lt $((2 ** 20)) ]]; then
          swap_size=1G
        else
          swap_size=$((mem_size))K
        fi
      ''
  )}

  sgdisk \
    --zap-all \
    --new 0:0:${
      {
        efi = "+100M";
        bios = "+1M";
      }
      .${cfg.boot.type}
    } \
    --change-name 1:boot \
    --typecode 1:${
      {
        efi = "EF00";
        bios = "EF02";
      }
      .${cfg.boot.type}
    } \
    --new "0:0:${if cfg.swap.enable then "-$swap_size" else "0"}" \
    --change-name 2:root \
    --typecode 2:8300 \
    ${lib.optionalString cfg.swap.enable ''
      --new 0:0:0 \
      --change-name 3:swap \
      --typecode 3:8200 \
    ''} \
    '${cfg.device}'

  # Without this, lsblk reports empty PARTLABEL
  udevadm trigger
  lsblk \
    --noheadings \
    --list \
    --output PARTLABEL,PATH \
    '${cfg.device}' |
    awk '
      $1 == "boot" {boot = $2}
      $1 == "root" {root = $2}
      $1 == "swap" {swap = $2}
      END {print boot, root, swap}
    ' |
    (
      read -r boot root swap
      ${
        {
          ext4 = "mkfs.ext4 \"$root\"";
          xfs = "mkfs.xfs -f \"$root\"";
          btrfs = "mkfs.btrfs --force \"$root\"";
        }
        .${cfg.root.format}
      }
      mount "$root" /mnt
      ${lib.optionalString (cfg.boot.type == "efi") ''
        mkfs.fat -F 32 "$boot"
        mkdir /mnt/boot
        mount "$boot" /mnt/boot
      ''}
      ${lib.optionalString cfg.swap.enable ''
        mkswap "$swap"
        swapon "$swap"
      ''}
    )
''
