{
  lib,
  lib',
}:
{

  importDirOrFile =
    base: name: default:
    (lib'.internal.importDirAttrs base).${name} or default;
  importDirAttrs =
    base:
    if lib.pathExists base then
      lib.concatMapAttrs (
        name: v:
        if v == "directory" then
          if lib.pathExists "${base}/${name}/default.nix" then
            {
              ${name} = import "${base}/${name}";
            }
          else
            { }
        else
          let
            n = lib.removeSuffix ".nix" name;
          in
          if n != name then
            {
              ${n} = import "${base}/${name}";
            }
          else
            { }
      ) (builtins.readDir base)
    else
      { };
  call =
    f: args:
    if lib.isFunction f then
      let
        params = lib.functionArgs f;
      in
      f (if params == { } then args else lib.intersectAttrs params args)
    else
      f;
  joinPath =
    parts:
    "${lib.head parts}${
      lib.concatStrings (map (part: if part == "" then "" else "/${part}") (lib.drop 1 parts))
    }";
  optionalPath = path: if lib.pathExists path then [ path ] else [ ];
  recursiveFilter =
    pred: v:
    if lib.isAttrs v then
      lib.concatMapAttrs (
        name: subv:
        if pred name subv then
          {
            ${name} = lib'.internal.recursiveFilter pred subv;
          }
        else
          { }
      ) v
    else if lib.isList v then
      lib.concatLists (
        lib.imap0 (i: subv: if pred i subv then [ (lib'.internal.recursiveFilter pred subv) ] else [ ]) v
      )
    else
      v;
  evalModulesAssertWarn =
    args:
    let
      result = lib.evalModules (
        args
        // {
          modules = args.modules or [ ] ++ [
            {
              options = {
                assertions = lib.mkOption {
                  type = lib.types.listOf lib.types.unspecified;
                  internal = true;
                  default = [ ];
                  example = [
                    {
                      assertion = false;
                      message = "you can't enable this for that reason";
                    }
                  ];
                  description = ''
                    This option allows modules to express conditions that must
                    hold for the evaluation of the system configuration to
                    succeed, along with associated error messages for the user.
                  '';
                };
                warnings = lib.mkOption {
                  internal = true;
                  default = [ ];
                  type = lib.types.listOf lib.types.str;
                  example = [ "The `foo' service is deprecated and will go away soon!" ];
                  description = ''
                    This option allows modules to show warnings to users during
                    the evaluation of the system configuration.
                  '';
                };
              };
            }
          ];
        }
      );
      failedAssertions = map (x: x.message) (lib.filter (x: !x.assertion) result.config.assertions);
    in
    if failedAssertions != [ ] then
      throw "\nFailed assertions:\n${lib.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else
      lib.showWarnings result.config.warnings (
        result
        // {
          config = lib.removeAttrs result.config [
            "assertions"
            "warnings"
          ];
        }
      );
}
