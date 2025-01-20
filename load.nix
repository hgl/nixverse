{
  lib,
  lib',
}:
flake:
let
  publicDir = flake.outPath;
  privateDir = "${publicDir}/private";
  allPkgs = importDirAttrs "${publicDir}/pkgs" // importDirAttrs "${privateDir}/pkgs";
  nixosModules =
    importDirAttrs "${publicDir}/modules/nixos"
    // importDirAttrs "${privateDir}/modules/nixos";
  darwinModules =
    importDirAttrs "${publicDir}/modules/darwin"
    // importDirAttrs "${privateDir}/modules/darwin";
  homeManagerModules =
    importDirAttrs "${publicDir}/modules/homeManager"
    // importDirAttrs "${privateDir}/modules/homeManager";
  loadConfigurations =
    os:
    lib.concatMapAttrs (
      name: entity:
      if entity.type == "node" && entity.node.os == os then
        {
          ${name} = entity.configuration;
        }
      else
        { }
    ) entities;
  entities =
    lib.zipAttrsWith
      (
        name: entityList:
        let
          first = lib.elemAt entityList 0;
          second = lib.elemAt entityList 1;
          desc =
            entity:
            if entity.type == "node" then
              if entity.node.group == "" then
                "${
                  lib.optionalString (!(lib.pathExists "${publicDir}/nodes/${name}/node.nix")) "private/"
                }nodes/${name}/node.nix"
              else
                "${
                  lib.optionalString (
                    !(lib.pathExists "${publicDir}/nodes/${entity.node.group}/nodes.nix")
                  ) "private/"
                }nodes/${entity.node.group}/nodes.nix#${name}"
            else
              "${
                lib.optionalString (!(lib.pathExists "${publicDir}/nodes/${name}/group.nix")) "private/"
              }nodes/${name}/group.nix";
        in
        assert lib.assertMsg (
          lib.length entityList == 1
        ) "${name} is defined by two different types of nodes:\n- ${desc first}\n- ${desc second}";
        first
      )
      (
        lib.mapAttrsToList (
          name: entityMeta:
          assert lib.assertMsg (name != "common")
            "\"common\" is a reserved node name, cannot be used for ${
              lib.optionalString (!entityMeta.public) "private/"
            }nodes/common/${entityMeta.type}.nix";
          assert lib.assertMsg (name != "current")
            "\"current\" is a reserved node name, cannot be used for ${
              lib.optionalString (!entityMeta.public) "private/"
            }nodes/current/${entityMeta.type}.nix";
          if entityMeta.type == "node" then
            loadNode name
          else if entityMeta.type == "nodes" then
            loadNodes name
          else
            loadGroup name
        ) entitiesMeta
      );
  entitiesMeta =
    let
      typesPublic = loadEntityTypes publicDir;
      typesPrivate = loadEntityTypes privateDir;
    in
    lib.zipAttrsWith
      (
        name: dirList:
        let
          first = lib.elemAt dirList 0;
          second = lib.elemAt dirList 1;
        in
        (
          if lib.length dirList == 2 then
            assert lib.assertMsg (first == second)
              "Node type mismatch: ${name} is defined both in nodes/${name}/${first}.nix and private/nodes/${name}/${second}.nix";
            {
              type = first;
              public = true;
              private = true;
            }
          else if lib.hasAttr name typesPublic then
            {
              type = first;
              public = true;
              private = false;
            }
          else
            {
              type = first;
              public = false;
              private = true;
            }
        )
      )
      [
        typesPublic
        typesPrivate
      ];
  loadEntityTypes =
    dir:
    if lib.pathExists "${dir}/nodes" then
      lib.concatMapAttrs (
        name: v:
        if v == "directory" then
          let
            base = "${dir}/nodes/${name}";
          in
          if lib.pathExists "${base}/node.nix" then
            { ${name} = "node"; }
          else if lib.pathExists "${base}/nodes.nix" then
            { ${name} = "nodes"; }
          else if lib.pathExists "${base}/group.nix" then
            { ${name} = "group"; }
          else
            { }
        else
          { }
      ) (builtins.readDir "${dir}/nodes")
    else
      { };
  loadNode =
    nodeName:
    let
      loadRaw =
        dir:
        let
          path = "${dir}/nodes/${nodeName}/node.nix";
        in
        lib.optionalAttrs (lib.pathExists path) (import path);
    in
    {
      ${nodeName} = loadRawNode {
        groupName = "";
        inherit nodeName;
        rawNode = {
          public = loadRaw publicDir;
          private = loadRaw privateDir;
        };
      };
    };
  loadNodes =
    groupName:
    let
      loadRaw =
        dir:
        let
          path = "${dir}/nodes/${groupName}/nodes.nix";
        in
        lib.optionalAttrs (lib.pathExists path) (
          let
            v = import path;
            nodeNames = (lib.attrNames v);
          in
          assert lib.assertMsg (lib.isAttrs v)
            "${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/nodes.nix must evaluate to an attribute set";
          assert lib.assertMsg (lib.all (nodeName: nodeName != "current") nodeNames)
            "\"current\" is a reserved node name, cannot be used in ${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/nodes.nix must not contain a node named ${groupName}, which is the same as the group name";
          assert lib.assertMsg (lib.all (nodeName: nodeName == "common" || nodeName != groupName) nodeNames)
            "${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/nodes.nix must not contain a node named ${groupName}, which is the same as the group name";
          v
        );
      rawPublic = loadRaw publicDir;
      rawPrivate = loadRaw privateDir;
      rawCommonPublic = rawPublic.common or null;
      rawCommonPrivate = rawPrivate.common or null;
      nodes =
        lib.zipAttrsWith
          (
            nodeName: raws:
            let
              first = lib.elemAt raws 0;
              second = lib.elemAt raws 1;
            in
            loadRawNode {
              inherit groupName nodeName;
              rawCommon = {
                public = rawCommonPublic;
                private = rawCommonPrivate;
              };
              rawNode =
                if lib.length raws == 2 then
                  {
                    public = first;
                    private = second;
                  }
                else if lib.hasAttr nodeName rawPublic then
                  {
                    public = first;
                    private = null;
                  }
                else
                  {
                    public = null;
                    private = first;
                  };
            }
          )
          ([
            (lib.removeAttrs rawPublic [ "common" ])
            (lib.removeAttrs rawPrivate [ "common" ])
          ]);
    in
    {
      ${groupName} = {
        type = "group";
        group = {
          children = lib.mapAttrs (_: _: true) nodes;
          nodes = lib.mapAttrs (_: { node, ... }: node) nodes;
        };
      };
    }
    // nodes;
  loadGroup =
    groupName:
    let
      groupPublic = loadRaw publicDir;
      groupPrivate = loadRaw privateDir;
      loadRaw =
        dir:
        let
          path = "${dir}/nodes/${groupName}/group.nix";
        in
        lib.optionalAttrs (lib.pathExists path) (
          let
            raw = import path;
            v =
              (lib.evalModules {
                modules = [
                  {
                    _file = "${lib.optionalString (dir == privateDir) "private/"}nodes/${groupName}/group.nix";
                    options.children = lib.mkOption {
                      type = lib.types.attrsOf lib.types.bool;
                    };
                    config = raw;
                  }
                ];
              }).config;
            children = lib.filterAttrs (_: child: child) v.children;
          in
          assert lib.assertMsg (lib.isAttrs raw)
            "${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/group.nix must evaluate to an attribute set";
          assert lib.assertMsg (lib.all (name: name != groupName) (lib.attrNames children))
            "${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/group.nix#children must not contain the group's own name";
          assert lib.assertMsg (lib.all (name: name != "common") (lib.attrNames children))
            "\"common\" is a reserved node name, cannot be used in ${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/group.nix#children";
          assert lib.assertMsg (lib.all (name: name != "current") (lib.attrNames children))
            "\"current\" is a reserved node name, cannot be used in ${
              lib.optionalString (dir == privateDir) "private/"
            }nodes/${groupName}/group.nix#children";
          assert lib.all (
            name:
            assert lib.assertMsg (lib.hasAttr name entities)
              "${
                lib.optionalString (dir == privateDir) "private/"
              }nodes/${groupName}/group.nix#children contains unknown node ${name}";
            true
          ) (lib.attrNames children);
          {
            inherit children;
          }
        );
      findNodes =
        {
          parent,
          children,
          visited,
          path,
        }:
        lib.concatMapAttrs (
          child: _:
          assert lib.assertMsg (!(lib.hasAttr child visited))
            "circular group containment: ${lib.concatStringsSep " > " (path ++ [ child ])}";
          if entities.${child}.type == "node" then
            { ${child} = entities.${child}.node; }
          else
            findNodes {
              parent = child;
              children = entities.${child}.group.children;
              visited = visited // {
                ${child} = true;
              };
              path = path ++ [ child ];
            }
        ) children;
      children =
        let
          v = groupPublic.children or { } // groupPrivate.children or { };
        in
        assert lib.assertMsg (
          v != { }
        ) "nodes/${groupName}/group.nix#children must contain at least one child";
        v;
      nodes = findNodes {
        parent = groupName;
        inherit children;
        visited = {
          ${groupName} = true;
        };
        path = [
          groupName
        ];
      };
      group = {
        inherit children nodes;
      };
    in
    {
      ${groupName} = {
        type = "group";
        inherit group;
      };
    };
  loadRawNode =
    {
      groupName,
      nodeName,
      rawCommon ? null,
      rawNode,
    }:
    let
      commonSubdir = "nodes/${groupName}/common";
      nodeSubdir = joinPath [
        "nodes"
        groupName
        nodeName
      ];
      entrypointLoc =
        {
          common,
          pubic,
        }:
        "${lib.optionalString (!pubic) "private/"}nodes/${
          if groupName == "" then
            "${nodeName}/node.nix"
          else
            "${groupName}/nodes.nix#${if common then "common" else nodeName}"
        }";
      inputs =
        if channel == "unstable" then
          lib.concatMapAttrs (
            name: input:
            if lib.hasSuffix "-unstable-${os}" name then
              { ${lib.removeSuffix "-unstable-${os}" name} = input; }
            else if lib.hasSuffix "-unstable" name then
              { ${lib.removeSuffix "-unstable" name} = input; }
            else
              { }
          ) flake.inputs
        else
          lib.concatMapAttrs (
            name: input:
            if lib.hasSuffix "-unstable-${os}" name then
              { ${lib.removeSuffix "-${os}" name} = input; }
            else if lib.hasSuffix "-unstable" name then
              { ${name} = input; }
            else if lib.hasSuffix "-${channel}-${os}" name then
              { ${lib.removeSuffix "-${channel}-${os}" name} = input; }
            else if lib.hasSuffix "-${channel}-any" name then
              { ${lib.removeSuffix "-${channel}-any" name} = input; }
            else
              { }
          ) flake.inputs;
      loadLib =
        {
          subdir,
          lib',
        }:
        let
          args = {
            inherit (inputs.nixpkgs) lib;
            inherit inputs lib';
          };
          libPublic = call (importDirOrFile (joinPath [
            publicDir
            subdir
          ]) "lib" { }) args;
          libPrivate = call (importDirOrFile (joinPath [
            privateDir
            subdir
          ]) "lib" { }) args;
        in
        lib.recursiveUpdate libPublic libPrivate;
      topLib = loadLib {
        subdir = "";
        lib' = topLib;
      };
      nodeLib =
        if groupName == "" then
          lib.recursiveUpdate topLib (loadLib {
            subdir = nodeSubdir;
            lib' = nodeLib;
          })
        else
          let
            groupLib = lib.recursiveUpdate topLib (loadLib {
              subdir = commonSubdir;
              lib' = groupLib;
            });
          in
          lib.recursiveUpdate groupLib (loadLib {
            subdir = nodeSubdir;
            lib' = nodeLib;
          });
      loadRaw =
        {
          pubic,
          common,
        }:
        let
          rawPart = if pubic then "public" else "private";
          raw = if common then rawCommon.${rawPart} else rawNode.${rawPart};
          v = lib.optionalAttrs (raw != null) (call raw nodeArgs);
        in
        assert lib.assertMsg (lib.isAttrs v)
          "${entrypointLoc { inherit pubic common; }} must evaluate to an attribute set";
        assert lib.assertMsg (!(v ? name))
          "Must not specify \"name\" in ${entrypointLoc { inherit pubic common; }}";
        assert lib.assertMsg (!(v ? group))
          "Must not specify \"group\" in ${entrypointLoc { inherit pubic common; }}";
        assert lib.assertMsg (!(v ? config))
          "Must not specify \"config\" in ${entrypointLoc { inherit pubic common; }}";
        v;
      commonPublic = loadRaw {
        pubic = true;
        common = true;
      };
      commonPrivate = loadRaw {
        pubic = false;
        common = true;
      };
      common = lib.recursiveUpdate commonPublic commonPrivate;
      nodeArgs =
        {
          inherit (inputs.nixpkgs) lib;
          inherit inputs nodes;
          lib' = nodeLib;
        }
        // lib.optionalAttrs (groupName != "") {
          inherit common;
        };
      nodePublic = loadRaw {
        pubic = true;
        common = false;
      };
      nodePrivate = loadRaw {
        pubic = false;
        common = false;
      };
      node =
        let
          n = lib.recursiveUpdate (lib.optionalAttrs (groupName != "") common) (
            lib.recursiveUpdate nodePublic nodePrivate
          );
        in
        assert lib.assertMsg (n ? os) (
          "Missing \"os\" in ${
            entrypointLoc {
              pubic = true;
              common = false;
            }
          }"
        );
        assert lib.assertMsg (n ? channel) (
          "Missing \"channel\" in ${
            entrypointLoc {
              pubic = true;
              common = false;
            }
          }"
        );
        n
        // {
          name = nodeName;
          group = groupName;
        }
        // (lib.evalModules {
          modules = [
            {
              options = {
                os = lib.mkOption {
                  type = lib.types.enum [
                    "nixos"
                    "darwin"
                  ];
                };
                channel = lib.mkOption {
                  type = lib.types.nonEmptyStr;
                };
                parititions = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.submodule {
                      options = {
                        device = lib.mkOption {
                          type = lib.types.path;
                        };
                        boot.type = lib.mkOption {
                          type = lib.types.enum [
                            "efi"
                            "bios"
                          ];
                        };
                        root.format = lib.mkOption {
                          type = lib.types.enum [
                            "ext4"
                            "xfs"
                            "btrfs"
                          ];
                        };
                        swap.enable = lib.mkOption {
                          type = lib.types.bool;
                        };
                      };
                    }
                  );
                  default = null;
                };
              };
            }
            (lib.optionalAttrs (groupName != "") {
              _file = entrypointLoc {
                pubic = true;
                common = true;
              };
              config = lib.mkOverride 1000 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } commonPublic
              );
            })
            (lib.optionalAttrs (groupName != "") {
              _file = entrypointLoc {
                pubic = false;
                common = true;
              };
              config = lib.mkOverride 1001 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } commonPrivate
              );
            })
            {
              _file = entrypointLoc {
                pubic = true;
                common = false;
              };
              config = lib.mkOverride 1002 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } nodePublic
              );
            }
            {
              _file = entrypointLoc {
                pubic = false;
                common = false;
              };
              config = lib.mkOverride 1003 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } nodePrivate
              );
            }
          ];
        }).config;
      inherit (node) os channel;
      configurationPaths =
        let
          paths =
            if groupName == "" then
              optionalPath "${publicDir}/${nodeSubdir}/configuration.nix"
              ++ optionalPath "${privateDir}/${nodeSubdir}/configuration.nix"
            else
              optionalPath "${publicDir}/${commonSubdir}/configuration.nix"
              ++ optionalPath "${privateDir}/${commonSubdir}/configuration.nix"
              ++ optionalPath "${publicDir}/${nodeSubdir}/configuration.nix"
              ++ optionalPath "${privateDir}/${nodeSubdir}/configuration.nix";
        in
        assert lib.assertMsg (lib.length paths != 0)
          "Missing nodes${
            lib.optionalString (groupName != "") "/${groupName}"
          }/${nodeName}/configuration.nix";
        paths
        ++ (
          lib.optionals (groupName != "") (
            optionalPath "${publicDir}/${commonSubdir}/hardware-configuration.nix"
            ++ optionalPath "${privateDir}/${commonSubdir}/hardware-configuration.nix"
          )
          ++ optionalPath "${publicDir}/${nodeSubdir}/hardware-configuration.nix"
          ++ optionalPath "${privateDir}/${nodeSubdir}/hardware-configuration.nix"
        );
      homeManagerUsers =
        lib.zipAttrsWith
          (userName: paths: {
            homePaths = paths;
          })
          (
            lib.optionals (groupName != "") (
              getHomePaths "${publicDir}/${commonSubdir}" ++ getHomePaths "${privateDir}/${commonSubdir}"
            )
            ++ getHomePaths "${publicDir}/${nodeSubdir}"
            ++ getHomePaths "${privateDir}/${nodeSubdir}"
          );
      getHomePaths =
        dir:
        let
          d = "${dir}/home";
        in
        if lib.pathExists d then
          lib'.concatMapAttrsToList (
            userName: v:
            if v == "directory" && lib.pathExists "${d}/${userName}/home.nix" then
              [
                {
                  ${userName} = "${d}/${userName}/home.nix";
                }
              ]
            else
              [ ]
          ) (builtins.readDir d)
        else
          [ ];
      hasSshHostKey =
        let
          subpath = "${nodeSubdir}/fs/etc/ssh/ssh_host_ed25519_key.pub";
        in
        lib.pathExists "${privateDir}/${subpath}" || lib.pathExists "${publicDir}/${subpath}";
      secretsYamlPath =
        let
          paths =
            optionalPath "${privateDir}/${nodeSubdir}/secrets.yaml"
            ++ optionalPath "${publicDir}/${nodeSubdir}/secrets.yaml";
        in
        if lib.length paths == 0 then
          ""
        else if lib.length paths == 1 then
          lib.head paths
        else
          lib.warn "secrets.yaml exists in both ${nodeSubdir} and private/${nodeSubdir}, only using the latter" (
            lib.head paths
          );
      mkSystem =
        {
          nixos = inputs.nixpkgs.lib.nixosSystem;
          darwin = inputs.nix-darwin.lib.darwinSystem;
        }
        .${os};
      nodes = lib.mapAttrs' (
        name: entity:
        if entity.type == "node" then
          let
            group = if entity.node.group == "" then null else entities.${entity.node.group}.group;
          in
          if name == nodeName then
            lib.nameValuePair "current" (
              lib.removeAttrs entity.node [ "config" ]
              // {
                inherit group;
              }
            )
          else
            lib.nameValuePair name (
              entity.node
              // {
                inherit group;
              }
            )
        else
          lib.nameValuePair name entity.group
      ) entities;
      configuration = mkSystem {
        specialArgs = {
          inherit inputs nodes;
          lib' = nodeLib;
          modules' =
            {
              nixos = nixosModules;
              darwin = darwinModules;
            }
            .${os};
        };
        modules =
          [
            (
              {
                config,
                pkgs,
                lib,
                ...
              }:
              let
                inherit (config.nixpkgs.hostPlatform) system;
                pkgs' = lib.mapAttrs (name: v: pkgs.callPackage v { }) allPkgs;
              in
              {
                _module.args =
                  {
                    inherit pkgs';
                  }
                  // lib.optionalAttrs (node.channel != "unstable" && flake.inputs ? nixpkgs-unstable) {
                    pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
                  };
                networking.hostName = lib.mkDefault nodes.current.name;
              }
            )
          ]
          ++
            lib.optional
              (
                node.parititions != null
                && lib.elem node.parititions.boot.type [
                  "efi"
                  "bios"
                ]
              )
              {
                fileSystems."/" = {
                  device = "/dev/disk/by-partlabel/root";
                  fsType = node.parititions.root.format;
                };
                swapDevices = lib.optional node.parititions.swap.enable {
                  device = "/dev/disk/by-partlabel/swap";
                };
              }
          ++ lib.optional hasSshHostKey {
            imports = [ inputs.sops-nix.nixosModules.sops ];
            services.openssh.hostKeys = [ ];
            sops.age =
              {
                sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
              }
              // lib.optionalAttrs (secretsYamlPath != "") {
                defaultSopsFile = lib.mkDefault secretsYamlPath;
              };
          }
          ++ lib.optional (node.os == "nixos") (
            { pkgs, ... }:
            {
              # Needed for syncing fs when deploying
              environment.systemPackages = [ pkgs.rsync ];
            }
          )
          ++ lib.optional (homeManagerUsers != { }) (
            { pkgs', ... }:
            {
              imports = [
                {
                  nixos = inputs.home-manager.nixosModules.home-manager;
                  darwin = inputs.home-manager.darwinModules.home-manager;
                }
                .${os}
              ];
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit
                    lib'
                    pkgs'
                    inputs
                    nodes
                    ;
                  modules' = homeManagerModules;
                };
                users = lib.mapAttrs (
                  _:
                  { homePaths }:
                  {
                    imports = homePaths;
                  }
                ) homeManagerUsers;
              };
            }
          )
          ++ configurationPaths;
      };
    in
    {
      type = "node";
      node = node // {
        inherit (configuration) config;
      };
      inherit configuration;
    };
  importDirOrFile =
    base: name: default:
    (importDirAttrs base).${name} or default;
  importDirAttrs =
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
  call = f: args: if lib.isFunction f then f (lib.intersectAttrs (lib.functionArgs f) args) else f;
  joinPath =
    parts:
    "${lib.head parts}${
      lib.concatStrings (map (part: if part == "" then "" else "/${part}") (lib.drop 1 parts))
    }";
  optionalPath = path: if lib.pathExists path then [ path ] else [ ];
  filterRecursive =
    pred: sl:
    if lib.isAttrs sl then
      lib'.concatMapListToAttrs (
        name:
        let
          v = sl.${name};
        in
        if pred name v then
          [
            (lib.nameValuePair name (filterRecursive pred v))
          ]
        else
          [ ]
      ) (lib.attrNames sl)
    else if lib.isList sl then
      map (lib'.filterRecursive pred) sl
    else
      sl;
in
{
  inherit nixosModules darwinModules homeManagerModules;
  packages = lib'.forAllSystems (
    system:
    let
      pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
    in
    lib.mapAttrs (_: v: pkgs.callPackage v { }) allPkgs
  );
  nixosConfigurations = loadConfigurations "nixos";
  darwinConfigurations = loadConfigurations "darwin";
  nodes = lib.mapAttrs (
    _: entity:
    if entity.type == "node" then
      {
        inherit (entity) type;
        node = filterRecursive (n: v: !(lib.isFunction v)) (
          lib.removeAttrs entity.node (
            [ "config" ] ++ lib.optional (entity.node.parititions == null) "parititions"
          )
        );
      }
    else
      entity
      // {
        group = entity.group // {
          nodes = lib.mapAttrs (_: _: true) entity.group.nodes;
        };
      }
  ) entities;
}
