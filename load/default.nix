{
  lib,
  lib',
  self,
}:
flake: outputs:
let
  final = import ./load.nix {
    inherit
      lib
      lib'
      self
      flake
      outputs
      ;
  };
in
outputs
// lib'.mapListToAttrs (key: lib.nameValuePair key (final.${key} // outputs.${key} or { })) [
  "nixosModules"
  "darwinModules"
  "homeModules"
  "nixosConfigurations"
  "darwinConfigurations"
]
// {
  inherit (final) nixverse;
}
