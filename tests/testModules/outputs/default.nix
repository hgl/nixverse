{
  lib,
  darwinModules',
  nixosModules',
  ...
}:
let
  evalModule = module: (lib.evalModules { modules = [ module ]; }).config.test;
in
{
  flake.moduleValues = {
    nixosOsOnly = (evalModule nixosModules'.osOnly).osOnly;
    darwinOsOnly = (evalModule darwinModules'.osOnly).osOnly;
    nixosOverridden = (evalModule nixosModules'.overridden).overridden;
    darwinOverridden = (evalModule darwinModules'.overridden).overridden;
  };
}
