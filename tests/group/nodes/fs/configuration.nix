{
  nixpkgs.hostPlatform = "x86_64-linux";
  fileSystems = {
    "/" = {
      fsType = "zfs";
    };
  };
}
