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
      if entity.type == "node" && entity.value.os == os then
        {
          ${name} = entity.configuration;
        }
      else
        { }
    ) entities;
  entities = lib.mapAttrs (
    _: entityObj:
    {
      inherit (entityObj) type;
    }
    // (if entityObj.type == "node" then loadNode entityObj else loadGroup entityObj)
  ) entityObjs;
  entityObjs = lib.zipAttrsWith (
    entityName: entityObjList:
    let
      inherit (lib.findFirst (obj: obj ? type) { type = "node"; } entityObjList) type;
    in
    {
      inherit type;
      name = entityName;
      parents = builtins.foldl' (accu: entityObj: accu // entityObj.parents or { }) { } entityObjList;
    }
    // (lib.findFirst (obj: obj ? rawValue) { rawValue = null; } entityObjList)
    // lib.optionalAttrs (type == "group") (
      lib.findFirst (entityObj: entityObj ? children) (throw "This should not be evaluated") entityObjList
    )
  ) entityObjLists;
  entityObjLists = (
    lib'.concatMapAttrsToList (
      entityName:
      { type, publicExist, ... }:
      let
        loc = "${lib.optionalString (!publicExist) "private/"}nodes/current/${type}.nix";
      in
      assert lib.assertMsg (
        entityName != "current"
      ) "\"current\" is a reserved node name, cannot be used for ${loc}";
      if type == "node" then
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
        ]
      else
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
                  assert lib.assertMsg (
                    name != "current"
                  ) "\"current\" is a reserved node name, cannot be used for ${loc}";
                  true
                ) names;
                v
              );
            };
          children =
            let
              v =
                lib.optionalAttrs (rawValue.public != null) (lib.removeAttrs rawValue.public [ "common" ])
                // lib.optionalAttrs (rawValue.private != null) (lib.removeAttrs rawValue.private [ "common" ]);
            in
            assert lib.assertMsg (v != { }) "${subpath} must contain at least one child";
            lib.mapAttrs (_: _: true) v;
        in
        [
          {
            ${entityName} = {
              type = "group";
              inherit rawValue children;
            };
          }
          (lib.mapAttrs (childName: _: {
            parents = {
              ${entityName} = true;
            };
          }) children)
        ]
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
    entityObj:
    let
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
          inherit (entityObj) name parents;
        };
      valueLocs =
        let
          merged =
            foldParents
              (
                { values, value }:
                currentObj: childObj:
                let
                  inherit (currentObj) rawValue;
                  commonPublic =
                    if rawValue.public ? common then
                      let
                        v = lib.recursiveUpdate value (
                          loadValue rawValue.public.common loc { common = commonPrivate.value; }
                        );
                        loc = "nodes/${currentObj.name}/group.nix#common";
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
                        loc = "private/nodes/${currentObj.name}/group.nix#common";
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
                    if lib.hasAttr childObj.name rawValue.public then
                      let
                        v = lib.recursiveUpdate commonPrivate.value (
                          loadValue rawValue.public.${childObj.name} loc { common = commonPrivate.value; }
                        );
                        loc = "nodes/${currentObj.name}/group.nix#${childObj.name}";
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
                    if lib.hasAttr childObj.name rawValue.private then
                      let
                        v = lib.recursiveUpdate childPublic.value (
                          loadValue rawValue.private.${childObj.name} loc { common = commonPrivate.value; }
                        );
                        loc = "private/nodes/${currentObj.name}/group.nix#${childObj.name}";
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
              };
        in
        merged.values
        ++ lib.optionals (entityObj.rawValue != null) (
          let
            inherit (entityObj) rawValue;
            nodePublic =
              if rawValue ? public then
                let
                  v = lib.recursiveUpdate merged.value (loadValue rawValue.public loc { common = merged.value; });
                  loc = "nodes/${entityObj.name}/node.nix";
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
                  loc = "private/nodes/${entityObj.name}/node.nix";
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
      nodeOptions = import ./nodeOptions.nix lib;
      foldParents =
        f: nul:
        let
          foldP =
            obj: nul:
            builtins.foldl' (
              accu: parentName:
              let
                parentObj = entityObjs.${parentName};
              in
              f (foldP parentObj accu) parentObj obj
            ) nul (lib.attrNames obj.parents);
        in
        foldP entityObj nul;
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
        if entityObj.rawValue != null then
          lib.recursiveUpdate parentsLib (loadLib "nodes/${entityObj.name}" { lib' = nodeLib; })
        else
          parentsLib;
      parentsLib = foldParents (
        accu: parentObj: childObj:
        let
          commonLib = lib.recursiveUpdate accu (
            loadLib "nodes/${parentObj.name}/common" { lib' = commonLib; }
          );
          childLib = lib.recursiveUpdate commonLib (
            loadLib "nodes/${parentObj.name}/${childObj.name}" { lib' = childLib; }
          );
        in
        childLib
      ) topLib;
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
        name: entity:
        if entity.type == "node" then
          {
            ${name} = entity.value;
          }
          // lib.optionalAttrs (name == entityObj.name) {
            current = entity.value;
          }
        else
          {
            ${name} = lib.removeAttrs entity [ "type" ];
          }
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
            sops.age =
              {
                sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
              }
              // lib.optionalAttrs (secretsYamlPath != "") {
                defaultSopsFile = lib.mkDefault secretsYamlPath;
              };
          }
          ++ lib.optional (os == "nixos") (
            { pkgs, ... }:
            {
              # Needed for syncing fs when deploying
              environment.systemPackages = [ pkgs.rsync ];
            }
          )
          ++ lib.optional (homePaths != { }) (
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
                users = lib.mapAttrs (_: paths: {
                  imports = paths;
                }) homePaths;
              };
            }
          )
          ++ configurationPaths;
      };
      mkSystem =
        {
          nixos = inputs.nixpkgs.lib.nixosSystem;
          darwin = inputs.nix-darwin.lib.darwinSystem;
        }
        .${os};
      configurationPaths =
        let
          paths = findPaths { name = "configuration.nix"; };
        in
        assert lib.assertMsg (lib.length paths != 0)
          "Missing nodes${
            lib.optionalString (entityObj.rawValue == null) "/${lib.head (lib.attrNames entityObj.parents)}"
          }/${entityObj.name}/configuration.nix";
        paths ++ findPaths { name = "hardware-configuration.nix"; };
      findPaths =
        {
          name,
          common ? true,
        }:
        foldParents (
          ps: currentObj: childObj:
          ps
          ++ lib.optionals common (
            optionalPath "${publicDir}/nodes/${currentObj.name}/common/${name}"
            ++ optionalPath "${privateDir}/nodes/${currentObj.name}/common/${name}"
          )
          ++ optionalPath "${publicDir}/nodes/${currentObj.name}/${childObj.name}/${name}"
          ++ optionalPath "${privateDir}/nodes/${currentObj.name}/${childObj.name}/${name}"
        ) [ ]
        ++ lib.optionals (entityObj.rawValue != null) (
          optionalPath "${publicDir}/nodes/${entityObj.name}/${name}"
          ++ optionalPath "${privateDir}/nodes/${entityObj.name}/${name}"
        );
      homePaths = lib.zipAttrs (
        foldParents (
          ps: currentObj: childObj:
          ps
          ++ getHomePaths "${publicDir}/nodes/${currentObj.name}/common"
          ++ getHomePaths "${privateDir}/nodes/${currentObj.name}/common"
          ++ getHomePaths "${publicDir}/nodes/${currentObj.name}/${childObj.name}"
          ++ getHomePaths "${privateDir}/nodes/${currentObj.name}/${childObj.name}"
        ) [ ]
        ++ lib.optionals (entityObj.rawValue != null) (
          getHomePaths "${publicDir}/nodes/${entityObj.name}"
          ++ getHomePaths "${privateDir}/nodes/${entityObj.name}"
        )
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
          paths = findPaths { name = "fs/etc/ssh/ssh_host_ed25519_key.pub"; };
          len = lib.length paths;
        in
        assert lib.assertMsg (len <= 1)
          "Mutiple ed25519 SSH host keys found:\n${map (path: "- ${path}\n") paths}";
        len == 1;
      secretsYamlPath =
        let
          paths = findPaths {
            name = "secrets.yaml";
            common = false;
          };
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
      value = nodeValue;
      inherit configuration;
    };
  loadGroup =
    entityObj:
    let
      checkCyclic =
        children: visited: path:
        lib.all (
          name:
          assert lib.assertMsg (!(lib.hasAttr name visited))
            "circular group containment: ${lib.concatStringsSep " > " (path ++ [ name ])}";
          if entityObjs.${name}.type == "node" then
            true
          else
            checkCyclic entityObjs.${name}.children (
              visited
              // {
                ${name} = true;
              }
            ) (path ++ [ name ])
        ) (lib.attrNames children);
    in
    assert checkCyclic entityObj.children { ${entityObj.name} = true; } [ entityObj.name ];
    {
      inherit (entityObj) name parents children;
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
      map (filterRecursive pred) sl
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
        value = filterRecursive (n: v: !(lib.isFunction v)) (lib.removeAttrs entity.value [ "config" ]);
      }
    else
      entity
  ) entities;
}
