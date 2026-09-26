# PaladinCaernSidhe — WoW Forever

Version 1.0.0

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

## CurseForge publishing

The GitHub Actions workflow packages and uploads the addon to CurseForge when a version tag is pushed (for example, `v0.1.1`).

Configure these values in the GitHub repository under **Settings > Secrets and variables > Actions**:

- Add the CurseForge project ID as a repository variable named `CURSEFORGE_PROJECT_ID`.
- Add a CurseForge API token as a repository secret named `CF_API_TOKEN`.

Create a tag for the version and push it to GitHub to publish:

```sh
git tag -a v0.1.1 -m "v0.1.1"
git push origin v0.1.1
```
