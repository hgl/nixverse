{
  lib,
  lib',
  flake,
}:
let
  publicDir = flake.outPath;
  privateDir = "${publicDir}/private";
  final = {
    pkgs = importDirAttrs "${publicDir}/pkgs" // importDirAttrs "${privateDir}/pkgs";
    nixosModules =
      importDirAttrs "${publicDir}/modules/nixos"
      // importDirAttrs "${privateDir}/modules/nixos";
    darwinModules =
      importDirAttrs "${publicDir}/modules/darwin"
      // importDirAttrs "${privateDir}/modules/darwin";
    homeManagerModules =
      importDirAttrs "${publicDir}/modules/homeManager"
      // importDirAttrs "${privateDir}/modules/homeManager";
    nixosConfigurations = loadConfigurations "nixos";
    darwinConfigurations = loadConfigurations "darwin";
    # Expose for tests
    flakePath = publicDir;
    entities = lib.mapAttrs (
      name: entityObj:
      {
        node = loadNode name;
        group = loadGroup name;
      }
      .${entityObj.type}
    ) entityObjs;
    nixverse = {
      inherit lib lib';
      nodesMakefileVars =
        let
          inherit (segregateEntityNames (lib.attrNames final.entities)) nodes groups;
        in
        ''
          .PHONY: ${toString (map (nodeName: "nodes/${nodeName}") (lib.attrNames nodes))}
          ${toString (
            lib.concatStringsSep "\n" (
              lib.concatMap (
                groupName:
                let
                  group = final.entities.${groupName};
                  childNodes = lib.filter (childName: final.entities.${childName}.type == "node") group.childNames;
                in
                if childNodes == [ ] then [ ] else [ "${groupName}_node_names := ${toString childNodes}" ]
              ) (lib.attrNames groups)
            )
          )}
          ${toString (
            lib.concatStringsSep "\n" (
              lib.concatMap (
                nodeName:
                let
                  node = final.entities.${nodeName};
                in
                [
                  "node_${nodeName}_os := ${node.value.os}"
                  "node_${nodeName}_channel := ${node.value.channel}"
                ]
              ) (lib.attrNames nodes)
            )
          )}
        '';
      getNodesMakefileTargets =
        entityNames:
        toString (map (nodeName: "nodes/${nodeName}") (findNodeNames (normalizeEntityNames entityNames)));
      getNodeBuildJobs =
        entityNames:
        let
          nodeNames = findNodeNames (normalizeEntityNames entityNames);
        in
        lib.concatMap (
          nodeName:
          let
            node = final.entities.${nodeName};
          in
          if node.value.deploy.buildHost != "" then
            [ ]
          else
            [
              {
                name = nodeName;
                command = "build_node ${toShellValue flake} ${toShellValue nodeName} ${toShellValue node.value.os}";
              }
            ]
        ) nodeNames;
      getNodeDeployJobs =
        entityNames:
        let
          nodeNames = findNodeNames (normalizeEntityNames entityNames);
          numNode = lib.length nodeNames;
        in
        map (
          nodeName:
          let
            node = final.entities.${nodeName};
          in
          assert lib.assertMsg (
            numNode != 1 -> node.deploy.targetHost != ""
          ) "deploy multiple nodes to local is not allowed";
          {
            name = nodeName;
            command = "deploy_node ${toShellValue flake} ${toShellValue nodeName} ${toShellValue node.value.os} ${toShellValue node.value.deploy.targetHost} ${toShellValue node.value.deploy.buildHost} ${toShellValue node.value.deploy.buildHost} ${toShellValue node.value.deploy.useRemoteSudo} ${toShellValue node.value.deploy.sshOpts}";
          }
        ) nodeNames;
      getNodeValueData =
        entityNames:
        let
          inherit (segregateEntityNames (normalizeEntityNames entityNames)) nodes groups;
        in
        lib.mapAttrs (
          groupName: _:
          let
            group = final.entities.${groupName};
          in
          {
            inherit (group) type;
            name = groupName;
            parents = group.parentNames;
            children = group.childNames;
          }
        ) groups
        // lib.mapAttrs (
          nodeName: _:
          let
            node = final.entities.${nodeName};
          in
          filterRecursive (_: v: !(lib.isFunction v)) (lib.removeAttrs node.value [ "config" ])
        ) nodes;
      getSecretsMakefileVars =
        entityNames:
        let
          nodeNames = findNodeNames entityNames;
        in
        ''
          node_names := ${toString nodeNames}
          ${lib.concatStringsSep "\n" (
            lib.concatMap (
              nodeName:
              let
                entityObj = entityObjs.${nodeName};
              in
              [
                "node_${nodeName}_dir := ${
                  if entityObj.rawValue == null then
                    "nodes/${lib.head entityObj.parentNames}/${nodeName}"
                  else
                    "nodes/${nodeName}"
                }"
                "node_${nodeName}_secrets_sections := ${
                  toString (
                    map ({ parentName, ... }: parentName) (lib.reverseList (findAncestorNames nodeName)) ++ [ nodeName ]
                  )
                }"
              ]
            ) nodeNames
          )}
        '';
    };
  };
  loadConfigurations =
    os:
    lib.concatMapAttrs (
      name: entity:
      if entity.type == "node" && entity.value.os == os then
        {
          ${name} = entity.configuration;
        }
      else
        { }
    ) final.entities;
  entityObjs =
    lib.zipAttrsWith
      (
        _: objs:
        let
          inherit (lib.findFirst (obj: obj ? type) { type = "node"; } objs) type;
        in
        {
          inherit type;
          inherit (lib.findFirst (obj: obj ? rawValue) { rawValue = null; } objs) rawValue;
          parentNames = lib.attrNames (
            lib'.concatMapListToAttrs (
              obj: if obj ? parentName then { ${obj.parentName} = true; } else { }
            ) objs
          );
        }
        // {
          node = { };
          group = {
            inherit (lib.findFirst (obj: obj ? childNames) (throw "impossible") objs) childNames;
          };
        }
        .${type}
      )
      (
        lib'.concatMapAttrsToList (
          entityName:
          { type, publicExist, ... }:
          let
            loc = "${lib.optionalString (!publicExist) "private/"}nodes/${entityName}/${type}.nix";
          in
          assert lib.assertMsg (entityName != "common") "\"common\" is a reserved node name: ${loc}";
          assert lib.assertMsg (entityName != "current") "\"current\" is a reserved node name: ${loc}";
          {
            node =
              let
                subpath = "nodes/${entityName}/node.nix";
                load =
                  dir:
                  let
                    path = "${dir}/${subpath}";
                    v = import path;
                  in
                  lib.optionalAttrs (lib.pathExists path) {
                    ${if dir == publicDir then "public" else "private"} = v;
                  };
              in
              [
                {
                  ${entityName} = {
                    type = "node";
                    rawValue = load publicDir // load privateDir;
                  };
                }
              ];
            group =
              let
                rawValue = load publicDir // load privateDir;
                subpath = "nodes/${entityName}/group.nix";
                load =
                  dir:
                  let
                    path = "${dir}/${subpath}";
                    v = import path;
                    names = lib.attrNames v;
                    loc = "${lib.optionalString (dir == privateDir) "private/"}${subpath}";
                  in
                  {
                    ${if dir == publicDir then "public" else "private"} = lib.optionalAttrs (lib.pathExists path) (
                      assert lib.assertMsg (lib.isAttrs v) "${loc} must evaluate to an attribute set";
                      assert lib.assertMsg (lib.all (name: name != entityName) names) "${loc} must not contain itself";
                      assert lib.all (
                        name:
                        assert lib.assertMsg (name != "current") "\"current\" is a reserved node name: ${loc}";
                        true
                      ) names;
                      v
                    );
                  };
                childNames =
                  let
                    v =
                      lib.optionalAttrs (rawValue.public != null) (lib.removeAttrs rawValue.public [ "common" ])
                      // lib.optionalAttrs (rawValue.private != null) (lib.removeAttrs rawValue.private [ "common" ]);
                  in
                  assert lib.assertMsg (v != { }) "${subpath} must contain at least one child";
                  lib.attrNames v;
              in
              [
                {
                  ${entityName} = {
                    type = "group";
                    inherit rawValue childNames;
                  };
                }
              ]
              ++ map (childName: {
                ${childName} = {
                  parentName = entityName;
                };
              }) childNames;
          }
          .${type}
        ) entityDirs
      );
  entityDirs =
    let
      typesPublic = loadEntityTypes publicDir;
      typesPrivate = loadEntityTypes privateDir;
    in
    lib.zipAttrsWith
      (
        entityName: dirList:
        let
          first = lib.elemAt dirList 0;
          second = lib.elemAt dirList 1;
        in
        (
          if lib.length dirList == 2 then
            assert lib.assertMsg (first == second)
              "Node type mismatch: ${entityName} is defined both in nodes/${entityName}/${first}.nix and private/nodes/${entityName}/${second}.nix";
            {
              type = first;
              publicExist = true;
              privateExist = true;
            }
          else if lib.hasAttr entityName typesPublic then
            {
              type = first;
              publicExist = true;
              privateExist = false;
            }
          else
            {
              type = first;
              publicExist = false;
              privateExist = true;
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
        entityName: v:
        if v == "directory" then
          let
            d = "${dir}/nodes/${entityName}";
          in
          if lib.pathExists "${d}/node.nix" then
            { ${entityName} = "node"; }
          else if lib.pathExists "${d}/group.nix" then
            { ${entityName} = "group"; }
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
      inherit (entityObjs.${nodeName}) rawValue parentNames;
      inherit (nodeValue) os channel;
      nodeValue =
        builtins.foldl' (
          accu: { value, ... }: lib.recursiveUpdate accu (lib.removeAttrs value (lib.attrNames nodeOptions))
        ) { } valueLocs
        // (lib.evalModules {
          modules =
            [
              { options = nodeOptions; }
            ]
            ++ lib.imap0 (
              i:
              { value, loc }:
              {
                _file = loc;
                config = lib.mkOverride (1000 + i) (lib.intersectAttrs nodeOptions value);
              }
            ) valueLocs;
        }).config
        // {
          type = "node";
          name = nodeName;
          parents = parentNames;
          inherit (configuration) config;
        };
      valueLocs =
        let
          merged =
            builtins.foldl'
              (
                { values, value }:
                { parentName, entityName }:
                let
                  inherit (entityObjs.${parentName}) rawValue;
                  commonPublic =
                    if rawValue.public ? common then
                      let
                        v = lib.recursiveUpdate value (
                          loadValue rawValue.public.common loc { common = commonPrivate.value; }
                        );
                        loc = "nodes/${parentName}/group.nix#common";
                      in
                      {
                        optional = [
                          {
                            value = v;
                            inherit loc;
                          }
                        ];
                        value = v;
                      }
                    else
                      {
                        optional = [ ];
                        inherit value;
                      };
                  commonPrivate =
                    if rawValue.private ? common then
                      let
                        v = lib.recursiveUpdate commonPublic.value (
                          loadValue rawValue.private.common loc { common = commonPrivate.value; }
                        );
                        loc = "private/nodes/${parentName}/group.nix#common";
                      in
                      {
                        optional = [
                          {
                            value = v;
                            inherit loc;
                          }
                        ];
                        value = v;
                      }
                    else
                      {
                        optional = [ ];
                        value = commonPublic.value;
                      };
                  childPublic =
                    if lib.hasAttr entityName rawValue.public then
                      let
                        v = lib.recursiveUpdate commonPrivate.value (
                          loadValue rawValue.public.${entityName} loc { common = commonPrivate.value; }
                        );
                        loc = "nodes/${parentName}/group.nix#${entityName}";
                      in
                      {
                        optional = [
                          {
                            value = v;
                            inherit loc;
                          }
                        ];
                        value = v;
                      }
                    else
                      {
                        optional = [ ];
                        value = commonPrivate.value;
                      };
                  childPrivate =
                    if lib.hasAttr entityName rawValue.private then
                      let
                        v = lib.recursiveUpdate childPublic.value (
                          loadValue rawValue.private.${entityName} loc { common = commonPrivate.value; }
                        );
                        loc = "private/nodes/${parentName}/group.nix#${entityName}";
                      in
                      {
                        optional = [
                          {
                            value = v;
                            inherit loc;
                          }
                        ];
                        value = v;
                      }
                    else
                      {
                        optional = [ ];
                        value = childPublic.value;
                      };
                in
                {
                  values =
                    values
                    ++ commonPublic.optional
                    ++ commonPrivate.optional
                    ++ childPublic.optional
                    ++ childPrivate.optional;
                  value = childPrivate.value;
                }
              )
              {
                values = [ ];
                value = { };
              }
              (findAncestorNames nodeName);
        in
        merged.values
        ++ lib.optionals (rawValue != null) (
          let
            nodePublic =
              if rawValue ? public then
                let
                  v = lib.recursiveUpdate merged.value (loadValue rawValue.public loc { common = merged.value; });
                  loc = "nodes/${nodeName}/node.nix";
                in
                {
                  optional = [
                    {
                      value = v;
                      inherit loc;
                    }
                  ];
                  value = v;
                }
              else
                {
                  optional = [ ];
                  value = merged.value;
                };
            nodePrivate =
              if rawValue ? private then
                let
                  v = lib.recursiveUpdate merged.value (loadValue rawValue.private loc { common = merged.value; });
                  loc = "private/nodes/${nodeName}/node.nix";
                in
                {
                  optional = [
                    {
                      value = v;
                      inherit loc;
                    }
                  ];
                  value = v;
                }
              else
                {
                  optional = [ ];
                  value = nodePublic.value;
                };
          in
          nodePublic.optional ++ nodePrivate.optional
        );
      loadValue =
        raw: loc: extraArgs:
        let
          v = call raw (
            {
              inherit (inputs.nixpkgs) lib;
              inherit inputs nodes;
              lib' = nodeLib;
            }
            // extraArgs
          );
        in
        assert lib.assertMsg (lib.isAttrs v) "${loc} must evaluate to an attribute set";
        assert lib.assertMsg (!(v ? type)) "Must not specify \"type\" in ${loc}";
        assert lib.assertMsg (!(v ? name)) "Must not specify \"name\" in ${loc}";
        assert lib.assertMsg (!(v ? parents)) "Must not specify \"parents\" in ${loc}";
        assert lib.assertMsg (!(v ? config)) "Must not specify \"config\" in ${loc}";
        v;
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
      nodeLib =
        if rawValue != null then
          lib.recursiveUpdate parentsLib (loadLib "nodes/${nodeName}" { lib' = nodeLib; })
        else
          parentsLib;
      parentsLib = builtins.foldl' (
        accu:
        { parentName, entityName }:
        let
          commonLib = lib.recursiveUpdate accu (loadLib "nodes/${parentName}/common" { lib' = commonLib; });
          childLib = lib.recursiveUpdate commonLib (
            loadLib "nodes/${parentName}/${entityName}" { lib' = childLib; }
          );
        in
        childLib
      ) topLib (findAncestorNames nodeName);
      topLib = loadLib "" { lib' = topLib; };
      loadLib =
        subdir: extraArgs:
        let
          args = {
            inherit (inputs.nixpkgs) lib;
            inherit inputs;
          } // extraArgs;
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
      nodes = lib.concatMapAttrs (
        entityName: entity:
        {
          node =
            {
              ${entityName} = entity.value;
            }
            // lib.optionalAttrs (entityName == nodeName) {
              current = entity.value;
            };
          group = {
            ${entityName} = {
              inherit (entity) type;
              name = entityName;
              parents = entity.parentNames;
              children = entity.childNames;
            };
          };
        }
        .${entity.type}
      ) final.entities;
      configuration = mkConfiguration {
        specialArgs =
          {
            inherit inputs nodes;
            lib' = nodeLib;
            modules' =
              {
                nixos = final.nixosModules;
                darwin = final.darwinModules;
              }
              .${os};
          }
          // lib.optionalAttrs (lib.pathExists privateDir) {
            privatePath = privateDir;
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
                pkgs' = lib.mapAttrs (name: v: pkgs.callPackage v { }) final.pkgs;
              in
              {
                _module.args =
                  {
                    inherit pkgs';
                  }
                  // lib.optionalAttrs (nodeValue.channel != "unstable" && flake.inputs ? nixpkgs-unstable) {
                    pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
                  };
                networking.hostName = lib.mkDefault nodes.current.name;
              }
            )
          ]
          ++ lib.optional (nodeValue.parititions != null) {
            fileSystems."/" = {
              device = "/dev/disk/by-partlabel/root";
              fsType = nodeValue.parititions.root.format;
            };
            swapDevices = lib.optional nodeValue.parititions.swap.enable {
              device = "/dev/disk/by-partlabel/swap";
            };
          }
          ++ lib.optional hasSshHostKey {
            imports = [ inputs.sops-nix.nixosModules.sops ];
            services.openssh.hostKeys = [ ];
            sops =
              {
                age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
              }
              // lib.optionalAttrs (secretsYamlFile != "") {
                defaultSopsFile = lib.mkDefault secretsYamlFile;
              };
          }
          ++ lib.optional (os == "nixos") (
            { pkgs, ... }:
            {
              # Needed for syncing fs when deploying
              environment.systemPackages = [ pkgs.rsync ];
            }
          )
          ++ lib.optional (homeFiles != { }) (
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
                  modules' = final.homeManagerModules;
                };
                users = lib.mapAttrs (_: paths: {
                  imports = paths;
                }) homeFiles;
              };
            }
          )
          ++ configurationFiles;
      };
      mkConfiguration =
        {
          nixos = inputs.nixpkgs.lib.nixosSystem;
          darwin = inputs.nix-darwin.lib.darwinSystem;
        }
        .${os};
      configurationFiles =
        let
          paths = findFilesInNodeRecursive nodeName "configuration.nix";
        in
        assert lib.assertMsg (lib.length paths != 0)
          "Missing nodes${
            lib.optionalString (rawValue == null) "/${lib.head parentNames}"
          }/${nodeName}/configuration.nix";
        paths
        ++ findFilesInNodeRecursive nodeName "hardware-configuration.nix"
        ++ findFilesInNodeRecursive nodeName "disk-config.nix";
      homeFiles = lib.zipAttrs (
        builtins.foldl' (
          paths:
          { parentName, entityName }:
          paths
          ++ findHomeFiles "${publicDir}/nodes/${parentName}/common"
          ++ findHomeFiles "${privateDir}/nodes/${parentName}/common"
          ++ findHomeFiles "${publicDir}/nodes/${parentName}/${entityName}"
          ++ findHomeFiles "${privateDir}/nodes/${parentName}/${entityName}"
        ) [ ] (findAncestorNames nodeName)
        ++ lib.optionals (rawValue != null) (
          findHomeFiles "${publicDir}/nodes/${nodeName}" ++ findHomeFiles "${privateDir}/nodes/${nodeName}"
        )
      );
      findHomeFiles =
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
          paths = findFilesInNode nodeName "fs/etc/ssh/ssh_host_ed25519_key.pub";
          len = lib.length paths;
        in
        assert lib.assertMsg (len <= 1)
          "Mutiple ed25519 SSH host keys found:\n${map (path: "- ${path}\n") paths}";
        len == 1;
      secretsYamlFile =
        let
          paths = findFilesInNode nodeName "secrets.yaml";
          len = lib.length paths;
        in
        if len == 0 then
          ""
        else if len == 1 then
          lib.head paths
        else
          throw "Mutiple secrets.yaml found:\n${map (path: "- ${path}\n") paths}";
    in
    {
      type = "node";
      value = nodeValue;
      inherit rawValue parentNames configuration;
    };
  loadGroup =
    groupName:
    let
      inherit (entityObjs.${groupName}) rawValue parentNames childNames;
      cyclic =
        childNames: visited: path:
        lib.any (
          childName:
          let
            entityObj = entityObjs.${childName};
          in
          assert lib.assertMsg (!(lib.hasAttr childName visited))
            "circular group containment: ${lib.concatStringsSep " > " (path ++ [ childName ])}";
          {
            node = false;
            group = cyclic entityObj.childNames (
              visited
              // {
                ${childName} = true;
              }
            ) (path ++ [ childName ]);
          }
          .${entityObj.type}
        ) childNames;

    in
    assert !cyclic childNames { ${groupName} = true; } [ groupName ];
    {
      type = "group";
      inherit rawValue parentNames childNames;
    };
  findFilesInNodeRecursive =
    nodeName: fileName:
    builtins.foldl' (
      paths:
      { parentName, entityName }:
      paths
      ++ optionalPath "${publicDir}/nodes/${parentName}/common/${fileName}"
      ++ optionalPath "${privateDir}/nodes/${parentName}/common/${fileName}"
      ++ optionalPath "${publicDir}/nodes/${parentName}/${entityName}/${fileName}"
      ++ optionalPath "${privateDir}/nodes/${parentName}/${entityName}/${fileName}"
    ) [ ] (findAncestorNames nodeName)
    ++ lib.optionals (entityObjs.${nodeName}.rawValue != null) (
      optionalPath "${publicDir}/nodes/${nodeName}/${fileName}"
      ++ optionalPath "${privateDir}/nodes/${nodeName}/${fileName}"
    );
  findFilesInNode =
    nodeName: fileName:
    if entityObjs.${nodeName}.rawValue == null then
      lib.concatMap (
        parentName:
        optionalPath "${publicDir}/nodes/${parentName}/${nodeName}/${fileName}"
        ++ optionalPath "${privateDir}/nodes/${parentName}/${nodeName}/${fileName}"
      ) entityObjs.${nodeName}.parentNames
    else
      optionalPath "${publicDir}/nodes/${nodeName}/${fileName}"
      ++ optionalPath "${privateDir}/nodes/${nodeName}/${fileName}";
  findAncestorNames =
    entityName:
    let
      find =
        entityName: visited:
        let
          inherit (entityObjs.${entityName}) parentNames;
        in
        map (parentName: { inherit parentName entityName; }) parentNames
        ++ lib.concatMap (
          parentName:
          if lib.hasAttr parentName visited then
            [ ]
          else
            find parentName (visited // { ${entityName} = true; })
        ) parentNames;
    in
    find entityName { };
  normalizeEntityNames =
    entityNames:
    let
      names = lib.unique entityNames;
    in
    assert lib.all (
      entityName:
      if lib.hasAttr entityName final.entities then true else throw "Unknown node ${entityName}"
    ) names;
    names;
  findNodeNames =
    entityNames:
    let
      find =
        entityNames: visited:
        lib.concatMap (
          entityName:
          let
            entity = final.entities.${entityName};
          in
          if lib.hasAttr entityName visited then
            [ ]
          else
            {
              node = [ entityName ];
              group = find entity.childNames (
                visited
                // {
                  ${entityName} = true;
                }
              );
            }
            .${entity.type}
        ) entityNames;
    in
    find entityNames { };
  segregateEntityNames =
    entityNames:
    builtins.foldl'
      (
        accu: entityName:
        let
          entity = final.entities.${entityName};
        in
        {
          node = accu // {
            nodes = accu.nodes // {
              ${entityName} = true;
            };
          };
          group =
            let
              inherit (segregateEntityNames entity.childNames) nodes groups;
            in
            accu
            // {
              nodes = accu.nodes // nodes;
              groups =
                accu.groups
                // {
                  ${entityName} = true;
                }
                // groups;
            };
        }
        .${entity.type}
      )
      {
        nodes = { };
        groups = { };
      }
      entityNames;
  nodeOptions = import ./nodeOptions.nix lib;
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
  call =
    f: args:
    if lib.isFunction f then
      let
        params = lib.functionArgs f;
      in
      f (if params == { } then args else lib.intersectAttrs params args)
    else
      f;
  joinPath =
    parts:
    "${lib.head parts}${
      lib.concatStrings (map (part: if part == "" then "" else "/${part}") (lib.drop 1 parts))
    }";
  optionalPath = path: if lib.pathExists path then [ path ] else [ ];
  filterRecursive =
    pred: v:
    if lib.isAttrs v then
      lib.concatMapAttrs (
        name: subv:
        if pred name subv then
          {
            ${name} = filterRecursive pred subv;
          }
        else
          { }
      ) v
    else if lib.isList v then
      map (subv: filterRecursive pred subv) v
    else
      v;
  toShellValue =
    v:
    let
      str = toString v;
    in
    if str == "" then "''" else lib.escapeShellArg str;
in
final
