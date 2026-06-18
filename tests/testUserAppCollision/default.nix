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
  userAppCollision = {
    expr = outputs.apps.x86_64-linux.default;
    expectedError = {
      type = "ThrownError";
      msg = "App `x86_64-linux.default` is defined by nixverse and `outputs/perSystem/apps.nix`";
    };
  };
}
