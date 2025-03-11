{
  stdenv,
  bash,
  writeTextDir,
}:
args:
derivation (
  {
    name = "shell";
    inherit (stdenv.hostPlatform) system;
    builder = "${bash}/bin/bash";
    outputs = [ "out" ];
    stdenv = writeTextDir "setup" ''
      set -e

      # This is needed for `--pure` to work as expected.
      # https://github.com/NixOS/nix/issues/5092
      export PATH=

      for p in $packages; do
        PATH=$p/bin:$PATH
      done
    '';
  }
  // args
)
