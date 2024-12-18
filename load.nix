{
  lib,
  lib',
  self,
}:
flake:
let
  flakeSelf = {
    nixosModules = importDir "${flake}/modules/nixos";
    darwinModules = importDir "${flake}/modules/darwin";
    homeManagerModules = importDir "${flake}/modules/homeManager";
    packages = lib'.forAllSystems (
      system:
      let
        pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
      in
      lib.mapAttrs (name: v: pkgs.callPackage v { }) (importDir "${flake}/pkgs")
    );
    nixosConfigurations = configurations.nixos;
    darwinConfigurations = configurations.darwin;
    nodes = lib.concatMapAttrs (
      name: entity:
      if entity ? node then
        { ${name} = entity.node; }
      else if entity ? nodes then
        lib.mapAttrs (name: entity: entity.node) entity.nodes
      else
        { }
    ) entities;
    nodeGroups = lib.concatMapAttrs (
      name: entity:
      if entity ? nodes then { ${name} = lib.mapAttrs (name: entity: entity.node) entity.nodes; } else { }
    ) entities;
  };
  configurations =
    let
      grouped = lib.groupBy ({ node, ... }: node.os) (
        lib'.concatMapAttrsToList (
          name: entity:
          if entity ? node then
            [ entity ]
          else if entity ? nodes then
            lib.mapAttrsToList (name: entity: entity) entity.nodes
          else
            [ ]
        ) entities
      );
    in
    lib.mapAttrs (
      os: entities:
      lib'.mapListToAttrs (
        entity@{
          inputs,
          node,
          configurationPath,
          ...
        }:
        let
          mkSystem =
            {
              nixos = inputs.nixpkgs.lib.nixosSystem;
              darwin = inputs.nix-darwin.lib.darwinSystem;
            }
            .${node.os};
          modules =
            {
              nixos = flakeSelf.nixosModules;
              darwin = flakeSelf.darwinModules;
            }
            .${node.os};
        in
        lib.nameValuePair node.name (mkSystem {
          specialArgs = {
            inherit (entity) inputs node lib';
            modules' = modules;
            hmModules' = flakeSelf.homeManagerModules;
          };
          modules = [
            (
              { config, pkgs, ... }:
              {
                _module.args =
                  {
                    pkgs' = lib.mapAttrs (name: v: pkgs.callPackage v { }) (importDir "${flake}/pkgs");
                  }
                  // lib.optionalAttrs (node.channel != "unstable" && flake.inputs ? nixpkgs-unstable) {
                    pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${config.nixpkgs.hostPlatform};
                  };
                networking.hostName = lib.mkDefault node.name;
                # Needed for syncing fs when deploying
                environment.systemPackages = with pkgs; [ rsync ];
              }
            )
            "${flake}/${configurationPath}"
          ];
        })
      ) entities
    ) grouped;
  entities =
    let
      loadEntities =
        base:
        if lib.pathExists "${flake}/${base}" then
          lib.concatMapAttrs (
            name: v:
            if v == "directory" then
              if lib.pathExists "${flake}/${base}/${name}/node.nix" then
                loadNode name "${base}/${name}"
              else if lib.pathExists "${flake}/${base}/${name}/nodes.nix" then
                loadGroup name "${base}/${name}"
              else
                { }
            else
              { }
          ) (builtins.readDir "${flake}/${base}")
        else
          { };
      loadNode = name: base: {
        ${name} = loadEntrypoint {
          inherit name base;
          entrypoint = import "${flake}/${base}/node.nix";
          group = "";
        };
      };
      loadGroup = name: base: {
        ${name} = {
          nodes = loadEntrypoint {
            name = null;
            inherit base;
            entrypoint = import "${flake}/${base}/nodes.nix";
            group = name;
          };
        };
      };
      loadEntrypoint =
        {
          name,
          base,
          entrypoint,
          group,
        }:
        if group == "" then
          loadNodeEntrypoint {
            inherit
              name
              base
              entrypoint
              group
              ;
            common = null;
          }
        else
          let
            common = entrypoint.common or { };
          in
          lib.mapAttrs (
            name: value:
            loadNodeEntrypoint {
              inherit
                name
                common
                base
                group
                ;
              entrypoint = value;
            }
          ) (lib.removeAttrs entrypoint [ "common" ]);
      loadNodeEntrypoint =
        {
          name,
          base,
          entrypoint,
          common,
          group,
        }:
        let
          inputs =
            if channel == "unstable" then
              lib.concatMapAttrs (
                input-name: input:
                if lib.hasSuffix "-unstable-${os}" input-name then
                  { ${lib.removeSuffix "-unstable-${os}" input-name} = input; }
                else if lib.hasSuffix "-unstable" input-name then
                  { ${lib.removeSuffix "-unstable" input-name} = input; }
                else
                  { }
              ) flake.inputs
            else
              lib.concatMapAttrs (
                input-name: input:
                if lib.hasSuffix "-unstable-${os}" input-name then
                  { ${lib.removeSuffix "-${os}" input-name} = input; }
                else if lib.hasSuffix "-unstable" input-name then
                  { ${input-name} = input; }
                else if lib.hasSuffix "-${channel}-${os}" input-name then
                  { ${lib.removeSuffix "-${channel}-${os}" input-name} = input; }
                else if lib.hasSuffix "-${channel}" input-name then
                  { ${lib.removeSuffix "-${channel}" input-name} = input; }
                else
                  { }
              ) flake.inputs;
          flakeLib = callWithOptionalArgs (importFile flake "lib" { }) {
            inherit (inputs.nixpkgs) lib;
            inherit inputs;
            lib' = flakeLib;
          };
          commonLib =
            flakeLib
            // callWithOptionalArgs (importFile "${flake}/${base}/common" "lib" { }) {
              inherit (inputs.nixpkgs) lib;
              inherit inputs;
              lib' = commonLib;
            };
          baseLib =
            lib.optionalAttrs (group != "") commonLib
            // callWithOptionalArgs (importFile "${flake}/${base}" "lib" { }) {
              inherit (inputs.nixpkgs) lib;
              inherit inputs;
              lib' = baseLib;
            };
          nodeLib =
            if group == "" then
              baseLib
            else
              baseLib
              // callWithOptionalArgs (importFile "${flake}/${nodeDir}" "lib" { }) {
                inherit (inputs.nixpkgs) lib;
                inherit inputs;
                lib' = nodeLib;
              };
          nodeDir = if group == "" then base else "${base}/${name}";
          configurationPath =
            if lib.pathExists "${flake}/${nodeDir}/configuration.nix" then
              "${nodeDir}/configuration.nix"
            else if group != "" && lib.pathExists "${flake}/${base}/common/configuration.nix" then
              "${base}/common/configuration.nix"
            else
              abort "Missing configuration.nix for node ${name}";
          common' = callWithOptionalArgs common nodeArgs;
          nodeArgs =
            {
              inherit (inputs.nixpkgs) lib;
              inherit node inputs;
              lib' = nodeLib;
            }
            // lib.optionalAttrs (group != "") {
              common = common';
            };
          raw = lib.recursiveUpdate (lib.optionalAttrs (group != "") common') (
            callWithOptionalArgs entrypoint nodeArgs
          );
          node =
            assert lib.assertMsg (raw ? os) "Missing attribute \"os\"";
            assert lib.assertMsg (raw ? channel) "Missing attribute \"channel\"";
            assert lib.assertMsg (!(raw ? name)) "Must not specify attribute \"name\" for node ${name}";
            assert lib.assertMsg (!(raw ? group)) "Must not specify attribute \"group\" for node ${name}";
            raw
            // {
              inherit name group;
              dir = nodeDir;
              baseDir = base;
            };
          inherit (node) os channel;
        in
        {
          inherit inputs node configurationPath;
          lib' = nodeLib;
        };
    in
    loadEntities "nodes";
  importFile =
    base: name: default:
    (importDir base).${name} or default;
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
  callWithOptionalArgs =
    f: args: if lib.isFunction f then f (lib.intersectAttrs (lib.functionArgs f) args) else f;
in
flakeSelf
