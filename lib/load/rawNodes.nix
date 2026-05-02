{
  lib,
  lib',
  userFlakePath,
}:
let
  rawNodes = lib.mapAttrs (
    nodeName: raw:
    {
      host = raw // {
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
              ) linkedNodes.${parentName}.defs
            ) parentNames
            ++ acc
          ) [ ] [ nodeName ]
          ++ raw.defs;
      };
      group =
        let
          cyclic =
            parentNames: visited: path:
            lib.any (
              parentName:
              let
                node = linkedNodes.${parentName};
              in
              assert lib.assertMsg (!lib.hasAttr parentName visited)
                "cyclic group containment: ${lib.concatStringsSep " ⊇ " ([ parentName ] ++ path)}";
              cyclic node.parentNames (
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
          hostNames = lib.filter (name: linkedNodes.${name}.type == "host") descendantNames;
        in
        assert !(cyclic raw.parentNames { ${nodeName} = true; } [ nodeName ]);
        assert lib.assertMsg (lib.length hostNames != 0) "Group is empty: ${(lib.head raw.defs).file}";
        lib.removeAttrs raw [ "defs" ]
        // {
          inherit descendantNames hostNames;
          recursiveFoldChildNames = f: nul: recursiveFoldChildNames f nul [ nodeName ];
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
      recursiveFoldParentNames = f: nul: recursiveFoldParentNames f nul [ nodeName ];
    }
  ) linkedNodes;
  linkedNodes = lib.mapAttrs (
    nodeName: raws:
    let
      reversedRaws = lib.reverseList raws;
      baseRaw = lib.findFirst (raw: raw.type != null) (lib.head reversedRaws) reversedRaws;
      type = if baseRaw.type == null then "host" else baseRaw.type;
      dir = baseRaw.dir or "nodes/${nodeName}";
      defs = lib.concatMap (raw: lib.optional (raw ? def) raw.def) raws;
    in
    {
      inherit type defs;
      name = nodeName;
      path = "${userFlakePath}/${dir}";
      privatePath = "${userFlakePath}/private/${dir}";
      parentNames = lib.attrNames (
        lib'.concatMapListToAttrs (
          raw: lib.optionalAttrs (raw ? parentName) { ${raw.parentName} = true; }
        ) raws
      );
    }
    // lib.optionalAttrs (type == "host") {
      createdByGroup = baseRaw.type == null;
    }
    // lib.optionalAttrs (type == "group") {
      childNames = lib.attrNames (
        lib'.concatMapListToAttrs (def: lib.removeAttrs def.value [ "common" ]) defs
      );
    }
  ) expandedNodes;
  expandedNodes = lib.zipAttrs (
    lib'.concatMapAttrsToList (
      nodeName: raws:
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
              dir = "nodes/${nodeName}/${childName}";
              parentName = nodeName;
            };
          }) children
        ) raws
      )
    ) slicedNodes
    ++ lib'.concatMapAttrsToList (
      nodeName: raws:
      map (raw: {
        ${nodeName} = raw;
      }) raws
    ) slicedNodes
  );
  slicedNodes = lib.zipAttrsWith (
    nodeName: raws:
    let
      first = lib.elemAt raws 0;
      second = lib.elemAt raws 1;
    in
    assert lib.assertMsg (lib.length raws == 2 -> first.type == second.type)
      "${nodeName} cannot simultaneously be a ${first.type} (${first.def.file}) and a ${second.type} (${second.def.file})";
    assert
      first.type == "group"
      -> lib.all (
        raw:
        assert lib.assertMsg (lib.isAttrs raw.def.value) "Group must be an attribute set: ${raw.def.file}";
        assert lib.all (
          name:
          assert lib.assertMsg (name != "current") "Node name \"current\" is reserved: ${raw.def.file}";
          assert lib.assertMsg (name != nodeName) "Group cannot contain itself: ${raw.def.file}";
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
        nodeName: type:
        let
          hostFile = "${dir}/nodes/${nodeName}/host.nix";
          hostValue = import hostFile;
          groupFile = "${dir}/nodes/${nodeName}/group.nix";
          groupValue = import groupFile;
          raws =
            assert lib.assertMsg (
              lib.match "[^[:space:]._]+" nodeName != null
            ) "Node name cannot contain any space, . (dot) or _ (underscore): ${dir}/nodes/${nodeName}";
            assert lib.assertMsg (
              nodeName != "current"
            ) "Node name \"current\" is reserved: ${dir}/nodes/${nodeName}";
            lib.optional (lib.pathExists hostFile) {
              ${nodeName} = {
                type = "host";
                def = {
                  loc = [ ];
                  file = hostFile;
                  value = hostValue;
                };
              };
            }
            ++ lib.optional (lib.pathExists groupFile) {
              ${nodeName} = {
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
        lib.optional (nodeName != "common" && n != 0) (
          assert lib.assertMsg (
            n == 1
          ) "${nodeName} cannot simultaneously be a host (${hostFile}) and a group (${groupFile})";
          lib.head raws
        )
      ) (builtins.readDir "${dir}/nodes")
    );
  recursiveFoldParentNames =
    f: nul: nodeNames:
    let
      fold =
        nul: nodeNames:
        builtins.foldl' (
          acc: nodeName:
          let
            inherit (linkedNodes.${nodeName}) parentNames;
          in
          fold (f acc parentNames nodeName) parentNames
        ) nul nodeNames;
    in
    fold nul nodeNames;
  recursiveFoldChildNames =
    f: nul: nodeNames:
    let
      fold =
        nul: nodeNames:
        builtins.foldl' (
          acc: nodeName:
          let
            childNames = linkedNodes.${nodeName}.childNames or [ ];
          in
          fold (f acc childNames nodeName) childNames
        ) nul nodeNames;
    in
    fold nul nodeNames;
in
rawNodes
