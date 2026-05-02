{
  lib,
  lib',
  userFlake,
  ...
}:
let
  rawNodes = import ../../lib/load/rawNodes.nix {
    inherit lib lib';
    userFlakePath = userFlake.outPath;
  };
in
{
  empty = {
    expr = rawNodes.group;
    expectedError = {
      type = "ThrownError";
      msg = "Group is empty: ${userFlake}/nodes/group/group.nix";
    };
  };
}
