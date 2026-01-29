// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDinoProtocol
/// @author dinoitaly@gmail.com
/// @notice Interface for the DinoProtocol main contract
/// @dev Defines entry/exit points and view functions for the dual-token system
interface IDinoProtocol {

    /// @notice System state based on collateral ratio
    enum SystemState {
        NORMAL,
        CAUTION,
        RECOVERY,
        CRITICAL
    }

    // ** ----- Entry Points ----- **

    /// @notice Mint DPRIME and DNYLD tokens by depositing ETH
    function enterDinoETH() external payable;

    /// @notice Mint DPRIME and DNYLD tokens by depositing WETH
    /// @param amount Amount of WETH to deposit
    function enterDinoWETH(uint256 amount) external;

    // ** ----- Entry Points ----- **

    /// @notice Quote DPRIME and DNYLD amounts for a given deposit
    /// @param amount Amount to quote
    /// @return dprimeAmountQuoted Estimated DPRIME to receive
    /// @return dnyldAmountQuoted Estimated DNYLD to receive
    function quoteDinoPosition(uint256 amount) external returns (uint256 dprimeAmountQuoted, uint256 dnyldAmountQuoted);

    // ** ----- Exit Points  ----- **

    /// @notice Redeem DPRIME tokens for ETH
    /// @param dprimeAmount Amount of DPRIME to redeem
    function redeemDPRIME(uint256 dprimeAmount) external;

    /// @notice Redeem DNYLD tokens for ETH
    /// @param dnyldAmount Amount of DNYLD to redeem
    function redeemDNYLD(uint256 dnyldAmount) external;

    // ** ----- Events  ----- **

    /// @notice Emitted when user enters the protocol
    /// @param user User address
    /// @param ethAmount ETH deposited
    /// @param dprimeAmount DPRIME minted
    /// @param dnyldAmount DNYLD minted
    event DinoExposure(address indexed user, uint256 ethAmount, uint256 dprimeAmount, uint256 dnyldAmount);

    /// @notice Emitted when DPRIME is redeemed
    /// @param user User address
    /// @param dprimeAmount DPRIME burned
    /// @param ethAmount ETH returned
    /// @param fee Fee charged
    event DPRIMERedeemed(address indexed user, uint256 dprimeAmount, uint256 ethAmount, uint256 fee);

    /// @notice Emitted when DNYLD is redeemed
    /// @param user User address
    /// @param dnyldAmount DNYLD burned
    /// @param ethAmount ETH returned
    /// @param fee Fee charged
    event DNYLDRedeemed(address indexed user, uint256 dnyldAmount, uint256 ethAmount, uint256 fee);

    /// @notice Emitted when system state changes
    /// @param previousState Previous state
    /// @param newState New state
    event SystemStateChange(SystemState previousState, SystemState newState);

    /// @notice Emitted when redemption freeze starts
    event RedeemFrezeStarted();

    /// @notice Emitted when redemption freeze ends
    event RedeemFrezeLifted();

    // ** ----- View Functions ----- **

    /// @notice Get DPRIME token address
    /// @return DPRIME address
    function getDprimeAddress() external view returns (address);

    /// @notice Get DNYLD token address
    /// @return DNYLD address
    function getDnyldAddress() external view returns (address);

    /// @notice Get Oracle contract address
    /// @return Oracle address
    function getOracleAddress() external view returns (address);

    /// @notice Get CollateralVault address
    /// @return Vault address
    function getVaultAddress() external view returns (address);

    /// @notice Get WETH token address
    /// @return WETH address
    function getWethAddress() external view returns (address);

    /// @notice Get USDC token address
    /// @return USDC address
    function getUsdcAddress() external view returns (address);

    /// @notice Get admin address
    /// @return Admin address
    function getAdminAddress() external view returns (address);

    /// @notice Get current day counter
    /// @return Current day
    function getCurrentDay() external view returns (uint256);

    /// @notice Get liquidity ratio (1.5x)
    /// @return Liquidity ratio in WAD
    function getLiquidityRatio() external view returns (uint256);

    /// @notice Get minimum mint amount
    /// @return Minimum amount in ETH
    function getDprimeMinimumMintAmount() external view returns (uint256);

    /// @notice Get DPRIME base fee
    /// @return Base fee in basis points
    function getDprimeBaseFee() external view returns (uint256);

    /// @notice Get DNYLD base fee
    /// @return Base fee in basis points
    function getDnyldBaseFee() external view returns (uint256);

    /// @notice Get current freeze window
    /// @return freezeStartTime Freeze start timestamp
    /// @return freezeEndTime Freeze end timestamp
    function getCurentFreezeWindow() external view returns (uint256 freezeStartTime, uint256 freezeEndTime);

    /// @notice Get current system state
    /// @return Current SystemState
    function getSystemState() external view returns (SystemState);

    /// @notice Get system collateral ratio
    /// @return CR in WAD
    function getSystemCR() external view returns (uint256);

    /// @notice Get DNYLD Net Asset Value
    /// @return NAV in WAD
    function getNAV() external view returns (uint256);

    /// @notice Get DNYLD redemption headroom
    /// @return Redeemable DNYLD amount
    function getHeadroom() external view returns (uint256);

    /// @notice Get DPRIME redemption fee
    /// @param amount Amount to redeem
    /// @return Fee amount
    function getDprimeRedemptionFee(uint256 amount) external view returns (uint256);

    /// @notice Get DNYLD redemption fee
    /// @param amount Amount to redeem
    /// @return Fee amount
    function getDnyldRedemptionFee(uint256 amount) external view returns (uint256);

    /// @notice Get current ETH price
    /// @return Price in USD with 18 decimals
    function getEthPrice() external view returns (uint256);

    /// @notice Get total DPRIME supply
    /// @return Total minted DPRIME
    function getTotalMintedDprime() external view returns (uint256);

    /// @notice Get total DNYLD supply
    /// @return Total minted DNYLD
    function getTotalMintedDnyld() external view returns (uint256);

    /// @notice Get total collateral value in USD
    /// @return Collateral value in USD
    function getTotalCollateralUsd() external view returns (uint256);

    /// @notice Get daily DPRIME redemption cap
    /// @return Maximum redeemable today
    function getDailyDprimeRedemptionCap() external view returns (uint256);

    /// @notice Get DPRIME redeemed today
    /// @return Amount redeemed
    function getDailyDprimeRedemptionUsed() external view returns (uint256);

    /// @notice Check if DNYLD is redeemable
    /// @return True if redeemable
    function isDnyldRedeemable() external view returns (bool);

    /// @notice Check if DPRIME is redeemable
    /// @return True if redeemable
    function isDprimeRedeemable() external view returns (bool);


}
