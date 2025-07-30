{
  makefileInputs,
}:
{
  lib,
  stdenv,
  makeShellWrapper,
  gnumake,
}:
stdenv.mkDerivation {
  name = "nixverse-make";
  nativeBuildInputs = [
    makeShellWrapper
  ];
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    makeShellWrapper ${lib.getExe gnumake} $out/bin/make \
      --prefix PATH : ${lib.makeBinPath makefileInputs}
    runHook postInstall
  '';
  meta = {
    mainProgram = "make";
  };
}
