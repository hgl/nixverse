{
  lib,
  lib',
  userFlake,
  ...
}:
let
  rawEntities = import ../../lib/load/rawEntities.nix {
    inherit lib lib' userFlake;
    userFlakePath = userFlake.outPath;
  };
in
{
  selfRef = {
    expr = rawEntities.selfRef;
    expectedError = {
      type = "ThrownError";
      msg = "Group cannot contain itself: /.+";
    };
  };
}
