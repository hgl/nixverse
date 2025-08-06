{
  lib,
  lib',
  userInputs,
  userFlakePath,
  userLib,
  userPkgs,
  userModules,
  nodes,
  rawEntity,
}:
let
  nodeName = rawEntity.name;
  inherit (metaConfig) os channel;
  nodesWithCurrent = lib.concatMapAttrs (
    entityName: entity:
    {
      ${entityName} = entity;
    }
    // lib.optionalAttrs (entityName == nodeName) {
      current = entity;
    }
  ) nodes;
  metaConfig =
    let
      inherit
        (lib.evalModules {
          specialArgs = {
            lib' = userLib;
            lib = userInputs.nixpkgs-unstable.lib;
            inputs = userInputs;
            nodes = nodesWithCurrent;
          };
          modules = [
            ./modules/nixos/assertions.nix
            ./modules/nixos/meta.nix
          ]
          ++ map (
            def:
            (
              args:
              {
                _file = "${def.file}${
                  lib.optionalString (lib.length def.loc != 0) "#${lib.concatStringsSep "." def.loc}"
                }";
              }
              // lib'.call def.value {
                inherit (args)
                  lib
                  lib'
                  nodes
                  ;
                inputs = userInputs;
              }
            )
          ) rawEntity.defs;
        })
        config
        ;
    in
    lib.asserts.checkAssertWarn config.assertions config.warnings (
      lib.removeAttrs config [
        "assertions"
        "warnings"
      ]
    );
  inputs' =
    let
      v = lib.concatMapAttrs (
        name: userInput:
        let
          input' =
            lib.removeAttrs userInput [
              "nixosModules"
              "darwinModules"
            ]
            // {
              modules =
                {
                  nixos = userInput.nixosModules or { };
                  darwin = userInput.darwinModules or { };
                }
                .${os};
            };
        in
        if channel != "unstable" && lib.hasSuffix "-unstable-${os}" name then
          { ${lib.removeSuffix "-${os}" name} = input'; }
        else if channel != "unstable" && lib.hasSuffix "-unstable" name then
          { ${name} = input'; }
        else if lib.hasSuffix "-${channel}-${os}" name then
          { ${lib.removeSuffix "-${channel}-${os}" name} = input'; }
        else if lib.hasSuffix "-${channel}" name then
          { ${lib.removeSuffix "-${channel}" name} = input'; }
        else if lib.hasSuffix "-any" name then
          { ${lib.removeSuffix "-any" name} = input'; }
        else
          { }
      ) userInputs;
    in
    assert lib.assertMsg (v ? nixpkgs)
      "Missing the flake input nixpkgs-${channel}${
        lib.optionalString (channel != "unstable") "-${os}"
      }, required by node ${nodeName}";
    v;
  baseModule =
    {
      lib,
      pkgs,
      nodes,
      ...
    }:
    {
      _module.args = {
        pkgs' = userPkgs pkgs;
      };
      networking.hostName = lib.mkDefault nodes.current.name;
    };
  configuration = mkConfiguration {
    specialArgs = {
      lib' = userLib;
      inputs' = lib.mapAttrs (name: input: lib.removeAttrs input [ "homeModules" ]) inputs';
      modules' = userModules.${os};
      nodes = nodesWithCurrent;
    }
    // lib.optionalAttrs (lib.pathExists "${userFlakePath}/private") {
      privatePath = "${userFlakePath}/private";
    };
    modules = [
      baseModule
    ]
    ++ configurationPaths
    ++ recursiveFindFiles "hardware-configuration.nix"
    ++ diskConfigPaths
    ++ lib.optional (diskConfigPaths != [ ]) (
      assert lib.assertMsg (inputs' ? disko)
        "Missing the flake input disko-${channel}${
          lib.optionalString (channel != "unstable") "-${os}"
        }, required by node ${nodeName}";
      {
        imports = [ inputs'.disko.modules.disko ];
      }
    )
    ++ lib.optional (secretsPaths != null) (
      assert lib.assertMsg (inputs' ? sops-nix)
        "Missing the flake input sops-nix-${channel}${
          lib.optionalString (channel != "unstable") "-${os}"
        }, required by node ${nodeName}";
      {
        imports = [ inputs'.sops-nix.modules.sops ];
        sops.defaultSopsFile = lib.mkDefault secretsPaths;
      }
    )
    ++ lib.optional (homeFiles != { }) (
      assert lib.assertMsg (inputs' ? home-manager)
        "Missing the flake input home-manager-${channel}${
          lib.optionalString (channel != "unstable") "-${os}"
        }, required by node ${nodeName}";
      (
        { pkgs', ... }:
        {
          imports = [ inputs'.home-manager.modules.home-manager ];
          home-manager = {
            useGlobalPkgs = lib.mkDefault true;
            useUserPackages = lib.mkDefault true;
            extraSpecialArgs = {
              inherit lib';
              inputs' = lib.mapAttrs (
                name: input':
                lib.removeAttrs input' [ "homeModules" ]
                // {
                  modules = input'.homeModules;
                }
              ) inputs';
              modules' = userModules.home;
              nodes = nodesWithCurrent;
            };
            users = lib.mapAttrs (userName: paths: {
              imports = paths;
              _module.args = {
                inherit pkgs';
              };
            }) homeFiles;
          };
        }
      )
    );
  };
  configurationPaths =
    let
      paths = recursiveFindFiles "configuration.nix";
    in
    assert lib.assertMsg (lib.length paths != 0) "Missing ${rawEntity.path}/configuration.nix";
    paths;
  diskConfigPaths = lib.optionals (os == "nixos") (recursiveFindFiles "disk-config.nix");
  sshHostKeyPath =
    let
      paths =
        lib'.optionalPath "${rawEntity.path}/ssh_host_ed25519_key"
        ++ lib'.optionalPath "${rawEntity.privatePath}/ssh_host_ed25519_key";
      n = lib.length paths;
      path = lib.head paths;
    in
    assert lib.assertMsg (n <= 1) "Both ${path} and ${lib.elemAt paths 1} exist, only one is allowed";
    if n == 0 then
      null
    else
      assert lib.assertMsg (lib.pathExists "${path}.pub") "Missing SSH host pubkey: ${path}";
      path;
  secretsPaths =
    let
      paths =
        lib'.optionalPath "${rawEntity.path}/secrets.yaml"
        ++ lib'.optionalPath "${rawEntity.privatePath}/secrets.yaml";
      n = lib.length paths;
      path = lib.head paths;
    in
    assert lib.assertMsg (n <= 1) "Both ${path} and ${lib.elemAt paths 1} exist, only one is allowed";
    if n == 0 then null else path;
  mkConfiguration =
    {
      nixos = inputs'.nixpkgs.lib.nixosSystem;
      darwin =
        assert lib.assertMsg (inputs' ? nix-darwin)
          "Missing the flake input nix-darwin-${channel}${
            lib.optionalString (channel != "unstable") "-${os}"
          }, required by node ${nodeName}";
        inputs'.nix-darwin.lib.darwinSystem;
    }
    .${os};
  recursiveFindFiles =
    fileName:
    lib'.optionalPath "${userFlakePath}/nodes/common/${fileName}"
    ++ lib'.optionalPath "${userFlakePath}/private/nodes/common/${fileName}"
    ++ lib.concatMap (
      parentName:
      lib'.optionalPath "${userFlakePath}/nodes/${parentName}/common/${fileName}"
      ++ lib'.optionalPath "${userFlakePath}/private/nodes/${parentName}/common/${fileName}"
    ) rawEntity.groupNames
    ++ lib'.optionalPath "${rawEntity.path}/${fileName}"
    ++ lib'.optionalPath "${rawEntity.privatePath}/${fileName}";
  homeFiles = lib'.importPathsInSubdirs (
    lib.concatMap (parentName: [
      "${userFlakePath}/nodes/${parentName}/common/users"
      "${userFlakePath}/private/nodes/${parentName}/common/users"
    ]) rawEntity.groupNames
    ++ [
      "${rawEntity.path}/users"
      "${rawEntity.privatePath}/users"
    ]
  ) [ "home" ];
in
lib.removeAttrs rawEntity [
  "createdByGroup"
  "parentNames"
  "groupNames"
]
// metaConfig
// {
  parents = lib.genAttrs rawEntity.parentNames (name: nodes.${name});
  groups = lib.genAttrs rawEntity.groupNames (name: nodes.${name});
  inherit configuration diskConfigPaths sshHostKeyPath;
  inherit (configuration) config;
  dir = lib.removePrefix "${userFlakePath}/" rawEntity.path;
}
