# CoTankTracker

[![](https://shields.io/badge/github-gray?logo=github&style=for-the-badge&logoColor=white)](https://github.com/zerbiniandrea/CoTankTracker)
[![](https://shields.io/badge/ko--fi-FF5E5B?logo=ko-fi&style=for-the-badge&logoColor=white)](https://ko-fi.com/zerbyy)

Minimal oUF co-tank unit frame for World of Warcraft

Automatically detects the other tank in your raid and displays a compact unit frame with health, name, buffs, and debuffs. No configuration needed — just install and go.

## Layout

Defensive cooldowns below the health bar, boss and tank mechanics above it. That is the default, and there is nothing to pick: **Reset All to Defaults** in `/ctt` restores it.

Private aura support was removed. Patch 12.1 renders private auras through aura containers, so boss and role mechanics now arrive as ordinary debuffs. The debuff row shows them with the **Boss + Role** filter, which is the default.

## Features

- Automatically finds the other tank in your raid or party
- Health bar with class-colored name
- Debuffs with filtering (boss and role mechanics, raid-relevant, important, all)
- Defensive cooldown tracking
- Fully configurable size, position, fonts, textures, and aura layout
- Test mode for previewing the frame with mock auras

## Configuration

Type `/ctt` to open the options panel.

## Support

If CoTankTracker keeps an eye on your co-tank for you, consider [supporting development on Ko-fi](https://ko-fi.com/zerbyy) ❤️
