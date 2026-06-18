{
  lib,
  lib',
  userFlake,
  ...
}:
let
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  outputs = lib'.load {
    inputs = userFlake.inputs // {
      self = userFlake;
    };
    flakePath = userFlake.outPath;
    inherit systems;
  };
in
{
  outputs = {
    expr = {
      inherit (outputs) template legacyPackages;
      packages = outputs.packages;
      makefileInputs = lib.mapAttrs (_: value: lib.length value) outputs.makefileInputs;
      devShellPackages = lib.mapAttrs (
        _: packages: lib.sort builtins.lessThan (map (package: package.pname or package.name) packages)
      ) outputs.devShellPackages;
      apps = lib.mapAttrs (_: apps: {
        nixverse = apps.nixverse.type == "app" && builtins.isString apps.nixverse.program;
        default = apps.default.type == "app" && builtins.isString apps.default.program;
        make = apps.make.type == "app" && builtins.isString apps.make.program;
      }) outputs.apps;
    };
    expected = {
      template = 1;
      packages = lib.genAttrs systems (system: {
        foo = "foo-${system}";
      });
      legacyPackages = {
        x86_64-linux = {
          foo = true;
          nodePkgs = true;
          nodePkgs' = "foo-x86_64-linux";
          nodeLib = true;
          nodeLib' = true;
          bar = true;
          perSystemPkgs' = "foo-x86_64-linux";
          perSystemDevShellPackages' = [
            "gawk"
            "hello"
          ];
          perSystemArgPkgs' = "foo-x86_64-linux";
        };
      }
      // lib'.concatMapListToAttrs (
        system:
        lib.optionalAttrs (system != "x86_64-linux") {
          ${system} = {
            bar = true;
            perSystemPkgs' = "foo-${system}";
            perSystemDevShellPackages' = [
              "gawk"
              "hello"
            ];
            perSystemArgPkgs' = "foo-${system}";
          };
        }
      ) systems;
      apps = lib.genAttrs systems (_: {
        nixverse = true;
        default = true;
        make = true;
      });
      makefileInputs = {
        x86_64-linux = 3;
        aarch64-linux = 2;
      };
      devShellPackages = lib.genAttrs systems (_: [
        "gawk"
        "hello"
      ]);
    };
  };
}
