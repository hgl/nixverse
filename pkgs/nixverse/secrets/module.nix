{ lib, ... }:
let
  inherit (lib) types;
in
{
  freeformType = types.attrsOf types.raw;
  options.nodes = lib.mkOption {
    type = types.attrs;
    default = { };
  };
}
