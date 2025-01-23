lib: {
  os = lib.mkOption {
    type = lib.types.enum [
      "nixos"
      "darwin"
    ];
  };
  channel = lib.mkOption {
    type = lib.types.nonEmptyStr;
  };
  parititions = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          device = lib.mkOption {
            type = lib.types.path;
          };
          boot.type = lib.mkOption {
            type = lib.types.enum [
              "efi"
              "bios"
            ];
          };
          root.format = lib.mkOption {
            type = lib.types.enum [
              "ext4"
              "xfs"
              "btrfs"
            ];
          };
          swap.enable = lib.mkOption {
            type = lib.types.bool;
          };
        };
      }
    );
    default = null;
  };
}
