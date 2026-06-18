{
  lib,
  outputs',
  pkgs,
  pkgs',
  ...
}:
{
  bar = pkgs ? gawk;
  perSystemPkgs' = outputs'.packages.foo;
  perSystemDevShellPackages' = lib.sort builtins.lessThan (
    map (package: package.pname or package.name) outputs'.devShellPackages
  );
  perSystemArgPkgs' = pkgs'.foo;
}
