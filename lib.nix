{ lib, lib' }:
{
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  callWithOptionalArgs =
    f: args: if lib.isFunction f then f (lib.intersectAttrs (lib.functionArgs f) args) else f;
  mapListToAttrs = f: list: lib.listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: lib.listToAttrs (lib.concatMap f list);

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
            (lib.nameValuePair name (lib'.filterRecursive pred v))
          ]
        else
          [ ]
      ) (lib.attrNames sl)
    else if lib.isList sl then
      map (lib'.filterRecursive pred) sl
    else
      sl;

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

  loadNodes =
    flake: releases:
    lib.concatMap (
      release:
      let
        base = "${flake}/nodes/${release}";
        names =
          if lib.pathExists base then
            lib'.concatMapAttrsToList (
              name: v:
              if v == "directory" && lib.pathExists "${base}/${name}/configuration.nix" then [ name ] else [ ]
            ) (builtins.readDir base)
          else
            [ ];
      in
      map (name: lib'.loadNode flake release name) names
    ) releases;

  loadNode =
    flake: release: name:
    let
      parts = lib.split "-" release;
      os = lib.elemAt parts 0;
      channel = lib.elemAt parts 2;
      base = "${flake}/nodes/${release}/${name}";
      normalizedInputs =
        lib.removeAttrs flake.inputs [ "nixpkgs-stable-darwin" ]
        // lib.optionalAttrs (os == "darwin") {
          nixpkgs-stable = flake.inputs.nixpkgs-stable-darwin;
        };
      inputs = lib.mapAttrs' (k: v: lib.nameValuePair (lib.removeSuffix "-${channel}" k) v) (
        if channel == "stable" then
          lib.filterAttrs (k: v: !(lib.hasSuffix "-unstable" k)) normalizedInputs
        else
          normalizedInputs
      );
      flakeLib = lib'.importFile flake "lib";
      nodeLib = lib'.importFile base "lib";
      finalLib =
        lib'.callWithOptionalArgs flakeLib libArgs
        // lib.optionalAttrs (nodeLib != null) (lib'.callWithOptionalArgs nodeLib libArgs);
      libArgs = {
        inherit (inputs.nixpkgs) lib;
        inputs' = inputs;
        lib' = finalLib;
      };
      raw = lib'.callWithOptionalArgs (import base) libArgs;
      extraAttrs = {
        inherit release os channel;
        basePath = base;
      };
      imported =
        if lib.pathExists "${base}/default.nix" then
          if lib.isAttrs raw then
            let
              extraAttrs' = extraAttrs // {
                inherit name;
                group = "";
              };
              forbiddenNames = lib.attrNames (lib.intersectAttrs extraAttrs' raw);
            in
            if forbiddenNames != [ ] then
              abort "must not specify these attributes in node (${base}/default.nix): ${toString forbiddenNames}"
            else
              {
                node = raw // extraAttrs';
              }
          else if lib.isList raw then
            if raw == [ ] then
              abort "must not be an empty list: ${base}/default.nix"
            else
              let
                extraAttrs' = extraAttrs // {
                  group = name;
                };
              in
              {
                nodes = lib.imap0 (
                  i: node:
                  if !lib.isAttrs node then
                    abort "must be a list of attrsets: ${base}/default.nix"
                  else
                    let
                      forbiddenNames = lib.attrNames (lib.intersectAttrs extraAttrs' node);
                    in
                    if !(node ? name) then
                      abort "missing name for node [${toString i}]: ${base}/default.nix"
                    else if forbiddenNames != [ ] then
                      abort "must not specify these attributes in node ${node.name} (${base}/default.nix): ${toString forbiddenNames}"
                    else
                      node // extraAttrs'
                ) raw;
              }
          else
            abort "must be a list of attrsets or an attrset: ${base}/default.nix"
        else
          {
            group = "";
            node = {
              inherit name;
            };
          };
      node = imported // {
        inherit inputs;
        lib = finalLib;
      };
    in
    node;

  importFile = base: name: (lib'.importDir base).${name} or null;
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
}
