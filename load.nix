{
  lib,
  lib',
  self,
}:
flake:
let
  loadOsConfigurations =
    releases:
    let
      nodes = lib'.loadNodes flake releases;
      args = lib.concatMap (
        node:
        if node ? nodes then
          map (n: lib.removeAttrs node [ "nodes" ] // { node = n; }) node.nodes
        else
          [ node ]
      ) nodes;
    in
    lib'.mapListToAttrs (
      { inputs, node, ... }@arg:
      let
        mkSystem =
          {
            nixos = inputs.nixpkgs.lib.nixosSystem;
            darwin = inputs.nix-darwin.lib.darwinSystem;
          }
          .${node.os};
      in
      lib.nameValuePair node.name (mkSystem {
        specialArgs = {
          inputs' = inputs;
          node' = node;
          lib' = arg.lib;
          modules' = if node.os == "nixos" then flakeSelf.nixosModules else flakeSelf.darwinModules;
        };
        modules = [
          (
            { config, pkgs, ... }:
            {
              _module.args =
                {
                  pkgs' = lib.mapAttrs (name: v: pkgs.callPackage v { }) (lib'.importDir "${flake}/pkgs");
                }
                // lib.optionalAttrs (node.channel == "stable" && flake.inputs ? nixpkgs-unstable) {
                  pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${config.nixpkgs.hostPlatform};
                };
              networking.hostName = lib.mkDefault node.name;
            }
          )
          "${node.basePath}/configuration.nix"
        ];
      })
    ) args;
  flakeSelf = {
    self = flake;
    nixosModules = lib'.importDir "${flake}/modules/nixos";
    darwinModules = lib'.importDir "${flake}/modules/darwin";
    packages = lib'.forAllSystems (
      system:
      let
        pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
        nixverse = pkgs.callPackage (import ./package.nix) {
          nixos-anywhere = self.inputs.nixos-anywhere.packages.${system}.default;
        };
      in
      {
        inherit nixverse;
      }
      // lib.mapAttrs (name: v: pkgs.callPackage v { }) (lib'.importDir "${flake}/pkgs")
    );
    nixosConfigurations = loadOsConfigurations lib'.releaseGroups.nixos;
    darwinConfigurations = loadOsConfigurations lib'.releaseGroups.darwin;
  };
in
flakeSelf
