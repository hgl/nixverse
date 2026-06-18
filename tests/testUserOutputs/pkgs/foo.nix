{ inputs', stdenv }:
assert inputs'.sample.packages.pkg == "pkg-${stdenv.hostPlatform.system}";
"foo-${stdenv.hostPlatform.system}"
