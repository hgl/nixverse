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
  allNodes' = self.lib.concatMapAttrsToList (_: loadNodes') releaseGroups;
  toNodes =
    nodes':
    lib.concatMap (
      { node', nodeSelf }:
      if node'.group == "" then
        [
          {
            node = node';
            inherit nodeSelf;
          }
        ]
      else
        let
          attrs = lib.removeAttrs node' [ "nodes" ];
        in
        map (n: {
          node = n // attrs;
          inherit nodeSelf;
        }) node'.nodes
    ) nodes';
  loadNode' =
    release: name:
    let
      base = "${flake}/nodes/${release}/${name}";
      releaseParts = lib.split "-" release;
      os = lib.elemAt releaseParts 0;
      channel = lib.elemAt releaseParts 2;
      nodeSelf =
        let
          inputs = lib.mapAttrs' (k: v: lib.nameValuePair (lib.removeSuffix "-${channel}" k) v) (
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
        in
        {
          inherit inputs;
          inherit (flake) outPath;
          lib = callArgs (importFile flake "lib") {
            inherit inputs;
            inherit (inputs.nixpkgs) lib;
          };
          modules = if os == "nixos" then flakeSelf.nixosModules else flakeSelf.darwinModules;
        };
      node' =
        if lib.pathExists "${base}/default.nix" then
          let
            raw = callArgs (import base) {
              inherit (nodeSelf.inputs.nixpkgs) lib;
              self = {
                inherit (nodeSelf) inputs lib;
              };
            };
          in
          if lib.isAttrs raw then
            if raw ? name then
              lib.abort "must not specify node name for a singleton node: ${base}/default.nix"
            else
              {
                inherit name;
                group = "";
              }
              // raw
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
            inherit name;
            group = "";
          };
    in
    {
      node' = node' // {
        inherit release os channel;
        basePath = base;
      };
      inherit nodeSelf;
    };
  loadNodes' =
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
      map (name: loadNode' release name) names
    ) releases;
  configs =
    releases:
    self.lib.mapListToAttrs (
      { node, nodeSelf }:
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
        system =
          (import
            "${node.basePath}/${
              lib.optionalString (node.group != "") "${node.name}/"
            }hardware-configuration.nix"
            {
              config = null;
              pkgs = null;
              modulesPath = null;
              inherit (nodeSelf.inputs.nixpkgs) lib;
            }
          ).nixpkgs.hostPlatform.content;
      in
      lib.nameValuePair node.name (mkSystem {
        specialArgs = {
          inherit node;
          self = nodeSelf // {
            packages = flakeSelf.packages.${system};
          };
        };
        modules = [
          (
            { config, ... }:
            {
              _module.args = lib.optionalAttrs (node.channel == "stable" && flake.inputs ? nixpkgs-unstable) {
                pkgs-unstable = flake.inputs.nixpkgs-unstable.legacyPackages.${config.nixpkgs.hostPlatform};
              };
              networking.hostName = lib.mkDefault node.name;
            }
          )
          "${node.basePath}/configuration.nix"
        ];
      })
    ) (toNodes (loadNodes' releases));
  importFile =
    base: name:
    if lib.pathExists "${base}/${name}.nix" then
      import "${base}/${name}.nix"
    else if lib.pathExists "${base}/${name}/default.nix" then
      import "${base}/${name}"
    else
      null;
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
      lib.mapAttrs (name: v: pkgs.callPackage v { }) (importDir "${flake}/packages")
    );
    nixosConfigurations = configs releaseGroups.nixos;
    darwinConfigurations = configs releaseGroups.darwin;
    loadNode = name: lib.findFirst ({ node, ... }: node.name == name) null (toNodes allNodes');
    loadNodeGroup =
      name:
      lib.findFirst ({ node, ... }: node.group == name) null (
        lib.concatMap (
          { node', nodeSelf }:
          if node'.group == "" then
            [ ]
          else
            [
              {
                node = node';
                inherit nodeSelf;
              }
            ]
        ) allNodes'
      );
  };
in
flakeSelf
