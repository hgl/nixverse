{
  lib,
  lib',
  userInputs,
  userFlakePath,
  userLib,
  getUserPkgs,
  getUserInputs,
  getUserModules,
  userNodes,
  rawNode,
}:
let
  hostName = rawNode.name;
  inherit (metaConfig) os channel system;
  metaConfig =
    let
      inherit
        (lib.evalModules {
          specialArgs = {
            lib' = userLib;
            lib = userInputs.nixpkgs-unstable.lib;
            inputs = userInputs;
            nodes = userNodes;
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
                inherit (args) lib lib';
                inputs = userInputs;
                nodes = userNodes;
              }
            )
          ) rawNode.defs;
        })
        config
        options
        ;
    in
    assert lib.assertMsg (options.channel.isDefined
    ) "Missing required meta configuration `channel` for host `${hostName}`";
    assert lib.assertMsg (options.system.isDefined
    ) "Missing required meta configuration `system` for host `${hostName}`";
    lib.asserts.checkAssertWarn config.assertions config.warnings (
      lib.removeAttrs config [
        "assertions"
        "warnings"
      ]
    );
  inputs' = getUserInputs {
    inherit
      system
      channel
      os
      ;
    moduleType = os;
  };
  baseModule =
    {
      lib,
      pkgs,
      nodes,
      ...
    }:
    {
      _module.args = {
        pkgs' = getUserPkgs pkgs;
      };
      # Not using lib.mkDefault because
      # 1. it's explicitly set by user
      # 2. hardware-configuration.nix already uses lib.mkDefault and can
      #    conflict
      nixpkgs.hostPlatform = system;
      networking.hostName = lib.mkDefault nodes.current.name;
      environment.systemPackages = [ pkgs.rsync ]; # for fs sync support
    };
  configuration = mkConfiguration {
    specialArgs = {
      lib' = userLib;
      inherit inputs';
      modules' = getUserModules os;
      nodes = userNodes;
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
        }, required by host ${hostName}";
      {
        imports = [ inputs'.disko.modules.disko ];
      }
    )
    ++ lib.optional (secretsPaths != null) (
      assert lib.assertMsg (inputs' ? sops-nix)
        "Missing the flake input sops-nix-${channel}${
          lib.optionalString (channel != "unstable") "-${os}"
        }, required by host ${hostName}";
      {
        imports = [ inputs'.sops-nix.modules.sops ];
        sops.defaultSopsFile = lib.mkDefault secretsPaths;
      }
    )
    ++ lib.optional (homeFiles != { }) (
      assert lib.assertMsg (inputs' ? home-manager)
        "Missing the flake input home-manager-${channel}${
          lib.optionalString (channel != "unstable") "-${os}"
        }, required by host ${hostName}";
      (
        { pkgs', ... }:
        {
          imports = [ inputs'.home-manager.modules.home-manager ];
          home-manager = {
            useGlobalPkgs = lib.mkDefault true;
            useUserPackages = lib.mkDefault true;
            extraSpecialArgs = {
              lib' = userLib;
              inputs' = getUserInputs {
                inherit
                  system
                  channel
                  os
                  ;
                moduleType = "home";
              };
              modules' = getUserModules "home";
              nodes = userNodes;
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
    assert lib.assertMsg (lib.length paths != 0) "Missing ${rawNode.path}/configuration.nix";
    paths;
  diskConfigPaths = lib.optionals (os == "nixos") (recursiveFindFiles "disk-config.nix");
  sshHostKeyPath =
    let
      paths =
        lib'.optionalPath "${rawNode.path}/secrets/fs/etc/ssh/ssh_host_ed25519_key"
        ++ lib'.optionalPath "${rawNode.privatePath}/secrets/fs/etc/ssh/ssh_host_ed25519_key";
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
        lib'.optionalPath "${rawNode.path}/secrets/default.yaml"
        ++ lib'.optionalPath "${rawNode.privatePath}/secrets/default.yaml";
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
          }, required by host ${hostName}";
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
    ) rawNode.groupNames
    ++ lib'.optionalPath "${rawNode.path}/${fileName}"
    ++ lib'.optionalPath "${rawNode.privatePath}/${fileName}";
  homeFiles = lib'.importPathsInSubdirs (
    lib.concatMap (parentName: [
      "${userFlakePath}/nodes/${parentName}/common/users"
      "${userFlakePath}/private/nodes/${parentName}/common/users"
    ]) rawNode.groupNames
    ++ [
      "${rawNode.path}/users"
      "${rawNode.privatePath}/users"
    ]
  ) [ "home" ];
in
lib.removeAttrs rawNode [
  "createdByGroup"
  "parentNames"
  "groupNames"
]
// metaConfig
// {
  parents = lib.genAttrs rawNode.parentNames (name: userNodes.${name});
  groups = lib.genAttrs rawNode.groupNames (name: userNodes.${name});
  inherit configuration diskConfigPaths sshHostKeyPath;
  inherit (configuration) config pkgs;
  pkgs' = getUserPkgs configuration.pkgs;
  lib = configuration.pkgs.lib;
  lib' = userLib;
  dir = lib.removePrefix "${userFlakePath}/" rawNode.path;
}
