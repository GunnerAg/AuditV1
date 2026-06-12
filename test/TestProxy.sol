// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title TestProxy
 * @notice Thin wrapper over ERC1967Proxy so Hardhat compiles and caches its artifact.
 * @dev Deploy this instead of importing ERC1967Proxy directly in tests.
 *      In test: const ProxyFactory = await ethers.getContractFactory("TestProxy");
 *               const proxy = await ProxyFactory.deploy(impl.address, initData);
 */
contract TestProxy is ERC1967Proxy {
    constructor(address logic, bytes memory data)
        ERC1967Proxy(logic, data) {}
}
