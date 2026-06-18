{
  lib,
  lib',
  userLib,
  inputs,
  userFlakePath,
  userNodes,
  nodes,
}:
{
  getNodeNames =
    nodeNames:
    lib.attrNames (
      lib'.concatMapListToAttrs (
        nodeName:
        let
          node = nodes.${nodeName};
        in
        assert lib.assertMsg (lib.hasAttr nodeName nodes) "Unknown node ${nodeName}";
        {
          host = {
            ${nodeName} = true;
          };
          group = lib.mapAttrs (nodeName: node: true) node.hosts;
        }
        .${node.type}
      ) nodeNames
    );
  validNodeName =
    nodeName:
    assert lib.assertMsg (lib.hasAttr nodeName nodes) "Unknown node ${nodeName}";
    assert lib.assertMsg (nodes.${nodeName}.type == "host") "${nodeName} is a group, not a node";
    true;
  getNodesMakefile =
    nodeNames: lib.concatLines (map (nodeName: "$(eval $(call DefineNode,${nodeName}))") nodeNames);
  getSecretsMakefile =
    nodeNames:
    lib.concatLines (
      map (
        nodeName:
        let
          node = nodes.${nodeName};
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
          node = nodes.${nodeName};
        in
        "${nodeName},${node.dir},${toString (lib.attrNames node.groups)}"
      ) nodeNames
    );
  userMakefile = lib.concatLines (
    lib'.concatMapAttrsToList (
      nodeName: node:
      {
        host = [
          ".PHONY: nodes/${nodeName}"
          "node_${nodeName}_os := ${node.os}"
          "node_${nodeName}_channel := ${node.channel}"
        ];
        group = [
          ".PHONY: nodes/${nodeName}"
          "nodes/${nodeName}: ${
            toString (map (descendantName: "nodes/${descendantName}") (lib.attrNames node.descendants))
          }"
          "group_${nodeName}_nodes := ${toString (lib.attrNames node.hosts)}"
        ];
      }
      .${node.type}
    ) nodes
  );
  getNodeInstallCommands =
    {
      nodeNames,
      userFlakeSourcePath,
      reboot,
      lustrate,
    }:
    map (
      nodeName:
      let
        node = nodes.${nodeName};
        targetHostArg = lib.escapeShellArg node.install.targetHost;
        sshOpts = "${lib.escapeShellArg (map (opt: "-o ${lib.escapeShellArg opt}") node.deploy.sshOpts)}";
        hwFileArg = lib.escapeShellArg "${userFlakeSourcePath}/${node.dir}/hardware-configuration.nix";
        flakeArg = "--flake ${lib.escapeShellArg "${userFlakeSourcePath}#${nodeName}"}";
        fsDirArg = lib.escapeShellArg "${userFlakeSourcePath}/build/nodes/${nodeName}/fs";
      in
      assert lib.assertMsg (
        node.os != "darwin"
      ) "Deploy to the darwin node ${nodeName} directly to install nix-darwin";
      assert lib.assertMsg (
        node.install.targetHost != null
      ) "Missing meta configuration install.targetHost for node ${nodeName}";
      {
        name = nodeName;
        command =
          if lustrate then
            ''
              set -euo pipefail

              cmd=$(cat <<'EOF'
              set -euo pipefail

              mem_swap_less_than_1g() {
                awk '
                  BEGIN { size = 0 }
                  /^MemTotal:/ { size += $2 }
                  /^SwapTotal:/ { size += $2 }
                  END { exit (size < 1024 * 1024 ? 0 : 1) }
                ' /proc/meminfo
              }
              if mem_swap_less_than_1g; then
                dd if=/dev/zero of=/swapfile bs=1M count=1024
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
              fi
              tar -C / -xf- --no-same-owner || [[ $? = 2 ]]
              if ! command -v nix &>/dev/null; then
                install_url='https://artifacts.nixos.org/experimental-installer'
                curl --fail --silent --show-error --location --proto =https \
                  --tlsv1.2 --location "$install_url" | sh -s -- install --no-confirm
                . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
              fi

              : >/etc/NIXOS
              cat <<EOF2 >/etc/NIXOS_LUSTRATE
              /etc/ssh/ssh_host_ed25519_key
              /etc/ssh/ssh_host_ed25519_key.pub
              EOF2

              nix profile add nixpkgs#nixos-install-tools
              if [[ -d /boot/efi ]]; then
                umount /boot/efi
              fi
              find /boot -mindepth 1 -delete
              EOF
              )
              if [[ -d ${fsDirArg} ]]; then
                tar -C ${fsDirArg} -cpf- .
              else
                :
              fi | ssh ${targetHostArg} "$cmd"

              if [[ ! -e ${hwFileArg} ]]; then
                ssh ${targetHostArg} nixos-generate-config \
                  --show-hardware-config >${hwFileArg}
                git add --intent-to-add --force ${hwFileArg}
              fi

              NIX_SSHOPTS=${sshOpts} nixos-rebuild boot \
                --install-bootloader --target-host ${targetHostArg} ${flakeArg} \
                ${lib.optionalString node.install.useSubstitutes "--use-substitutes"} \
                ${lib.optionalString node.install.useRemoteSudo "--use-remote-sudo"} \
                "$@"
              ssh ${targetHostArg} reboot
            ''
          else
            ''
              if [[ -d ${fsDirArg} ]]; then
                set -- --extra-files ${fsDirArg}
              fi
              nixos-anywhere --no-disko-deps \
                ${flakeArg} ${sshOpts} \
                --build-on ${if node.install.buildOnRemote then "remote" else "local"} \
                --phases kexec,disko,install${lib.optionalString reboot ",reboot"} \
                ${lib.optionalString (!node.install.useSubstitutes) "--no-substitute-on-destination"} \
                --generate-hardware-config nixos-generate-config ${hwFileArg} \
                "$@" ${targetHostArg}
            '';
      }
    ) nodeNames;
  getNodeBuildCommands =
    nodeNames:
    map (
      nodeName:
      let
        node = nodes.${nodeName};
        attrPath =
          {
            nixos = "nixosConfigurations.${nodeName}.config.system.build.toplevel";
            darwin = "darwinConfigurations.${nodeName}.system";
          }
          .${node.os};
      in
      {
        name = nodeName;
        command = "nix build --no-link --show-trace ${lib.escapeShellArg "${userFlakePath}#${attrPath}"}";
      }
    ) nodeNames;
  getNodeDeployCommands =
    {
      nodeNames,
      userFlakeSourcePath,
      nixversePath,
      dryRun,
      ephemeral,
      reboot,
    }:
    let
      localNodeNames = lib.filter (nodeName: nodes.${nodeName}.deploy.targetHost == null) nodeNames;
    in
    assert lib.assertMsg (
      lib.length localNodeNames <= 1
    ) "Deploying multiple local nodes in parallel is not allowed";
    map (
      nodeName:
      let
        node = nodes.${nodeName};
        targetHost = lib.optionalString (
          node.deploy.targetHost != null
        ) "--target-host ${lib.escapeShellArg node.deploy.targetHost}";
        buildHost = lib.optionalString (
          node.deploy.targetHost != null && node.deploy.buildOnRemote
        ) "--build-host ${lib.escapeShellArg node.deploy.targetHost}";
        useSubstitutes = lib.optionalString (node.deploy.useSubstitutes) "--use-substitutes";
        useRemoteSudo = lib.optionalString (node.deploy.useRemoteSudo) "--use-remote-sudo";
        sshOpts = map (opt: "-o ${lib.escapeShellArg opt}") node.deploy.sshOpts;
        common = "--flake '${userFlakePath}#${nodeName}' --show-trace";
        rebuildAction =
          if dryRun then
            "build"
          else if ephemeral then
            "test"
          else if reboot then
            "boot"
          else
            "switch";
        rebuild =
          {
            nixos = "NIX_SSHOPTS=${lib.escapeShellArg sshOpts} nixos-rebuild ${rebuildAction} ${targetHost} ${buildHost} ${useSubstitutes} ${useRemoteSudo} ${common}";
            darwin = "sudo darwin-rebuild ${if dryRun then "build" else "switch"} ${common}";
          }
          .${node.os};
        rebootCommand =
          if node.deploy.targetHost != null then
            "ssh ${lib.concatStringsSep " " sshOpts} ${lib.escapeShellArg node.deploy.targetHost} ${lib.optionalString node.deploy.useRemoteSudo "sudo "}reboot"
          else
            "reboot";
      in
      assert lib.assertMsg (
        reboot -> node.os == "nixos"
      ) "--reboot is only supported for a NixOS node, which ${nodeName} is not";
      assert lib.assertMsg (
        ephemeral -> node.os == "nixos"
      ) "--ephemeral is only supported for a NixOS node, which ${nodeName} is not";
      {
        name = nodeName;
        command = lib.concatLines (
          [
            "set -e"
            rebuild
          ]
          ++ lib.optionals (node.deploy.targetHost != null) [
            ". ${lib.escapeShellArg "${nixversePath}/share/nixverse/utils.sh"}"
            "rsync_fs ${lib.escapeShellArg node.deploy.targetHost} ${lib.escapeShellArg "${userFlakeSourcePath}/build/nodes/${nodeName}/fs"}"
          ]
          ++ lib.optional reboot rebootCommand
        );
      }
    ) nodeNames;
  getNodeGenhwCommands =
    {
      nodeNames,
      userFlakeSourcePath,
      nixversePath,
    }:
    map (
      nodeName:
      let
        node = nodes.${nodeName};
      in
      assert lib.assertMsg (
        node.deploy.targetHost != null
      ) "Missing meta configuration deploy.targetHost for node  ${nodeName}";
      {
        name = nodeName;
        command = ''
          ssh ${lib.escapeShellArg node.deploy.targetHost} nixos-generate-config --show-hardware-config \
            >${lib.escapeShellArg "${userFlakeSourcePath}/${node.dir}/hardware-configuration.nix"}
        '';
      }
    ) nodeNames;
  getNodeRsyncCommands =
    nodeNames: userFlakeSourcePath: nixversePath:
    let
      localNodeNames = lib.filter (nodeName: nodes.${nodeName}.deploy.targetHost == null) nodeNames;
    in
    assert lib.assertMsg (
      lib.length localNodeNames <= 1
    ) "Deploying multiple local nodes in parallel is not allowed";
    lib.concatMap (
      nodeName:
      let
        node = nodes.${nodeName};
      in
      lib.optional (node.deploy.targetHost != null) {
        name = nodeName;
        command = lib.concatLines [
          ". ${nixversePath}/share/nixverse/utils.sh"
          "rsync_fs '${node.deploy.targetHost}' '${userFlakeSourcePath}/build/nodes/${nodeName}/fs'"
        ];
      }
    ) nodeNames;
}
