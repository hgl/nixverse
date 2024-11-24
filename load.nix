{ lib, self }:
flake:
let
  callArgs =
    f: args: if lib.isFunction f then f (lib.intersectAttrs (lib.functionArgs f) args) else f;
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
  entities = self.lib.concatMapAttrsToList (_: loadEntities) releaseGroups;
  extractNodes =
    entities:
    lib.concatMap (
      entity:
      if entity.group == "" then
        [
          {
            node =
              entity.node
              // lib.removeAttrs entity [
                "node"
                "moduleArgs"
              ];
            inherit (entity) moduleArgs;
          }
        ]
      else
        let
          attrs = lib.removeAttrs entity [
            "nodes"
            "moduleArgs"
          ];
        in
        map (n: {
          node = n // attrs;
          inherit (entity) moduleArgs;
        }) entity.nodes
    ) entities;
  loadEntity =
    release: name:
    let
      base = "${flake}/nodes/${release}/${name}";
      releaseParts = lib.split "-" release;
      os = lib.elemAt releaseParts 0;
      channel = lib.elemAt releaseParts 2;
      inputs' = lib.mapAttrs' (k: v: lib.nameValuePair (lib.removeSuffix "-${channel}" k) v) (
        let
          no-darwin = lib.removeAttrs flake.inputs [ "nixpkgs-stable-darwin" ];
          ins =
            if os == "darwin" then
              no-darwin
              // {
                nixpkgs-stable = flake.inputs.nixpkgs-stable-darwin;
              }
            else
              no-darwin;
        in
        if channel == "stable" then lib.filterAttrs (k: v: !(lib.hasSuffix "-unstable" k)) ins else ins
      );
      moduleArgs = {
        inherit inputs';
        lib' = callArgs (importFile flake "lib") {
          inherit inputs';
          inherit (inputs'.nixpkgs) lib;
        };
        modules' = if os == "nixos" then flakeSelf.nixosModules else flakeSelf.darwinModules;
      };
      entity =
        if lib.pathExists "${base}/default.nix" then
          let
            raw = callArgs (import base) {
              inherit (moduleArgs.inputs'.nixpkgs) lib;
              inherit (moduleArgs) inputs' lib';
            };
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
    in
    entity
    // {
      inherit
        release
        os
        channel
        moduleArgs
        ;
      basePath = base;
    };
  loadEntities =
    releases:
    lib.concatMap (
      release:
      let
        base = "${flake}/nodes/${release}";
        names =
          if lib.pathExists base then
            self.lib.concatMapAttrsToList (
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
    self.lib.mapListToAttrs (
      { node, moduleArgs }:
      let
        mkSystem =
          with flake.inputs;
          {
            nixos-unstable = nixpkgs-unstable.lib.nixosSystem;
            nixos-stable = nixpkgs-stable.lib.nixosSystem;
            darwin-unstable = nix-darwin-unstable.lib.darwinSystem;
            darwin-stable = nix-darwin-stable.lib.darwinSystem;
          }
          .${node.release};
      in
      lib.nameValuePair node.name (mkSystem {
        specialArgs = {
          node' = node;
        } // moduleArgs;
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
    ) (extractNodes (loadEntities releases));
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
    packages = self.forAllSystems (
      system:
      let
        pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
      in
      lib.mapAttrs (name: v: pkgs.callPackage v { }) (importDir "${flake}/pkgs")
    );
    nixosConfigurations = configs releaseGroups.nixos;
    darwinConfigurations = configs releaseGroups.darwin;
    loadNode = name: lib.findFirst ({ node, ... }: node.name == name) null (extractNodes entities);
    loadNodeGroup =
      name:
      lib.findFirst (entity: entity.group == name) null (
        lib.concatMap (entity: if entity.group == "" then [ ] else [ entity ]) entities
      );
  };
in
flakeSelf
