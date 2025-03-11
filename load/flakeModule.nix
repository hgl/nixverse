{
  lib,
  ...
}:
{
  options = {
    inheritLib = lib.mkEnableOption "making the lib' argument inherit nixverse's lib" // {
      default = true;
    };
    inheritPkgs = lib.mkEnableOption "making the pkgs' argument inherit nixverse's packages" // {
      default = true;
    };
  };
}
