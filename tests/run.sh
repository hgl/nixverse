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
		self@{inputs, tests, ...}:
		let
			inherit (inputs.nixpkgs) lib;
			lib' = self.lib;
		in
	EOF
)

expectSuccess() {
	local expr=$1
	local expectedResult=$2
	if ! result=$(nix eval --json --show-trace --apply "$prefixExpression ($expr)" "$flake#self"); then
		die "$expr failed to evaluate, but it was expected to succeed"
	fi
	if [[ ! "$result" == "$expectedResult" ]]; then
		die "$expr == $result, but $expectedResult was expected"
	fi
}

expectFailure() {
	local expr=$1
	local expectedErrorRegex=$2
	if result=$(nix eval --json --show-trace --apply "$prefixExpression ($expr)" "$flake#self" 2>"$work/stderr"); then
		die "$expr evaluated successfully to $result, but it was expected to fail"
	fi
	if [[ ! "$(<"$work/stderr")" =~ $expectedErrorRegex ]]; then
		die "Error was $(<"$work/stderr"), but $expectedErrorRegex was expected"
	fi
}

expectSuccess 'tests.lib.nodes.toplib-node.node.top' '1'
expectSuccess 'tests.lib.nodes.toplib-nodes-0.node.top' '1'
expectSuccess 'tests.lib.nodes.toplib-nodes-1.node.top' '2'
expectSuccess 'lib.intersectAttrs {top=1;x=1;node=1;} tests.lib.nodes.nodelib-node.node' '{"node":4,"top":2,"x":3}'
expectSuccess 'lib.intersectAttrs {top=1;x=1;node=1;} tests.lib.nodes.nodelib-nodes-0.node' '{"node":4,"top":2,"x":3}'
expectSuccess 'lib.intersectAttrs {top=1;x=1;node=1;} tests.lib.nodes.nodelib-nodes-1.node' '{"node":5,"top":3,"x":4}'

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
