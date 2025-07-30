{
  lib,
  lib',
  userFlake,
  userFlakePath,
}:
let
  rawEntities = lib.mapAttrs (
    entityName: raw:
    {
      node = raw // {
        defs =
          recursiveFoldParentNames (
            acc: parentNames: childName:
            lib.concatMap (
              parentName:
              lib.concatMap (
                def:
                lib.optional (def.value ? common) {
                  loc = [ "common" ];
                  inherit (def) file;
                  value = def.value.common;
                }
                ++ lib.optional (lib.hasAttr childName def.value) {
                  loc = [ childName ];
                  inherit (def) file;
                  value = def.value.${childName};
                }
              ) linkedEntities.${parentName}.defs
            ) parentNames
            ++ acc
          ) [ ] [ entityName ]
          ++ raw.defs;
      };
      group =
        let
          cyclic =
            parentNames: visited: path:
            lib.any (
              parentName:
              let
                entity = linkedEntities.${parentName};
              in
              assert lib.assertMsg (!lib.hasAttr parentName visited)
                "cyclic group containment: ${lib.concatStringsSep " ⊇ " ([ parentName ] ++ path)}";
              cyclic entity.parentNames (
                visited
                // {
                  ${parentName} = true;
                }
              ) ([ parentName ] ++ path)
            ) parentNames;
          descendantNames =
            raw.childNames
            ++ recursiveFoldChildNames (
              acc: childNames: parentName:
              acc ++ childNames
            ) [ ] raw.childNames;
          nodeNames = lib.filter (name: linkedEntities.${name}.type == "node") descendantNames;
        in
        assert !(cyclic raw.parentNames { ${entityName} = true; } [ entityName ]);
        assert lib.assertMsg (lib.length nodeNames != 0) "Group is empty: ${(lib.head raw.defs).file}";
        lib.removeAttrs raw [ "defs" ]
        // {
          inherit descendantNames nodeNames;
          recursiveFoldChildNames = f: nul: recursiveFoldChildNames f nul [ entityName ];
        };
    }
    .${raw.type}
    // {
      groupNames =
        recursiveFoldParentNames (
          acc: parentNames: childName:
          parentNames ++ acc
        ) [ ] raw.parentNames
        ++ raw.parentNames;
      recursiveFoldParentNames = f: nul: recursiveFoldParentNames f nul [ entityName ];
    }
  ) linkedEntities;
  linkedEntities = lib.mapAttrs (
    entityName: raws:
    let
      reversedRaws = lib.reverseList raws;
      baseRaw = lib.findFirst (raw: raw.type != null) (lib.head reversedRaws) reversedRaws;
      type = if baseRaw.type == null then "node" else baseRaw.type;
      dir = baseRaw.dir or "nodes/${entityName}";
      defs = lib.concatMap (raw: lib.optional (raw ? def) raw.def) raws;
    in
    {
      inherit type defs;
      name = entityName;
      path = "${userFlakePath}/${dir}";
      privatePath = "${userFlakePath}/private/${dir}";
      parentNames = lib.attrNames (
        lib'.concatMapListToAttrs (
          raw: lib.optionalAttrs (raw ? parentName) { ${raw.parentName} = true; }
        ) raws
      );
    }
    // lib.optionalAttrs (type == "node") {
      createdByGroup = baseRaw.type == null;
    }
    // lib.optionalAttrs (type == "group") {
      childNames = lib.attrNames (
        lib'.concatMapListToAttrs (def: lib.removeAttrs def.value [ "common" ]) defs
      );
    }
  ) expandedEntities;
  expandedEntities = lib.zipAttrs (
    lib'.concatMapAttrsToList (
      entityName: raws:
      let
        inherit (lib.head raws) type;
      in
      lib.optionals (type == "group") (
        lib.concatMap (
          raw:
          let
            children = lib.removeAttrs raw.def.value [ "common" ];
          in
          lib.mapAttrsToList (childName: childRaw: {
            ${childName} = {
              type = null;
              dir = "nodes/${entityName}/${childName}";
              parentName = entityName;
            };
          }) children
        ) raws
      )
    ) slicedEntities
    ++ lib'.concatMapAttrsToList (
      entityName: raws:
      map (raw: {
        ${entityName} = raw;
      }) raws
    ) slicedEntities
  );
  slicedEntities = lib.zipAttrsWith (
    entityName: raws:
    let
      first = lib.elemAt raws 0;
      second = lib.elemAt raws 1;
    in
    assert lib.assertMsg (lib.length raws == 2 -> first.type == second.type)
      "${entityName} cannot simultaneously be a ${first.type} (${first.def.file}) and a ${second.type} (${second.def.file})";
    assert
      first.type == "group"
      -> lib.all (
        raw:
        assert lib.assertMsg (lib.isAttrs raw.def.value) "Group must be an attribute set: ${raw.def.file}";
        assert lib.all (
          name:
          assert lib.assertMsg (name != "current") "Node name \"current\" is reserved: ${raw.def.file}";
          assert lib.assertMsg (name != entityName) "Group cannot contain itself: ${raw.def.file}";
          true
        ) (lib.attrNames raw.def.value);
        true
      ) raws;
    raws
  ) (loadDir userFlakePath ++ loadDir "${userFlakePath}/private");
  loadDir =
    dir:
    lib.optionals (lib.pathExists "${dir}/nodes") (
      lib'.concatMapAttrsToList (
        entityName: type:
        let
          nodeFile = "${dir}/nodes/${entityName}/node.nix";
          nodeValue = import nodeFile;
          groupFile = "${dir}/nodes/${entityName}/group.nix";
          groupValue = import groupFile;
          raws =
            assert lib.assertMsg (
              lib.match "[^[:space:]._]+" entityName != null
            ) "Node name cannot contain any space, . (dot) or _ (underscore): ${dir}/nodes/${entityName}";
            assert lib.assertMsg (
              entityName != "current"
            ) "Node name \"current\" is reserved: ${dir}/nodes/${entityName}";
            lib.optional (lib.pathExists nodeFile) {
              ${entityName} = {
                type = "node";
                def = {
                  loc = [ ];
                  file = nodeFile;
                  value = nodeValue;
                };
              };
            }
            ++ lib.optional (lib.pathExists groupFile) {
              ${entityName} = {
                type = "group";
                def = {
                  loc = [ ];
                  file = groupFile;
                  value = groupValue;
                };
              };
            };
          n = lib.length raws;
        in
        lib.optional (entityName != "common" && n != 0) (
          assert lib.assertMsg (
            n == 1
          ) "${entityName} cannot simultaneously be a node (${nodeFile}) and a group (${groupFile})";
          lib.head raws
        )
      ) (builtins.readDir "${dir}/nodes")
    );
  recursiveFoldParentNames =
    f: nul: entityNames:
    let
      fold =
        nul: entityNames:
        builtins.foldl' (
          acc: entityName:
          let
            inherit (linkedEntities.${entityName}) parentNames;
          in
          fold (f acc parentNames entityName) parentNames
        ) nul entityNames;
    in
    fold nul entityNames;
  recursiveFoldChildNames =
    f: nul: entityNames:
    let
      fold =
        nul: entityNames:
        builtins.foldl' (
          acc: entityName:
          let
            childNames = linkedEntities.${entityName}.childNames or [ ];
          in
          fold (f acc childNames entityName) childNames
        ) nul entityNames;
    in
    fold nul entityNames;
in
rawEntities
