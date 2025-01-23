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
		tests:
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

expectSuccess 'tests.group.nodes.newGroupNode-0.value.x' '1'
expectSuccess 'tests.group.nodes.standaloneNode.value.x' '1'
expectSuccess 'tests.group.nodes.standaloneNode.value.x' '1'
expectSuccess 'tests.group.nodes.nodeA.value.x' '"nodeAParentB"'

expectSuccess 'tests.lib.nodes.topLib-node.value.final' '{"lib":true,"libP":{"common":null,"node":null,"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.topLib-group-0.value.final' '{"lib":true,"libP":{"common":null,"node":null,"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.commonLib-0.value.final' '{"lib":true,"libP":{"common":{"lib":true,"libP":{"override":"common","top":{"lib":true,"libP":{"override":"top"}}}},"node":null,"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.nodeLib-node.value.final' '{"lib":true,"libP":{"common":null,"node":{"lib":true,"libP":{"override":"node","top":{"lib":true,"libP":{"override":"top"}}}},"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.nodeLib-group-0.value.final' '{"lib":true,"libP":{"common":null,"node":{"lib":true,"libP":{"override":"node","top":{"lib":true,"libP":{"override":"top"}}}},"top":{"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.nodeCommonLib-0.value.final' '{"lib":true,"libP":{"common":{"lib":true,"libP":{"override":"common","top":{"lib":true,"libP":{"override":"top"}}}},"node":{"lib":true,"libP":{"override":"node","top":{"lib":true,"libP":{"override":"top"}}}},"top":{"lib":true,"libP":{"override":"top"}}}}'

expectSuccess 'tests.nodeArgs.nodes.node.value.final' '{"common":true,"inputs":1,"nodes":{"current":"node"}}'
expectSuccess 'tests.nodeArgs.nodes.group-0.value.final' '{"common":true,"inputs":1,"nodes":{"current":"group-0"}}'
expectSuccess 'tests.nodeArgs.nodes.groupCommon-0.value.final' '{"common":{"common":{"nodes":{"current":{"name":"groupCommon-0","override":"node"},"groupCommon-0":"node"},"override":"common"},"override":"common"},"inputs":1,"nodes":{"current":{"name":"groupCommon-0","override":"node"},"groupCommon-0":"node"}}'
expectSuccess 'tests.nodeArgs.nodes.containNode-node.value.final' '{"common":{"common":{"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-node","override":"node"}},"override":"common"}},"inputs":1,"nodes":{"containNode-group-0":{"common":{"common":{"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-group-0","override":"groupNode"}},"override":"common"}},"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-group-0","override":"groupNode"}}},"containNode-node":{"common":{"common":{"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-node","override":"node"}},"override":"common"},"override":"common"},"nodes":{"containNode-group-0Override":"groupNode","containNode-nodeOverride":"node","current":{"name":"containNode-node","override":"node"}}},"current":{"name":"containNode-node","override":"node"}}}'

expectFailure 'tests.selfRef.nodes.selfRef' "nodes/selfRef/group.nix must not contain itself"
expectFailure 'tests.crossRef.nodes.cross' 'circular group containment: cross > cross2 > cross'
expectFailure 'tests.groupEmpty.nodes.group' "nodes/group/group.nix must contain at least one child"
expectFailure 'tests.groupEmptyCommon.nodes.group' "nodes/group/group.nix must contain at least one child"
expectFailure 'tests.groupEmptyDeep.nodes.group' "nodes/group2/group.nix must contain at least one child"

expectSuccess 'tests.confPath.nixosConfigurations.node.config.nixverse-test' '"bar"'
expectSuccess 'tests.confPath.nixosConfigurations.groupCommon-0.config.nixverse-test' '"bar"'
expectSuccess 'tests.confPath.nixosConfigurations.group-0.config.nixverse-test' '{"bar":1,"bar2":1}'
expectSuccess 'tests.hwconfPath.nixosConfigurations.node.config.nixverse-test' '"bar"'
expectSuccess 'tests.hwconfPath.nixosConfigurations.groupCommon-0.config.nixverse-test' '"bar"'
expectSuccess 'tests.hwconfPath.nixosConfigurations.group-0.config.nixverse-test' '{"bar":1,"bar2":1}'
expectSuccess 'tests.home.nixosConfigurations.node.config.home-manager.users.foo.nixverse-test' '"bar"'
expectSuccess 'tests.home.nixosConfigurations.groupCommon-0.config.home-manager.users.foo.nixverse-test' '"bar"'
expectSuccess 'tests.home.nixosConfigurations.group-0.config.home-manager.users.foo.nixverse-test' '{"bar":1,"bar2":1}'

expectSuccess 'tests.private.nodes.node.value.final' '{"x":2,"y":3}'
expectSuccess 'tests.private.nixosConfigurations.node.config.nixverse-test' '2'
expectSuccess 'tests.private.nodes.group-0.value.final' '{"current":2,"currentPrivate":2,"x":2,"y":3}'
expectSuccess 'tests.private.nixosConfigurations.group-0.config.nixverse-test' '2'
expectSuccess 'tests.private.nodes.groupCommon-0.value.final' '{"currentCommon":4,"currentNode":4,"x":4,"y":5}'
expectSuccess 'tests.private.nixosConfigurations.groupCommon-0.config.nixverse-test' '4'
expectSuccess 'tests.private.nixosConfigurations.overrideNodeCommonOnly-0.config.nixverse-test' '{"currentCommon":4,"currentNode":4}'
