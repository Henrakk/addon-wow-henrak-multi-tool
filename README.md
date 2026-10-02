# MultiTool — WoW Forever

Version 1.0.11

## Structure

MultiTool/
│
├── MultiTool.toc
│
├── Core/
│   ├── Core.lua
│   ├── Buffs.lua
│   └── Events.lua
│
├── UI/
│   ├── Tracker.lua
│   ├── XPBar.lua
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
- Keeps the seal countdown synchronized with the aura's actual remaining time, including in combat.
- Displays a separate XP bar with rested XP, session XP, and XP per hour; click the bar to reset session statistics.
- Shows a quest-completion XP projection segment and the projected XP total/percentage directly on the XP bar, with the detailed projection in its tooltip.
- Settings are available in the game's AddOns settings.
- The XP bar has its own **Experience Bar** subsection in the addon's settings; it starts unlocked and can be dragged directly.
- `/mtool` opens settings; `/mtool lock`, `/mtool unlock`, `/mtool reset`, `/mtool class <CLASS>`, `/mtool size <N>`, `/mtool auto`, `/mtool questxp` manage the frame (alias: `/multitool`).

## CurseForge publishing

The GitHub Actions workflow packages and uploads the addon to CurseForge when a version tag is pushed (for example, `v1.0.4`). Both `Interface: 16001` and `Interface-Forever: 16001` mark compatibility with WoW Forever `1.60.1`; keep them in sync when updating the supported client version.

Configure these values in the GitHub repository under **Settings > Secrets and variables > Actions**:

- Add the CurseForge project ID as a repository variable named `CURSEFORGE_PROJECT_ID`.
- Add a CurseForge API token as a repository secret named `CF_API_TOKEN`.

Create a tag for the version and push it to GitHub to publish:

```sh
git tag -a v1.0.4 -m "v1.0.4"
git push origin v1.0.4
```
