{
  lib,
  lib',
  userFlake,
  ...
}:
let
  userBundleNames = import ../../lib/load/userBundleNames.nix {
    inherit lib;
    userFlakePath = userFlake.outPath;
  };
  getUserModules = import ../../lib/load/getUserModules.nix {
    inherit lib lib' userBundleNames;
    userFlakePath = userFlake.outPath;
  };
  evalModule = module: (lib.evalModules { modules = [ module ]; }).config.test;
in
{
  osModules = {
    expr = {
      nixosOsOnly = (evalModule (getUserModules "nixos").osOnly).osOnly;
      darwinOsOnly = (evalModule (getUserModules "darwin").osOnly).osOnly;
      nixosOverridden = (evalModule (getUserModules "nixos").overridden).overridden;
      darwinOverridden = (evalModule (getUserModules "darwin").overridden).overridden;
    };
    expected = {
      nixosOsOnly = "os";
      darwinOsOnly = "os";
      nixosOverridden = "nixos";
      darwinOverridden = "darwin";
    };
  };
}
