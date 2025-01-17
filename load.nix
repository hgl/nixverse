{
  lib,
  lib',
}:
flakeMain:
let
  flakeOverride = if flakeMain.inputs ? override then flakeMain.inputs.override else null;
  allInputs = flakeMain.inputs or { } // flakeOverride.inputs or { };
  allPkgs =
    importDirAttrs "${flakeMain}/pkgs"
    // lib.optionalAttrs (flakeOverride != null) (importDirAttrs "${flakeOverride}/pkgs");
  nixosModules =
    importDirAttrs "${flakeMain}/modules/nixos"
    // lib.optionalAttrs (flakeOverride != null) (importDirAttrs "${flakeOverride}/modules/nixos");
  darwinModules =
    importDirAttrs "${flakeMain}/modules/darwin"
    // lib.optionalAttrs (flakeOverride != null) (importDirAttrs "${flakeOverride}/modules/darwin");
  homeManagerModules =
    importDirAttrs "${flakeMain}/modules/homeManager"
    // lib.optionalAttrs (flakeOverride != null) (
      importDirAttrs "${flakeOverride}/modules/homeManager"
    );
  loadConfigurations =
    os:
    lib.mapAttrs (_: entity: loadConfiguration entity) (
      lib.filterAttrs (_: entity: entity.type == "node" && entity.node.os == os) entities
    );
  loadConfiguration =
    entity@{
      node,
      inputs,
      configurationPaths,
      hardwareConfigurationPaths,
      secrets,
      homeManagerUsers,
      ...
    }:
    let
      inherit (node) os;
      mkSystem =
        {
          nixos = inputs.nixpkgs.lib.nixosSystem;
          darwin = inputs.nix-darwin.lib.darwinSystem;
        }
        .${os};
      modules =
        {
          nixos = nixosModules;
          darwin = darwinModules;
        }
        .${os};
      homeMangagerModule =
        {
          nixos = inputs.home-manager.nixosModules.home-manager;
          darwin = inputs.home-manager.darwinModules.home-manager;
        }
        .${os};
    in
    mkSystem {
      specialArgs = {
        inherit inputs node;
        lib' = entity.lib;
        modules' = modules;
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
                // lib.optionalAttrs (node.channel != "unstable" && allInputs ? nixpkgs-unstable) {
                  pkgs-unstable = allInputs.nixpkgs-unstable.legacyPackages.${system};
                };
              networking.hostName = lib.mkDefault node.name;
            }
          )
        ]
        ++
          lib.optional
            (
              node.parititions != null
              && lib.elem node.parititions.bootType [
                "efi"
                "bios"
              ]
            )
            {
              fileSystems."/" = {
                device = "/dev/disk/by-partlabel/root";
                fsType = node.parititions.format;
              };
              swapDevices = lib.optional node.parititions.swan.enable {
                device = "/dev/disk/by-partlabel/swap";
              };
            }
        ++ lib.optional (secrets != null) {
          imports = [ inputs.sops-nix.nixosModules.sops-nix ];
          services.openssh.hostKeys = [ ];
          sops.age =
            {
              sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
            }
            // lib.optionalAttrs (secrets.secretsYamlPath != "") {
              defaultSopsFile = lib.mkDefault secrets.secretsYamlPath;
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
            imports = [ homeMangagerModule ];
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit
                  lib'
                  pkgs'
                  inputs
                  node
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
        ++ configurationPaths
        ++ hardwareConfigurationPaths;
    };
  entities = lib.zipAttrsWith (
    name: values:
    let
      desc =
        entity:
        if entity.type == "node" then
          if entity.node.group == "" then
            "${
              lib.optionalString (!(lib.pathExists "${flakeMain}/nodes/${name}/node.nix")) "<override>/"
            }nodes/${name}/node.nix"
          else
            "${
              lib.optionalString (
                !(lib.pathExists "${flakeMain}/nodes/${entity.node.group}/nodes.nix")
              ) "<override>/"
            }nodes/${entity.node.group}/nodes.nix#${name}"
        else
          "${
            lib.optionalString (!(lib.pathExists "${flakeMain}/nodes/${name}/group.nix")) "<override>/"
          }nodes/${name}/group.nix";
      first = lib.elemAt values 0;
      second = lib.elemAt values 1;
    in
    assert lib.assertMsg (
      lib.length values == 1
    ) "${name} is defined by two different types of nodes:\n- ${desc first}\n- ${desc second}";
    first
  ) entityList;
  entityList = lib.mapAttrsToList (
    name: base:
    assert lib.assertMsg (name != "common")
      "\"common\" is a reserved node name, cannot be used for ${
        lib.optionalString (base.main == null) "<override>/"
      }nodes/common/${base.entrypoint}";
    if base.entrypoint == "node.nix" then
      loadNode {
        nodeName = name;
        inherit base;
      }
    else if base.entrypoint == "nodes.nix" then
      loadNodes {
        groupName = name;
        inherit base;
      }
    else
      loadGroup {
        groupName = name;
        inherit base;
      }
  ) entityDirs;
  entityDirs =
    let
      dirsMain = loadEntityDirs flakeMain;
      dirsOverride = lib.optionalAttrs (flakeOverride != null) (loadEntityDirs flakeOverride);
    in
    lib.zipAttrsWith
      (
        name: dirList:
        let
          first = lib.elemAt dirList 0;
          second = lib.elemAt dirList 1;
        in
        {
          inherit (first) entrypoint;
        }
        // (
          if lib.length dirList == 2 then
            assert lib.assertMsg (first.entrypoint == second.entrypoint)
              "Node type mismatch: ${name} is defined both in nodes/${name}/${first.entrypoint} and <override>/nodes/${name}/${second.entrypoint}";
            {
              main = first.outPath;
              override = second.outPath;
            }
          else if lib.hasAttr name dirsMain then
            {
              main = first.outPath;
              override = "";
            }
          else
            {
              main = "";
              override = first.outPath;
            }
        )
      )
      [
        dirsMain
        dirsOverride
      ];
  loadEntityDirs =
    dir:
    if lib.pathExists "${dir}/nodes" then
      lib.concatMapAttrs (
        name: v:
        if v == "directory" then
          let
            base = "${dir}/nodes/${name}";
          in
          if lib.pathExists "${base}/node.nix" then
            {
              ${name} = {
                entrypoint = "node.nix";
                outPath = base;
              };
            }
          else if lib.pathExists "${base}/nodes.nix" then
            {
              ${name} = {
                entrypoint = "nodes.nix";
                outPath = base;
              };
            }
          else if lib.pathExists "${base}/group.nix" then
            {
              ${name} = {
                entrypoint = "group.nix";
                outPath = base;
              };
            }
          else
            { }
        else
          { }
      ) (builtins.readDir "${dir}/nodes")
    else
      { };
  loadNode =
    {
      nodeName,
      base,
    }:
    {
      ${nodeName} =
        {
          type = "node";
        }
        // loadRawNode {
          groupName = "";
          inherit nodeName base;
          rawNode = {
            main = lib.optionalAttrs (base.main != "") (import "${base.main}/${base.entrypoint}");
            override = lib.optionalAttrs (base.override != "") (import "${base.override}/${base.entrypoint}");
          };
        };
    };
  loadNodes =
    {
      groupName,
      base,
    }:
    let
      loadRaw =
        dir:
        lib.optionalAttrs (dir != "") (
          let
            v = import "${dir}/nodes.nix";
          in
          assert lib.assertMsg (lib.isAttrs v)
            "${
              lib.optionalString (dir == base.override) "<override>/"
            }nodes/${groupName}/nodes.nix must evaluate to an attribute set";
          assert lib.assertMsg
            (lib.all (nodeName: nodeName == "common" || nodeName != groupName) (lib.attrNames v))
            "${
              lib.optionalString (dir == base.override) "<override>/"
            }nodes/${groupName}/nodes.nix must not contain a node named ${groupName}, which is the same as the group name";
          v
        );
      rawMain = loadRaw base.main;
      rawOverride = loadRaw base.override;
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
              inherit base;
              rawCommon = {
                main = rawMain.common or null;
                override = rawOverride.common or null;
              };
              rawNode =
                if lib.length raws == 2 then
                  {
                    main = first;
                    override = second;
                  }
                else if lib.hasAttr nodeName rawMain then
                  {
                    main = first;
                    override = null;
                  }
                else
                  {
                    main = null;
                    override = first;
                  };
            }
          )
          ([
            (lib.removeAttrs rawMain [ "common" ])
            (lib.removeAttrs rawOverride [ "common" ])
          ]);
    in
    {
      ${groupName} = {
        type = "group";
        group =
          let
            names = lib.attrNames nodes;
          in
          {
            children = names;
            nodes = names;
          };
      };
    }
    // lib.mapAttrs (
      nodeName: node:
      {
        type = "node";
      }
      // node
    ) nodes;
  loadGroup =
    {
      groupName,
      base,
    }:
    let
      loadRaw =
        dir:
        lib.optionalAttrs (dir != "") (
          let
            raw = import "${dir}/group.nix";
            v =
              (lib.evalModules {
                modules = [
                  {
                    _file = "${lib.optionalString (dir == base.override) "<override>/"}nodes/${groupName}/group.nix";
                    options.children = lib.mkOption {
                      type = lib.types.nonEmptyListOf lib.types.nonEmptyStr;
                    };
                    config = raw;
                  }
                ];
              }).config;
            findNodes =
              {
                parent,
                children,
                visited,
                path,
              }:
              lib.concatMap (
                child:
                assert lib.assertMsg (!(lib.hasAttr child visited))
                  "circular group containment: ${lib.concatStringsSep " > " (path ++ [ child ])}";
                if entities.${child}.type == "node" then
                  [ child ]
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
          in
          assert lib.assertMsg (lib.isAttrs raw)
            "${
              lib.optionalString (dir == base.override) "<override>/"
            }nodes/${groupName}/group.nix must evaluate to an attribute set";
          assert lib.assertMsg (lib.all (name: name != groupName) v.children)
            "${
              lib.optionalString (dir == base.override) "<override>/"
            }nodes/${groupName}/group.nix#children must not contain the group's own name";
          assert lib.assertMsg (lib.all (name: name != "common") v.children)
            "\"common\" is a reserved node name, cannot be used in ${
              lib.optionalString (dir == base.override) "<override>/"
            }nodes/${groupName}/group.nix#children";
          assert lib.all (
            name:
            assert lib.assertMsg (lib.hasAttr name entities)
              "${
                lib.optionalString (dir == base.override) "<override>/"
              }nodes/${groupName}/group.nix#children contains unknown node ${name}";
            true
          ) v.children;
          v
          // {
            nodes = findNodes {
              parent = groupName;
              inherit (group) children;
              visited = {
                ${groupName} = true;
              };
              path = [
                groupName
              ];
            };
          }
        );
      groupMain = loadRaw base.main;
      groupOverride = loadRaw base.override;
      group = {
        children = lib.unique (groupMain.children or [ ] ++ groupOverride.children or [ ]);
        nodes = lib.unique (groupMain.nodes or [ ] // groupOverride.nodes or [ ]);
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
      base,
      rawCommon ? null,
      rawNode,
    }:
    let
      inputs =
        if channel == "unstable" then
          lib.concatMapAttrs (
            inputName: input:
            if lib.hasSuffix "-unstable-${os}" inputName then
              { ${lib.removeSuffix "-unstable-${os}" inputName} = input; }
            else if lib.hasSuffix "-unstable" inputName then
              { ${lib.removeSuffix "-unstable" inputName} = input; }
            else
              { }
          ) allInputs
        else
          lib.concatMapAttrs (
            inputName: input:
            if lib.hasSuffix "-unstable-${os}" inputName then
              { ${lib.removeSuffix "-${os}" inputName} = input; }
            else if lib.hasSuffix "-unstable" inputName then
              { ${inputName} = input; }
            else if lib.hasSuffix "-${channel}-${os}" inputName then
              { ${lib.removeSuffix "-${channel}-${os}" inputName} = input; }
            else if lib.hasSuffix "-${channel}" inputName then
              { ${lib.removeSuffix "-${channel}" inputName} = input; }
            else
              { }
          ) allInputs;
      loadLib =
        {
          dir,
          subdir ? "",
          lib',
        }:
        let
          args = {
            inherit (inputs.nixpkgs) lib;
            inherit inputs lib';
          };
          libMain = lib.optionalAttrs (dir.main != "") (
            call (importDirOrFile (joinPath [
              dir.main
              subdir
            ]) "lib" { }) args
          );
          libOverride = lib.optionalAttrs (dir.override != "") (
            call (importDirOrFile (joinPath [
              dir.override
              subdir
            ]) "lib" { }) args
          );
        in
        lib.recursiveUpdate libMain libOverride;
      topLib = loadLib {
        dir = {
          main = flakeMain.outPath;
          override = lib.optionalString (flakeOverride != null) flakeOverride.outPath;
        };
        lib' = topLib;
      };
      nodeLib =
        if groupName == "" then
          lib.recursiveUpdate topLib (loadLib {
            dir = base;
            lib' = nodeLib;
          })
        else
          let
            groupLib = lib.recursiveUpdate topLib (loadLib {
              dir = base;
              subdir = "common";
              lib' = groupLib;
            });
          in
          lib.recursiveUpdate groupLib (loadLib {
            dir = base;
            subdir = nodeName;
            lib' = nodeLib;
          });
      loadRaw =
        part:
        let
          raw =
            if part.common then
              if !part.override then rawCommon.main else rawCommon.override
            else if !part.override then
              rawNode.main
            else
              rawNode.override;
          attrName = if part.common then "common" else nodeName;
          v = lib.optionalAttrs (raw != null) (call raw nodeArgs);
        in
        assert lib.assertMsg (lib.isAttrs v)
          "${lib.optionalString part.override "<override>/"}nodes/${nodeName}/nodes.nix#${attrName} must evaluate to an attribute set";
        assert lib.assertMsg (!(v ? name))
          "Must not specify \"name\" in ${lib.optionalString part.override "<override>/"}nodes/${nodeName}/nodes.nix#${attrName}";
        assert lib.assertMsg (!(v ? group))
          "Must not specify \"group\" in ${lib.optionalString part.override "<override>/"}nodes/${nodeName}/nodes.nix#${attrName}";
        v;
      commonMain = loadRaw {
        common = true;
        override = false;
      };
      commonOverride = loadRaw {
        common = true;
        override = true;
      };
      common = lib.recursiveUpdate commonMain commonOverride;
      nodeArgs =
        {
          inherit (inputs.nixpkgs) lib;
          inherit node inputs;
          lib' = nodeLib;
        }
        // lib.optionalAttrs (groupName != "") {
          inherit common;
        };
      nodeMain = loadRaw {
        common = false;
        override = false;
      };
      nodeOverride = loadRaw {
        common = false;
        override = true;
      };
      node =
        let
          n = lib.recursiveUpdate (lib.optionalAttrs (groupName != "") common) (
            lib.recursiveUpdate nodeMain nodeOverride
          );
        in
        assert lib.assertMsg (n ? os) (
          if groupName == "" then
            "Missing \"os\" in nodes/${nodeName}/node.nix"
          else
            "Missing \"os\" in nodes/${groupName}/nodes.nix#${nodeName}"
        );
        assert lib.assertMsg (n ? channel) (
          if groupName == "" then
            "Missing \"channel\" in nodes/${nodeName}/node.nix"
          else
            "Missing \"channel\" in nodes/${groupName}/nodes.nix#${nodeName}"
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
              _file = "nodes/${nodeName}/common.nix";
              config = lib.mkOverride 1000 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                } commonMain
              );
            })
            (lib.optionalAttrs (groupName != "") {
              _file = "<override>/nodes/${nodeName}/common.nix";
              config = lib.mkOverride 1001 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } commonOverride
              );
            })
            {
              _file = "${
                if groupName == "" then "nodes/${nodeName}/node.nix" else "nodes/${groupName}/nodes.nix#${nodeName}"
              }";
              config = lib.mkOverride 1002 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } nodeMain
              );
            }
            {
              _file = "${
                if groupName == "" then
                  "<override>/nodes/${nodeName}/node.nix"
                else
                  "<override>/nodes/${groupName}/nodes.nix#${nodeName}"
              }";
              config = lib.mkOverride 1003 (
                lib.intersectAttrs {
                  os = true;
                  channel = true;
                  parititions = true;
                } nodeOverride
              );
            }
          ];
        }).config;
      inherit (node) os channel;
      configurationPaths =
        let
          paths =
            if groupName == "" then
              getPaths base.main "configuration.nix" ++ getPaths base.override "configuration.nix"
            else
              getPaths base.main "common/configuration.nix"
              ++ getPaths base.override "common/configuration.nix"
              ++ getPaths base.main "${nodeName}/configuration.nix"
              ++ getPaths base.override "${nodeName}/configuration.nix";
        in
        assert lib.assertMsg (lib.length paths != 0) (
          if groupName == "" then
            "Missing nodes/${nodeName}/configuration.nix"
          else
            "Missing nodes/${groupName}/${node}/configuration.nix"
        );
        paths;
      getPaths =
        dir: subpath:
        lib.optionals (dir != "") (
          optionalPath "${joinPath [
            dir
            subpath
          ]}"
        );
      hardwareConfigurationPaths =
        if groupName == "" then
          getPaths base.main "hardware-configuration.nix"
          ++ getPaths base.override "hardware-configuration.nix"
        else
          getPaths base.main "common/hardware-configuration.nix"
          ++ getPaths base.override "common/hardware-configuration.nix"
          ++ getPaths base.main "${nodeName}/hardware-configuration.nix"
          ++ getPaths base.override "${nodeName}/hardware-configuration.nix";
      homeManagerUsers =
        lib.zipAttrsWith
          (userName: paths: {
            homePaths = paths;
          })
          (
            if groupName == "" then
              getHomePaths base.main "" ++ getHomePaths base.override ""
            else
              getHomePaths base.main "common"
              ++ getHomePaths base.override "common"
              ++ getHomePaths base.main nodeName
              ++ getHomePaths base.override nodeName
          );
      getHomePaths =
        dir: subdir:
        let
          findPaths =
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
        in
        lib.optionals (dir != "") (
          findPaths (joinPath [
            dir
            subdir
          ])
        );
      hasSshHostKey =
        dir:
        dir != ""
        && lib.pathExists (joinPath [
          "${dir}/nodes"
          groupName
          "${nodeName}/fs/etc/ssh/ssh_host_ed25519_key.pub"
        ]);
      secretsYamlPath =
        let
          paths = getPaths base.main "secrets.yaml" ++ getPaths base.override "secrets.yaml";
        in
        if lib.length paths == 0 then
          ""
        else if lib.length paths == 1 then
          lib.elemAt paths 0
        else
          let
            dir = joinPath [
              "nodes"
              groupName
              nodeName
            ];
          in
          lib.warn "secrets.yaml exists in both ${dir} and <override>/${dir}, only using the latter" (
            lib.elemAt paths 1
          );
    in
    {
      type = "node";
      inherit
        node
        inputs
        configurationPaths
        hardwareConfigurationPaths
        homeManagerUsers
        ;
      lib = nodeLib;
      secrets =
        if hasSshHostKey base.main || hasSshHostKey base.override then
          {
            inherit secretsYamlPath;
          }
        else
          null;
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
  joinPath = parts: "${lib.concatStrings (map (part: if part == "" then "" else "/${part}") parts)}";
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
      pkgs = flakeMain.inputs.nixpkgs-unstable.legacyPackages.${system};
    in
    lib.mapAttrs (_: v: pkgs.callPackage v { }) allPkgs
  );
  nixosConfigurations = loadConfigurations "nixos";
  darwinConfigurations = loadConfigurations "darwin";
  nodes = lib.mapAttrs (
    name: entity:
    if entity.type == "node" then
      {
        inherit (entity) type;
        node = filterRecursive (n: v: !(lib.isFunction v)) entity.node;
      }
    else
      entity
  ) entities;
}
