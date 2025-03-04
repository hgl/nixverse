{
  lib,
  lib',
}:
{
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  mapListToAttrs = f: list: lib.listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: lib.zipAttrsWith (name: values: lib.last values) (map f list);
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
