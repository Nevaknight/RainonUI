# RainonUI — Changelog

## 1.4.3

* Updated for game patch 12.1.0.
* **Paladin tab rebuilt** — macros are now grouped by ability, each with an icon-and-name header and one-click RU/EU buttons (RU row on top, EU below). Every button has an info icon that explains exactly what the macro does; clicking a button creates that macro in your General macros, ready to drag onto your action bars.
* **Expanded the paladin macro set** — Rebuke (focus / auto-kick), Avenging Wrath + trinket, self-ping, potions, battle rez, Word of Glory, Blessing of Sacrifice, Blessing of Protection (plus a BoP + taunt combo), Blessing of Spellwarding, Blessing of Freedom, and two Divine Shield combos — each in both RU and EU client languages.
* **New "Dungeons" tab** (works with Mythic Dungeon Tools): quick links to MDT and its helper plugin, and a button per current-season dungeon that shares that dungeon's weekly route into MDT with one click on the chat link it posts. A master "Enable module" toggle turns the whole thing on/off (off = no extra triggers loaded).
* **MDT enemy notes** — you can attach your own note to any dungeon NPC and it shows under MDT's mouseover tooltip. Made the hook install reliable no matter when you first open MDT during a session, and fixed a first-hover sizing glitch.
* **Teleport prompt** now includes the current-season dungeon portals (Altar of Fangs, Voidscar Arena, King's Rest, Murder Row, Ruby Life Pools, Temple of Sethraliss, The Blinding Vale, Den of Nalorakk), while keeping the previous ones.
* **New "Faction unlock" hide option** in the Scripts tab — hides the large "Journey Unlocked" major-faction toast.
* **Interface polish** — all checkboxes now use the modern Blizzard style; the settings window scrollbar moved outside the frame so content uses the full width; the in-game reload button was removed and the "Links" tab moved into the side strip; the Links tab was rebuilt (Addon description, Boosty, Discord, Report a bug).

## 1.4.2

* New "Sounds" tab in the settings window to mute specific sound effects, split into "General" (minimap ping) and "Paladin" (Shield of the Righteous, Avenger's Shield, Blessed Hammer). Choices persist between sessions and re-apply on login, with a "Restore all sounds" button. Muting uses the game's own MuteSoundFile, so it only affects the selected files.
* New "Raid warnings" toggle in the Scripts tab that hides the large centered Raid Warning text on screen (the chat line stays). On 12.0 the raid-warning sound is played through the new C_Sound system and can't be muted from an addon, so this option hides the on-screen text only.
* New "Abundance" section in the Comforts tab: play a sound of your choice when an Abundance event finishes, with the same sound picker used elsewhere.
* Added a "Sound tracker" diagnostic window (/rstrack, or the Diagnostics test panel) that lists sounds played through the interface so you can identify them; the window is wider for readability.
* Cleanup: removed leftover experimental modules and dead code for a leaner release.

## 1.4.1

* Knowledge window: new "Darkmoon Faire" column that tracks each character's monthly Darkmoon profession quest, toggleable from the "Columns" button. It auto-hides while the faire isn't running and reappears on its own during the event (detected from the in-game calendar — no need to open the calendar yourself).
* Knowledge window: hovering a character's name now shows their realm in a tooltip, so same-named characters on different realms are easy to tell apart. The "Open with profession" toggle also moved to the Professions tab, next to the "Weekly Knowledge…" button.
* Teleport prompt: enlarged the inner box so the button sits perfectly inside it, and centered the window title.
* On-screen alert stickers redesigned with a cleaner framed panel and a title bar; the break sticker now shows its countdown in a circular badge, and the whole sticker block can be repositioned in Edit Mode.
* Temporarily removed the consumables reminder and the delve-map reminder while they are being reworked.

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
