// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal mock of the Agent ID ERC-721 for LOCAL TESTS ONLY.
///         Only implements what AgentArena reads: balanceOf(address).
///         Never deployed to mainnet.
contract MockAgentID {
    mapping(address => uint256) private _balances;

    function mint(address to) external {
        _balances[to] += 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}
