{
  lib,
  lib',
  self,
  inputs,
  userFlake,
  userFlakePath,
  userLib,
  getUserPkgs,
  systems,
  userNodes,
  userOutputsNodes,
  nodes,
}:
let
  getOutputPaths =
    type:
    lib'.allImportPathsInDirs [
      "${userFlakePath}/private/outputs/${type}"
      "${userFlakePath}/outputs/${type}"
    ];
  getOutputPath = outputPaths: outputName: lib.removePrefix "${userFlakePath}/" (lib.head outputPaths.${outputName});

  flakeOutputPaths = getOutputPaths "flake";
  perSystemOutputPaths = getOutputPaths "perSystem";

  getInputs' =
    system:
    lib.mapAttrs (_: input:
      input
      // {
        packages = input.packages.${system} or { };
        legacyPackages = input.legacyPackages.${system} or { };
      }
    ) inputs;

  mergeOutputValues =
    {
      outputName,
      left,
      right,
      mergeSystemAttrs ? false,
    }:
    if lib.isAttrs left.value && lib.isAttrs right.value then
      let
        outputNameCollisions = lib.intersectAttrs left.value right.value;
        mergeAttr =
          name: _:
          if mergeSystemAttrs && lib.elem name systems then
            mergeOutputValues {
              outputName = "${outputName}.${name}";
              left = {
                inherit (left) path;
                value = left.value.${name};
              };
              right = {
                inherit (right) path;
                value = right.value.${name};
              };
            }
          else
            throw "Output `${outputName}.${name}` is defined in both `${left.path}` and `${right.path}`";
      in
      left.value // right.value // lib.mapAttrs mergeAttr outputNameCollisions
    else if lib.isList left.value && lib.isList right.value then
      left.value ++ right.value
    else
      throw "Output `${outputName}` is defined in both `${left.path}` and `${right.path}`, but the values are not both attribute sets or both lists";

  mergeOutputPathValues =
    {
      outputName,
      paths,
      call,
      mergeSystemAttrs ? false,
    }:
    (builtins.foldl' (
      left: path:
      let
        right = {
          path = lib.removePrefix "${userFlakePath}/" path;
          value = call path;
        };
      in
      {
        path = "${left.path}, ${right.path}";
        value = mergeOutputValues {
          inherit
            outputName
            left
            right
            mergeSystemAttrs
            ;
        };
      }
    ) {
      path = lib.removePrefix "${userFlakePath}/" (lib.head paths);
      value = call (lib.head paths);
    } (builtins.tail paths)).value;

  flakeOutputs = lib.mapAttrs (
    outputName: paths:
    mergeOutputPathValues {
      inherit outputName paths;
      mergeSystemAttrs = true;
      call =
        path:
        lib'.call (import path) {
          inherit inputs lib;
          outputs = finalOutputs;
          nodes = userOutputsNodes;
        };
    }
  ) flakeOutputPaths;

  perSystemOutputs = lib.zipAttrsWith (_: values: lib.foldl' (acc: value: acc // value) { } values) (
    map (
      system:
      let
        pkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
        pkgs' = getUserPkgs pkgs;
      in
      lib.mapAttrs (outputName: paths: {
        ${system} = mergeOutputPathValues {
          outputName = "${outputName}.${system}";
          inherit paths;
          call =
            path:
            lib'.call (import path) {
              inherit
                lib
                system
                pkgs
                pkgs'
                ;
              inputs' = getInputs' system;
              outputs' = getOutputs' system;
              nodes = userOutputsNodes;
            };
        };
      }) perSystemOutputPaths
    ) systems
  );

  mergePerSystemOutput =
    outputName: perSystemOutput:
    if !(builtins.hasAttr outputName flakeOutputs) then
      perSystemOutput
    else
      let
        flakeOutput = flakeOutputs.${outputName};
        mergeSystemOutput =
          system: perSystemSystemOutput:
          if !(builtins.hasAttr system flakeOutput) then
            perSystemSystemOutput
          else
            let
              flakeSystemOutput = flakeOutput.${system};
            in
            mergeOutputValues {
              outputName = "${outputName}.${system}";
              left = {
                path = getOutputPath flakeOutputPaths outputName;
                value = flakeSystemOutput;
              };
              right = {
                path = getOutputPath perSystemOutputPaths outputName;
                value = perSystemSystemOutput;
              };
            };
      in
      assert lib.assertMsg (lib.isAttrs flakeOutput)
        "Flake output `${outputName}` must be an attribute set to merge with `outputs/perSystem/${outputName}.nix`";
      flakeOutput // lib.mapAttrs mergeSystemOutput perSystemOutput;

  userOutputs = flakeOutputs // lib.mapAttrs mergePerSystemOutput perSystemOutputs;

  apps = lib'.concatMapListToAttrs (
    system:
    let
      pkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
      nixverse = {
        type = "app";
        program = self.packages.${system}.nixverse;
      };
      makefileInputsOutput = finalOutputs.makefileInputs or null;
      makefileInputs =
        if lib.isAttrs makefileInputsOutput && builtins.hasAttr system makefileInputsOutput then
          makefileInputsOutput.${system}
        else
          null;
      nixverseApps = {
        inherit nixverse;
        default = nixverse;
      }
      // lib.optionalAttrs (makefileInputs != null) {
        make = {
          type = "app";
          program =
            pkgs.callPackage (import ./packages/make.nix { inherit makefileInputs; }) { };
        };
      };
      userApps = userOutputs.apps.${system} or { };
      appNameCollisions = lib.intersectAttrs nixverseApps userApps;
      appNameCollision = lib.head (lib.attrNames appNameCollisions);
      appOutputPath =
        if builtins.hasAttr appNameCollision (perSystemOutputs.apps.${system} or { }) then
          getOutputPath perSystemOutputPaths "apps"
        else
          getOutputPath flakeOutputPaths "apps";
    in
    assert lib.assertMsg (appNameCollisions == { })
      "App `${system}.${appNameCollision}` is defined by nixverse and `${appOutputPath}`";
    {
      ${system} = nixverseApps // userApps;
    }
  ) systems;

  getOutputs' =
    system:
    lib.mapAttrs (
      _: output: if lib.isAttrs output && builtins.hasAttr system output then output.${system} else output
    ) finalOutputs;

  loadConfigurations =
    os:
    lib.concatMapAttrs (
      name: node:
      if node.type == "host" && node.os == os then
        {
          ${name} = node.configuration;
        }
      else
        { }
    ) nodes;

  finalOutputs =
    {
      lib = userLib;
      nixosConfigurations = loadConfigurations "nixos";
      darwinConfigurations = loadConfigurations "darwin";
      inherit apps;
      nixverse = {
        inherit
          lib
          lib'
          userNodes
          nodes
          ;
        inherit (userFlake) inputs;
        getSecrets = import ./getSecrets.nix {
          inherit
            lib
            lib'
            inputs
            userLib
            userNodes
            nodes
            ;
        };
      }
      // import ../../pkgs/nixverse/output.nix {
        inherit
          lib
          lib'
          userLib
          inputs
          userFlakePath
          userNodes
          nodes
          ;
      };
    }
    // lib.removeAttrs userOutputs [
      "lib"
      "nixosConfigurations"
      "darwinConfigurations"
      "nixverse"
      "apps"
    ];
in
assert lib.assertMsg (
  !(userOutputs ? nixosConfigurations)
) "Do not specify the nixosConfigurations flake output, it is generated automatically";
assert lib.assertMsg (
  !(userOutputs ? darwinConfigurations)
) "Do not specify the darwinConfigurations flake output, it is generated automatically";
assert lib.assertMsg (
  !(userOutputs ? lib)
) "Do not specify the lib flake output, it is generated automatically";
assert lib.assertMsg (
  !(userOutputs ? nixverse)
) "Do not specify the nixverse flake output, it is used internally by nixverse";
finalOutputs
