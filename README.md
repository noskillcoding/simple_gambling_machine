# Simple Gambling Machine

A decentralized gambling contract written in Solidity. Users deposit ETH in a sequence, and after a timeout, the last depositor can claim the majority of the pot, while a portion is distributed randomly among previous depositors. The contract is designed for transparency and fairness, with all logic on-chain. Available at https://simplegamblingmachine.eth.limo/

## Features
- **Tiered Deposit System:** Deposit requirements and timeouts change based on the number of deposits.
- **Winner Takes Most:** The last depositor after a timeout can claim 80% of the pot.
- **Random Rewards:** 10% of the pot is split among up to 5 random previous depositors.
- **Fully On-Chain:** All logic, including randomness, is handled on-chain.
- **No House Edge:** All funds are distributed to players.

## How It Works
1. Users deposit ETH according to the current required amount (which changes as more deposits are made).
2. Each deposit resets the timer. The timer duration depends on the current deposit tier.
3. If the timer expires, the last depositor can claim the main prize, and random rewards are distributed.
4. The game resets for the next round.

## Contract Details
- **Solidity Version:** 0.8.29
- **Initial Funding:** 0.2 ETH (required to deploy)
- **Circular Buffer:** Tracks up to 5096 depositors per round
- **Events:** `DepositMade`, `GameWon`, `RandomReward`

## Getting Started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/) (for Solidity development and testing)
- Node.js (optional, for additional tooling)

### Installation
1. Clone the repository:
   ```sh
git clone <your-repo-url>
cd simple_gambling_machine
```
2. Install Foundry (if not already installed):
   ```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Building the Contract
```sh
forge build
```

### Running Tests
```sh
forge test
```

## File Structure
- `src/SimpleGamblingMachine.sol` — Main contract
- `test/SimpleGamblingMachine.t.sol` — Test suite (using Foundry)
- `foundry.toml` — Foundry configuration

## Security & Disclaimer
This contract is for educational and experimental purposes. Use at your own risk. The randomness is not secure for high-value use cases.

## License
MIT 
