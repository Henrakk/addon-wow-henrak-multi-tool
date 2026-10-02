# MultiTool

## v1.0.11 (2026-10-02)

- Update the standard TOC interface version to `16001` so WoW Forever `1.60.1` no longer marks the addon as out of date.
- Fix the seal countdown not resuming from the full duration when recasting a seal (including recasting the same seal already active): removed fragile comparisons that could prevent the timer from resyncing with the refreshed aura, so it now always restarts immediately on a successful cast and reconciles with the server's real expiration as soon as it's available.
- Fix the seal countdown wrongly restarting when casting Judgement or Exorcism: the cast-detection was matching on raw numeric spell IDs, which could misidentify unrelated spells as a seal cast on this server. It now matches on the seal's own localized name instead, the same reliable identity already used for seal buff detection.

## v1.0.10 (2026-09-30)

- Fix completed quest XP still reporting 0: the modern `C_QuestLog.GetInfo` API was being trusted for completion state on a server where it never populates `isComplete`, so completed quests were silently skipped. Completion is now detected from the legacy `GetQuestLogTitle` result first (matching the "Quest Complete!" label shown in the default quest log), falling back to `C_QuestLog` only when the legacy API is unavailable.
- Try more reward-XP lookup methods (by index, by quest ID, and via `C_QuestLog.GetQuestLogRewardXP`) so XP is found regardless of which calling convention the server implements.
- Expand `/mtool questxp` debug output to show both the legacy and modern completion flags side by side, plus the final resolved value, to make future diagnosis faster.
- Fix a Lua error ("bad argument #2 to 'tonumber' (base out of range)") when `GetQuestLogRewardXP` returns multiple values on this server; every lookup now wraps its call in parentheses to only use the first return value.
- Stop capping the projected XP text/percentage at 100%: if completed quests' reward XP exceeds what's needed to level up, the number and percentage shown (both on the bar and in the tooltip) now go above the max/100% instead of being clamped, so you can see how far past the level threshold you'd land. The visual gold segment on the bar itself is still clamped to the bar's width, since it can't represent XP beyond the current level.

## v1.0.9 (2026-09-30)

- Rename the primary slash command from `/mt` to `/mtool`: `/mt` is a built-in Blizzard command (`/maintank`) that was intercepting the addon's command, causing "You aren't in a party" instead of opening settings or running `/mt questxp`. `/multitool` remains available as an alias.
- Fix completed-quest XP detection not returning any value on clients where `GetQuestLogRewardXP` ignores the index argument, by falling back to `SelectQuestLogEntry`.
- Add support for the modern `C_QuestLog` API (used by some client forks) alongside the legacy `GetQuestLogTitle` globals, so quest XP projection works regardless of which API the client exposes.
- Add a `/mtool questxp` debug command that prints quest log entries, detected completion state, and reward XP to help diagnose detection issues.
- Change the quest-projection segment on the XP bar (and its tooltip lines) to a bright gold color for better visibility.

## v1.0.8 (2026-09-30)

- Show the projected XP total and percentage directly on the XP bar when completed quests are ready to turn in.
- Rename the addon settings category title from "Paladin Caern Sidhe" to "MultiTool".

## v1.0.7 (2026-09-30)

- Rename the addon from PaladinCaernSidhe/HenrakMultiTool to **MultiTool** (folder, `.toc`, saved variables, slash commands).
- Replace slash commands `/henrak` and `/hmt` with `/mt` (alias `/multitool`); settings remain reachable with `/mt` alone.
- Automatically migrate existing saved settings from the old `HenrakMultiToolDB` / `PaladinCaernSidheDB` variables.

## v1.0.6 (2026-09-30)

- Fix the XP quest-projection bar never appearing: `GetQuestLogTitle` return values were misaligned, so completed quest XP was never detected.

## v1.0.5 (2026-09-30)

- Match the seal countdown to the aura's actual expiration, including in combat.
- Start the fallback countdown only after a successful seal cast.

## v1.0.4 (2026-09-28)

- Refresh seal status and countdown after a successful recast in combat.
- Use a single absolute expiration time for the seal countdown.
- Align displayed countdown seconds with the in-game timer.