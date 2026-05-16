{
  lib',
  userFlake,
  ...
}:
let
  outputs = lib'.load {
    inputs = userFlake.inputs // {
      self = userFlake;
    };
    flakePath = userFlake.outPath;
  };
in
{
  osModules = {
    expr = outputs.moduleValues;
    expected = {
      nixosOsOnly = "os";
      darwinOsOnly = "os";
      nixosOverridden = "nixos";
      darwinOverridden = "darwin";
    };
  };
}
