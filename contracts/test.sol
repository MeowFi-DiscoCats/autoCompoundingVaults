// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestERC20 is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TestERC4626Vault is ERC4626 {
    using Math for uint256;

    constructor(ERC20 _asset) ERC4626(_asset) ERC20("erc","erc")
    {
        
    }

    function totalAssets() public view override returns (uint256) {
        return ERC20(asset()).balanceOf(address(this));
    }

    function generateYield(uint256 amount) public {
        TestERC20(address(asset())).mint(address(this), amount);
    }

    // function previewDeposit(uint256 assets) public view override returns (uint256) {
    //     uint256 fee = assets / 1000;
    //     return _convertToShares(assets - fee, Math.Rounding.DOWN);
    // }

    // function previewWithdraw(uint256 assets) public view override returns (uint256) {
    //     uint256 fee = assets / 1000;
    //     return _convertToShares(assets + fee, Math.Rounding.UP);
    // }
}