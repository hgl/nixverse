{
  lib,
  lib',
  pkgs,
  entities,
}:
pkgs.writeShellApplication {
  name = "nixverse";
  text = ''
    echo "${lib.concatStringsSep " " (lib.attrNames entities)}"
  '';
}
