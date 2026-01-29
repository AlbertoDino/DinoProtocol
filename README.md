# DinoProtocol

> **WARNING: This is an experimental project. The smart contracts have NOT been audited. Use at your own risk.**

DinoProtocol is a dual-token DeFi system on Ethereum. Users deposit ETH at a 1.5x collateral ratio to mint DPRIME (a $1-pegged stablecoin) and DNYLD (a leveraged equity token). It features permissionless redemption, dynamic fees, multi-state crisis management, and oracle-driven pricing to maintain system solvency.

## Deployed Contracts (Ethereum Mainnet)

| Contract         | Address                                                                                                               |
|------------------|-----------------------------------------------------------------------------------------------------------------------|
| DinoProtocol     | [`0x441B35804c8c0CD2D812Dad9aE98257F1BB18071`](https://etherscan.io/address/0x441B35804c8c0CD2D812Dad9aE98257F1BB18071) |
| DPRIME           | [`0x1EeCAC6DB1Ea98E8535982ac2f59232cB4C86dAf`](https://etherscan.io/address/0x1EeCAC6DB1Ea98E8535982ac2f59232cB4C86dAf) |
| DNYLD            | [`0x870FD8c386aA8Dc437e61757630A8bfC24133396`](https://etherscan.io/address/0x870FD8c386aA8Dc437e61757630A8bfC24133396) |
| Oracle           | [`0x7583BA7be2eb285d569223E186c4ABa930270e05`](https://etherscan.io/address/0x7583BA7be2eb285d569223E186c4ABa930270e05) |
| CollateralVault  | [`0x61f5cBCbEf28432542239f5242219C5ceb8684a1`](https://etherscan.io/address/0x61f5cBCbEf28432542239f5242219C5ceb8684a1) |

---

## How It Works

### Dual-Token Model

DinoProtocol issues two tokens against a shared pool of overcollateralized ETH:

- **DPRIME** -- A stablecoin pegged to $1 USD. It represents a debt claim protected by the collateral pool.
- **DNYLD** -- An equity token representing a pro-rata claim on the surplus collateral (the spread above the 1.5x ratio). DNYLD provides leveraged ETH exposure.

### Entering a Position

When a user deposits ETH or WETH, the protocol enforces a 1.5x collateral ratio:

```
Collateral deposited     = $1.50 worth of ETH
DPRIME minted            = $1.00 (debt portion)
DNYLD minted             = $0.50 / NAV (equity portion)
```

Both tokens are minted together -- there is no way to mint one without the other. This is by design: every participant holds both the stable and leveraged side.

### Redeeming DPRIME

Any DPRIME holder can redeem for ETH at the $1 peg (subject to system state). A dynamic fee structure applies:

| Component    | Range       | Trigger                                    |
|--------------|-------------|--------------------------------------------|
| Base fee     | 0.5%        | Always applied                             |
| CR fee       | 0% -- 50%   | Scales up as collateral ratio drops         |
| Volume fee   | 0% -- 5%    | Scales with recent redemption volume        |

Daily redemption caps are enforced depending on system health.

### Redeeming DNYLD

DNYLD is redeemable at its Net Asset Value (NAV):

```
NAV = (Total Collateral USD - Total DPRIME) / Total DNYLD Supply
```

Redemption is only available when the system is in NORMAL or CAUTION state, and is further limited by headroom -- the excess equity above what is required to maintain the 1.5x ratio.

### System States

The protocol transitions between four states based on the system collateral ratio (CR):

| State        | CR Threshold | DPRIME Redemption           | DNYLD Redemption    |
|--------------|--------------|-----------------------------|---------------------|
| **NORMAL**   | CR >= 150%   | Unlimited, base fee         | Available at NAV    |
| **CAUTION**  | CR >= 135%   | Capped at 5%/day, fees up   | Limited by headroom |
| **RECOVERY** | CR >= 120%   | Capped at 2%/day, high fees | Suspended           |
| **CRITICAL** | CR < 120%    | Frozen (up to 180 days)     | Suspended           |

State transitions happen automatically on every mint and redeem operation.

### Oracle & Price Feeds

The protocol uses a multi-source oracle that aggregates prices from:

- **Chainlink** ETH/USD price feeds
- **Uniswap V3** TWAP (30-minute window by default)

A circuit breaker activates when price deviation exceeds a configurable threshold (default 10%), falling back to the last known valid price.

---

## Contract Architecture

```
src/contracts/
├── core/
│   ├── DinoProtocol.sol        Main protocol logic (minting, redemption, state management)
│   ├── CollateralVault.sol     Holds ETH/WETH collateral, deposit/withdraw operations
│   └── Oracle.sol              Multi-source price oracle with circuit breaker
├── tokens/
│   ├── DinoPrime.sol           DPRIME ERC-20 stablecoin (mint/burn by protocol only)
│   └── DinoYield.sol           DNYLD ERC-20 equity token (mint/burn by protocol only)
├── interfaces/
│   ├── IDinoProtocol.sol       Protocol interface and system state enum
│   ├── ICollateralVault.sol    Vault interface
│   ├── IOracle.sol             Oracle interface, OracleData struct, OracleType enum
│   ├── IDinoPrime.sol          DPRIME token interface
│   ├── IDinoYield.sol          DNYLD token interface
│   ├── IWETH.sol               Wrapped ETH interface
│   └── IUniswapV3Pool.sol      Uniswap V3 pool subset for TWAP queries
├── libraries/
│   ├── WadMath.sol             Fixed-point math (18-decimal WAD, basis points)
│   └── UniswapV3.sol           TWAP price calculation from Uniswap V3 pools
├── proxies/
│   └── Proxy.sol               ERC1967Proxy wrapper for UUPS deployments
└── mocks/
    ├── MockChainlinkAggregator.sol
    ├── MockUniswapV3Pool.sol
    ├── MockWETH.sol
    └── MockUSDC.sol
```

### Contract Interactions

```
User
 │
 ▼
DinoProtocol ──── mint/burn ────► DinoPrime (DPRIME)
 │                                DinoYield (DNYLD)
 │
 ├── deposit/withdraw ──────────► CollateralVault ──► WETH
 │
 └── getEthUscPrice ────────────► Oracle
                                    ├──► Chainlink Aggregators
                                    └──► Uniswap V3 Pools (via UniswapV3 library)
```

- **DinoProtocol** is the single entry point for users. It coordinates all operations.
- **DinoPrime** and **DinoYield** are controlled tokens -- only DinoProtocol (via `MINTER_ROLE`) can mint or burn.
- **CollateralVault** holds all ETH/WETH. Only DinoProtocol (via `OPERATOR_ROLE`) can deposit or withdraw.
- **Oracle** aggregates prices and enforces circuit breaker logic.

### Upgradeability

All core contracts use the UUPS proxy pattern (OpenZeppelin) and are upgradeable. Each contract requires an authorized role (`UPGRADER_ROLE` or `DEFAULT_ADMIN_ROLE`) to approve implementation upgrades.

### Key Dependencies

- [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) -- ERC-20, AccessControl, ReentrancyGuard, Pausable, UUPS
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) -- SafeERC20, Math

---

## Key Formulas

| Formula | Expression |
|---------|-----------|
| Collateral Ratio (CR) | `Total Collateral USD / Total DPRIME Supply` |
| NAV per DNYLD | `(Total Collateral USD - Total DPRIME) / Total DNYLD Supply` |
| DPRIME minted | `ETH deposited in USD / 1.5` |
| DNYLD minted | `(ETH in USD - DPRIME minted) / NAV` |
| Headroom | `(Current Equity - Min Equity) * Total DNYLD / Current Equity` |

---

## Tech Stack

- Solidity ^0.8.28
- Hardhat 3 with TypeScript
- [viem](https://viem.sh/) via `@nomicfoundation/hardhat-toolbox-viem`

---

## Disclaimer

This project is experimental and intended for educational and research purposes. The smart contracts have **not been audited** by any third party. There are inherent risks in interacting with unaudited smart contracts, including but not limited to loss of funds. Do not deposit funds you cannot afford to lose.
