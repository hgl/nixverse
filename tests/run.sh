#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit

die() {
	echo >&2 "test case failed: " "$@"
	exit 1
}
flake=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp="$(mktemp -d)"
clean_up() {
	rm -rf "$tmp"
}
trap clean_up EXIT SIGINT SIGTERM
work="$tmp/work"
mkdir "$work"
cd "$work"

prefixExpression=$(
	cat <<-EOF
		{ tests, lib, lib' }:
	EOF
)

expectSuccess() {
	local expr=$1
	local expectedResult=$2
	if ! result=$(nix eval --json --show-trace --apply "$prefixExpression ($expr)" "$flake#tests"); then
		die "$expr failed to evaluate, but it was expected to succeed"
	fi
	if [[ ! "$result" == "$expectedResult" ]]; then
		die "$expr == $result, but $expectedResult was expected"
	fi
}

expectFailure() {
	local expr=$1
	local expectedErrorRegex=$2
	if result=$(nix eval --json --show-trace --apply "$prefixExpression ($expr)" "$flake#tests" 2>"$work/stderr"); then
		die "$expr evaluated successfully to $result, but it was expected to fail"
	fi
	if [[ ! "$(<"$work/stderr")" =~ $expectedErrorRegex ]]; then
		die "Error was $(<"$work/stderr"), but $expectedErrorRegex was expected"
	fi
}

expectSuccess 'tests.group.entities.newGroupNode-0.value.x' '1'
expectSuccess 'tests.group.entities.standaloneNode.value.x' '1'
expectSuccess 'tests.group.entities.nodeA.value.x' '"nodeAParentB"'
expectSuccess '{ inherit (tests.group.entities.doubleLayer-node.value) channel x; }' '{"channel":"doubleLayer-node","x":"doubleLayer-node"}'
expectSuccess 'tests.group.entities.fs.value.config.fileSystems."/".fsType' '"zfs"'

expectSuccess 'tests.lib.entities.topLib-node.value.final' '{"lib":true,"libP":{"common":null,"node":null,"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.entities.topLib-group-0.value.final' '{"lib":true,"libP":{"common":null,"node":null,"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.entities.commonLib-0.value.final' '{"lib":true,"libP":{"common":{"lib":true,"libP":{"override":"common","top":{"lib":true,"libP":{"override":"top"}}}},"node":null,"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.entities.nodeLib-node.value.final' '{"lib":true,"libP":{"common":null,"node":{"lib":true,"libP":{"override":"node","top":{"lib":true,"libP":{"override":"top"}}}},"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.entities.nodeLib-group-0.value.final' '{"lib":true,"libP":{"common":null,"node":{"lib":true,"libP":{"override":"node","top":{"lib":true,"libP":{"override":"top"}}}},"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.entities.nodeCommonLib-0.value.final' '{"lib":true,"libP":{"common":{"lib":true,"libP":{"override":"common","top":{"lib":true,"libP":{"override":"top"}}}},"node":{"lib":true,"libP":{"override":"node","top":{"lib":true,"libP":{"override":"top"}}}},"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.entities.overrideLib-node.value.final' '{"libP":{"override":"group"}}'

expectSuccess 'tests.nodeArgs.entities.node.value.final' '{"common":true,"inputs":1,"nodes":{"current":"node"}}'
expectSuccess 'tests.nodeArgs.entities.group-0.value.final' '{"common":true,"inputs":1,"nodes":{"current":"group-0"}}'
expectSuccess 'tests.nodeArgs.entities.groupCommon-0.value.final' '{"common":{"common":{"nodes":{"current":{"name":"groupCommon-0","override":"node"},"groupCommon-0":"node"},"override":"common"},"override":"common"},"inputs":1,"nodes":{"current":{"name":"groupCommon-0","override":"node"},"groupCommon-0":"node"}}'
expectSuccess 'tests.nodeArgs.entities.containNode-node.value.final' '{"common":{"common":{"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-node","override":"node"}},"override":"common"}},"inputs":1,"nodes":{"containNode-group-0":{"common":{"common":{"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-group-0","override":"groupNode"}},"override":"common"}},"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-group-0","override":"groupNode"}}},"containNode-node":{"common":{"common":{"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-node","override":"node"}},"override":"common"},"override":"common"},"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-node","override":"node"}}},"current":{"name":"containNode-node","override":"node"}}}'

expectFailure 'tests.selfRef.entities.selfRef' "nodes/selfRef/group.nix must not contain itself"
expectFailure 'tests.crossRef.entities.cross' 'circular group containment: cross > cross2 > cross'
expectFailure 'tests.groupEmpty.entities.group' "nodes/group/group.nix must contain at least one child"
expectFailure 'tests.groupEmptyCommon.entities.group' "nodes/group/group.nix must contain at least one child"
expectFailure 'tests.groupEmptyDeep.entities.group' "nodes/group2/group.nix must contain at least one child"
# shellcheck disable=2016
expectFailure 'tests.disallowedNodeValueType.entities.node.value.type' 'type` is a reserved attribute name: nodes/node/node.nix'
# shellcheck disable=2016
expectFailure 'tests.disallowedNodeValueChannel.entities.node.value.channel' '`channel` must not be "any"'
expectFailure 'tests.wrongNodeValue.entities.node.value.os' "A definition for option \`os' is not of type"

expectSuccess 'tests.confPath.entities.node.value.config.nixverse-test' '"bar"'
expectSuccess 'tests.confPath.entities.groupCommon-0.value.config.nixverse-test' '"bar"'
expectSuccess 'tests.confPath.entities.group-0.value.config.nixverse-test' '{"bar":1,"bar2":1}'
expectSuccess 'tests.confPath.entities.doubleLayer-node.value.config.nixverse-test' '{"group":1,"node":1}'
expectSuccess 'tests.hwconfPath.entities.node.value.config.nixverse-test' '"bar"'
expectSuccess 'tests.hwconfPath.entities.groupCommon-0.value.config.nixverse-test' '"bar"'
expectSuccess 'tests.hwconfPath.entities.group-0.value.config.nixverse-test' '{"bar":1,"bar2":1}'
# shellcheck disable=2016
expectSuccess 'lib.removePrefix "${tests.secretsPath.flakePath}/" tests.secretsPath.entities.node.value.config.sops.defaultSopsFile' '"nodes/node/secrets.yaml"'
# shellcheck disable=2016
expectSuccess 'lib.removePrefix "${tests.secretsPath.flakePath}/" tests.secretsPath.entities.group-0.value.config.sops.defaultSopsFile' '"nodes/group/group-0/secrets.yaml"'
expectSuccess 'tests.home.entities.node.value.config.home-manager.users.foo.nixverse-test' '"bar"'
expectSuccess 'tests.home.entities.groupCommon-0.value.config.home-manager.users.foo.nixverse-test' '"bar"'
expectSuccess 'tests.home.entities.group-0.value.config.home-manager.users.foo.nixverse-test' '{"bar":1,"bar2":1}'

expectSuccess 'tests.private.entities.node.value.final' '{"x":2,"y":3}'
expectSuccess 'tests.private.entities.node.value.config.nixverse-test' '2'
expectSuccess 'tests.private.entities.group-0.value.final' '{"current":2,"currentPrivate":2,"x":2,"y":3}'
expectSuccess 'tests.private.entities.group-0.value.config.nixverse-test' '2'
expectSuccess 'tests.private.entities.groupCommon-0.value.final' '{"currentCommon":4,"currentNode":4,"x":4,"y":5}'
expectSuccess 'tests.private.entities.groupCommon-0.value.config.nixverse-test' '4'
expectSuccess 'tests.private.entities.overrideNodeCommonOnly-0.value.config.nixverse-test' '{"currentCommon":4,"currentNode":4}'
