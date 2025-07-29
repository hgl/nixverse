{ lib, config, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    os = mkOption {
      type = types.enum [
        "nixos"
        "darwin"
      ];
    };
    channel = mkOption {
      type = types.addCheck types.nonEmptyStr (x: x != "any");
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
            default = false;
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
