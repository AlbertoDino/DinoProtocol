// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Initializable }              from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable }   from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable }        from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable }            from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 }                     from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 }                  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DinoPrime }                  from "../tokens/DinoPrime.sol";
import { DinoYield }                  from "../tokens/DinoYield.sol";
import { CollateralVault }            from "./CollateralVault.sol";
import { IDinoProtocol }              from "../interfaces/IDinoProtocol.sol";
import { IOracle }                    from "../interfaces/IOracle.sol";
import { WadMath }                    from "../libraries/WadMath.sol";

/// @title DinoProtocol
/// @author dinoitaly@gmail.com
/// @notice Main protocol contract for DPRIME/DNYLD dual-token system with 1.5x collateralization
/// @dev Manages minting, redemption, system state transitions, and crisis management
contract DinoProtocol is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IDinoProtocol
{
    using SafeERC20 for IERC20;
    using WadMath for uint256;

    // ** ----- Roles ----- **
    bytes32 public constant MANAGER_ROLE  = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    // ** ----- Constants ----- **
    uint256 internal constant ONE_UNIT = 1e18;

    /*
    * System State Thresholds (all in WAD = 18 decimals)
    *
    * NORMAL (CR >= 150%):
    *   - All operations allowed
    *   - Base fees apply
    *   - System is healthy
    *
    * CAUTION (CR >= 135%):
    *   - All operations allowed
    *   - Elevated redemption fees (incentivize holding)
    *   - Warning state
    *
    * RECOVERY (CR >= 120%):
    *   - DPRIME redemption allowed (reduces liabilities)
    *   - DNYLD redemption BLOCKED (preserve buffer)
    *   - High fees
    *
    * CRITICAL (CR >= 110%):
    *   - All redemptions restricted
    *   - Recapitalization module active
    *   - Emergency state
    *
    * INSOLVENT (CR < 110%):
    *   - Protocol may be underwater
    *   - Governance intervention required
    */
    uint256 internal constant CR_HEALTHY  = 15e17;  // 1.50 (150%) - NORMAL threshold
    uint256 internal constant CR_WARNING  = 135e16; // 1.35 (135%) - CAUTION threshold
    uint256 internal constant CR_DANGER   = 12e17;  // 1.20 (120%) - RECOVERY threshold
    uint256 internal constant CR_CRITICAL = 11e17;  // 1.10 (110%) - Emergency floor
    uint256 internal constant LIQUIDITY_RATIO = 15e17;   // 1.5x - collateral ratio at mint

    uint256 internal constant MAX_FREEZE_DURATION = 180 days;    // 6 months
    uint256 internal constant DPRIME_VOLUME_WINDOW_BLOCKS = 100; // ~20 minutes

    // Fee constants (in basis points)
    uint256 internal constant DPRIME_BASE_FEE_BPS       = 50;  // 0.5%
    uint256 internal constant MAX_CR_FEE_BPS            = 5000;// 50%
    uint256 internal constant DPRIME_MAX_VOLUME_FEE_BPS = 500; // 5%
    uint256 internal constant DNYLD_FEE_BPS             = 50;  // 0.5%


    // ** ----- Variables ----- **
    DinoPrime       internal dprime;
    DinoYield       internal dnyld;
    CollateralVault internal vault;
    IOracle         internal oracle;
    address         internal admin;
    address         internal weth;
    address         internal usdc;

    SystemState     currentState;
    uint256         internal minMintAmount;
    uint256         internal minRedeemAmount;

    ///  Freeze management
    uint256         internal freezeStartTime;
    uint256         internal freezeEndTime;

    /// Daily redemption tracking
    uint256         internal currentDay;
    uint256         internal dailyDPRIMERedeemed;
    uint256         internal dailyDNYLDRedeemed;

    /// DPrime redemption volume tracking (for feee calculation)
    uint256         internal dprimeVolumeRedemption;
    uint256         internal dprimeLastVolumeResetBlock;


    // ** ----- Errors ----- **

    error ZeroAddress();
    error BadLR();
    error BelowMinimum();
    error SystemFrozen();
    error ExceedsDailyRedemptionCap();
    error DNYLDRedemptionSuspended();
    error InsufficientHeadroom();

    // ** ----- Events ----- **

    event OracleSet(address oracle);
    event StateChanged(SystemState oldState, SystemState newState);
    event FreezeActivated(uint256 freezeEndTime);
    event FreezeReset();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the DinoProtocol contract
    /// @dev Sets up roles, contract references, and initial state
    /// @param admin_ Admin address with DEFAULT_ADMIN_ROLE
    /// @param dprime_ DPRIME token contract address
    /// @param dnyld_ DNYLD token contract address
    /// @param weth_ WETH token address
    /// @param usdc_ USDC token address
    /// @param oracle_ Oracle contract address
    /// @param collateralVault_ CollateralVault contract address
    function initialize(
        address admin_,
        address dprime_,
        address dnyld_,
        address weth_,
        address usdc_,
        address oracle_,
        address collateralVault_
    ) external initializer
    {
        if (admin_ == address(0)) revert ZeroAddress();
        if (dprime_ == address(0)) revert ZeroAddress();
        if (dnyld_ == address(0)) revert ZeroAddress();
        if (weth_ == address(0)) revert ZeroAddress();
        if (usdc_ == address(0)) revert ZeroAddress();
        if (oracle_ == address(0)) revert ZeroAddress();
        if (collateralVault_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        admin  = admin_;
        dprime = DinoPrime(dprime_);
        dnyld  = DinoYield(dnyld_);
        oracle = IOracle(oracle_);
        vault  = CollateralVault(payable(collateralVault_));
        weth   = weth_;
        usdc   = usdc_;

        freezeStartTime     = 0;
        freezeEndTime       = 0;
        currentState        = SystemState.NORMAL;
        minMintAmount       = 0.01 ether;
        minRedeemAmount     = 1e18;  // 1 DPRIME/DNYLD
        currentDay          = block.timestamp / 1 days;
        dprimeLastVolumeResetBlock = block.number;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @notice Authorize contract upgrade
    /// @dev Only DEFAULT_ADMIN_ROLE can upgrade
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) { }

    // ** ----- Admin functions ----- **

    /// @notice Pause all protocol operations
    /// @dev Only PAUSER_ROLE can call
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause protocol operations
    /// @dev Only PAUSER_ROLE can call
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Set a new oracle contract address
    /// @dev Only DEFAULT_ADMIN_ROLE can call
    /// @param newOracle New oracle contract address
    function setOracle(address newOracle) external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if(newOracle == address(0)) revert ZeroAddress();
        oracle = IOracle(newOracle);

        emit OracleSet(newOracle);
    }

    // ** ----- Core Functions ----- **

    /// @notice Mint DPRIME and DNYLD tokens by depositing ETH
    /// @dev User deposits ETH at 1.5x ratio: receives 1 DPRIME per $1.5 deposited, plus DNYLD for equity portion
    function enterDinoETH() external payable override nonReentrant whenNotPaused
    {
        if (msg.value < minMintAmount) revert BelowMinimum();

        _updateSystemState();

        if (currentState == SystemState.CRITICAL) revert SystemFrozen();

        uint256 ethPrice     = oracle.updateEthUscAggPrice();
        uint256 ethUsdValue  = msg.value.wadMul(ethPrice);
        uint256 dprimeAmount = ethUsdValue.wadDiv(LIQUIDITY_RATIO);
        uint256 equityValue  = ethUsdValue - dprimeAmount;
        uint256 nav          = getNAV();
        uint256 dnyldAmount  = equityValue.wadDiv(nav);

        vault.depositETH{value : msg.value}();

        dprime.mint(msg.sender, dprimeAmount);
        dnyld.mint(msg.sender, dnyldAmount);

        emit DinoExposure(msg.sender, msg.value, ethPrice, dprimeAmount, dnyldAmount);

        _updateSystemState();
    }

    /// @notice Mint DPRIME and DNYLD tokens by depositing WETH
    /// @dev User deposits WETH at 1.5x ratio: receives 1 DPRIME per $1.5 deposited, plus DNYLD for equity portion
    /// @param amount Amount of WETH to deposit
    function enterDinoWETH(uint256 amount) external override nonReentrant whenNotPaused
    {
        if (amount < minMintAmount) revert BelowMinimum();

        _updateSystemState();

        if (currentState == SystemState.CRITICAL) revert SystemFrozen();

        // Transfer WETH from user
        // Safe transfer of amount from sender to address(this)
        IERC20(weth).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(weth).forceApprove(address(vault), amount);

        vault.deposit(amount);

        uint256 ethPrice     = oracle.updateEthUscAggPrice();
        uint256 ethUsdValue  = amount.wadMul(ethPrice);
        uint256 dprimeAmount = ethUsdValue.wadDiv(LIQUIDITY_RATIO);
        uint256 equityValue  = ethUsdValue - dprimeAmount;
        uint256 nav          = getNAV();
        uint256 dnyldAmount  = equityValue.wadDiv(nav);

        dprime.mint(msg.sender, dprimeAmount);
        dnyld.mint(msg.sender, dnyldAmount);

        emit DinoExposure(msg.sender, amount, ethPrice, dprimeAmount, dnyldAmount);

        _updateSystemState();
    }

    /// @notice Redeem DPRIME tokens for ETH
    /// @dev Burns DPRIME and returns equivalent USD value in ETH, minus fees
    /// @param dPrimeAmount Amount of DPRIME to redeem
    function redeemDPRIME(uint256 dPrimeAmount) external override nonReentrant whenNotPaused
    {
        if (dPrimeAmount < minRedeemAmount) revert BelowMinimum();

        _updateSystemState();
        _resetDailyCountersIfNeeded();

        // Check if Frozen state
        if (currentState == SystemState.CRITICAL) {
            if (block.timestamp < freezeEndTime) revert SystemFrozen();
        }

        uint256 dailyCap = getDailyDprimeRedemptionCap();
        if( dailyDPRIMERedeemed + dPrimeAmount > dailyCap)
            revert ExceedsDailyRedemptionCap();

        uint256 fee = getDprimeRedemptionFee(dPrimeAmount);
        uint256 dPrimeNetAmount = dPrimeAmount - fee;

        // Calculate ETH to return
        uint256 ethPrice     = oracle.getEthUscPrice();
        uint256 ethNetAmount = dPrimeNetAmount.wadDiv(ethPrice);

        // Update Tracking
        dailyDPRIMERedeemed += dPrimeAmount;
        _updateDPRIMERedemptionVolume(dPrimeAmount);

        // Burn DPRIME
        dprime.burnFrom(msg.sender, dPrimeAmount);

        // Withdraw WETH to user
        vault.withdrawEth(msg.sender, ethNetAmount);

        emit DPRIMERedeemed(msg.sender, dPrimeAmount, ethNetAmount, ethPrice, fee);
        _updateSystemState();

    }

    /// @notice Redeem DNYLD tokens for ETH based on NAV
    /// @dev Burns DNYLD and returns proportional equity value in ETH, subject to headroom
    /// @param amount Amount of DNYLD to redeem
    function redeemDNYLD(uint256 amount) external override nonReentrant whenNotPaused
    {
        if (amount < minRedeemAmount) revert BelowMinimum();

        _updateSystemState();
        _resetDailyCountersIfNeeded();

        // Check system state - DNYLD only redeemable in NORMAL
        if (currentState == SystemState.RECOVERY || currentState == SystemState.CRITICAL)
        {
            revert DNYLDRedemptionSuspended();
        }

        uint256 headroom = getHeadroom();
        if (amount > headroom)
            revert InsufficientHeadroom();

        // Calculate redemption value base on NAV
        uint256 nav = getNAV();
        uint256 redeptionValue  = amount.wadMul(nav);

        // Apply fee
        uint256 fee            = getDnyldRedemptionFee(redeptionValue);
        uint256 dnyldNetAmount = redeptionValue - fee;
        uint256 ethPrice       = oracle.getEthUscPrice();
        uint256 ethAmount      = dnyldNetAmount.wadDiv(ethPrice);

        // Update Tracking
        dailyDNYLDRedeemed += amount;
        dnyld.burnFrom(msg.sender, amount);

        // Withdraw WETH to user
        vault.withdrawEth(msg.sender, ethAmount);

        emit DNYLDRedeemed(msg.sender, amount, ethAmount, ethPrice, fee);
        _updateSystemState();
    }

    // ** ----- View Functions ----- **

    /// @notice Quote the DPRIME and DNYLD amounts for a given WETH deposit
    /// @dev Returns estimated token amounts without executing the trade
    /// @param amount Amount of WETH to quote
    /// @return dprimeAmountQuoted Estimated DPRIME tokens to receive
    /// @return dnyldAmountQuoted Estimated DNYLD tokens to receive
    function quoteDinoPosition(uint256 amount) external view override returns (uint256 dprimeAmountQuoted, uint256 dnyldAmountQuoted)
    {
        if (amount < minMintAmount) revert BelowMinimum();

        uint256 ethUsdValue = amount.wadMul(oracle.getEthUscPrice());
        dprimeAmountQuoted  = ethUsdValue.wadDiv(LIQUIDITY_RATIO);
        uint256 equityValue = ethUsdValue - dprimeAmountQuoted;
        uint256 nav         = getNAV();
        dnyldAmountQuoted   = equityValue.wadDiv(nav);
    }

    // ** ----- Internal Functions ----- **

    /// @notice Update system state based on current collateral ratio
    /// @dev Triggers freeze when entering CRITICAL, resets when leaving
    function _updateSystemState() internal
    {
        SystemState newState = getSystemState();

        if (currentState != newState)
        {
            // Trigger freeze when entering CRITICAL (only if not already frozen)
            if (newState == SystemState.CRITICAL && freezeStartTime == 0) {
                freezeStartTime = block.timestamp;
                freezeEndTime   = freezeStartTime + MAX_FREEZE_DURATION;
                emit FreezeActivated(freezeEndTime);
            }

            // Reset freeze when leaving CRITICAL
            if (currentState == SystemState.CRITICAL && newState != SystemState.CRITICAL) {
                freezeStartTime = 0;
                freezeEndTime   = 0;
                emit FreezeReset();
            }

            emit StateChanged(currentState, newState);
            currentState = newState;
        }
    }

    /// @notice Calculate CR-based redemption fee
    /// @dev Fee increases progressively as CR drops below healthy levels
    /// @param cr Current collateral ratio (18 decimals)
    /// @return Fee in basis points
    function _calculateCRFee(uint256 cr) internal pure returns (uint256)
    {
        // No fee if healthy
        if (cr >= CR_HEALTHY) return 0;  // >= 1.5

        // 0% to 2% as CR drops from 1.5 to 1.35
        if (cr >= CR_WARNING) {
            return ((CR_HEALTHY - cr) * 200) / (CR_HEALTHY - CR_WARNING);
        }

        // 2% to 10% as CR drops from 1.35 to 1.2
        if (cr >= CR_DANGER) {
            return 200 + ((CR_WARNING - cr) * 800) / (CR_WARNING - CR_DANGER);
        }

        // 10% to 50% as CR drops from 1.2 to 1.1
        if (cr >= CR_CRITICAL) {
            return 1000 + ((CR_DANGER - cr) * 4000) / (CR_DANGER - CR_CRITICAL);
        }

        // Below 1.1 - maximum fee
        return MAX_CR_FEE_BPS;
    }

    /// @notice Calculate volume-based redemption fee for DPRIME
    /// @dev Fee scales with recent redemption volume relative to total supply
    /// @param recentVolume Recent DPRIME redemption volume (WAD)
    /// @param totalSupply Total DPRIME supply (WAD)
    /// @return Fee in basis points
    function _calculateDPrimeVolumeFee(uint256 recentVolume, uint256 totalSupply) internal pure returns (uint256)
    {
        if (totalSupply == 0) return 0;
        uint256 volumeRatio = recentVolume.wadDiv(totalSupply);

        // Scale to max volume fee
        uint256 fee = volumeRatio.wadMul(DPRIME_MAX_VOLUME_FEE_BPS);

        return fee > DPRIME_MAX_VOLUME_FEE_BPS ? DPRIME_MAX_VOLUME_FEE_BPS : fee;
    }

    /// @notice Reset daily redemption counters if a new day has started
    /// @dev Called before redemption operations
    function _resetDailyCountersIfNeeded() internal
    {
        uint256 today = block.timestamp / 1 days;
        if( today != currentDay )
        {
            currentDay          = today;
            dailyDNYLDRedeemed  = 0;
            dailyDPRIMERedeemed = 0;
        }
    }

    /// @notice Update DPRIME redemption volume tracking for fee calculation
    /// @dev Resets volume if window has passed, otherwise accumulates
    /// @param amount Amount being redeemed
    function _updateDPRIMERedemptionVolume(uint256 amount) internal
    {
        if(block.number > dprimeLastVolumeResetBlock + DPRIME_VOLUME_WINDOW_BLOCKS)
        {
            dprimeVolumeRedemption     = amount;
            dprimeLastVolumeResetBlock = block.number;
        }
        else
        {
            dprimeVolumeRedemption += amount;
        }
    }

    // ** ----- View Functions ----- **

    /// @notice Get DPRIME token contract address
    /// @return DPRIME contract address
    function getDprimeAddress() external view returns (address) {
        return address(dprime);
    }

    /// @notice Get DNYLD token contract address
    /// @return DNYLD contract address
    function getDnyldAddress() external view returns (address) {
        return address(dnyld);
    }

    /// @notice Get Oracle contract address
    /// @return Oracle contract address
    function getOracleAddress() external view returns (address) {
        return address(oracle);
    }

    /// @notice Get CollateralVault contract address
    /// @return Vault contract address
    function getVaultAddress() external view returns (address) {
        return address(vault);
    }

    /// @notice Get WETH token address
    /// @return WETH address
    function getWethAddress() external view returns (address) {
        return address(weth);
    }

    /// @notice Get USDC token address
    /// @return USDC address
    function getUsdcAddress() external view returns (address) {
        return address(usdc);
    }

    /// @notice Get admin address
    /// @return Admin address
    function getAdminAddress() external view returns (address) {
        return address(admin);
    }

    /// @notice Get current day counter for daily limits
    /// @return Current day number
    function getCurrentDay() external view returns (uint256) {
        return currentDay;
    }

    /// @notice Get the liquidity ratio (collateralization requirement)
    /// @return Liquidity ratio in WAD (1.5e18 = 150%)
    function getLiquidityRatio() external pure returns (uint256) {
        return LIQUIDITY_RATIO;
    }

    /// @notice Get minimum mint amount for DPRIME
    /// @return Minimum ETH amount required to mint
    function getDprimeMinimumMintAmount() external view returns (uint256) {
        return minMintAmount;
    }

    /// @notice Get DPRIME base redemption fee
    /// @return Base fee in basis points
    function getDprimeBaseFee() external pure returns (uint256) {
        return DPRIME_BASE_FEE_BPS;
    }

    /// @notice Get DNYLD base redemption fee
    /// @return Base fee in basis points
    function getDnyldBaseFee() external pure returns (uint256) {
        return DNYLD_FEE_BPS;
    }

    /// @notice Get current freeze window timestamps
    /// @return freezeStartTime_ Freeze start timestamp
    /// @return freezeEndTime_ Freeze end timestamp
    function getCurentFreezeWindow() external view returns (uint256 freezeStartTime_, uint256 freezeEndTime_) {
        freezeStartTime_ = freezeStartTime;
        freezeEndTime_ = freezeEndTime;
    }


    /// @notice Get the current system state based on collateral ratio
    /// @return SystemState enum value (NORMAL, CAUTION, RECOVERY, CRITICAL)
    function getSystemState() public view override returns (SystemState)
    {
        uint256 cr = getSystemCR();
        if (cr >= CR_HEALTHY) return SystemState.NORMAL;    // >= 1.50
        if (cr >= CR_WARNING) return SystemState.CAUTION;   // >= 1.35
        if (cr >= CR_DANGER)  return SystemState.RECOVERY;  // >= 1.20
        return SystemState.CRITICAL;
    }

    /// @notice Get the current system collateral ratio
    /// @return Collateral ratio in WAD (18 decimals)
    function getSystemCR() public view override returns (uint256)
    {
        uint256 totalDebt   = dprime.totalSupply();
        if (totalDebt == 0) return type(uint256).max;  // No debt = infinite CR

        uint256 totalCollateral = getTotalCollateralUsd();
        return totalCollateral.wadDiv(totalDebt);
    }

    /// @notice Get the Net Asset Value per DNYLD token
    /// @dev NAV = (Total Collateral USD - Total DPRIME) / Total DNYLD
    /// @return NAV in WAD (18 decimals), returns 1e18 for first mint
    function getNAV() public view override returns (uint256)
    {
        uint256 totalDPRIME        = dprime.totalSupply();
        uint256 totalDNYLD         = dnyld.totalSupply();
        uint256 totalCollateralUsd = getTotalCollateralUsd();

        // First mint - NAV = $1
        if (totalDNYLD == 0) return ONE_UNIT;

        // NAV = (Collateral - DPRIME) / DNYLD
        if (totalCollateralUsd <= totalDPRIME) return 0;

        uint256 equity = totalCollateralUsd - totalDPRIME;
        return equity.wadDiv(totalDNYLD);
    }

    /// @notice Get available headroom for DNYLD redemption
    /// @dev Headroom is excess equity above minimum required to maintain CR target
    /// @return DNYLD tokens redeemable without breaking CR target
    function getHeadroom() public view override returns (uint256)
    {
        uint256 totalCollateralUSD = getTotalCollateralUsd();
        uint256 totalDPRIME        = dprime.totalSupply();
        uint256 totalDNYLD         = dnyld.totalSupply();

        if (totalDNYLD == 0) return 0;

        // Calculate current equity
        if (totalCollateralUSD <= totalDPRIME) return 0;

        uint256 currentEquity = totalCollateralUSD - totalDPRIME;

        // Minimum equity required to maintain CR_TARGET
        uint256 minEquity = totalDPRIME.wadMul(LIQUIDITY_RATIO - ONE_UNIT);

        if (currentEquity <= minEquity) return 0;
        uint256 excessEquity = currentEquity - minEquity;

        return (excessEquity * totalDNYLD) / currentEquity;
    }

    /// @notice Calculate total DPRIME redemption fee for given amount
    /// @dev Combines base fee, CR-based fee, and volume-based fee
    /// @param amount DPRIME amount to redeem
    /// @return Total fee amount in DPRIME
    function getDprimeRedemptionFee(uint256 amount) public view override returns (uint256)
    {
        uint256 cr        = getSystemCR();
        uint256 crFee     = _calculateCRFee(cr);
        uint256 volumeFee = _calculateDPrimeVolumeFee(dprimeVolumeRedemption, dprime.totalSupply());
        uint256 totalFee  = DPRIME_BASE_FEE_BPS + crFee + volumeFee;

        // Cap at 100% (10000 bps)
        if (totalFee > 10000) totalFee = 10000;

        return amount.bpsMul(totalFee);
    }

    /// @notice Calculate DNYLD redemption fee for given amount
    /// @dev Flat fee based on DNYLD_FEE_BPS
    /// @param amount Redemption value in USD
    /// @return Fee amount
    function getDnyldRedemptionFee(uint256 amount) public pure override returns (uint256)
    {
        return amount.bpsMul(DNYLD_FEE_BPS);
    }

    /// @notice Get current ETH price from oracle
    /// @return ETH price in USD with 18 decimals
    function getEthPrice() public view override returns (uint256)
    {
        return oracle.getEthUscPrice();
    }

    /// @notice Get total DPRIME tokens in circulation
    /// @return Total DPRIME supply
    function getTotalMintedDprime() public view override returns (uint256)
    {
        return dprime.totalSupply();
    }

    /// @notice Get total DNYLD tokens in circulation
    /// @return Total DNYLD supply
    function getTotalMintedDnyld() public view override returns (uint256)
    {
        return dnyld.totalSupply();
    }

    /// @notice Get total system collateral value in USD
    /// @return Collateral value in USD with 18 decimals
    function getTotalCollateralUsd() public view override returns (uint256)
    {
        uint256 collateralETH = vault.getTotalCollateralEth();
        uint256 ethPrice      = oracle.getEthUscPrice();
        return collateralETH.wadMul(ethPrice);
    }

    /// @notice Get daily DPRIME redemption cap based on system state
    /// @dev Cap decreases as system health deteriorates
    /// @return Maximum DPRIME redeemable today
    function getDailyDprimeRedemptionCap()
        public
        view
        override
        returns (uint256)
    {
        SystemState state   = getSystemState();
        uint256 totalSupply = dprime.totalSupply();

        if (state == SystemState.NORMAL) return type(uint256).max;
        if (state == SystemState.CAUTION) return (totalSupply * 10) / 100; // 10%
        if (state == SystemState.RECOVERY) return (totalSupply * 2) / 100; // 2%
        return 0; // CRITICAL - frozen

    }

    /// @notice Get amount of DPRIME redeemed today
    /// @return DPRIME redeemed in current day
    function getDailyDprimeRedemptionUsed() public view override returns (uint256)
    {
        return dailyDPRIMERedeemed;
    }

    /// @notice Check if DNYLD is currently redeemable
    /// @dev Blocked in RECOVERY/CRITICAL states or when no headroom
    /// @return True if DNYLD can be redeemed
    function isDnyldRedeemable() public view override returns (bool)
    {
        SystemState state = getSystemState();
        if (state == SystemState.RECOVERY || state == SystemState.CRITICAL)
        {
            return false;
        }

        return getHeadroom() > 0;
    }

    /// @notice Check if DPRIME is currently redeemable
    /// @dev Blocked in CRITICAL state during freeze period
    /// @return True if DPRIME can be redeemed
    function isDprimeRedeemable() public view override returns (bool)
    {
        SystemState state = getSystemState();
        if (state == SystemState.CRITICAL)
        {
            return freezeEndTime == 0 || block.timestamp >= freezeEndTime;
        }
        return true;
    }

    /// @notice Get cached current system state
    /// @return Current SystemState enum value
    function getCurrentState()  public view returns (SystemState)
    {
        return currentState;
    }

    /// @notice Receive ETH
    /// @dev Required for ETH transfers to contract
    receive() external payable {}
}
