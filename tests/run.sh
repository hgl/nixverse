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

expectSuccess 'tests.lib.nodes.topLib-node.node.final' '{"inputs":1,"lib":true,"libP":{"common":null,"node":null,"top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.topLib-nodes-0.node.final' '{"inputs":1,"lib":true,"libP":{"common":null,"node":null,"top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.commonLib-0.node.final' '{"inputs":1,"lib":true,"libP":{"common":{"inputs":1,"lib":true,"libP":{"override":"common","top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}},"node":null,"top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.nodeLib-node.node.final' '{"inputs":1,"lib":true,"libP":{"common":null,"node":{"inputs":1,"lib":true,"libP":{"override":"node","top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}},"top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.nodeLib-nodes-0.node.final' '{"inputs":1,"lib":true,"libP":{"common":null,"node":{"inputs":1,"lib":true,"libP":{"override":"node","top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}},"top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}}'
expectSuccess 'tests.lib.nodes.nodeCommonLib-nodes-0.node.final' '{"inputs":1,"lib":true,"libP":{"common":{"inputs":1,"lib":true,"libP":{"override":"common","top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}},"node":{"inputs":1,"lib":true,"libP":{"override":"node","top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}},"top":{"inputs":1,"lib":true,"libP":{"override":"top"}}}}'

expectFailure 'tests.selfNodes.nodes.selfNodes' 'nodes/selfNodes/nodes.nix must not contain a node named selfNodes'
expectFailure 'tests.selfGroup.nodes.selfGroup' "nodes/selfGroup/group.nix#children must not contain the group's own name"
expectFailure 'tests.crossRef.nodes.cross' 'circular group containment: cross > cross2 > cross'
expectFailure 'tests.nodeNodesNameCollision.nodes.n0' 'n0 is defined by two different types of nodes:'
expectFailure 'tests.groupEmpty.nodes.group' "nodes/group/group.nix#children must contain at least one child"
expectFailure 'tests.groupEmptyDeep.nodes.group' "nodes/group2/group.nix#children must contain at least one child"
expectFailure 'tests.groupUnknown.nodes.group' 'nodes/group/group.nix#children contains unknown node n0'
expectFailure 'tests.groupUnknownDeep.nodes.group' 'nodes/group2/group.nix#children contains unknown node n0'

expectSuccess 'tests.confPath.nixosConfigurations.node.config.nixverse-test' '"bar"'
expectSuccess 'tests.confPath.nixosConfigurations.nodes-common-0.config.nixverse-test' '"bar"'
expectSuccess 'tests.confPath.nixosConfigurations.nodes-0.config.nixverse-test' '{"bar":1,"bar2":1}'
expectSuccess 'tests.hwconfPath.nixosConfigurations.node.config.nixverse-test' '"bar"'
expectSuccess 'tests.hwconfPath.nixosConfigurations.nodes-common-0.config.nixverse-test' '"bar"'
expectSuccess 'tests.hwconfPath.nixosConfigurations.nodes-0.config.nixverse-test' '{"bar":1,"bar2":1}'

expectSuccess 'tests.home.nixosConfigurations.node.config.home-manager.users.foo.nixverse-test' '"bar"'
expectSuccess 'tests.home.nixosConfigurations.nodes-common-0.config.home-manager.users.foo.nixverse-test' '"bar"'
expectSuccess 'tests.home.nixosConfigurations.nodes-0.config.home-manager.users.foo.nixverse-test' '{"bar":1,"bar2":1}'

expectSuccess 'tests.override.nodes.node.node.final' '{"x":2,"y":3}'
expectSuccess 'tests.override.nixosConfigurations.node.config.nixverse-test' '2'
expectSuccess 'tests.override.nodes.nodes-0.node.final' '{"current":2,"currentOverride":2,"x":2,"y":3}'
expectSuccess 'tests.override.nixosConfigurations.nodes-0.config.nixverse-test' '2'
expectSuccess 'tests.override.nodes.nodesCommon-0.node.final' '{"currentCommon":4,"currentNode":4,"x":4,"y":5}'
expectSuccess 'tests.override.nixosConfigurations.nodesCommon-0.config.nixverse-test' '4'
expectSuccess 'tests.override.nixosConfigurations.overrideNodeCommonOnly-0.config.nixverse-test' '{"currentCommon":4,"currentNode":4}'
