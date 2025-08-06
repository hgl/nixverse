{
  lib,
  lib',
  userFlake,
  ...
}:
let
  rawEntities = import ../../lib/load/rawEntities.nix {
    inherit lib lib';
    userFlakePath = userFlake.outPath;
  };
  group0 = { };
  common = {
    os = "nixos";
    channel = "unstable";
  };
in
{
  rawEntities = {
    expr = lib.mapAttrs (
      entityName: rawEntity:
      lib.removeAttrs rawEntity [
        "recursiveFoldChildNames"
        "recursiveFoldParentNames"
      ]
    ) rawEntities;
    expected = {
      node0 = {
        type = "node";
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
            file = "${userFlake}/nodes/node0/node.nix";
            value = {
              os = "nixos";
              channel = "unstable";
            };
          }
        ];
      };
      groupNode0 = {
        type = "node";
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
        nodeNames = [
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
        nodeNames = [
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
        nodeNames = [
          "groupNode0"
          "node0"
        ];
      };
      node1priv = {
        type = "node";
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
            file = "${userFlake}/private/nodes/node1priv/node.nix";
            value = { };
          }
        ];
      };
    };
  };
}
