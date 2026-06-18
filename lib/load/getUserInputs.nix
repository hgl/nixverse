{
  lib,
  inputs,
}:
{
  system,
  channel,
  os,
  moduleType,
}:
let
  userFlakeInputs = lib.concatMapAttrs (
    name: rawInput:
    let
      input =
        lib.removeAttrs rawInput [
          "homeManagerModules"
          "homeModules"
          "nixosModules"
          "darwinModules"
        ]
        // {
          packages = rawInput.packages.${system} or { };
          legacyPackages = rawInput.legacyPackages.${system} or { };
          modules = {
            nixos = rawInput.nixosModules or { };
            darwin = rawInput.darwinModules or { };
            home = rawInput.homeManagerModules or rawInput.homeModules or { };
          }.${moduleType};
        };
    in
    if channel != "unstable" && lib.hasSuffix "-unstable-${os}" name then
      { ${lib.removeSuffix "-${os}" name} = input; }
    else if channel != "unstable" && lib.hasSuffix "-unstable" name then
      { ${name} = input; }
    else if lib.hasSuffix "-${channel}-${os}" name then
      { ${lib.removeSuffix "-${channel}-${os}" name} = input; }
    else if lib.hasSuffix "-${channel}" name then
      { ${lib.removeSuffix "-${channel}" name} = input; }
    else if lib.hasSuffix "-none" name then
      { }
    else
      { ${name} = input; }
  ) (lib.removeAttrs inputs [ "self" ]);
in
assert lib.assertMsg (userFlakeInputs ? nixpkgs)
  "Missing the flake input nixpkgs-${channel}${lib.optionalString (channel != "unstable") "-${os}"}";
userFlakeInputs
