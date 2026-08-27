# RainonUI — Changelog

## 1.5.0

* **Cleanup pass — focus on the working modules.** The combat timer and the early raid talent-reminder mode were moved to the archive (see the vault's ARCHIVE.md); their code is preserved with restore notes.
* **Talent-reminder windows now remember where you put them.** Drag the reminder, the counters window, the NPC detail window or the dungeon picker anywhere on screen and each one reopens in the same spot — the same behaviour as the Teleport popup.
* **Ability tooltips in the counters list.** Hovering an enemy ability in the "what this talent counters" list now shows the full in-game spell tooltip, just like the large NPC window already did.
* **Tank mark is smarter.** It only offers the mark when you are actually in a party (not in a raid) and only to players in the tank role — healers and damage dealers no longer get the prompt.
* **The Break sticker got a close button.** A single X on the "Break" sticker lets you dismiss it manually without waiting for the timer.
* **Talent reminder is paladin-only**, enforced everywhere the window can open.
* **Safer defaults.** Feast, Food, "Leaving combat", Tank mark, Bonus roll and the Mythic keystone window are all off by default now, so a fresh profile stays quiet until you opt in.
* Fixed the overlap between the "messages from other players" note and the "Feast" checkbox on the Scripts tab.

## 1.4.5

* **Raid-utility alerts are back** — Healthstone/Soulwell, Cauldron, Repair, Feast, Mailbox, Summon and similar "someone dropped X" stickers work again. On 12.1 another player's cast can't be read directly, so RainonUI now quietly broadcasts *your own* cast to the group over a hidden addon channel (no chat spam) and everyone running RainonUI — or Northern Sky Raid Tools — sees the alert. The Healthstone alert is skipped when you already hold 3.
* **Updated consumable IDs** for Midnight (feasts and cauldrons) and removed outdated ones.
* **Scripts tab** is split into two clear sections — "No addon required" and "Requires RainonUI".
* **Collapsible section bars** styled like the quest-log headers (rounded bar with a gold +/−) across the Scripts, Paladin and Comforts tabs.
* **Paladin tab** — each ability is now a collapsible box with its spell icon; open one to reveal its RU/EU macro buttons.
* **Comforts tab redesign** — a "General" section (Teleports, Reload button), "Tank mark" as its own section with an info hint, and compact one-line rows for Resurrection and Abundance with the sound pickers aligned in one column and made taller. The CraftSim option moved to the Professions tab.
* Full-width layout across the settings tabs.
