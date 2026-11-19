# PULAU BRAINROT

PULAU BRAINROT is a tropical island brainrot game for Roblox. Eight bases rim a sandy island, each with six pedestals waiting for a creature, and a two-lane dock runs out over the water where seven tiers of sea-animal brainrots spawn — from a flapping flying fish to a golden kraken — that you take, carry over your head, and place on your pedestals so they earn you cash every second. Watch the sky: a tropical storm rolls in on a timer, sweeps anyone caught on the dock or out of their base, and turns the swept brainrots into openable shells worth cracking.

## Mechanics

- **Starting cash:** $200.
- **Bases:** 8 plots, 6 pedestals each, for 48 pedestal slots on the island. Each player is assigned their own base.
- **Dock:** a two-lane pier that restocks itself, holding up to 6 brainrots at a time and adding one roughly every 8 seconds. Take one and it rides above your head.
- **Seven tiers** (name, rarity, price, income per second):

  | Tier | Name | Price | Income/s |
  | ---- | ---- | ----- | -------- |
  | 1 | Ikan Terbang (Common) | 50 | 5 |
  | 2 | Kepiting Disco (Uncommon) | 150 | 15 |
  | 3 | Penyu Turbo (Rare) | 400 | 40 |
  | 4 | Gurita DJ (Epic) | 1,000 | 100 |
  | 5 | Hiu Bajak Laut (Legendary) | 3,000 | 300 |
  | 6 | Paus Api (Mythic) | 12,000 | 1,200 |
  | 7 | Kraken Emas (Ultra Rare) | 50,000 | 10,000 |

  Tier weights are 45% / 25% / 18% / 8% / 2.8% / 1% / 0.2% from Common up to Ultra Rare.
- **Income per second:** every placed brainrot ticks its income once a quarter second, summed across all six pedestals.
- **Sell at half:** selling a placed brainrot refunds half its price (floored).
- **Base lock:** lock your base for 30 seconds so nobody can steal from it while you are away.
- **Stealing:** server-validated. Hold the Steal prompt on another player's pedestal for 2.5 seconds; the server re-checks ownership, the lock, the empty slot and a 4 second cooldown before the brainrot moves to your hands.
- **Rebirth:** costs `100,000 × 2^rebirths` (100,000 for the first; doubles each rebirth) and grants an income multiplier of `1 + 0.5 × rebirths` (×1.5 after one, ×2 after two, and so on), resetting your stacks and refilling you with $100.
- **Tropical storm:** the first storm hits 2 minutes after the server starts, then one every 3 minutes. A 10 second warning leads a wave that sweeps anyone on the dock or carrying a brainrot outside their base; swept brainrots become shells. Shells last 60 seconds.
- **Shell opening by distance band:** a shell's roll depends on how far it lies from the island centre — within 120 studs (near) opens Common or Uncommon, from 120 to 260 studs (mid) opens Rare or Epic, and beyond 260 studs (far) opens Legendary, Mythic or Ultra Rare.
- **HUD:** cash, income per second, the carried brainrot and its income, rebirth count and next rebirth cost, a storm countdown, the base lock timer, and alert cards for spawns, steals, shells and storm phases.

## Controls

- **WASD / arrow keys** — move.
- **Space** — jump.
- **Proximity prompts** — walk up to a dock brainrot and press `E` to *Take* it; press `E` on a pedestal to *Place* the brainrot you carry or *Sell* the one on it; hold `E` on another player's pedestal to *Steal*; press `E` at your base gate to *Lock* it for 30 seconds; hold `E` at the plaza to *Rebirth*; press `E` on a storm shell to *Open* it.

## How to run it

1. Install Rojo 7.7 or newer.
2. Build the place from the repository root:

   ```
   rojo build default.project.json --output game.rbxl
   ```

3. Open `game.rbxl` in Studio and press Play (or start a local server with two players to try stealing).

## Repository layout

```
.
├── main.ts                  the hand-in: checks the entry, copies it to /output, writes dossier.json
├── PLAY.json                the published place's url, place_id and universe_id
├── default.project.json     the Rojo project that builds game.rbxl
├── game.rbxl                the built place file handed in
├── src/
│   ├── server/              authoritative gameplay: Config, World, Bases, Dock, Carry, Pedestal,
│   │                        Lock, Steal, Rebirth, Storm, Cast, BrainrotFactory, Save, PlayerState
│   └── client/              rendering only: init.client, Hud, Fx
├── screenshots/             the four entry screenshots below
├── vendor/makefun-roblox.ts the vendored make.fun dossier library
└── LICENSE                  MIT
```

## Screenshots

- `screenshots/1-cover.jpg` — the cover: the island, the dock and the bases from above, with the HUD.
- `screenshots/2-carry.jpg` — a player carrying a brainrot over their head off the two-lane dock.
- `screenshots/3-base.jpg` — a base with brainrots filling its pedestals and the cash and income HUD readouts.
- `screenshots/4-overview.jpg` — the full island overview: eight bases, the pier and the surrounding sea.

## About

Built by a coding agent for the make.fun `roblox-brainrot-01` bounty.

MIT licensed — see `LICENSE`.
<!-- recorded build witness -->
