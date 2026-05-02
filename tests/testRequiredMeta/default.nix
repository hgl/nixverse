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
  missing-channel = {
    expr = outputs.nixverse.nodes.missing-channel;
    expectedError = {
      type = "ThrownError";
      msg = "Missing required meta configuration `channel` for host `missing-channel`";
    };
  };
  missing-system = {
    expr = outputs.nixverse.nodes.missing-system;
    expectedError = {
      type = "ThrownError";
      msg = "Missing required meta configuration `system` for host `missing-system`";
    };
  };
  unsupported-system = {
    expr = outputs.nixverse.nodes.unsupported-system;
    expectedError = {
      type = "ThrownError";
      msg = "Unsupported host system `x86_64-freebsd`";
    };
  };
}
