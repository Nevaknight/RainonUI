# RainonUI — Changelog

## 1.4.0

* Treatise reminder: an unused weekly treatise in your bags or warband bank now gets a moving pixel-glow border so you don't forget to use it. Works for every profession, in both the default Blizzard bags/bank and in Baganator.
* New toggle in the Professions tab to turn the treatise glow on or off, and a separate toggle for the treatise tooltip caption (both moved here from other places).
* New "Resurrection" section in the Comforts tab with two independent options: play a sound when someone resurrects you (the "Resurrect" prompt), and play a sound when an ally in your party/raid casts a resurrection spell (single or mass — e.g. paladin Redemption/Absolution, priest Resurrection/Mass Resurrection, and more).
* Sounds are now pulled through LibSharedMedia, the standard shared media library (like BigWigs/DBM): the picker lists the addon's own voice sounds, standard game sounds, and any sounds registered by other addons, in a scrollable capped-height list. Choosing a sound also enables its option automatically, and each choice previews as you pick it.
* Settings window reorganized: the "Currency" tab was removed and its contents (bag purchase + Moxie info) merged into the Professions tab under a divider; the paladin buff options moved into a dedicated "Paladin" tab.
* The addon no longer opens or creates any windows during combat (only the combat timer stays active), preventing action-blocked errors.
* Removed the stray helper text at the bottom of the settings box for a cleaner layout.
* Teleport prompt redesigned to a clean Blizzard style: the teleport button sits inside the box (no dungeon icon on it, no editor-blue frames, centered text) and the destination dungeon name now shows in the button's tooltip on hover. You can drag the prompt anywhere and it remembers where you put it; it only closes after you actually teleport (not on click), and it no longer appears while the teleport is on cooldown.
* Various layout fixes, including the Paladin tab macro rows.

## 1.3.3

* Fixed a combat error (ADDON_ACTION_BLOCKED / "Interface action failed") caused by the profession-buff icons being touched during combat.
* Paladin weapon-buff icon now disappears on its own once the rite is applied (added a light poll while the icon is shown).
* Alchemy charges (2/2, 4/4, etc.) are now kept as a per-character snapshot and always shown in the Knowledge window, regardless of the character's profession or whether a profession window is open; the snapshot is no longer wiped when data is momentarily unavailable.
* Weekly objectives (Abundant Offerings, weekly quest, treatise) now show as not-done after the weekly reset for characters whose snapshot predates the reset.
* The addon no longer reacts to unrelated third-party addons loading (only Blizzard modules and boss mods), to avoid interfering with other addons.

## 1.3.2

* Fix spells

## 1.3.1

* Clickable profession crafting-buff icons: click to drink the selected Haranir Phial, or to shatter the selected essence.
* Professions tab: dropdowns to choose the phial quality and the essence used for shattering.
* Macros tab: per-macro info tooltips, spell icons, and a cleaner layout.

## 1.3.0

* Edit Mode: reposition and resize the teleport window, the paladin weapon-buff icon, and all movers natively in Blizzard's Edit Mode, with a settings dialog (X/Y coordinates + size %). Uses the embedded LibEditMode library.
* New "Macros" tab: one-click creation of ready-made paladin macros (RU/EU spell names) in the general macro list.
* Custom addon logo shown in the AddOns list and on the minimap button.
* Minimap button: left-click opens the settings window, right-click opens the Knowledge \& charges window.
* Knowledge window: enable/disable individual characters and remove them from the list.
* Paladin weapon-buff reminder now triggers on ready check, with a 30-minute rebuff threshold.
* Alchemy charge timing fix (2/2 charges = 12h50m).
* Added Discord link to the Links tab.
