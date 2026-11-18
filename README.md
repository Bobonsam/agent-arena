# Agent Arena

**The daily game for Agent ID holders** — a dApp on BNB Chain built for the Binance Wallet *Agent ID Hackathon*.

Check in once a day to build your streak, and call the daily prediction mission. Every core action requires holding an **Agent ID** — the non-transferable ERC-721 identity of an Agentic Wallet (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f` on BNB Chain). Because an Agent ID can never be transferred and only one can be claimed per user, it works as the game's anti-sybil identity core: one real agent, one streak, one leaderboard entry.

🌐 **Play:** https://bobonsam.github.io/agent-arena/
📜 **Contract:** `AgentArena` on BNB Chain — [`0x9d882de345fe123384b3d79ad681776126fd13c9`](https://bscscan.com/address/0x9d882de345fe123384b3d79ad681776126fd13c9), deployed 18 Nov 2026 via CREATE2 (tx `0x5cdf7a0423ab0406312beac4790a82335c6c6ea68d1290cd09b99fb7e32baa10`), source verified (Sourcify full match, forwarded to BscScan).

## How to play

1. Open the site in your wallet's dApp browser (or any BNB Chain wallet) and connect.
2. The site checks `balanceOf(your address)` on the Agent ID contract. Holders can play; everyone else can spectate the leaderboard.
3. **Check in** once per UTC day: +10 points, plus +1 bonus per streak day (capped at +20). Miss a day and the streak resets.
4. **Predict** the daily mission (one call per day). If you're right, claim **+50 points** the next day.
5. Streak tiers: **Bronze** at 3 days, **Silver** at 7, **Gold** at 14.

## Rules & safety design

- **Points are a game score only.** They are not a token, cannot be transferred or exchanged, and have no monetary value. Nothing in this project promises returns.
- **You sign everything yourself.** Every action is a transaction initiated and confirmed by the player in their own wallet. The site offers no QR-code login for Agentic Wallet, stores no sessions, and never asks for a seed phrase, private key, or pairing code.
- **The contract never touches user assets.** It holds no funds and has no function that can transfer anything from a player's wallet.
- **Owner powers are deliberately small** (and documented in the source): publish a mission for a future day, resolve a past mission once, and an emergency pause. The owner **cannot** change any player's points, streak, or predictions, cannot edit or re-resolve a mission, and cannot change the Agent ID contract address (it is fixed at deployment).

## Contract design

`contracts/AgentArena.sol` (Solidity ^0.8.24, no external dependencies):

| Action | Gate | Effect |
|---|---|---|
| `checkIn()` | Agent ID | streak/points update, once per UTC day |
| `predict(choice)` | Agent ID | one prediction on today's mission |
| `claimPrediction(day)` | Agent ID | +50 if the prediction was correct |
| `setMission(day, …)` | owner | publish a future day's mission (no overwrites) |
| `resolveMission(day, option)` | owner | resolve once, irreversible |
| `setPaused(bool)` | owner | emergency pause of game actions |

Local test suite (`test_local.py`, py-evm): 27/27 checks pass — gate enforcement, streak math and reset, prediction lifecycle, claim rules, owner limits, pause.

## Run it locally

```bash
npm install solc@0.8.28
node compile.js                     # compiles contracts/ into build/
python3 -m venv venv && ./venv/bin/pip install web3 eth-tester py-evm
./venv/bin/python test_local.py     # full logic test suite
```

## License

MIT — see `LICENSE`.
