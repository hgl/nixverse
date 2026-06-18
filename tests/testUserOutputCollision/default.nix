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
    systems = [ "x86_64-linux" ];
  };
in
{
  userOutputSystemNestedCollision = {
    expr = outputs.legacyPackages.x86_64-linux.foo;
    expectedError = {
      type = "ThrownError";
      msg = "Output `legacyPackages.x86_64-linux.foo` is defined in both `outputs/flake/legacyPackages.nix` and `outputs/perSystem/legacyPackages.nix`";
    };
  };
  userOutputSystemTypeCollision = {
    expr = outputs.mismatch.x86_64-linux;
    expectedError = {
      type = "ThrownError";
      msg = "Output `mismatch.x86_64-linux` is defined in both `outputs/flake/mismatch.nix` and `outputs/perSystem/mismatch.nix`, but the values are not both attribute sets or both lists";
    };
  };
}
