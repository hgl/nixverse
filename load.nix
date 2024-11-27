{
  lib,
  lib',
  self,
}:
flake:
let
  releaseGroups = {
    nixos = [
      "nixos-unstable"
      "nixos-stable"
    ];
    darwin = [
      "darwin-unstable"
      "darwin-stable"
    ];
  };
  # an entity is either a node or a node group with module args
  entities = lib'.concatMapAttrsToList (_: loadEntities) releaseGroups;
  toModuleArgSet =
    entities:
    lib.concatMap (
      entity:
      let
        extraArgNames = [
          "inputs"
          "lib"
          "modules"
        ];
        extraArgs = lib'.mapListToAttrs (name: lib.nameValuePair "${name}'" entity.${name}) extraArgNames;
      in
      if entity.group == "" then
        [
          (
            {
              node' =
                entity.node
                // lib.removeAttrs entity (
                  [
                    "node"
                  ]
                  ++ extraArgNames
                );
            }
            // extraArgs
          )
        ]
      else
        let
          attrs = lib.removeAttrs entity (
            [
              "nodes"
            ]
            ++ extraArgNames
          );
        in
        map (
          n:
          {
            node' = n // attrs;
          }
          // extraArgs
        ) entity.nodes
    ) entities;
  loadEntity =
    release: name:
    let
      releaseParts = lib.split "-" release;
      os = lib.elemAt releaseParts 0;
      channel = lib.elemAt releaseParts 2;
      base = "${flake}/nodes/${release}/${name}";
      inputs = lib.mapAttrs' (k: v: lib.nameValuePair (lib.removeSuffix "-${channel}" k) v) (
        let
          ins =
            lib.removeAttrs flake.inputs [ "nixpkgs-stable-darwin" ]
            // lib.optionalAttrs (os == "darwin") {
              nixpkgs-stable = flake.inputs.nixpkgs-stable-darwin;
            };
        in
        if channel == "stable" then lib.filterAttrs (k: v: !(lib.hasSuffix "-unstable" k)) ins else ins
      );
      flakeLib = importFile flake "lib";
      entityLib = importFile base "lib";
      finalLib =
        lib'.callWithOptionalArgs flakeLib libArgs
        // lib.optionalAttrs (entityLib != null) (lib'.callWithOptionalArgs entityLib libArgs);
      libArgs = {
        inherit (inputs.nixpkgs) lib;
        inputs' = inputs;
        lib' = finalLib;
      };
      modules = if os == "nixos" then flakeSelf.nixosModules else flakeSelf.darwinModules;
      imported =
        if lib.pathExists "${base}/default.nix" then
          let
            raw = lib'.callWithOptionalArgs (import base) libArgs;
          in
          if lib.isAttrs raw then
            if raw ? name then
              lib.abort "must not specify node name for a singleton node: ${base}/default.nix"
            else
              {
                group = "";
                node = {
                  inherit name;
                } // raw;
              }
          else if lib.isList raw then
            {
              group = name;
              nodes = lib.imap0 (
                i: node:
                if !lib.isAttrs node then
                  lib.abort "must be a list of attrsets: ${base}/default.nix"
                else if !(node ? name) then
                  lib.abort "missing name for node [${toString i}]: ${base}/default.nix"
                else
                  node
              ) raw;
            }
          else
            lib.abort "must be a list of attrsets or an attrset: ${base}/default.nix"
        else
          {
            group = "";
            node = {
              inherit name;
            };
          };
      entity = imported // {
        inherit
          release
          os
          channel
          inputs
          modules
          ;
        basePath = base;
        lib = finalLib;
      };
    in
    entity;
  loadEntities =
    releases:
    lib.concatMap (
      release:
      let
        base = "${flake}/nodes/${release}";
        names =
          if lib.pathExists base then
            lib'.concatMapAttrsToList (
              name: v:
              if v == "directory" && lib.pathExists "${base}/${name}/configuration.nix" then [ name ] else [ ]
            ) (builtins.readDir base)
          else
            [ ];
      in
      map (name: loadEntity release name) names
    ) releases;
  configs =
    releases:
    lib'.mapListToAttrs (
      moduleArgs:
      let
        mkSystem =
          with moduleArgs.inputs';
          {
            nixos = nixpkgs.lib.nixosSystem;
            darwin = nix-darwin.lib.darwinSystem;
          }
          .${node.os};
        node = moduleArgs.node';
      in
      lib.nameValuePair node.name (mkSystem {
        specialArgs = moduleArgs;
        modules = [
          (
            { config, pkgs, ... }:
            {
              _module.args =
                {
                  pkgs' = lib.mapAttrs (name: v: pkgs.callPackage v { }) (importDir "${flake}/pkgs");
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
    ) (toModuleArgSet (loadEntities releases));
  importFile = base: name: (importDir base).${name} or null;
  importDir =
    base:
    if lib.pathExists base then
      lib.concatMapAttrs (
        name: v:
        if v == "directory" then
          if lib.pathExists "${base}/${name}/default.nix" then
            {
              ${name} = import "${base}/${name}";
            }
          else
            { }
        else
          let
            n = lib.removeSuffix ".nix" name;
          in
          if n != name then
            {
              ${n} = import "${base}/${name}";
            }
          else
            { }
      ) (builtins.readDir base)
    else
      { };
  flakeSelf = {
    nixosModules = importDir "${flake}/modules/nixos";
    darwinModules = importDir "${flake}/modules/darwin";
    packages = lib'.forAllSystems (
      system:
      let
        pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
        nixverse = pkgs.callPackage (import ./package.nix { inherit self lib entities; }) { };
      in
      {
        inherit nixverse;
      }
      // lib.mapAttrs (name: v: pkgs.callPackage v { }) (importDir "${flake}/pkgs")
    );
    nixosConfigurations = configs releaseGroups.nixos;
    darwinConfigurations = configs releaseGroups.darwin;
  };
in
flakeSelf
