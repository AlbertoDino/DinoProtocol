// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Initializable }              from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable }   from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable }        from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable }            from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 }                     from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 }                  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH }                      from "../interfaces/IWETH.sol";
import { ICollateralVault }           from "../interfaces/ICollateralVault.sol";

/// @title CollateralVault
/// @author dinoitaly@gmail.com
/// @notice Holds ETH/WETH collateral for the DinoProtocol system
/// @dev Upgradeable vault with role-based access control for deposits and withdrawals
contract CollateralVault is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ICollateralVault
{
    using SafeERC20 for IERC20;

    // ** ----- Roles ----- **

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ** ----- Events ----- **

    event WETHUpdated(address indexed oldWETH, address indexed newWETH);
    event DinoProtocolSet(address dinoProtocol);

    // ** ----- Errors ----- **
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientCollateral();
    error TransferFailed();

    // ** ----- Variables ----- **

    uint256 internal totalCollateral_;
    address internal dinoProtocol;
    IWETH   internal weth;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the CollateralVault contract
    /// @dev Sets up roles and contract references
    /// @param admin Admin address with DEFAULT_ADMIN_ROLE
    /// @param dinoProtocol_ DinoProtocol contract address (gets OPERATOR_ROLE)
    /// @param weth_ WETH token address
    function initialize(
        address admin,
        address dinoProtocol_,
        address weth_
    ) external initializer {
        if (
            admin == address(0) ||
            dinoProtocol_ == address(0) ||
            weth_ == address(0)
        ) {
            revert ZeroAddress();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        weth = IWETH(weth_);
        dinoProtocol = dinoProtocol_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, dinoProtocol_);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ** ----- Write Functions ----- **

    /// @notice Deposit WETH into the vault
    /// @dev Only callable by OPERATOR_ROLE (DinoProtocol)
    /// @param amount Amount of WETH to deposit
    function deposit(uint256 amount) external override nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();

        IERC20(address(weth)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        totalCollateral_ += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Deposit ETH into the vault (auto-wraps to WETH)
    /// @dev Only callable by OPERATOR_ROLE (DinoProtocol)
    function depositETH()
        external
        payable
        override
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        if (msg.value == 0) revert ZeroAmount();

        // The syntax {value: ...} sends the ETH currently held by the function execution
        weth.deposit{value: msg.value}();
        totalCollateral_ += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw collateral as ETH (unwraps from WETH)
    /// @dev Only callable by OPERATOR_ROLE (DinoProtocol)
    /// @param to Recipient address
    /// @param amount Amount of ETH to withdraw
    function withdrawEth(
        address to,
        uint256 amount
    ) external override nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > totalCollateral_) revert InsufficientCollateral();

        totalCollateral_ -= amount;

        weth.withdraw(amount);

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(to, amount);
    }

    /// @notice Update WETH token address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param _newWETH New WETH contract address
    function setWETH(
        address _newWETH
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newWETH == address(0)) revert ZeroAddress();

        address oldWETH = address(weth);
        weth = IWETH(_newWETH);

        emit WETHUpdated(oldWETH, _newWETH);
    }

    /// @notice Update DinoProtocol address and transfer OPERATOR_ROLE
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    /// @param protocol New DinoProtocol contract address
    function setDinoProtocol(address protocol) external
    {
        if(!hasRole(DEFAULT_ADMIN_ROLE,msg.sender)) revert("MISS_ROLE");

        _revokeRole(OPERATOR_ROLE, dinoProtocol);

        dinoProtocol = protocol;

       _grantRole(OPERATOR_ROLE, dinoProtocol);

        emit DinoProtocolSet(dinoProtocol);
    }

    /// @notice Pause vault operations
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause vault operations
    /// @dev Only callable by DEFAULT_ADMIN_ROLE
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ** ----- View Functions ----- **

    /// @notice Get total collateral held in vault (in ETH/WETH)
    /// @return Total collateral amount
    function getTotalCollateralEth() external view override returns (uint256) {
        return totalCollateral_;
    }

    /// @notice Get DinoProtocol contract address
    /// @return DinoProtocol address
    function getDinoProtocol() external view returns (address)
    {
        return dinoProtocol;
    }

    /// @notice Get WETH token address
    /// @return WETH address
    function getWethAddress() external view returns (address)
    {
        return address(weth);
    }

    // ** ----- Internal Functions ----- **

    /// @notice Authorize contract upgrade
    /// @dev Only UPGRADER_ROLE can upgrade
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /// @notice Receive ETH (required for WETH unwrapping)
    /// @dev Only accepts ETH from WETH contract
    receive() external payable {
        require(msg.sender == address(weth), "Only WETH");
    }
}
