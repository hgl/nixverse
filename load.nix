{
  lib,
  lib',
  self,
}:
flake:
let
  flakePkgs = importDir "${flake}/pkgs";
  secretsPkgs = importDir "${flake.inputs.secrets}/pkgs";
  nixosModules =
    importDir "${flake}/modules/nixos"
    // lib.optionalAttrs (flake.inputs ? secrets) (importDir "${flake.inputs.secrets}/modules/nixos");
  darwinModules =
    importDir "${flake}/modules/darwin"
    // lib.optionalAttrs (flake.inputs ? secrets) (importDir "${flake.inputs.secrets}/modules/darwin");
  hmModules =
    importDir "${flake}/modules/homeManager"
    // lib.optionalAttrs (flake.inputs ? secrets) (
      importDir "${flake.inputs.secrets}/modules/homeManager"
    );
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
          nodeDir,
          nodeBaseDir,
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
              nixos = nixosModules;
              darwin = darwinModules;
            }
            .${node.os};
        in
        lib.nameValuePair node.name (mkSystem {
          specialArgs =
            {
              inherit (entity) inputs node lib';
              modules' = modules;
              hmModules' = hmModules;
            }
            // lib.optionalAttrs (flake.inputs ? secrets) {
              secrets =
                {
                  inherit (flake.inputs.secrets) outPath;
                }
                // lib.optionalAttrs
                  (node.group != "" && lib.pathExists "${flake.inputs.secrets}/${nodeBaseDir}/common")
                  {
                    common = "${flake.inputs.secrets}/${nodeBaseDir}/common";
                  }
                // lib.optionalAttrs (lib.pathExists "${flake.inputs.secrets}/${nodeDir}") {
                  node = "${flake.inputs.secrets}/${nodeDir}";
                };
            };
          modules = [
            (
              { config, pkgs, ... }:
              {
                _module.args =
                  let
                    inherit (config.nixpkgs.hostPlatform) system;
                    nixverse = pkgs.callPackage (import ./packages/nixverse/wrapped.nix node) {
                      nixverse = pkgs.callPackage (import ./packages/nixverse) {
                        inherit (self.inputs.nix-darwin.packages.${system}) darwin-rebuild;
                      };
                    };
                  in
                  {
                    pkgs' =
                      lib.optionalAttrs (node ? flakeSource) {
                        inherit nixverse;
                        # TOOD check input nix-darwin exists if node.os is darwin
                        config = pkgs.callPackage (import ./packages/config node) {
                          inherit nixverse;
                        };
                      }
                      // lib.mapAttrs (name: v: pkgs.callPackage v { }) flakePkgs
                      // lib.optionalAttrs (flake.inputs ? secrets) (
                        lib.mapAttrs (name: v: pkgs.callPackage v { }) secretsPkgs
                      );
                  }
                  // lib.optionalAttrs (node.channel != "unstable" && flake.inputs ? nixpkgs-unstable) {
                    pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
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
          secretsEntrypoint =
            if flake.inputs ? secrets && lib.pathExists "${flake.inputs.secrets}/${base}/node.nix" then
              import "${flake.inputs.secrets}/${base}/node.nix"
            else
              # TODO check if user has mistakenly used nodes.nix
              { };
          group = "";
        };
      };
      loadGroup = name: base: {
        ${name} = {
          nodes = loadEntrypoint {
            name = null;
            inherit base;
            entrypoint = import "${flake}/${base}/nodes.nix";
            secretsEntrypoint =
              if flake.inputs ? secrets && lib.pathExists "${flake.inputs.secrets}/${base}/nodes.nix" then
                import "${flake.inputs.secrets}/${base}/nodes.nix"
              else
                # TODO check if user has mistakenly used node.nix
                { };
            group = name;
          };
        };
      };
      loadEntrypoint =
        {
          name,
          base,
          entrypoint,
          secretsEntrypoint,
          group,
        }:
        if group == "" then
          loadNodeEntrypoint {
            inherit
              name
              base
              entrypoint
              secretsEntrypoint
              group
              ;
            common = null;
            secretsCommon = null;
          }
        else
          let
            common = entrypoint.common or { };
            secretsCommon = secretsEntrypoint.common or { };
          in
          lib.mapAttrs (
            name: value:
            loadNodeEntrypoint {
              inherit
                name
                common
                secretsCommon
                base
                group
                ;
              entrypoint = value;
              secretsEntrypoint = secretsEntrypoint.${name} or { };
            }
          ) (lib.removeAttrs entrypoint [ "common" ]);
      loadNodeEntrypoint =
        {
          name,
          base,
          entrypoint,
          secretsEntrypoint,
          common,
          secretsCommon,
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
          commonAttrs = lib.recursiveUpdate (callWithOptionalArgs common nodeArgs) (
            callWithOptionalArgs secretsCommon nodeArgs
          );
          nodeArgs =
            {
              inherit (inputs.nixpkgs) lib;
              inherit node inputs;
              lib' = nodeLib;
            }
            // lib.optionalAttrs (group != "") {
              common = commonAttrs;
            };
          entrypointAttrs = lib.recursiveUpdate (lib.optionalAttrs (group != "") commonAttrs) (
            lib.recursiveUpdate (callWithOptionalArgs entrypoint nodeArgs) (
              callWithOptionalArgs secretsEntrypoint nodeArgs
            )
          );
          node =
            assert lib.assertMsg (entrypointAttrs ? os) "Missing attribute \"os\"";
            assert lib.assertMsg (entrypointAttrs ? channel) "Missing attribute \"channel\"";
            assert lib.assertMsg (
              !(entrypointAttrs ? name)
            ) "Must not specify attribute \"name\" for node ${name}";
            assert lib.assertMsg (
              !(entrypointAttrs ? group)
            ) "Must not specify attribute \"group\" for node ${name}";
            entrypointAttrs
            // {
              inherit name group;
            };
          inherit (node) os channel;
        in
        {
          inherit
            inputs
            node
            nodeDir
            configurationPath
            ;
          lib' = nodeLib;
          nodeBaseDir = base;
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
{
  inherit nixosModules darwinModules;
  homeManagerModules = hmModules;
  packages = lib'.forAllSystems (
    system:
    let
      pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
    in
    lib.mapAttrs (name: v: pkgs.callPackage v { }) flakePkgs
    // lib.optionalAttrs (flake.inputs ? secrets) (
      lib.mapAttrs (name: v: pkgs.callPackage v { }) secretsPkgs
    )
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
}
