# PaladinCaernSidhe — WoW Forever

Version 0.1.0

## Structure

PaladinCaernSidhe/
│
├── PaladinCaernSidhe.toc
│
├── Core/
│   ├── Core.lua
│   ├── Buffs.lua
│   └── Events.lua
│
├── UI/
│   ├── Tracker.lua
│   ├── Icon.lua
│   └── Options.lua
│
├── Localization/
│   ├── enUS.lua
│   └── frFR.lua
│
└── README.md

## What it does
- Displays selected Paladin self-buffs as icons.
- Detects buffs by spell ID, so the same code works on English and French clients.
- Shows the localized name + missing / manquant when a selected buff is absent.
- Displays a short remaining-time counter when an aura has an expiration time.
- Settings are available in the game's AddOns settings.
- /pcs opens settings; /pcs lock, /pcs unlock, /pcs reset manage the frame.
