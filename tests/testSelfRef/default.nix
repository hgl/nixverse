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
  selfRef = {
    expr = rawNodes.selfRef;
    expectedError = {
      type = "ThrownError";
      msg = "Group cannot contain itself: /.+";
    };
  };
}
