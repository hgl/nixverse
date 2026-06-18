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
  osTypeModuleCollision = {
    expr = outputs.nixverse.nodes.node0.config.networking.hostName;
    expectedError = {
      type = "ThrownError";
      msg = "Module `collide` exists in both `modules/os` and `modules/nixos`";
    };
  };
}
