{
  lib,
  lib',
  self,
  flake,
  outputs,
}:
let
  inherit (lib'.internal)
    call
    importDirOrFile
    importDirAttrs
    optionalPath
    ;
  publicDir = flake.outPath;
  privateDir = "${publicDir}/private";
  rawPkgs = importDirAttrs "${publicDir}/pkgs" // importDirAttrs "${privateDir}/pkgs";
  userLibArgs =
    assert lib.assertMsg (
      flake.inputs ? nixpkgs-unstable
    ) "Missing required flake input nixpkgs-unstable";
    {
      inherit (flake.inputs.nixpkgs-unstable) lib;
      lib' = userLib;
      inherit (flake) inputs;
    };
  userLib = lib.recursiveUpdate (call (importDirOrFile publicDir "lib" { }) userLibArgs) (
    call (importDirOrFile privateDir "lib" { }) userLibArgs
  );
  final = {
    lib = userLib;
    nixosModules =
      importDirAttrs "${publicDir}/modules/nixos"
      // importDirAttrs "${privateDir}/modules/nixos";
    darwinModules =
      importDirAttrs "${publicDir}/modules/darwin"
      // importDirAttrs "${privateDir}/modules/darwin";
    homeModules =
      importDirAttrs "${publicDir}/modules/home"
      // importDirAttrs "${privateDir}/modules/home";
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
    nixverse = flakeSrc: {
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
        toString (
          map (nodeName: "nodes/${nodeName}") (
            recursiveFindDescendantNodeNames (validateEntityNames entityNames)
          )
        );
      getNodeInstallJobs =
        entityNames:
        let
          nodeNames = recursiveFindDescendantNodeNames (validateEntityNames entityNames);
        in
        map (
          nodeName:
          let
            node = final.entities.${nodeName};
          in
          assert lib.assertMsg (
            node.value.os != "darwin"
          ) "Darwin node ${nodeName} doesn't need to be installed first, it's directly deployable.";
          assert lib.assertMsg (
            node.value.install.targetHost != ""
          ) "Either install.targetHost or deploy.targetHost must not be empty for node ${nodeName}";
          assert lib.assertMsg (node.diskConfigFiles != [ ]) "Missing disk-config.nix for node ${nodeName}";
          {
            n = nodeName;
            c = "install_node ${lib.escapeShellArg flakeSrc} ${lib.escapeShellArg nodeName} ${lib.escapeShellArg node.dir} ${lib.escapeShellArg node.value.install.targetHost} ${lib.escapeShellArg node.value.install.buildOnRemote} ${lib.escapeShellArg node.value.install.useSubstitutes} ${lib.escapeShellArg node.sshHostKey} ${
              toString (map (opt: lib.escapeShellArg opt) node.value.deploy.sshOpts)
            }";
          }
        ) nodeNames;
      getNodeBuildJobs =
        entityNames:
        let
          nodeNames = recursiveFindDescendantNodeNames (validateEntityNames entityNames);
        in
        lib.concatMap (
          nodeName:
          let
            node = final.entities.${nodeName};
          in
          [
            {
              n = nodeName;
              c = "build_node ${lib.escapeShellArg flakeSrc} ${lib.escapeShellArg nodeName} ${lib.escapeShellArg node.value.os}";
            }
          ]
        ) nodeNames;
      getNodeDeployJobs =
        entityNames:
        let
          nodeNames = recursiveFindDescendantNodeNames (validateEntityNames entityNames);
          numNode = lib.length nodeNames;
        in
        map (
          nodeName:
          let
            node = final.entities.${nodeName};
          in
          assert lib.assertMsg (numNode != 1 -> node.value.deploy.targetHost != "")
            "Deploying multiple nodes where some of them are local is not allowed, deploy the local nodes individually.";
          {
            n = nodeName;
            c = "deploy_node ${lib.escapeShellArg flakeSrc} ${lib.escapeShellArg nodeName} ${lib.escapeShellArg node.value.os} ${lib.escapeShellArg node.value.deploy.targetHost} ${lib.escapeShellArg node.value.deploy.buildOnRemote} ${lib.escapeShellArg node.value.deploy.useSubstitutes} ${lib.escapeShellArg node.value.deploy.useRemoteSudo} ${
              lib.escapeShellArg (map (opt: "-o ${lib.escapeShellArg opt}") node.value.deploy.sshOpts)
            }";
          }
        ) nodeNames;
      evalData = {
        inherit (userLibArgs) lib lib';
        nodes = lib.mapAttrs (_: entity: entity.value) final.entities;
      };
      getSecretsMakefileVars =
        entityNames:
        let
          nodeNames = recursiveFindDescendantNodeNames entityNames;
        in
        ''
          node_names := ${toString nodeNames}
          ${lib.concatStringsSep "\n" (
            lib.concatMap (
              nodeName:
              let
                node = final.entities.${nodeName};
              in
              [
                "node_${nodeName}_dir := ${node.dir}"
                "node_${nodeName}_secrets_sections := ${
                  toString (
                    map ({ parentName, ... }: parentName) (recursiveFindAncestorNames nodeName) ++ [ nodeName ]
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
          else if typesPublic ? ${entityName} then
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
      definedByGroup = rawValue == null;
      nodeDir = "nodes${lib.optionalString definedByGroup "/${lib.head parentNames}"}/${nodeName}";

      nodeValue =
        let
          len = lib.length valueLocs;
          config =
            (lib.evalModules {
              modules =
                [
                  {
                    imports = [
                      ./modules/assertions.nix
                      ./modules/node.nix
                    ];
                    # Ignore config values without corresponding options
                    _module.check = false;
                  }
                ]
                ++ lib.imap0 (
                  i:
                  { value, loc }:
                  {
                    _file = loc;
                    config = lib.mkOverride (1000 + len - 1 - i) value;
                  }
                ) valueLocs;
            }).config;
          v =
            builtins.foldl' (accu: { value, ... }: lib.recursiveUpdate accu value) { } valueLocs
            // lib.removeAttrs config [
              "assertions"
              "warnings"
            ]
            // {
              type = "node";
              name = nodeName;
              parentGroups = lib'.mapListToAttrs (
                name: lib.nameValuePair name final.entities.${name}.value
              ) parentNames;
              groups = lib'.mapListToAttrs (
                name: lib.nameValuePair name final.entities.${name}.value
              ) (findAllGroupNames [ nodeName ]);
              inherit (configuration) config;
            };
        in
        lib.asserts.checkAssertWarn config.assertions config.warnings v;
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
              (recursiveFindAncestorNames nodeName);
        in
        merged.values
        ++ lib.optionals (!definedByGroup) (
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
              lib' = final.lib;
            }
            // extraArgs
          );
        in
        assert lib.assertMsg (lib.isAttrs v) "${loc} must evaluate to an attribute set";
        assert lib.assertMsg (!v ? type) "`type` is a reserved attribute name: ${loc}";
        assert lib.assertMsg (!v ? name) "`name` is a reserved attribute name: ${loc}";
        assert lib.assertMsg (!v ? parentGroups) "`parentGroups` is a reserved attribute name: ${loc}";
        assert lib.assertMsg (!v ? groups) "`groups` is a reserved attribute name: ${loc}";
        assert lib.assertMsg (!v ? config) "`config` is a reserved attribute name: ${loc}";
        v;
      inputs =
        let
          v = lib.concatMapAttrs (
            name: input:
            if channel != "unstable" && lib.hasSuffix "-unstable-${os}" name then
              { ${lib.removeSuffix "-${os}" name} = input; }
            else if channel != "unstable" && lib.hasSuffix "-unstable" name then
              { ${name} = input; }
            else if lib.hasSuffix "-${channel}-${os}" name then
              { ${lib.removeSuffix "-${channel}-${os}" name} = input; }
            else if lib.hasSuffix "-${channel}" name then
              { ${lib.removeSuffix "-${channel}" name} = input; }
            else if lib.hasSuffix "-any" name then
              { ${lib.removeSuffix "-any" name} = input; }
            else
              { }
          ) flake.inputs;
        in
        assert lib.assertMsg (v ? nixpkgs)
          "Missing flake input nixpkgs-${channel}${
            lib.optionalString (channel != "unstable") "-${os}"
          }, required by node ${nodeName}";
        v;
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
            ${entityName} = entity.value;
          };
        }
        .${entity.type}
      ) final.entities;
      baseModule =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          _module.args =
            let
              inherit (config.nixpkgs.hostPlatform) system;
              optionalPkgsUnstableAttr = lib.optionalAttrs (channel != "unstable") (
                assert lib.assertMsg (
                  flake.inputs ? nixpkgs-unstable
                ) "Missing required flake input nixpkgs-unstable";
                {
                  pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
                }
              );
              callPackage = pkgs.newScope (
                optionalPkgsUnstableAttr
                // {
                  inherit pkgs';
                }
              );
              pkgs' = lib.mapAttrs (_: v: callPackage v { }) rawPkgs;
            in
            { inherit pkgs'; } // optionalPkgsUnstableAttr;
          networking.hostName = lib.mkDefault nodes.current.name;
        };
      configuration = mkConfiguration {
        specialArgs =
          {
            inherit inputs nodes;
            lib' = final.lib;
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
          [ baseModule ]
          ++ configurationFiles
          ++ lib.optional (diskConfigFiles != [ ]) (
            assert lib.assertMsg (inputs ? disko)
              "Missing flake input disko-${channel}${
                lib.optionalString (channel != "unstable") "-${os}"
              }, required by node ${nodeName}";
            {
              imports = [ inputs.disko.nixosModules.disko ];
            }
          )
          ++ lib.optional (sshHostKey != "") (
            assert lib.assertMsg (inputs ? sops-nix)
              "Missing flake input sops-nix-${channel}${
                lib.optionalString (channel != "unstable") "-${os}"
              }, required by node ${nodeName}";
            {
              imports = [ inputs.sops-nix.nixosModules.sops ];
              services.openssh.hostKeys = [
                {
                  bits = 4096;
                  path = "/etc/ssh/ssh_host_rsa_key";
                  type = "rsa";
                }
              ];
              sops =
                {
                  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
                }
                // lib.optionalAttrs (secretsYamlFile != "") {
                  defaultSopsFile = lib.mkDefault secretsYamlFile;
                };
            }
          )
          ++ lib.optional (homeFiles != { }) (
            assert lib.assertMsg (inputs ? home-manager)
              "Missing flake input home-manager-${channel}${
                lib.optionalString (channel != "unstable") "-${os}"
              }, required by node ${nodeName}";
            (
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
                  useGlobalPkgs = lib.mkDefault true;
                  useUserPackages = lib.mkDefault true;
                  extraSpecialArgs = {
                    inherit
                      lib'
                      pkgs'
                      inputs
                      nodes
                      ;
                    modules' = final.homeModules;
                  };
                  users = lib.mapAttrs (_: paths: {
                    imports = paths;
                  }) homeFiles;
                };
              }
            )
          );
      };
      mkConfiguration =
        {
          nixos = inputs.nixpkgs.lib.nixosSystem;
          darwin =
            assert lib.assertMsg (inputs ? nix-darwin)
              "Missing flake input nix-darwin-${channel}${
                lib.optionalString (channel != "unstable") "-${os}"
              }, required by node ${nodeName}";
            inputs.nix-darwin.lib.darwinSystem;
        }
        .${os};
      configurationFiles =
        let
          paths = recursiveFindFilesInNode nodeName "configuration.nix";
        in
        assert lib.assertMsg (lib.length paths != 0) "Missing ${nodeDir}/configuration.nix";
        paths ++ recursiveFindFilesInNode nodeName "hardware-configuration.nix" ++ diskConfigFiles;
      diskConfigFiles = lib.optionals (os == "nixos") (
        recursiveFindFilesInNode nodeName "disk-config.nix"
      );
      homeFiles = lib.zipAttrs (
        lib.concatMap (
          { parentName, entityName }:
          findHomeFiles "${publicDir}/nodes/${parentName}/common"
          ++ findHomeFiles "${privateDir}/nodes/${parentName}/common"
          ++ findHomeFiles "${publicDir}/nodes/${parentName}/${entityName}"
          ++ findHomeFiles "${privateDir}/nodes/${parentName}/${entityName}"
        ) (recursiveFindAncestorNames nodeName)
        ++ lib.optionals (!definedByGroup) (
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
      sshHostKey =
        let
          paths = findFilesInNode nodeName "ssh_host_ed25519_key";
          path = lib.elemAt paths 0;
          len = lib.length paths;
        in
        assert lib.assertMsg (len <= 1) "Mutiple SSH host keys found:\n${map (path: "- ${path}\n") paths}";
        if len == 0 then
          ""
        else
          assert lib.assertMsg (lib.pathExists "${path}.pub") "Missing SSH host pubkey: ${path}";
          path;
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
      dir = nodeDir;
      inherit
        rawValue
        parentNames
        configuration
        sshHostKey
        diskConfigFiles
        nodes # Exposed for tests
        ;
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
          assert lib.assertMsg (!lib.hasAttr childName visited)
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
      value = {
        type = "group";
        name = groupName;
        parentGroups = lib'.mapListToAttrs (
          name: lib.nameValuePair name final.entities.${name}.value
        ) parentNames;
        groups = lib'.mapListToAttrs (
          name: lib.nameValuePair name final.entities.${name}.value
        ) (findAllGroupNames [ groupName ]);
        children = lib'.mapListToAttrs (
          name: lib.nameValuePair name final.entities.${name}.value
        ) childNames;
        childNodes = lib'.mapListToAttrs (name: lib.nameValuePair name final.entities.${name}.value) (
          lib.filter (entityName: final.entities.${entityName}.type == "node") childNames
        );
        nodes = lib'.mapListToAttrs (name: lib.nameValuePair name final.entities.${name}.value) (
          recursiveFindDescendantNodeNames childNames
        );
      };
    };
  recursiveFindFilesInNode =
    nodeName: fileName:
    lib.concatMap (
      { parentName, entityName }:
      optionalPath "${publicDir}/nodes/${parentName}/common/${fileName}"
      ++ optionalPath "${privateDir}/nodes/${parentName}/common/${fileName}"
      ++ optionalPath "${publicDir}/nodes/${parentName}/${entityName}/${fileName}"
      ++ optionalPath "${privateDir}/nodes/${parentName}/${entityName}/${fileName}"
    ) (recursiveFindAncestorNames nodeName)
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
  recursiveFindAncestorNames =
    entityName:
    let
      find =
        entityName: visited:
        let
          inherit (entityObjs.${entityName}) parentNames;
        in
        lib.concatMap (
          parentName:
          if lib.hasAttr parentName visited then
            [ ]
          else
            find parentName (visited // { ${entityName} = true; })
        ) parentNames
        ++ map (parentName: { inherit parentName entityName; }) parentNames;
    in
    find entityName { };
  validateEntityNames =
    entityNames:
    let
      names = lib.unique entityNames;
    in
    assert lib.all (
      entityName:
      if lib.hasAttr entityName final.entities then true else throw "Unknown node ${entityName}"
    ) names;
    names;
  recursiveFindDescendantNodeNames =
    entityNames:
    let
      find =
        entityNames:
        lib'.concatMapListToAttrs (
          entityName:
          let
            entity = final.entities.${entityName};
          in
          {
            node = {
              ${entityName} = true;
            };
            group = find entity.childNames;
          }
          .${entity.type}
        ) entityNames;
    in
    lib.attrNames (find entityNames);
  findAllGroupNames =
    entityNames:
    lib.attrNames (
      lib'.concatMapListToAttrs (
        entityName:
        lib'.concatMapListToAttrs (
          { parentName, ... }:
          {
            ${parentName} = true;
          }
        ) (recursiveFindAncestorNames entityName)
      ) entityNames
    );
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
in
final
