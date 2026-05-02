{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  systemSuffix = lib.last (lib.splitString "-" config.system);
in
{
  options = {
    os = mkOption {
      type = types.enum [
        "nixos"
        "darwin"
      ];
      readOnly = true;
      default =
        {
          darwin = "darwin";
          linux = "nixos";
        }
        .${systemSuffix} or (throw "Unsupported host system `${config.system}`");
    };
    channel = mkOption {
      type = types.addCheck types.nonEmptyStr (x: x != "any");
    };
    system = mkOption {
      type = types.nonEmptyStr;
    };
    deploy = mkOption {
      type = types.submodule {
        options = {
          targetHost = mkOption {
            type = types.nullOr types.nonEmptyStr;
            default = null;
          };
          buildOnRemote = mkOption {
            type = types.bool;
            default = false;
          };
          useSubstitutes = mkOption {
            type = types.bool;
            default = true;
          };
          useRemoteSudo = mkOption {
            type = types.bool;
            default = false;
          };
          sshOpts = mkOption {
            type = types.listOf types.nonEmptyStr;
            default = [ ];
          };
        };
      };
      default = { };
    };
    install = mkOption {
      type = types.submodule {
        options = {
          targetHost = mkOption {
            type = types.str;
            default = config.deploy.targetHost;
          };
          buildOnRemote = mkOption {
            type = types.bool;
            default = config.deploy.buildOnRemote;
          };
          useSubstitutes = mkOption {
            type = types.bool;
            default = config.deploy.useSubstitutes;
          };
          useRemoteSudo = mkOption {
            type = types.bool;
            default = config.deploy.useRemoteSudo;
          };
          sshOpts = mkOption {
            type = types.listOf types.nonEmptyStr;
            default = config.deploy.sshOpts;
          };
        };
      };
      default = { };
    };
  };
}
