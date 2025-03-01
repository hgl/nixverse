{
  lib,
  config,
  pkgs,
  ...
}:
{
  options = {
    os = lib.mkOption {
      type = lib.types.enum [
        "nixos"
        "darwin"
      ];
    };
    channel = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    deploy = lib.mkOption {
      type = lib.types.submodule {
        options = {
          local = lib.mkOption {
            type = lib.types.enum [
              null
              true
            ];
            default = null;
          };
          buildHost = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          targetHost = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          useRemoteSudo = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          sshOpts = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = [ ];
          };
        };
      };
      default = { };
    };
    install = lib.mkOption {
      type = lib.types.submodule {
        options = {
          buildOnRemote = lib.mkOption {
            type = lib.types.bool;
            default = config.deploy.buildHost != "";
          };
          targetHost = lib.mkOption {
            type = lib.types.str;
            default = config.deploy.targetHost;
          };
          sshOpts = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = config.deploy.sshOpts;
          };
          parititions = lib.mkOption {
            type = lib.types.submodule {
              options = {
                device = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                };
                boot.type = lib.mkOption {
                  type = lib.types.enum [
                    null
                    "efi"
                    "bios"
                  ];
                  default = null;
                };
                root.format = lib.mkOption {
                  type = lib.types.enum [
                    null
                    "ext4"
                    "xfs"
                    "btrfs"
                  ];
                  default = null;
                };
                swap = {
                  enable = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                  };
                  size = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                  };
                };
                script = lib.mkOption {
                  type = lib.types.path;
                  default =
                    let
                      cfg = config.install.partitions;
                    in
                    pkgs.writeShellScript "partition" ''
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
                      echo "Partitioning disk"
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
                          --typecode 3:8200
                        ''} \
                        "$device"

                      # Without this, lsblk reports empty PARTLABEL
                      udevadm trigger
                      lsblk \
                        --noheadings \
                        --list \
                        --output PARTLABEL,PATH \
                        "$device" |
                        awk '
                          $1 == "boot" {boot = $2}
                          $1 == "root" {root = $2}
                          $1 == "swap" {swap = $2}
                          END {print boot, root, swap}
                        ' |
                        (
                          read -r boot root swap

                          case $root_format in
                          ext4) mkfs.ext4 "$root" ;;
                          xfs) mkfs.xfs -f "$root" ;;
                          btrfs) mkfs.btrfs --force "$root" ;;
                          esac
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
                    '';
                };
              };
            };
            default = { };
          };
        };
      };
      default = { };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf config.install.parititions.script == null)
  ];
}
