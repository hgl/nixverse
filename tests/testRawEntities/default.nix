{
  lib,
  lib',
  userFlake,
  ...
}:
let
  rawNodes = import ../../lib/load/rawNodes.nix {
    inherit lib lib';
    userFlakePath = userFlake.outPath;
  };
  group0 = { };
  common = {
    system = "x86_64-linux";
    channel = "unstable";
  };
in
{
  rawNodes = {
    expr = lib.mapAttrs (
      nodeName: rawNode:
      lib.removeAttrs rawNode [
        "recursiveFoldChildNames"
        "recursiveFoldParentNames"
      ]
    ) rawNodes;
    expected = {
      node0 = {
        type = "host";
        name = "node0";
        createdByGroup = false;
        path = "${userFlake}/nodes/node0";
        privatePath = "${userFlake}/private/nodes/node0";
        parentNames = [ "group0" ];
        groupNames = [
          "parentGroup0"
          "group0"
        ];
        defs = [
          {
            loc = [ "group0" ];
            file = "${userFlake}/nodes/parentGroup0/group.nix";
            value = group0;
          }
          {
            loc = [ "common" ];
            file = "${userFlake}/nodes/group0/group.nix";
            value = common;
          }
          {
            loc = [ "node0" ];
            file = "${userFlake}/nodes/group0/group.nix";
            value = { };
          }
          {
            loc = [ ];
            file = "${userFlake}/nodes/node0/host.nix";
            value = {
              system = "x86_64-linux";
              channel = "unstable";
            };
          }
        ];
      };
      groupNode0 = {
        type = "host";
        name = "groupNode0";
        createdByGroup = true;
        path = "${userFlake}/nodes/group1/groupNode0";
        privatePath = "${userFlake}/private/nodes/group1/groupNode0";
        parentNames = [
          "group0"
          "group1"
        ];
        groupNames = [
          "parentGroup0"
          "group0"
          "group1"
        ];
        defs = [
          {
            loc = [ "group0" ];
            file = "${userFlake}/nodes/parentGroup0/group.nix";
            value = group0;
          }
          {
            loc = [ "common" ];
            file = "${userFlake}/nodes/group0/group.nix";
            value = common;
          }
          {
            loc = [ "groupNode0" ];
            file = "${userFlake}/nodes/group0/group.nix";
            value = { };
          }
          {
            loc = [ "groupNode0" ];
            file = "${userFlake}/nodes/group1/group.nix";
            value = { };
          }
        ];
      };
      group0 = {
        type = "group";
        name = "group0";
        path = "${userFlake}/nodes/group0";
        privatePath = "${userFlake}/private/nodes/group0";
        childNames = [
          "groupNode0"
          "node0"
        ];
        descendantNames = [
          "groupNode0"
          "node0"
        ];
        hostNames = [
          "groupNode0"
          "node0"
        ];
        parentNames = [ "parentGroup0" ];
        groupNames = [ "parentGroup0" ];
      };
      group1 = {
        type = "group";
        name = "group1";
        path = "${userFlake}/nodes/group1";
        privatePath = "${userFlake}/private/nodes/group1";
        childNames = [
          "groupNode0"
          "node1priv"
        ];
        descendantNames = [
          "groupNode0"
          "node1priv"
        ];
        hostNames = [
          "groupNode0"
          "node1priv"
        ];
        parentNames = [ ];
        groupNames = [ ];
      };
      parentGroup0 = {
        type = "group";
        name = "parentGroup0";
        path = "${userFlake}/nodes/parentGroup0";
        privatePath = "${userFlake}/private/nodes/parentGroup0";
        childNames = [ "group0" ];
        parentNames = [ ];
        groupNames = [ ];
        descendantNames = [
          "group0"
          "groupNode0"
          "node0"
        ];
        hostNames = [
          "groupNode0"
          "node0"
        ];
      };
      node1priv = {
        type = "host";
        name = "node1priv";
        createdByGroup = false;
        path = "${userFlake}/nodes/node1priv";
        privatePath = "${userFlake}/private/nodes/node1priv";
        parentNames = [ "group1" ];
        groupNames = [ "group1" ];
        defs = [
          {
            loc = [ "node1priv" ];
            file = "${userFlake}/private/nodes/group1/group.nix";
            value = { };
          }
          {
            loc = [ ];
            file = "${userFlake}/private/nodes/node1priv/host.nix";
            value = { };
          }
        ];
      };
    };
  };
}
