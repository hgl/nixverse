{
  lib,
  config,
  ...
}:
{
  options = {
    os = lib.mkOption {
      type = lib.types.enum [
        "nixos"
        "darwin"
      ];
    };
    channel = lib.mkOption {
      type = lib.types.nonEmptyStr;
    };
    deploy = lib.mkOption {
      type = lib.types.submodule {
        options = {
          local = lib.mkOption {
            type = lib.types.enum [
              null
              true
            ];
            default = null;
          };
          buildHost = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          targetHost = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          useRemoteSudo = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          sshOpts = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = [ ];
          };
        };
      };
      default = { };
    };
    install = lib.mkOption {
      type = lib.types.submodule {
        options = {
          buildOnRemote = lib.mkOption {
            type = lib.types.bool;
            default = config.deploy.buildHost != "";
          };
          targetHost = lib.mkOption {
            type = lib.types.str;
            default = config.deploy.targetHost;
          };
          sshOpts = lib.mkOption {
            type = lib.types.listOf lib.types.nonEmptyStr;
            default = config.deploy.sshOpts;
          };
        };
      };
      default = { };
    };
  };
  config = {
    assertions = [
      {
        assertion = config.deploy.local == true -> config.deploy.targetHost == "";
        message = "Only one of `deploy.local` and `deploy.targetHost` can be specified";
      }
      {
        assertion =
          !lib.elem config.channel [
            "any"
            "ignore"
          ];
        message = "`channel` must not be \"${config.channel}\", which is a reserved value";
      }
    ];
  };
}
