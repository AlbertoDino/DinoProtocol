// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Initializable }              from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable }           from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable }     from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC20BurnableUpgradeable }   from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { AccessControlUpgradeable }   from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable }            from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable }        from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IDinoYield }                 from "../interfaces/IDinoYield.sol";

/// @title DinoYield
/// @author dinoitaly@gmail.com
/// @notice DNYLD equity token representing pro-rata claim on system surplus
/// @dev ERC20 token with leveraged ETH exposure, mint/burn controlled by DinoProtocol
contract DinoYield is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IDinoYield
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    error ZeroAddress();

    event DinoProtocolSet(address dinoProtocol);

    address internal dinoProtocol;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the DinoYield token contract
    /// @dev Sets up ERC20, roles, and DinoProtocol reference
    /// @param admin Admin address with DEFAULT_ADMIN_ROLE
    /// @param protocol_ DinoProtocol contract address (gets MINTER_ROLE)
    function initialize(address admin, address protocol_) external initializer {
        if (admin == address(0)) revert ZeroAddress();

        __ERC20_init("DinoYield", "DNYLD");
        __ERC20Permit_init("DinoYield");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        dinoProtocol = protocol_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, protocol_);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    /// @notice Get DinoProtocol contract address
    /// @return DinoProtocol address
    function getDinoProtocol() external view returns (address)
    {
        return dinoProtocol;
    }

    // ** ----- Minter & Upgrader Role ----- **

    /// @notice Mint DNYLD tokens to an address
    /// @dev Only callable by MINTER_ROLE (DinoProtocol)
    /// @param to Recipient address
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burn DNYLD tokens from an address
    /// @dev Only callable by MINTER_ROLE (DinoProtocol)
    /// @param from Address to burn tokens from
    /// @param amount Amount of tokens to burn
    function burnFrom(address from,uint256 amount) public override(ERC20BurnableUpgradeable, IDinoYield) onlyRole(MINTER_ROLE)
    {
        _burn(from, amount);
    }

    /// @notice Authorize contract upgrade
    /// @dev Only UPGRADER_ROLE can upgrade
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade( address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // ** ----- Manager Role ----- **

    /// @notice Pause token operations
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause token operations
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Update DinoProtocol address and transfer MINTER_ROLE
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param protocol New DinoProtocol contract address
    function setDinoProtocol(address protocol) external
    {
        if(!hasRole(DEFAULT_ADMIN_ROLE,msg.sender)) revert("MISS_ROLE");

        _revokeRole(MINTER_ROLE, dinoProtocol);

        dinoProtocol = protocol;

       _grantRole(MINTER_ROLE,dinoProtocol);

        emit DinoProtocolSet(dinoProtocol);
    }
}
