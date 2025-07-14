{ lib, ... }:
{
  options = {
    inheritLib = lib.mkEnableOption "making the lib' argument inherit nixverse's lib" // {
      default = true;
    };
  };
}
