<h1 align="center">CoTankTracker</h1>
<p align="center">
  <img src="https://github.com/zerbiniandrea/CoTankTracker/blob/main/assets/logo.png?raw=true" width="180" />
</p>
<p align="center">Minimal oUF co-tank unit frame for World of Warcraft</p>

Automatically detects the other tank in your raid and displays a compact unit frame with health, name, buffs, and debuffs. No configuration needed — just install and go.

## Profiles

Two built-in profiles are available from the options panel. Switch between them anytime in `/ctt` under the **Profiles** section.

**Private Auras Only** (default) — Private auras above the health bar, externals below, no debuffs

<p align="center">
  <img src="https://github.com/zerbiniandrea/CoTankTracker/blob/main/assets/preview_private_auras_only.png?raw=true" />
</p>

**Full** — Debuffs, defensive cooldowns, and private auras all enabled

<p align="center">
  <img src="https://github.com/zerbiniandrea/CoTankTracker/blob/main/assets/preview_full.png?raw=true" />
</p>

## Features

- Automatically finds the other tank in your raid or party
- Health bar with class-colored name
- Debuffs with filtering (all, raid-relevant, important, player-applied)
- Defensive cooldown tracking
- Private aura support
- Built-in profiles for quick setup
- Fully configurable size, position, fonts, textures, and aura layout
- Test mode for previewing the frame with mock auras

## Configuration

Type `/ctt` to open the options panel.

- `/ctt test` — Show the frame with your character as the unit (preview mode)
- `/ctt hide` — Exit test mode
- `/ctt reset` — Reset frame position to center
