{
  lib,
  lib',
  userLib,
  userInputs,
  userFlakePath,
  userEntities,
  entities,
}:
{
  getNodeNames =
    entityNames:
    lib.attrNames (
      lib'.concatMapListToAttrs (
        entityName:
        let
          entity = entities.${entityName};
        in
        assert lib.assertMsg (lib.hasAttr entityName entities) "Unknown node ${entityName}";
        {
          node = {
            ${entityName} = true;
          };
          group = lib.mapAttrs (nodeName: node: true) entity.nodes;
        }
        .${entity.type}
      ) entityNames
    );
  validNodeName =
    nodeName:
    assert lib.assertMsg (lib.hasAttr nodeName entities) "Unknown node ${nodeName}";
    assert lib.assertMsg (entities.${nodeName}.type == "node") "${nodeName} is a group, not a node";
    true;
  getNodesMakefile =
    nodeNames: lib.concatLines (map (nodeName: "$(eval $(call DefineNode,${nodeName}))") nodeNames);
  getSecretsMakefile =
    nodeNames:
    lib.concatLines (
      map (
        nodeName:
        let
          node = entities.${nodeName};
        in
        "$(eval $(call DefineNodeSecrets,${nodeName},${node.dir}))"
      ) nodeNames
      ++ [
        "$(eval $(call DefineNodesSecrets,${toString nodeNames}))"
      ]
    );
  getNodesSecrets =
    secrets: nodeNames:
    let
      removeHiddenSecrets =
        attrs:
        if lib.isAttrs attrs then
          lib.concatMapAttrs (
            k: v:
            let
              removed = removeHiddenSecrets v;
            in
            lib.optionalAttrs (!lib.hasPrefix "_" k && removed != { }) { ${k} = removed; }
          ) attrs
        else if lib.isList attrs then
          map removeHiddenSecrets attrs
        else
          attrs;
    in
    lib.genAttrs nodeNames (nodeName: {
      "secrets.json" = builtins.toJSON (removeHiddenSecrets (secrets.nodes.${nodeName}));
    });
  getFSEntries =
    nodeNames:
    lib.concatLines (
      map (
        nodeName:
        let
          node = entities.${nodeName};
        in
        "${nodeName},${node.dir},${toString (lib.attrNames node.groups)}"
      ) nodeNames
    );
  userMakefile = lib.concatLines (
    lib'.concatMapAttrsToList (
      entityName: entity:
      {
        node = [
          ".PHONY: nodes/${entityName}"
          "node_${entityName}_os := ${entity.os}"
          "node_${entityName}_channel := ${entity.channel}"
        ];
        group = [
          ".PHONY: nodes/${entityName}"
          "nodes/${entityName}: ${
            toString (map (descendantName: "nodes/${descendantName}") (lib.attrNames entity.descendants))
          }"
          "group_${entityName}_nodes := ${toString (lib.attrNames entity.nodes)}"
        ];
      }
      .${entity.type}
    ) entities
  );
  getNodeInstallCommands =
    nodeNames: userFlakeSourcePath:
    map (
      nodeName:
      let
        node = entities.${nodeName};
        buildOn = "--build-on ${if node.install.buildOnRemote then "remote" else "local"}";
        useSubstitutes = lib.optionalString (!node.install.useSubstitutes) "--no-substitute-on-destination";
        extraFiles = "--extra-files '${userFlakeSourcePath}/build/nodes/${nodeName}/fs'";
      in
      assert lib.assertMsg (
        node.os != "darwin"
      ) "Deploy to the darwin node ${nodeName} directlt to install nix-darwin";
      assert lib.assertMsg (
        node.install.targetHost != null
      ) "Missing meta configuration install.targetHost for node ${nodeName}";
      assert lib.assertMsg (node.diskConfigPaths != [ ]) "Missing disk-config.nix for node ${nodeName}";
      {
        name = nodeName;
        command = ''
          nixos-anywhere --no-disko-deps \
            --flake '${userFlakePath}#${nodeName}' \
            --generate-hardware-config nixos-generate-config '${userFlakePath}/${node.dir}/hardware-configuration.nix' \
            ${buildOn} ${useSubstitutes} ${extraFiles} ${lib.escapeShellArg node.install.targetHost}
        '';
      }
    ) nodeNames;
  getNodeBuildCommands =
    nodeNames:
    map (
      nodeName:
      let
        node = entities.${nodeName};
        attrPath =
          {
            nixos = "nixosConfigurations.${nodeName}.config.system.build.toplevel";
            darwin = "darwinConfigurations.${nodeName}.system";
          }
          .${node.os};
      in
      {
        name = nodeName;
        command = "nix build --no-link --show-trace '${userFlakePath}#${attrPath}'";
      }
    ) nodeNames;
  getNodeDeployCommands =
    nodeNames: userFlakeSourcePath: nixversePath:
    let
      localNodeNames = lib.filter (nodeName: entities.${nodeName}.deploy.targetHost == null) nodeNames;
    in
    assert lib.assertMsg (
      lib.length localNodeNames <= 1
    ) "Deploying multiple local nodes in parallel is not allowed";
    map (
      nodeName:
      let
        node = entities.${nodeName};
        targetHost = lib.optionalString (
          node.deploy.targetHost != null
        ) "--target-host ${lib.escapeShellArg node.deploy.targetHost}";
        buildHost = lib.optionalString (
          node.deploy.targetHost != null && node.deploy.buildOnRemote
        ) "--build-host ${lib.escapeShellArg node.deploy.targetHost}";
        useSubstitutes = lib.optionalString (node.deploy.useSubstitutes) "--use-substitutes";
        useRemoteSudo = lib.optionalString (node.deploy.useRemoteSudo) "--use-remote-sudo";
        sshOpts = "NIX_SSHOPTS=${
          lib.escapeShellArg (map (opt: "-o ${lib.escapeShellArg opt}") node.deploy.sshOpts)
        }";
        common = "--flake '${userFlakePath}#${nodeName}' --show-trace";
        rebuild =
          {
            nixos = "${sshOpts} nixos-rebuild-ng switch ${targetHost} ${buildHost} ${useSubstitutes} ${useRemoteSudo} ${common}";
            darwin = "sudo darwin-rebuild switch ${common}";
          }
          .${node.os};
      in
      {
        name = nodeName;
        command = lib.concatLines (
          [ rebuild ]
          ++ lib.optionals (node.deploy.targetHost != null) [
            ". ${nixversePath}/lib/nixverse/utils.sh"
            "rsync_fs '${node.deploy.targetHost}' '${userFlakeSourcePath}/build/nodes/${nodeName}/fs'"
          ]
        );
      }
    ) nodeNames;
  getNodeRsyncCommands =
    nodeNames: userFlakeSourcePath: nixversePath:
    let
      localNodeNames = lib.filter (nodeName: entities.${nodeName}.deploy.targetHost == null) nodeNames;
    in
    assert lib.assertMsg (
      lib.length localNodeNames <= 1
    ) "Deploying multiple local nodes in parallel is not allowed";
    lib.concatMap (
      nodeName:
      let
        node = entities.${nodeName};
      in
      lib.optional (node.deploy.targetHost != null) {
        name = nodeName;
        command = lib.concatLines [
          ". ${nixversePath}/lib/nixverse/utils.sh"
          "rsync_fs '${node.deploy.targetHost}' '${userFlakeSourcePath}/build/nodes/${nodeName}/fs'"
        ];
      }
    ) nodeNames;
}
