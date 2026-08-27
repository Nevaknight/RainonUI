-- =========================================================================
-- RainonUI / TalentReminder (ЭКСПЕРИМЕНТАЛЬНЫЙ, тестовый модуль).
-- Идея заимствована из MythicPlusUtility: напоминаем игроку про важные
-- ПОЛЕЗНЫЕ таланты для подземелий. В коде — ТОЛЬКО паладин (другие классы
-- не заводим — так решили).
--
-- Окно в классическом стиле Blizzard (ButtonFrameTemplate). Показывает список
-- ключевых талантов паладина и статус «Изучен / Не изучен». Открывается:
--   • кнопкой из тестера («Подземелья → Напоминание о талантах»);
--   • слэшем /rstalent;
--   • автоматически при входе в подземелье, если модуль включён галкой
--     «Напоминание о талантах» (вкладка «Подземелья») и чего-то не хватает.
-- Галка по умолчанию ВЫКЛ (тестовая функция).
-- =========================================================================
local _, ns = ...

ns.TalentReminder = ns.TalentReminder or {}
local TR = ns.TalentReminder
TR.forcedInst = nil   -- тест: зафиксированное подземелье (перебивает текущее)

-- Полезные способности паладина — ТОЧНО из MythicPlusUtility (SpellsData.lua:
-- utilityAbilities.PALADIN + спек-ветки 65/66/70, включая базовые). Не выдумываем.
-- mark: "need"=+ (нужен), "skip"=− (не нужен), "opt"=± (опционально).
-- ⚠ mark сейчас ЗАГЛУШКА (единый на талант). Реальные +/− ПО ПОДЗЕМЕЛЬЮ дадим
--   позже через теговый движок (DATA по подземельям), как обсуждали.
-- spec: список спек-ID (65 Holy / 66 Prot / 70 Ret); nil = для всех спеков.
local PALADIN_TALENTS = {
    { id = 642,    mark = "need" },              -- Divine Shield (базовый, все)
    { id = 1022,   mark = "need" },              -- Blessing of Protection (все)
    { id = 204018, mark = "opt",  spec = {66} }, -- Blessing of Spellwarding (Prot)
    { id = 853,    mark = "need" },              -- Hammer of Justice (базовый, все)
    { id = 213644, mark = "need", spec = {66, 70} }, -- Cleanse Toxins (Prot/Ret)
    { id = 393024, mark = "opt",  spec = {65} }, -- Improved Cleanse (Holy)
    { id = 115750, mark = "need" },              -- Blinding Light (все)
    { id = 469321, mark = "opt"  },              -- Righteous Protection (все)
    { id = 1044,   mark = "need" },              -- Blessing of Freedom (все)
    { id = 10326,  mark = "opt"  },              -- Turn Evil (все)
    { id = 469304, mark = "opt"  },              -- Steed of Liberty (все)
}

-- Расовые способности-контры (эквивалент талантов: снять с себя/союзника ИЛИ
-- повесить на врага). Гейт — по РАСЕ (`race` = токен UnitRace, напр. "Dwarf",
-- "BloodElf", "Scourge"=Нежить). Показ/матч по мобам — как у талантов (по тегам,
-- ключ COUNTERS = spellID расовой). Направление (себя/союзник/враг) и справочник
-- рас — в [[_INDEX/TALENT_REMINDER]]. Наполняем по мере запросов Миши.
-- Пример строки: { id = 20594, mark = "opt", race = "Dwarf" }  -- Каменная форма
local RACIALS = {}

-- Данные «против кого использовать талант» (клик по таланту → окно мобов с
-- 3D-моделью). Собраны ОФФЛАЙН: абилки/нпц/теги из MythicPlusUtility
-- (InstancesData), имя/группы(g)/телепорт из MDT. В рантайме ни MPU, ни MDT не
-- нужны — игра грузит модель/имя/иконку/тултип по ID.
-- Матч «талант↔абилка» = общий тег (как MPU UtilityFunctions), посчитан заранее.
-- COUNTERS[talentSpellID] = { { npc, inst, dungeonTele, name, g, spell, icon, ability, note }, ... }
-- inst — EJ instanceID (окно фильтрует по ТЕКУЩЕМУ подземелью); dungeonTele — портал (иконка);
-- spell — SPELL_ID; name/g — из MDT; note/icon/ability — опционально.
local COUNTERS = {
    [642] = { -- Божественный щит (117)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=259446, inst=2993, dungeonTele=1286812, name="The Writhing Coil", g="46", spell=1310358 },
        { npc=261553, inst=2993, dungeonTele=1286812, name="Ravenous Descendant", g="5,6,7,9,10,13,14,15", spell=1306333 },
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1289416 },
        { npc=263109, inst=2993, dungeonTele=1286812, name="Ula'tek's Chosen", g="34,38,39,43", spell=1307567 },
        { npc=272271, inst=2993, dungeonTele=1286812, spell=1294569 },
        -- Den of Nalorakk
        { npc=241808, inst=2825, dungeonTele=1286807, name="Territorial Matriarch", g="4,11,14,15,17,18,25,27,28,33,37,38,40,41", spell=1238053 },
        { npc=241816, inst=2825, dungeonTele=1286807, name="Keen-Eyed Striker", g="2,4,6,9,16,19,21,30,31,35,36,39", spell=1238439 },
        { npc=241869, inst=2825, dungeonTele=1286807, name="Avatar of Determination", g="49,59", spell=1241464 },
        { npc=241872, inst=2825, dungeonTele=1286807, name="Frigid Mauler", g="44,46,47,52,57", spell=1309919 },
        { npc=245145, inst=2825, dungeonTele=1286807, name="Bonded Beasttamer", g="69,70,71", spell=1246865 },
        { npc=245567, inst=2825, dungeonTele=1286807, name="Starvation Effigy", g="3,12,13,16,20,23,24", spell=1238801 },
        { npc=248710, inst=2825, dungeonTele=1286807, spell=1234846 },
        { npc=261053, inst=2825, dungeonTele=1286807, spell=1263597 },
        -- Kings' Rest
        { npc=133943, inst=1762, dungeonTele=1286831, name="Minion of Zul", g="2,4", spell=276031 },
        { npc=134158, inst=1762, dungeonTele=1286831, name="Shadow-Borne Champion", g="5,7", spell=269976 },
        { npc=134174, inst=1762, dungeonTele=1286831, name="Risen Hexer", g="6", spell=269972 },
        { npc=134174, inst=1762, dungeonTele=1286831, name="Risen Hexer", g="6", spell=1294815 },
        { npc=135167, inst=1762, dungeonTele=1286831, name="Royal Berserker", g="26,30", spell=1301851 },
        { npc=135204, inst=1762, dungeonTele=1286831, name="Phantom Hex Priest", g="22,24", spell=270492 },
        { npc=135239, inst=1762, dungeonTele=1286831, name="Spectral Shaman", g="22,24", spell=270499 },
        { npc=135472, inst=1762, dungeonTele=1286831, spell=267273 },
        { npc=136160, inst=1762, dungeonTele=1286831, name="King Dazar", g="29", spell=1302945 },
        { npc=136976, inst=1762, dungeonTele=1286831, name="T'zala", g="29", spell=1303490 },
        { npc=136984, inst=1762, dungeonTele=1286831, name="Reban", g="29", spell=269369 },
        { npc=137484, inst=1762, dungeonTele=1286831, name="King A'akul", g="9", spell=1297918 },
        { npc=137485, inst=1762, dungeonTele=1286831, name="Bloodsworn Assassin", g="9", spell=1297781 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1297763 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        { npc=269811, inst=1762, dungeonTele=1286831, name="Kula the Butcher", g="27", spell=266231 },
        { npc=269811, inst=1762, dungeonTele=1286831, name="Kula the Butcher", g="27", spell=266191 },
        { npc=270502, inst=1762, dungeonTele=1286831, name="Half-Finished Mummy", g="13,20", spell=267763 },
        -- Murder Row
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474515 },
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474740 },
        { npc=235265, inst=2813, dungeonTele=1286809, name="Corrupted Warlock", g="29,30,38,48", spell=1217973 },
        { npc=235267, inst=2813, dungeonTele=1286809, name="Wrathguard Flayer", g="20,22,29,32,38,41,46", spell=1214922 },
        { npc=235267, inst=2813, dungeonTele=1286809, name="Wrathguard Flayer", g="20,22,29,32,38,41,46", spell=1295427 },
        { npc=236071, inst=2813, dungeonTele=1286809, name="Bribed Guard", g="3,9", spell=1295035 },
        { npc=236073, inst=2813, dungeonTele=1286809, name="Row Hooligan", g="1,3,8,9,11", spell=1216300 },
        { npc=236082, inst=2813, dungeonTele=1286809, name="Seductive Sayaad", g="10,25,34", spell=1201554 },
        { npc=236091, inst=2813, dungeonTele=1286809, name="Street Sneak", g="6,7,8", spell=1216590 },
        { npc=236893, inst=2813, dungeonTele=1286809, name="Warehouse Worker", g="16", spell=1311136 },
        { npc=236897, inst=2813, dungeonTele=1286809, name="Keen Taskmaster", g="16", spell=1216970 },
        -- Ruby Life Pools
        { npc=187897, inst=2521, dungeonTele=393256, name="Defier Draghar", spell=372796 },
        { npc=189893, inst=2521, dungeonTele=393256, name="Infused Whelp", spell=1305234 },
        -- Temple of Sethraliss
        { npc=134364, inst=1877, dungeonTele=1286828, name="Faithless Subjugator", g="18,23", spell=1314082 },
        { npc=134389, inst=1877, dungeonTele=1286828, name="Toxic Viper", g="35", spell=267027 },
        { npc=134602, inst=1877, dungeonTele=1286828, name="Shrouded Fang", g="2,4,5,8,9,10", spell=1308100 },
        { npc=134616, inst=1877, dungeonTele=1286828, name="Barbed Krolusk", g="1,4,7,9,14", spell=1291399 },
        { npc=135562, inst=1877, dungeonTele=1286828, name="Poisonous Viper", g="13,16,20,22,26", spell=1308148 },
        -- The Blinding Vale
        { npc=243030, inst=2859, dungeonTele=1286801, name="Lekshi", spell=1235865 },
        { npc=244887, inst=2859, dungeonTele=1286801, name="Ikuzz the Light Hunter", spell=1236658 },
        { npc=244887, inst=2859, dungeonTele=1286801, name="Ikuzz the Light Hunter", spell=1237166 },
        { npc=245339, inst=2859, dungeonTele=1286801, name="Underbrush Stalker", g="23,25,29,35,36,44,50,51,75,79", spell=1238076 },
        { npc=245410, inst=2859, dungeonTele=1286801, name="Lasher", g="19,20,21,22,25,27,28,32,34,35,36,38,39,40,42,45,47,48,50,54,64,69,71,77,78", spell=1238084 },
        { npc=245912, inst=2859, dungeonTele=1286801, name="Lightwarden Ruia", g="68", spell=1241058 },
        { npc=246871, inst=2859, dungeonTele=1286801, name="Luminous Thornmaw", g="58,61,63,76", spell=1242135 },
        { npc=247676, inst=2859, dungeonTele=1286801, name="Ziekket", spell=1247746 },
        { npc=249756, inst=2859, dungeonTele=1286801, name="Potatoad Matriarch", g="70", spell=1250937 },
        -- Voidscar Arena
        { npc=238883, inst=2923, dungeonTele=1286804, name="Dominated Brawler", g="1,6,7,33,36,53,55", spell=1254826 },
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1226031 },
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1263971 },
        { npc=243766, inst=2923, dungeonTele=1286804, name="Kilivore Screamer", g="19,24,28,37,40,45,51,52,55,57,59", spell=1233398 },
        { npc=243985, inst=2923, dungeonTele=1286804, name="Longtooth Tuskarr", g="1,10,11,14", spell=1310319 },
        { npc=243988, inst=2923, dungeonTele=1286804, name="Feral Saberon", g="1,5,6,10,11,13,48,49,52", spell=1267894 },
        { npc=249590, inst=2923, dungeonTele=1286804, name="Angry Krolusk", g="17", spell=1249621 },
        { npc=249608, inst=2923, dungeonTele=1286804, name="Raging Raptor", g="13", spell=1249661 },
        { npc=255001, inst=2923, dungeonTele=1286804, name="Gravitic Orb", g="63", spell=1287450 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1289258 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1311778 },
        { npc=267545, inst=2923, dungeonTele=1286804, name="Aegyra the Unyielding", g="9", spell=1299133 },
        -- Magisters' Terrace
        { npc=231861, inst=2811, dungeonTele=1254572, name="Arcanotron Custos", spell=1214038 },
        { npc=231865, inst=2811, dungeonTele=1254572, name="Degentrius", spell=1269631 },
        { npc=249086, inst=2811, dungeonTele=1254572, name="Void Terror", g="37,39,41,42,43,44,46,50,51,54,55,57", spell=1264693 },
        -- Maisara Caverns
        { npc=1531, inst=2874, dungeonTele=1254559, spell=1254175 },
        { npc=242964, inst=2874, dungeonTele=1254559, name="Keen Headhunter", g="4,6,13,20,23,24,26,32,39,43,44,54,55,57", spell=1266381 },
        { npc=247570, inst=2874, dungeonTele=1254559, name="Muro'jin", g="58", spell=1260709 },
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1266488 },
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1246666 },
        { npc=248678, inst=2874, dungeonTele=1254559, name="Hulking Juggernaut", g="19,29", spell=1256059 },
        { npc=248684, inst=2874, dungeonTele=1254559, name="Frenzied Berserker", g="1,4,6,10,13,15,21,23,25,26,29,39,40,43,44,46,52", spell=1255765 },
        { npc=249024, inst=2874, dungeonTele=1254559, name="Hollow Soulrender", g="68,77,81", spell=1271623 },
        { npc=253683, inst=2874, dungeonTele=1254559, name="Rokh'zal", g="62", spell=1259794 },
        -- Nexus-Point Xenas
        { npc=241647, inst=2915, dungeonTele=1254563, name="Flux Engineer", g="25,26,36,38,39", spell=249081 },
        { npc=248706, inst=2915, dungeonTele=1254563, name="Cursed Voidcaller", g="5,8,14,22", spell=1281636 },
        { npc=251853, inst=2915, dungeonTele=1254563, name="Grand Nullifier", g="6,9,11,14,18", spell=1282724 },
        -- Algeth'ar Academy
        { npc=191736, inst=2526, dungeonTele=393273, name="Crawth", spell=376997 },
        { npc=192329, inst=2526, dungeonTele=393273, name="Territorial Eagle", g="16,17,18", spell=377344 },
        { npc=192333, inst=2526, dungeonTele=393273, name="Alpha Eagle", g="17,18", spell=377389 },
        { npc=196044, inst=2526, dungeonTele=393273, name="Unruly Textbook", g="7,8,9", spell=388392 },
        { npc=196482, inst=2526, dungeonTele=393273, name="Overgrown Ancient", spell=388623 },
        { npc=197219, inst=2526, dungeonTele=393273, name="Vile Lasher", g="20,21,23", spell=1282244 },
        { npc=197398, inst=2526, dungeonTele=393273, name="Hungry Lasher", g="20,21,23", spell=389033 },
        { npc=197406, inst=2526, dungeonTele=393273, name="Aggravated Skitterfly", g="19,22", spell=390938 },
        -- Windrunner Spire
        { npc=231626, inst=2805, dungeonTele=1254400, name="Kalis", g="42", spell=1215803 },
        { npc=231631, inst=2805, dungeonTele=1254400, name="Commander Kroluk", spell=1253030 },
        { npc=232063, inst=2805, dungeonTele=1254400, name="Apex Lynx", g="17", spell=1216985 },
        { npc=232067, inst=2805, dungeonTele=1254400, name="Creeping Spindleweb", g="12,14,15", spell=1216822 },
        { npc=232146, inst=2805, dungeonTele=1254400, name="Phantasmal Mystic", g="58,60", spell=1216459 },
        { npc=232171, inst=2805, dungeonTele=1254400, name="Ardent Cutthroat", g="31,33,36,37,38,40,41", spell=473794 },
        { npc=232283, inst=2805, dungeonTele=1254400, name="Loyal Worg", g="54,55,57,59,60", spell=1253739 },
        { npc=232447, inst=2805, dungeonTele=1254400, spell=1217094 },
        -- Seat of the Triumvirate
        { npc=122316, inst=1753, dungeonTele=1254551, name="Saprish", g="31", spell=245742 },
        { npc=122403, inst=1753, dungeonTele=1254551, name="Shadowguard Champion", g="1,2,3,4,6,7,9,10,12,16,17,21,23,26,29,34,45", spell=1264036 },
        { npc=124171, inst=1753, dungeonTele=1254551, name="Merciless Subjugator", g="3,4,7,10,19,22,27", spell=1262509 },
        -- Skyreach
        { npc=75964, inst=1209, dungeonTele=1254557, name="Ranjit", spell=153757 },
        { npc=79303, inst=1209, dungeonTele=1254557, name="Adorned Bladetalon", g="3,12,24,26,32", spell=1254475 },
        { npc=250992, inst=1209, dungeonTele=1254557, name="Raging Squall", g="4,6,7,13,25", spell=1254678 },
        -- Pit of Saron
        { npc=36477, inst=658, dungeonTele=1254555, spell=1264186 },
        { npc=36494, inst=658, dungeonTele=1254555, spell=1261921 },
        { npc=36658, inst=658, dungeonTele=1254555, spell=1262930 },
        { npc=252555, inst=658, dungeonTele=1254555, name="Lumbering Plaguehorror", g="57,58,59,60,62,80", spell=1259132 },
        { npc=252558, inst=658, dungeonTele=1254555, name="Rotting Ghoul", g="21,23,24,25,30,31,34,37,41,42,45,49,51,71,81", spell=1258459 },
        { npc=252561, inst=658, dungeonTele=1254555, name="Quarry Tormentor", g="2,5,6,8,12,14,15,18,19,21,23,25,26,29,31,32,35,38,39,43,47,51,67,70,81,85", spell=1258434 },
        { npc=252566, inst=658, dungeonTele=1254555, name="Rimebone Coldwraith", g="43,47,48,50,61,70,73,85", spell=1258437 },
        { npc=252707, inst=658, dungeonTele=1254555, spell=1258997 },
    },
    [1022] = { -- Благословение защиты (42)
        -- Den of Nalorakk
        { npc=241816, inst=2825, dungeonTele=1286807, name="Keen-Eyed Striker", g="2,4,6,9,16,19,21,30,31,35,36,39", spell=1238439 },
        -- Kings' Rest
        { npc=135167, inst=1762, dungeonTele=1286831, name="Royal Berserker", g="26,30", spell=1301851 },
        { npc=136160, inst=1762, dungeonTele=1286831, name="King Dazar", g="29", spell=1302945 },
        { npc=136976, inst=1762, dungeonTele=1286831, name="T'zala", g="29", spell=1303490 },
        { npc=137474, inst=1762, dungeonTele=1286831, name="King Timalji", g="8", spell=270928, note="Можно дать милишнику, чтобы не бегал и продолжал бить" },
        { npc=137484, inst=1762, dungeonTele=1286831, name="King A'akul", g="9", spell=1297918 },
        { npc=137485, inst=1762, dungeonTele=1286831, name="Bloodsworn Assassin", g="9", spell=1297781, note="Снимаем с союзника на 2+ стаках, в приоритете хиллеру" },
        { npc=269811, inst=1762, dungeonTele=1286831, name="Kula the Butcher", g="27", spell=266231 },
        { npc=269811, inst=1762, dungeonTele=1286831, name="Kula the Butcher", g="27", spell=266191 },
        -- Murder Row
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474740 },
        { npc=235267, inst=2813, dungeonTele=1286809, name="Wrathguard Flayer", g="20,22,29,32,38,41,46", spell=1295427 },
        { npc=236071, inst=2813, dungeonTele=1286809, name="Bribed Guard", g="3,9", spell=1295035 },
        { npc=236073, inst=2813, dungeonTele=1286809, name="Row Hooligan", g="1,3,8,9,11", spell=1216300 },
        { npc=236893, inst=2813, dungeonTele=1286809, name="Warehouse Worker", g="16", spell=1311136 },
        -- Ruby Life Pools
        { npc=187897, inst=2521, dungeonTele=393256, name="Defier Draghar", spell=372796 },
        -- Temple of Sethraliss
        { npc=134616, inst=1877, dungeonTele=1286828, name="Barbed Krolusk", g="1,4,7,9,14", spell=1291399 },
        -- The Blinding Vale
        { npc=243030, inst=2859, dungeonTele=1286801, name="Lekshi", spell=1235865 },
        { npc=244887, inst=2859, dungeonTele=1286801, name="Ikuzz the Light Hunter", spell=1237166 },
        { npc=245339, inst=2859, dungeonTele=1286801, name="Underbrush Stalker", g="23,25,29,35,36,44,50,51,75,79", spell=1238076 },
        { npc=245912, inst=2859, dungeonTele=1286801, name="Lightwarden Ruia", g="68", spell=1241058 },
        { npc=246871, inst=2859, dungeonTele=1286801, name="Luminous Thornmaw", g="58,61,63,76", spell=1242135 },
        { npc=247676, inst=2859, dungeonTele=1286801, name="Ziekket", spell=1247746 },
        -- Voidscar Arena
        { npc=243766, inst=2923, dungeonTele=1286804, name="Kilivore Screamer", g="19,24,28,37,40,45,51,52,55,57,59", spell=1233398 },
        { npc=243988, inst=2923, dungeonTele=1286804, name="Feral Saberon", g="1,5,6,10,11,13,48,49,52", spell=1267894 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1311778 },
        { npc=267545, inst=2923, dungeonTele=1286804, name="Aegyra the Unyielding", g="9", spell=1299133 },
        -- Maisara Caverns
        { npc=242964, inst=2874, dungeonTele=1254559, name="Keen Headhunter", g="4,6,13,20,23,24,26,32,39,43,44,54,55,57", spell=1266381 },
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1266488 },
        { npc=248678, inst=2874, dungeonTele=1254559, name="Hulking Juggernaut", g="19,29", spell=1256059 },
        -- Algeth'ar Academy
        { npc=191736, inst=2526, dungeonTele=393273, name="Crawth", spell=376997 },
        { npc=192329, inst=2526, dungeonTele=393273, name="Territorial Eagle", g="16,17,18", spell=377344 },
        { npc=196482, inst=2526, dungeonTele=393273, name="Overgrown Ancient", spell=388623 },
        { npc=197219, inst=2526, dungeonTele=393273, name="Vile Lasher", g="20,21,23", spell=1282244 },
        -- Windrunner Spire
        { npc=232063, inst=2805, dungeonTele=1254400, name="Apex Lynx", g="17", spell=1216985 },
        { npc=232283, inst=2805, dungeonTele=1254400, name="Loyal Worg", g="54,55,57,59,60", spell=1253739 },
        { npc=232447, inst=2805, dungeonTele=1254400, spell=1217094 },
        -- Seat of the Triumvirate
        { npc=122316, inst=1753, dungeonTele=1254551, name="Saprish", g="31", spell=245742 },
        -- Skyreach
        { npc=75964, inst=1209, dungeonTele=1254557, name="Ranjit", spell=153757 },
        { npc=79303, inst=1209, dungeonTele=1254557, name="Adorned Bladetalon", g="3,12,24,26,32", spell=1254475 },
        -- Pit of Saron
        { npc=36658, inst=658, dungeonTele=1254555, spell=1262930 },
        { npc=252558, inst=658, dungeonTele=1254555, name="Rotting Ghoul", g="21,23,24,25,30,31,34,37,41,42,45,49,51,71,81", spell=1258459 },
        { npc=252707, inst=658, dungeonTele=1254555, spell=1258997 },
    },
    [204018] = { -- Благословение от заклинаний (54)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=259446, inst=2993, dungeonTele=1286812, name="The Writhing Coil", g="46", spell=1310358 },
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1289416 },
        { npc=263109, inst=2993, dungeonTele=1286812, name="Ula'tek's Chosen", g="34,38,39,43", spell=1307567 },
        { npc=272271, inst=2993, dungeonTele=1286812, spell=1294569 },
        -- Den of Nalorakk
        { npc=241869, inst=2825, dungeonTele=1286807, name="Avatar of Determination", g="49,59", spell=1241464 },
        { npc=241872, inst=2825, dungeonTele=1286807, name="Frigid Mauler", g="44,46,47,52,57", spell=1309919 },
        { npc=248710, inst=2825, dungeonTele=1286807, spell=1234846 },
        { npc=261053, inst=2825, dungeonTele=1286807, spell=1263597 },
        -- Kings' Rest
        { npc=133943, inst=1762, dungeonTele=1286831, name="Minion of Zul", g="2,4", spell=276031 },
        { npc=134174, inst=1762, dungeonTele=1286831, name="Risen Hexer", g="6", spell=269972 },
        { npc=134174, inst=1762, dungeonTele=1286831, name="Risen Hexer", g="6", spell=1294815 },
        { npc=135204, inst=1762, dungeonTele=1286831, name="Phantom Hex Priest", g="22,24", spell=270492 },
        { npc=135239, inst=1762, dungeonTele=1286831, name="Spectral Shaman", g="22,24", spell=270499 },
        { npc=135472, inst=1762, dungeonTele=1286831, spell=267273 },
        { npc=136984, inst=1762, dungeonTele=1286831, name="Reban", g="29", spell=269369 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        { npc=270502, inst=1762, dungeonTele=1286831, name="Half-Finished Mummy", g="13,20", spell=267763 },
        -- Murder Row
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474515 },
        { npc=235265, inst=2813, dungeonTele=1286809, name="Corrupted Warlock", g="29,30,38,48", spell=1217973 },
        { npc=236082, inst=2813, dungeonTele=1286809, name="Seductive Sayaad", g="10,25,34", spell=1201554 },
        { npc=236091, inst=2813, dungeonTele=1286809, name="Street Sneak", g="6,7,8", spell=1216590 },
        -- Ruby Life Pools
        { npc=189893, inst=2521, dungeonTele=393256, name="Infused Whelp", spell=1305234 },
        -- Temple of Sethraliss
        { npc=134364, inst=1877, dungeonTele=1286828, name="Faithless Subjugator", g="18,23", spell=1314082 },
        { npc=134389, inst=1877, dungeonTele=1286828, name="Toxic Viper", g="35", spell=267027 },
        { npc=134602, inst=1877, dungeonTele=1286828, name="Shrouded Fang", g="2,4,5,8,9,10", spell=1308100 },
        { npc=135562, inst=1877, dungeonTele=1286828, name="Poisonous Viper", g="13,16,20,22,26", spell=1308148 },
        -- The Blinding Vale
        { npc=244887, inst=2859, dungeonTele=1286801, name="Ikuzz the Light Hunter", spell=1236658 },
        { npc=245410, inst=2859, dungeonTele=1286801, name="Lasher", g="19,20,21,22,25,27,28,32,34,35,36,38,39,40,42,45,47,48,50,54,64,69,71,77,78", spell=1238084 },
        { npc=249756, inst=2859, dungeonTele=1286801, name="Potatoad Matriarch", g="70", spell=1250937 },
        -- Voidscar Arena
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1226031 },
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1263971 },
        { npc=249590, inst=2923, dungeonTele=1286804, name="Angry Krolusk", g="17", spell=1249621 },
        { npc=255001, inst=2923, dungeonTele=1286804, name="Gravitic Orb", g="63", spell=1287450 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1289258 },
        -- Magisters' Terrace
        { npc=231861, inst=2811, dungeonTele=1254572, name="Arcanotron Custos", spell=1214038 },
        { npc=231865, inst=2811, dungeonTele=1254572, name="Degentrius", spell=1269631 },
        -- Maisara Caverns
        { npc=1531, inst=2874, dungeonTele=1254559, spell=1254175 },
        { npc=247570, inst=2874, dungeonTele=1254559, name="Muro'jin", g="58", spell=1260709 },
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1246666 },
        { npc=249024, inst=2874, dungeonTele=1254559, name="Hollow Soulrender", g="68,77,81", spell=1271623 },
        { npc=253683, inst=2874, dungeonTele=1254559, name="Rokh'zal", g="62", spell=1259794 },
        -- Nexus-Point Xenas
        { npc=241647, inst=2915, dungeonTele=1254563, name="Flux Engineer", g="25,26,36,38,39", spell=249081 },
        { npc=248706, inst=2915, dungeonTele=1254563, name="Cursed Voidcaller", g="5,8,14,22", spell=1281636 },
        -- Algeth'ar Academy
        { npc=197398, inst=2526, dungeonTele=393273, name="Hungry Lasher", g="20,21,23", spell=389033 },
        -- Windrunner Spire
        { npc=231626, inst=2805, dungeonTele=1254400, name="Kalis", g="42", spell=1215803 },
        { npc=232067, inst=2805, dungeonTele=1254400, name="Creeping Spindleweb", g="12,14,15", spell=1216822 },
        { npc=232171, inst=2805, dungeonTele=1254400, name="Ardent Cutthroat", g="31,33,36,37,38,40,41", spell=473794 },
        -- Seat of the Triumvirate
        { npc=124171, inst=1753, dungeonTele=1254551, name="Merciless Subjugator", g="3,4,7,10,19,22,27", spell=1262509 },
        -- Pit of Saron
        { npc=36477, inst=658, dungeonTele=1254555, spell=1264186 },
        { npc=36494, inst=658, dungeonTele=1254555, spell=1261921 },
        { npc=252561, inst=658, dungeonTele=1254555, name="Quarry Tormentor", g="2,5,6,8,12,14,15,18,19,21,23,25,26,29,31,32,35,38,39,43,47,51,67,70,81,85", spell=1258434 },
        { npc=252566, inst=658, dungeonTele=1254555, name="Rimebone Coldwraith", g="43,47,48,50,61,70,73,85", spell=1258437 },
    },
    [853] = { -- Молот правосудия (24)
        -- Altar of Fangs
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1306385 },
        -- Kings' Rest
        { npc=135406, inst=1762, dungeonTele=1286831, name="Animated Gold" },
        -- Murder Row
        { npc=236082, inst=2813, dungeonTele=1286809, name="Seductive Sayaad", g="10,25,34", spell=1201554 },
        { npc=236084, inst=2813, dungeonTele=1286809, name="Felonious Mage", g="2,5,6,10,14", spell=1216571 },
        -- Ruby Life Pools
        { npc=188067, inst=2521, dungeonTele=393256, name="Flashfrost Chillweaver", g="2,7,12,33", spell=372743 },
        { npc=190206, inst=2521, dungeonTele=393256, name="Ashseer Flamelasher", g="15,16,17,20,29,36,38,39", spell=385536 },
        -- Temple of Sethraliss
        { npc=134388, inst=1877, dungeonTele=1286828, name="A Knot of Snakes", g="34", spell=263958 },
        { npc=134600, inst=1877, dungeonTele=1286828, name="Sandswept Hunter", g="1,4,6,9,10,13,16,23", spell=1308113 },
        { npc=269227, inst=1877, dungeonTele=1286828, name="Temple Disruptor", g="37,38", spell=1303535 },
        -- The Blinding Vale
        { npc=250202, inst=2859, dungeonTele=1286801, name="Newborn Potadpole", g="31", spell=1250829 },
        -- Voidscar Arena
        { npc=244708, inst=2923, dungeonTele=1286804, name="Voidminder", g="46,48,54", spell=1310324 },
        { npc=249603, inst=2923, dungeonTele=1286804, name="Protective Turtle", g="14", spell=1250021 },
        -- Maisara Caverns
        { npc=248692, inst=2874, dungeonTele=1254559, name="Reanimated Warrior", g="59,63,65,66,69,71,72,73,76,78,82,85,87,88,89,93", spell=1257716 },
        -- Nexus-Point Xenas
        { npc=241644, inst=2915, dungeonTele=1254563, name="Corewright Arcanist", g="1,2,26,28,32,34,35,40,41", spell=1285445 },
        { npc=241645, inst=2915, dungeonTele=1254563, name="Hollowsoul Scrounger", g="1,2,10,12,15,16,17,21,22", spell=1252204 },
        -- Algeth'ar Academy
        { npc=196044, inst=2526, dungeonTele=393273, name="Unruly Textbook", g="7,8,9", spell=388392 },
        -- Windrunner Spire
        { npc=232147, inst=2805, dungeonTele=1254400, name="Lingering Marauder", g="49,54,56,60", spell=1216637 },
        { npc=236891, inst=2805, dungeonTele=1254400, spell=1216848 },
        { npc=238035, inst=2805, dungeonTele=1254400, spell=1216449 },
        -- Seat of the Triumvirate
        { npc=122413, inst=1753, dungeonTele=1254551, name="Ruthless Riftstalker", g="12,14,25,28,33,34,35,37,41,45", spell=1277339 },
        { npc=122827, inst=1753, dungeonTele=1254551, name="Umbral Tentacle", g="49", spell=1268733 },
        -- Skyreach
        { npc=76154, inst=1209, dungeonTele=1254557, name="Suntalon Tamer", g="21,22", spell=1254686 },
        { npc=76267, inst=1209, dungeonTele=1254557 },
        -- Pit of Saron
        { npc=252707, inst=658, dungeonTele=1254555, spell=1258997 },
    },
    [213644] = { -- Очищение от токсинов (23)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1289416 },
        { npc=263109, inst=2993, dungeonTele=1286812, name="Ula'tek's Chosen", g="34,38,39,43", spell=1307567 },
        -- Den of Nalorakk
        { npc=248710, inst=2825, dungeonTele=1286807, spell=1234846 },
        -- Kings' Rest
        { npc=135472, inst=1762, dungeonTele=1286831, spell=267273 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        { npc=270502, inst=1762, dungeonTele=1286831, name="Half-Finished Mummy", g="13,20", spell=267763 },
        -- Murder Row
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474515 },
        { npc=236091, inst=2813, dungeonTele=1286809, name="Street Sneak", g="6,7,8", spell=1216590 },
        -- Temple of Sethraliss
        { npc=134389, inst=1877, dungeonTele=1286828, name="Toxic Viper", g="35", spell=267027 },
        { npc=134602, inst=1877, dungeonTele=1286828, name="Shrouded Fang", g="2,4,5,8,9,10", spell=1308100 },
        { npc=135562, inst=1877, dungeonTele=1286828, name="Poisonous Viper", g="13,16,20,22,26", spell=1308148 },
        -- The Blinding Vale
        { npc=249756, inst=2859, dungeonTele=1286801, name="Potatoad Matriarch", g="70", spell=1250937 },
        -- Voidscar Arena
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1226031 },
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1263971 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1289258 },
        -- Maisara Caverns
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1246666 },
        -- Algeth'ar Academy
        { npc=197398, inst=2526, dungeonTele=393273, name="Hungry Lasher", g="20,21,23", spell=389033 },
        -- Windrunner Spire
        { npc=232067, inst=2805, dungeonTele=1254400, name="Creeping Spindleweb", g="12,14,15", spell=1216822 },
        { npc=232171, inst=2805, dungeonTele=1254400, name="Ardent Cutthroat", g="31,33,36,37,38,40,41", spell=473794 },
        -- Pit of Saron
        { npc=36658, inst=658, dungeonTele=1254555, spell=1262930 },
        { npc=252558, inst=658, dungeonTele=1254555, name="Rotting Ghoul", g="21,23,24,25,30,31,34,37,41,42,45,49,51,71,81", spell=1258459 },
    },
    [393024] = { -- Улучшенное очищение (23)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1289416 },
        { npc=263109, inst=2993, dungeonTele=1286812, name="Ula'tek's Chosen", g="34,38,39,43", spell=1307567 },
        -- Den of Nalorakk
        { npc=248710, inst=2825, dungeonTele=1286807, spell=1234846 },
        -- Kings' Rest
        { npc=135472, inst=1762, dungeonTele=1286831, spell=267273 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        { npc=270502, inst=1762, dungeonTele=1286831, name="Half-Finished Mummy", g="13,20", spell=267763 },
        -- Murder Row
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474515 },
        { npc=236091, inst=2813, dungeonTele=1286809, name="Street Sneak", g="6,7,8", spell=1216590 },
        -- Temple of Sethraliss
        { npc=134389, inst=1877, dungeonTele=1286828, name="Toxic Viper", g="35", spell=267027 },
        { npc=134602, inst=1877, dungeonTele=1286828, name="Shrouded Fang", g="2,4,5,8,9,10", spell=1308100 },
        { npc=135562, inst=1877, dungeonTele=1286828, name="Poisonous Viper", g="13,16,20,22,26", spell=1308148 },
        -- The Blinding Vale
        { npc=249756, inst=2859, dungeonTele=1286801, name="Potatoad Matriarch", g="70", spell=1250937 },
        -- Voidscar Arena
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1226031 },
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1263971 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1289258 },
        -- Maisara Caverns
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1246666 },
        -- Algeth'ar Academy
        { npc=197398, inst=2526, dungeonTele=393273, name="Hungry Lasher", g="20,21,23", spell=389033 },
        -- Windrunner Spire
        { npc=232067, inst=2805, dungeonTele=1254400, name="Creeping Spindleweb", g="12,14,15", spell=1216822 },
        { npc=232171, inst=2805, dungeonTele=1254400, name="Ardent Cutthroat", g="31,33,36,37,38,40,41", spell=473794 },
        -- Pit of Saron
        { npc=36658, inst=658, dungeonTele=1254555, spell=1262930 },
        { npc=252558, inst=658, dungeonTele=1254555, name="Rotting Ghoul", g="21,23,24,25,30,31,34,37,41,42,45,49,51,71,81", spell=1258459 },
    },
    [115750] = { -- Ослепляющий свет (22)
        -- Kings' Rest (ручное — в MPU этой связи нет)
        { npc=135192, inst=1762, dungeonTele=1286831, name="Animated Guardian", g="24,26", spell=270502 },
        -- Altar of Fangs
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1306385 },
        -- Murder Row
        { npc=236082, inst=2813, dungeonTele=1286809, name="Seductive Sayaad", g="10,25,34", spell=1201554 },
        { npc=236084, inst=2813, dungeonTele=1286809, name="Felonious Mage", g="2,5,6,10,14", spell=1216571 },
        -- Ruby Life Pools
        { npc=188067, inst=2521, dungeonTele=393256, name="Flashfrost Chillweaver", g="2,7,12,33", spell=372743 },
        { npc=190206, inst=2521, dungeonTele=393256, name="Ashseer Flamelasher", g="15,16,17,20,29,36,38,39", spell=385536 },
        -- Temple of Sethraliss
        { npc=134388, inst=1877, dungeonTele=1286828, name="A Knot of Snakes", g="34", spell=263958 },
        { npc=134600, inst=1877, dungeonTele=1286828, name="Sandswept Hunter", g="1,4,6,9,10,13,16,23", spell=1308113 },
        { npc=269227, inst=1877, dungeonTele=1286828, name="Temple Disruptor", g="37,38", spell=1303535 },
        -- The Blinding Vale
        { npc=250202, inst=2859, dungeonTele=1286801, name="Newborn Potadpole", g="31", spell=1250829 },
        -- Voidscar Arena
        { npc=244708, inst=2923, dungeonTele=1286804, name="Voidminder", g="46,48,54", spell=1310324 },
        { npc=249603, inst=2923, dungeonTele=1286804, name="Protective Turtle", g="14", spell=1250021 },
        -- Maisara Caverns
        { npc=248692, inst=2874, dungeonTele=1254559, name="Reanimated Warrior", g="59,63,65,66,69,71,72,73,76,78,82,85,87,88,89,93", spell=1257716 },
        -- Nexus-Point Xenas
        { npc=241644, inst=2915, dungeonTele=1254563, name="Corewright Arcanist", g="1,2,26,28,32,34,35,40,41", spell=1285445 },
        { npc=241645, inst=2915, dungeonTele=1254563, name="Hollowsoul Scrounger", g="1,2,10,12,15,16,17,21,22", spell=1252204 },
        -- Algeth'ar Academy
        { npc=196044, inst=2526, dungeonTele=393273, name="Unruly Textbook", g="7,8,9", spell=388392 },
        -- Windrunner Spire
        { npc=232147, inst=2805, dungeonTele=1254400, name="Lingering Marauder", g="49,54,56,60", spell=1216637 },
        { npc=236891, inst=2805, dungeonTele=1254400, spell=1216848 },
        { npc=238035, inst=2805, dungeonTele=1254400, spell=1216449 },
        -- Seat of the Triumvirate
        { npc=122413, inst=1753, dungeonTele=1254551, name="Ruthless Riftstalker", g="12,14,25,28,33,34,35,37,41,45", spell=1277339 },
        { npc=122827, inst=1753, dungeonTele=1254551, name="Umbral Tentacle", g="49", spell=1268733 },
        -- Skyreach
        { npc=76154, inst=1209, dungeonTele=1254557, name="Suntalon Tamer", g="21,22", spell=1254686 },
        -- Pit of Saron
        { npc=252707, inst=658, dungeonTele=1254555, spell=1258997 },
    },
    [469321] = { -- Праведная защита (23)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=261557, inst=2993, dungeonTele=1286812, name="High Evolutionist", g="18,19,20,21,24,26,28,30,31,32", spell=1289416 },
        { npc=263109, inst=2993, dungeonTele=1286812, name="Ula'tek's Chosen", g="34,38,39,43", spell=1307567 },
        -- Den of Nalorakk
        { npc=248710, inst=2825, dungeonTele=1286807, spell=1234846 },
        -- Kings' Rest
        { npc=135472, inst=1762, dungeonTele=1286831, spell=267273 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        { npc=270502, inst=1762, dungeonTele=1286831, name="Half-Finished Mummy", g="13,20", spell=267763 },
        -- Murder Row
        { npc=234649, inst=2813, dungeonTele=1286809, name="Zaen Bladesorrow", g="17", spell=474515 },
        { npc=236091, inst=2813, dungeonTele=1286809, name="Street Sneak", g="6,7,8", spell=1216590 },
        -- Temple of Sethraliss
        { npc=134389, inst=1877, dungeonTele=1286828, name="Toxic Viper", g="35", spell=267027 },
        { npc=134602, inst=1877, dungeonTele=1286828, name="Shrouded Fang", g="2,4,5,8,9,10", spell=1308100 },
        { npc=135562, inst=1877, dungeonTele=1286828, name="Poisonous Viper", g="13,16,20,22,26", spell=1308148 },
        -- The Blinding Vale
        { npc=249756, inst=2859, dungeonTele=1286801, name="Potatoad Matriarch", g="70", spell=1250937 },
        -- Voidscar Arena
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1226031 },
        { npc=239008, inst=2923, dungeonTele=1286804, name="Atroxus", g="35", spell=1263971 },
        { npc=263228, inst=2923, dungeonTele=1286804, name="Agitated Voidscythe", g="20,25,30,42,49,58", spell=1289258 },
        -- Maisara Caverns
        { npc=247572, inst=2874, dungeonTele=1254559, name="Nekraxx", g="58", spell=1246666 },
        -- Algeth'ar Academy
        { npc=197398, inst=2526, dungeonTele=393273, name="Hungry Lasher", g="20,21,23", spell=389033 },
        -- Windrunner Spire
        { npc=232067, inst=2805, dungeonTele=1254400, name="Creeping Spindleweb", g="12,14,15", spell=1216822 },
        { npc=232171, inst=2805, dungeonTele=1254400, name="Ardent Cutthroat", g="31,33,36,37,38,40,41", spell=473794 },
        -- Pit of Saron
        { npc=36658, inst=658, dungeonTele=1254555, spell=1262930 },
        { npc=252558, inst=658, dungeonTele=1254555, name="Rotting Ghoul", g="21,23,24,25,30,31,34,37,41,42,45,49,51,71,81", spell=1258459 },
    },
    [1044] = { -- Благословение свободы (28)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=259446, inst=2993, dungeonTele=1286812, name="The Writhing Coil", g="46", spell=1310358 },
        { npc=272271, inst=2993, dungeonTele=1286812, spell=1294569 },
        -- Den of Nalorakk
        { npc=241869, inst=2825, dungeonTele=1286807, name="Avatar of Determination", g="49,59", spell=1241464 },
        { npc=241872, inst=2825, dungeonTele=1286807, name="Frigid Mauler", g="44,46,47,52,57", spell=1309919 },
        { npc=261053, inst=2825, dungeonTele=1286807, spell=1263597 },
        -- Kings' Rest
        { npc=134174, inst=1762, dungeonTele=1286831, name="Risen Hexer", g="6", spell=1294815 },
        { npc=135239, inst=1762, dungeonTele=1286831, name="Spectral Shaman", g="22,24", spell=270499 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        -- Ruby Life Pools
        { npc=189893, inst=2521, dungeonTele=393256, name="Infused Whelp", spell=1305234 },
        -- The Blinding Vale
        { npc=244887, inst=2859, dungeonTele=1286801, name="Ikuzz the Light Hunter", spell=1236658 },
        { npc=245410, inst=2859, dungeonTele=1286801, name="Lasher", g="19,20,21,22,25,27,28,32,34,35,36,38,39,40,42,45,47,48,50,54,64,69,71,77,78", spell=1238084 },
        -- Voidscar Arena
        { npc=249590, inst=2923, dungeonTele=1286804, name="Angry Krolusk", g="17", spell=1249621 },
        { npc=255001, inst=2923, dungeonTele=1286804, name="Gravitic Orb", g="63", spell=1287450 },
        -- Magisters' Terrace
        { npc=231861, inst=2811, dungeonTele=1254572, name="Arcanotron Custos", spell=1214038 },
        { npc=231865, inst=2811, dungeonTele=1254572, name="Degentrius", spell=1269631 },
        -- Maisara Caverns
        { npc=1531, inst=2874, dungeonTele=1254559, spell=1254175 },
        { npc=242964, inst=2874, dungeonTele=1254559, name="Keen Headhunter", g="4,6,13,20,23,24,26,32,39,43,44,54,55,57", spell=1266381 },
        { npc=247570, inst=2874, dungeonTele=1254559, name="Muro'jin", g="58", spell=1260709 },
        { npc=249024, inst=2874, dungeonTele=1254559, name="Hollow Soulrender", g="68,77,81", spell=1271623 },
        { npc=253683, inst=2874, dungeonTele=1254559, name="Rokh'zal", g="62", spell=1259794 },
        -- Nexus-Point Xenas
        { npc=241647, inst=2915, dungeonTele=1254563, name="Flux Engineer", g="25,26,36,38,39", spell=249081 },
        -- Seat of the Triumvirate
        { npc=124171, inst=1753, dungeonTele=1254551, name="Merciless Subjugator", g="3,4,7,10,19,22,27", spell=1262509 },
        -- Pit of Saron
        { npc=36477, inst=658, dungeonTele=1254555, spell=1264186 },
        { npc=36494, inst=658, dungeonTele=1254555, spell=1261921 },
        { npc=252566, inst=658, dungeonTele=1254555, name="Rimebone Coldwraith", g="43,47,48,50,61,70,73,85", spell=1258437 },
        { npc=252707, inst=658, dungeonTele=1254555, spell=1258997 },
    },
    [10326] = { -- Изгнание зла (1)
        -- Seat of the Triumvirate
        { npc=122716, inst=1753, dungeonTele=1254551, name="Coalesced Void", g="11" },
    },
    [469304] = { -- Скакун свободы (28)
        -- Altar of Fangs
        { npc=259445, inst=2993, dungeonTele=1286812, name="Rav'i", g="45", spell=1296069 },
        { npc=259446, inst=2993, dungeonTele=1286812, name="The Writhing Coil", g="46", spell=1310358 },
        { npc=272271, inst=2993, dungeonTele=1286812, spell=1294569 },
        -- Den of Nalorakk
        { npc=241869, inst=2825, dungeonTele=1286807, name="Avatar of Determination", g="49,59", spell=1241464 },
        { npc=241872, inst=2825, dungeonTele=1286807, name="Frigid Mauler", g="44,46,47,52,57", spell=1309919 },
        { npc=261053, inst=2825, dungeonTele=1286807, spell=1263597 },
        -- Kings' Rest
        { npc=134174, inst=1762, dungeonTele=1286831, name="Risen Hexer", g="6", spell=1294815 },
        { npc=135239, inst=1762, dungeonTele=1286831, name="Spectral Shaman", g="22,24", spell=270499 },
        { npc=137486, inst=1762, dungeonTele=1286831, name="Queen Patlaa", g="11", spell=1306763 },
        { npc=137989, inst=1762, dungeonTele=1286831, name="Embalming Fluid", g="16,18", spell=271564 },
        -- Ruby Life Pools
        { npc=189893, inst=2521, dungeonTele=393256, name="Infused Whelp", spell=1305234 },
        -- The Blinding Vale
        { npc=244887, inst=2859, dungeonTele=1286801, name="Ikuzz the Light Hunter", spell=1236658 },
        { npc=245410, inst=2859, dungeonTele=1286801, name="Lasher", g="19,20,21,22,25,27,28,32,34,35,36,38,39,40,42,45,47,48,50,54,64,69,71,77,78", spell=1238084 },
        -- Voidscar Arena
        { npc=249590, inst=2923, dungeonTele=1286804, name="Angry Krolusk", g="17", spell=1249621 },
        { npc=255001, inst=2923, dungeonTele=1286804, name="Gravitic Orb", g="63", spell=1287450 },
        -- Magisters' Terrace
        { npc=231861, inst=2811, dungeonTele=1254572, name="Arcanotron Custos", spell=1214038 },
        { npc=231865, inst=2811, dungeonTele=1254572, name="Degentrius", spell=1269631 },
        -- Maisara Caverns
        { npc=1531, inst=2874, dungeonTele=1254559, spell=1254175 },
        { npc=242964, inst=2874, dungeonTele=1254559, name="Keen Headhunter", g="4,6,13,20,23,24,26,32,39,43,44,54,55,57", spell=1266381 },
        { npc=247570, inst=2874, dungeonTele=1254559, name="Muro'jin", g="58", spell=1260709 },
        { npc=249024, inst=2874, dungeonTele=1254559, name="Hollow Soulrender", g="68,77,81", spell=1271623 },
        { npc=253683, inst=2874, dungeonTele=1254559, name="Rokh'zal", g="62", spell=1259794 },
        -- Nexus-Point Xenas
        { npc=241647, inst=2915, dungeonTele=1254563, name="Flux Engineer", g="25,26,36,38,39", spell=249081 },
        -- Seat of the Triumvirate
        { npc=124171, inst=1753, dungeonTele=1254551, name="Merciless Subjugator", g="3,4,7,10,19,22,27", spell=1262509 },
        -- Pit of Saron
        { npc=36477, inst=658, dungeonTele=1254555, spell=1264186 },
        { npc=36494, inst=658, dungeonTele=1254555, spell=1261921 },
        { npc=252566, inst=658, dungeonTele=1254555, name="Rimebone Coldwraith", g="43,47,48,50,61,70,73,85", spell=1258437 },
        { npc=252707, inst=658, dungeonTele=1254555, spell=1258997 },
    },
}

-- -------------------------------------------------------------------------
-- Помощники API (12.1: спелл-функции в C_Spell)
-- -------------------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then return info.name end
    end
    return "spell:" .. tostring(id)
end

-- Иконка способности по SPELL_ID (игра сама даёт текстуру; имя не пишем руками).
-- ВАЖНО: возвращаем ТОЛЬКО number/string — иначе `"|T"..tex` падает и рвёт весь
-- ряд (в 12.x API текстуры может вернуть таблицу → окно оставалось пустым).
local function isTex(t) return type(t) == "number" or type(t) == "string" end
local function SpellTex(id)
    if not id then return nil end
    local t = ns.GetSpellTexture and ns.GetSpellTexture(id)
    if not isTex(t) and C_Spell then
        if C_Spell.GetSpellTexture then local x = C_Spell.GetSpellTexture(id); if isTex(x) then t = x end end
        if not isTex(t) and C_Spell.GetSpellInfo then           -- 12.x: иконка в struct
            local info = C_Spell.GetSpellInfo(id)
            if info and isTex(info.iconID) then t = info.iconID end
        end
    end
    if isTex(t) then return t end
    return nil
end

-- Локализованное имя НПЦ по npcID (из клиента игры). Строим unit-ссылку с
-- фиктивным GUID и читаем тултип — имя приходит на языке клиента. Кэшируем.
-- Фолбэк — англ. имя из MDT (передаём), если API недоступен.
local npcNameCache = {}
-- 12.0 Secret Values: значение, полученное под тэйнтом аддона, бывает «secret» —
-- сравнивать его (`== ""`) НЕЛЬЗЯ, бросает и рвёт выполнение. Детектим безопасно.
local function IsSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        if ok then return res and true or false end
    end
    -- фолбэк: пробное сравнение в pcall; упало → это секрет
    return not pcall(function() return v == "" end)
end
local function NpcName(id, fallback)
    if npcNameCache[id] then return npcNameCache[id] end
    local nm
    pcall(function()
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local data = C_TooltipInfo.GetHyperlink(("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
            if data and data.lines and data.lines[1] then nm = data.lines[1].leftText end
        end
    end)
    -- Секретную строку сравнивать/кэшировать нельзя, но ПОКАЗАТЬ можно (SetText её
    -- принимает) — отдаём как есть (локализованное имя), без кэша.
    if nm ~= nil and IsSecret(nm) then return nm end
    if not nm or nm == "" then nm = fallback or ("НПЦ " .. tostring(id)) end
    npcNameCache[id] = nm
    return nm
end

-- Иконка подземелья: по спеллу-порталу телепорта (как во вкладке «Подземелья»),
-- иначе по challengeMapID через GetMapUIInfo, иначе плейсхолдер-ключ.
local function DungeonTex(e)
    if e.dungeonTele and ns.GetSpellTexture then
        local t = ns.GetSpellTexture(e.dungeonTele)
        if t then return t end
    end
    if e.dungeon and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local _, _, _, tex = C_ChallengeMode.GetMapUIInfo(e.dungeon)
        if tex then return tex end
    end
    return 525134
end

-- Знает ли игрок этот талант/спелл. IsPlayerSpell учитывает таланты.
local function IsKnown(id)
    local known = false
    pcall(function()
        if IsPlayerSpell then known = IsPlayerSpell(id) and true or false end
    end)
    return known
end

local function IsPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end

-- Текущий спек-ID игрока (65 Holy / 66 Prot / 70 Ret).
local function CurrentSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if idx and GetSpecializationInfo then
        return (GetSpecializationInfo(idx))
    end
end

-- Токен расы игрока ("Dwarf"/"BloodElf"/"Scourge"/…), для гейта расовых.
local function PlayerRace()
    local r
    pcall(function() r = select(2, UnitRace("player")) end)
    return r
end

-- Показывать ли способность: расовая (`t.race`) — только своя раса; талант
-- (`t.spec`) — по спеку (nil = все спеки).
local function TalentVisible(t, specID)
    if t.race then return t.race == PlayerRace() end
    if not t.spec then return true end
    if not specID then return true end
    for _, s in ipairs(t.spec) do if s == specID then return true end end
    return false
end

-- Видимые таланты: фильтр по спеку + сортировка по алфавиту (по имени в клиенте).
-- Имена считаем ОДИН раз ДО сортировки — иначе `SpellName` может под-грузиться
-- между вызовами компаратора (сразу после /reload) и table.sort упадёт.
-- Текущее подземелье. ВАЖНО: ключи COUNTERS/MPU = `instanceID` из
-- GetInstanceInfo() (8-е значение), а НЕ EJ journalInstanceID. MPU так же
-- (Core.lua: instanceID = select(8, GetInstanceInfo())). Прежний EJ_GetInstanceForMap
-- давал другой ID → в дунже не совпадало и окно падало на фолбэк.
local function TR_CurrentInst()
    local id
    pcall(function()
        local _, itype, _, _, _, _, _, instanceID = GetInstanceInfo()
        if itype == "party" and instanceID and instanceID > 0 then id = instanceID end
    end)
    return id
end
-- Реальное текущее подземелье имеет ПРИОРИТЕТ над тест-фиксацией (иначе стухший
-- forcedInst из пикера перебивал бы настоящий дунж).
local function ActiveInst() return TR_CurrentInst() or TR.forcedInst end
local function HasCounterHere(id, inst)
    local list = COUNTERS[id]
    if not (list and inst) then return false end
    for _, e in ipairs(list) do if e.inst == inst then return true end end
    return false
end

local function VisibleTalents()
    local specID = CurrentSpecID()
    -- В подземелье/при фиксации показываем только таланты, у кого ЕСТЬ применения
    -- в этом дунже (пустые, напр. Изгнание зла в Гробнице, не грузим). Вне дунжа
    -- (active == nil) — весь список (общая проверка «изучено ли»).
    local active = ActiveInst()
    local list = {}
    local function consider(t)
        if TalentVisible(t, specID) and ((not active) or HasCounterHere(t.id, active)) then
            list[#list + 1] = { t = t, name = SpellName(t.id) or "" }
        end
    end
    for _, t in ipairs(PALADIN_TALENTS) do consider(t) end
    for _, t in ipairs(RACIALS)        do consider(t) end
    -- сравнение в pcall: если имя вдруг secret (12.0), `<` не должен ронять список
    table.sort(list, function(a, b)
        local ok, res = pcall(function() return a.name < b.name end)
        return ok and res or false
    end)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.t end
    return out
end

-- Сколько важных талантов НЕ изучено.
local function MissingCount()
    local n = 0
    for _, t in ipairs(PALADIN_TALENTS) do
        if not IsKnown(t.id) then n = n + 1 end
    end
    return n
end

-- -------------------------------------------------------------------------
-- Окно (ButtonFrameTemplate — классические текстуры Blizzard)
-- -------------------------------------------------------------------------
local win
local rows = {}

-- -------------------------------------------------------------------------
-- Память позиции окон (1.5.0) — по образцу окна «Телепорт»: свободно тащим
-- окно за заголовок, при отпускании запоминаем точку в ns.db.positions[key],
-- при показе восстанавливаем (фолбэк — центр экрана). EditMode здесь не
-- участвует — окна не зарегистрированы в редакторе, поэтому просто drag+save.
-- -------------------------------------------------------------------------
local function TR_SavePos(frame, key)
    if not (frame and ns.db and ns.db.positions) then return end
    local p, _, rp, x, y = frame:GetPoint()
    if p then ns.db.positions[key] = { p = p, rp = rp, x = x, y = y } end
end

local function TR_RestorePos(frame, key)
    if not frame then return end
    frame:ClearAllPoints()
    local pos = ns.db and ns.db.positions and ns.db.positions[key]
    if pos and pos.p then
        frame:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- Навесить drag-с-памятью на окно (заменяет прямые StartMoving/StopMovingOrSizing).
local function TR_HookDrag(frame, key)
    frame:SetScript("OnDragStart", function(s)
        if InCombatLockdown() then return end
        s:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        TR_SavePos(s, key)
    end)
end

local PAD    = 14      -- отступ от рамки инсета
local ROW_H  = 30      -- высота строки таланта
local ICON   = 24      -- размер иконки
local WIN_W  = 440

local function BuildWindow()
    if win then return win end

    win = CreateFrame("Frame", "RainonUITalentReminder", UIParent, "ButtonFrameTemplate")
    win:SetSize(WIN_W, 360)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    TR_HookDrag(win, "talentwin")
    TR_RestorePos(win, "talentwin")
    -- закрытие по Esc
    table.insert(UISpecialFrames, "RainonUITalentReminder")

    -- Заголовок. Сначала штатный SetTitle (чтобы не был пустым), затем
    -- насильно центрируем сам FontString по всей ширине рамки — иначе с
    -- портретом он уезжает вправо (у ButtonFrameTemplate текст цепляется за
    -- контейнер, а не за центр окна).
    if win.SetTitle then pcall(win.SetTitle, win, "Напоминание о талантах") end
    local titleFS = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
    if titleFS then
        titleFS:SetText("Напоминание о талантах")
        titleFS:ClearAllPoints()
        titleFS:SetPoint("TOP", win, "TOP", 0, -6)
        titleFS:SetJustifyH("CENTER")
    end

    -- Портрет: регион запоминаем, картинку ставим в Refresh (подземелье может
    -- смениться между показами).
    win.Portrait = win.PortraitContainer and win.PortraitContainer.portrait or win.portrait

    -- Тёмный бокс-инсет содержит ТОЛЬКО строки талантов. Пояснение — НАД ним
    -- (на фоне рамки), кнопка — в нижней полосе ПОД ним. Геометрию инсета и
    -- высоту окна пересчитываем в Refresh.
    local host = win.Inset or win

    -- Подзаголовок-пояснение (родитель — само окно, чтобы стоять НАД инсетом).
    local sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetJustifyH("LEFT")
    win.Sub = sub

    -- Строки талантов создаём ЛЕНИВО (пул) — список зависит от спека, поэтому
    -- собираем/наполняем в Refresh. Фабрика одной строки:
    win.NewRow = function()
        local row = {}
        row.icon = host:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetJustifyH("LEFT")

        -- маркер важности: текст «Нужно / Не надо / Опционально»
        row.status = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.status:SetJustifyH("RIGHT")

        -- название не должно заезжать на маркер: правый край — слева от маркера
        -- с небольшим зазором, без переноса (длинное — обрежется, не наложится).
        row.name:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
        row.name:SetWordWrap(false)

        row.hover = CreateFrame("Button", nil, host)
        row.hover:SetHeight(ICON)
        row.hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(function() GameTooltip:SetSpellByID(row.id) end)
            if not ok then GameTooltip:SetText(SpellName(row.id)) end
            if COUNTERS[row.id] then
                GameTooltip:AddLine("Клик — против кого использовать", 0.4, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        row.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.hover:SetScript("OnClick", function()
            if COUNTERS[row.id] then TR.ShowCounters(row.id) end
        end)
        return row
    end

    -- Кнопка «Открыть окно талантов» — родитель окно (стоит в нижней полосе).
    local openBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    openBtn:SetSize(WIN_W - PAD * 2 - 16, 24)
    openBtn:SetText("Открыть окно талантов")
    openBtn:SetScript("OnClick", function()
        if InCombatLockdown() then
            ns.Print("окно талантов нельзя открыть в бою.")
            return
        end
        local ok = pcall(function()
            if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
                PlayerSpellsUtil.ToggleClassTalentFrame()
            elseif PlayerSpellsMicroButton then
                PlayerSpellsMicroButton:Click()
            end
        end)
        if not ok then ns.Print("не удалось открыть окно талантов.") end
    end)
    win.OpenBtn = openBtn

    win:Hide()
    return win
end

-- Портрет: иконка текущего подземелья (Журнал Приключений по карте игрока),
-- иначе — эмблема класса паладина. Всё в pcall — API может отсутствовать.
-- Портал подземелья → spellID для КВАДРАТНОЙ иконки (ключ = instanceID GetInstanceInfo).
local DUNGEON_TELE = { [2993]=1286812, [2825]=1286807, [1762]=1286831, [2813]=1286809,
    [2521]=393256, [1877]=1286828, [2859]=1286801, [2923]=1286804, [2811]=1254572,
    [2874]=1254559, [2915]=1254563, [2526]=393273, [2805]=1254400, [1753]=1254551,
    [1209]=1254557, [658]=1254555 }

local function SetPortrait()
    local p = win and win.Portrait
    if not p then return end
    local done = false
    -- Иконка = КВАДРАТНАЯ иконка портала подземелья (как в окнах утилити), а не
    -- широкий EJ-баннер — тот растягивался в кружок и выглядел криво.
    local inst = TR.forcedInst or TR_CurrentInst()
    if inst and DUNGEON_TELE[inst] then
        pcall(function()
            local tex = SpellTex(DUNGEON_TELE[inst])
            if tex then
                p:SetTexture(tex)
                p:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                done = true
            end
        end)
    end
    if not done then
        -- эмблема класса паладина (классический атлас кружков классов)
        pcall(function()
            p:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS["PALADIN"]
            if c then p:SetTexCoord(c[1], c[2], c[3], c[4])
            else p:SetTexCoord(0, 0.25, 0.75, 1) end
        end)
    end
end

-- Раскладка (в пикселях от верха рамки):
local TITLEBAR   = 24   -- высота плашки заголовка (портрет живёт тут же)
local PORTRAIT_CLEAR = 64  -- левый отступ пояснения, чтобы не лезло под портрет
local BOTTOM_BAR = 40   -- нижняя полоса рамки под инсетом (там кнопка)
local INSET_TOPPAD = 12 -- отступ первой строки от верха инсета
local INSET_BOTPAD = 10 -- отступ низа инсета под последней строкой

-- Перерисовать содержимое под текущие таланты.
local function Refresh()
    if not win then return end
    local host = win.Inset or win

    SetPortrait()

    local paladin = IsPaladin()
    if paladin then
        win.Sub:SetText("Проверь ключевые таланты паладина перед подземельем:")
    else
        win.Sub:SetText(ns.C("FFD100", "Этот модуль рассчитан на паладина.") ..
            " Ниже — список для примера.")
    end

    -- Пояснение НАД инсетом (на фоне рамки). Слева отступаем на ширину портрета
    -- (PORTRAIT_CLEAR), чтобы текст не заходил под круглую иконку в шапке.
    local subTop = TITLEBAR + 6
    win.Sub:ClearAllPoints()
    win.Sub:SetPoint("TOPLEFT", win, "TOPLEFT", PORTRAIT_CLEAR, -subTop)
    win.Sub:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -subTop)
    local subH = math.ceil(win.Sub:GetStringHeight())

    -- Инсет: верх — сразу под пояснением, низ — оставляем нижнюю полосу.
    local insetTopY = -(subTop + subH + 8)
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, insetTopY)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, BOTTOM_BAR)
    end

    -- Видимые таланты (фильтр по спеку + сортировка по алфавиту).
    local visible = VisibleTalents()

    -- прячем весь пул, затем наполняем нужное число строк
    for _, r in ipairs(rows) do r.icon:Hide(); r.name:Hide(); r.status:Hide(); r.hover:Hide() end

    local y = -INSET_TOPPAD
    for i, t in ipairs(visible) do
        local row = rows[i]
        if not row then row = win.NewRow(); rows[i] = row end
        row.id = t.id
        row.mark = t.mark

        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        row.icon:SetTexture((ns.GetSpellTexture and ns.GetSpellTexture(t.id)) or 134400)
        row.icon:Show()

        row.name:SetText(SpellName(t.id))
        row.name:Show()

        row.hover:ClearAllPoints()
        row.hover:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        row.hover:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, y)
        -- подсветка для кликабельных (есть данные «против кого»); снятие — через
        -- скрытие текстуры (SetHighlightTexture(nil) недопустим).
        if COUNTERS[t.id] then
            row.hover:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            local h = row.hover:GetHighlightTexture(); if h then h:Show() end
        else
            local h = row.hover:GetHighlightTexture(); if h then h:Hide() end
        end
        row.hover:Show()

        -- Цвет НАЗВАНИЯ: изучен → зелёный, не изучен → красный.
        if paladin and IsKnown(t.id) then
            row.name:SetTextColor(0.25, 0.9, 0.25)
        else
            row.name:SetTextColor(1, 0.33, 0.33)
        end

        -- Маркер важности текстом: Нужно / Не надо / Опционально.
        row.status:ClearAllPoints()
        row.status:SetPoint("RIGHT", host, "RIGHT", -PAD, 0)
        row.status:SetPoint("TOP", row.icon, "TOP", 0, -4)
        if row.mark == "need" then
            row.status:SetText(ns.C("40D040", "Нужно"))
        elseif row.mark == "skip" then
            row.status:SetText(ns.C("FF5555", "Не надо"))
        elseif row.mark == "opt" then
            row.status:SetText(ns.C("AAAAAA", "Опционально"))
        else
            row.status:SetText("")
        end
        row.status:Show()
        y = y - ROW_H
    end

    -- Кнопка — по центру нижней полосы (гориз. центр рамки + центр по высоте
    -- полосы BOTTOM_BAR). Родитель — окно, поэтому цепляемся за его низ.
    win.OpenBtn:ClearAllPoints()
    win.OpenBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, (BOTTOM_BAR - 24) / 2)

    -- Высота окна: пояснение + инсет (строки видимых) + нижняя полоса.
    local insetInnerH = INSET_TOPPAD + #visible * ROW_H + INSET_BOTPAD
    win:SetHeight((subTop + subH + 8) + insetInnerH + BOTTOM_BAR)
end
TR.Refresh = Refresh

-- -------------------------------------------------------------------------
-- Окно «против кого использовать талант» (клик по таланту).
-- Строка = 3D-модель моба (SetCreature, как MDT) | способность | что делать.
-- -------------------------------------------------------------------------
local cwin, crows = nil, {}
local curCounters   -- текущий список (для агрегации по НПЦ в большом окне)
local C_ROW_H, C_MODEL, C_PAD, C_TITLE, C_BOT = 76, 60, 12, 26, 12

-- Текущее подземелье — определено выше как TR_CurrentInst.
local CurrentInstanceID = TR_CurrentInst
local PREVIEW_INST = 1762  -- фолбэк вне подземелья (King's Rest) для теста
local C_MAXROWS    = 25    -- страховочный предел числа строк в окне

function TR.ShowCounters(talentID)
    local all = COUNTERS[talentID]
    if not all then return end
    -- СТРОГО одно подземелье: тест-фиксация → текущее → фолбэк King's Rest.
    -- Не в этом дунже целей нет → показываем пустое окно с пометкой (НЕ прыгаем
    -- на другие подземелья — иначе талант «захватывал» бы всё подряд).
    local inst = CurrentInstanceID() or TR.forcedInst or PREVIEW_INST
    local data = {}
    for _, e in ipairs(all) do if e.inst == inst then data[#data + 1] = e end end
    if #data > C_MAXROWS then
        local t = {}; for i = 1, C_MAXROWS do t[i] = data[i] end; data = t
    end
    curCounters = data

    if not cwin then
        cwin = CreateFrame("Frame", "RainonUITalentCounters", UIParent, "ButtonFrameTemplate")
        cwin:SetFrameStrata("DIALOG"); cwin:SetToplevel(true)
        cwin:SetMovable(true); cwin:EnableMouse(true); cwin:RegisterForDrag("LeftButton")
        cwin:SetClampedToScreen(true)
        TR_HookDrag(cwin, "talentcounters")
        table.insert(UISpecialFrames, "RainonUITalentCounters")
        cwin.host = cwin.Inset or cwin
    end

    -- заголовок = имя таланта, по центру рамки
    if cwin.SetTitle then pcall(cwin.SetTitle, cwin, SpellName(talentID)) end
    local titleFS = (cwin.TitleContainer and cwin.TitleContainer.TitleText) or cwin.TitleText
    if titleFS then
        titleFS:SetText(SpellName(talentID))
        titleFS:ClearAllPoints(); titleFS:SetPoint("TOP", cwin, "TOP", 0, -6); titleFS:SetJustifyH("CENTER")
    end
    -- портрет = иконка таланта
    pcall(function()
        local p = cwin.PortraitContainer and cwin.PortraitContainer.portrait or cwin.portrait
        if p then p:SetTexture((ns.GetSpellTexture and ns.GetSpellTexture(talentID)) or 134400)
            p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    local host = cwin.host
    TR_RestorePos(cwin, "talentcounters")
    local rowsH = (#data > 0) and (10 + #data * C_ROW_H + 10) or 56
    cwin:SetSize(380, (C_TITLE + 8) + rowsH + C_BOT)
    if cwin.Inset then
        cwin.Inset:ClearAllPoints()
        cwin.Inset:SetPoint("TOPLEFT", cwin, "TOPLEFT", 4, -(C_TITLE + 8))
        cwin.Inset:SetPoint("BOTTOMRIGHT", cwin, "BOTTOMRIGHT", -6, C_BOT)
    end

    -- пометка «нет целей» (когда в активном подземелье талант никого не ловит)
    if not cwin.emptyFS then
        cwin.emptyFS = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cwin.emptyFS:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -20)
        cwin.emptyFS:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, -20)
        cwin.emptyFS:SetJustifyH("CENTER"); cwin.emptyFS:SetWordWrap(true)
    end
    if #data == 0 then
        cwin.emptyFS:SetText("В этом подземелье цели для этого таланта не отмечены.")
        cwin.emptyFS:Show()
    else
        cwin.emptyFS:Hide()
    end

    for _, r in ipairs(crows) do r:Hide() end
    local y = -8
    for i, e in ipairs(data) do
        local r = crows[i]
        if not r then
            r = CreateFrame("Frame", nil, host)
            r.model = CreateFrame("PlayerModel", nil, r)
            r.model:SetSize(C_MODEL, C_MODEL)
            r.model:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.model:EnableMouse(true)
            r.model:SetScript("OnMouseUp", function()
                if r._entry then TR.ShowNpc(r._entry) end
            end)
            r.model:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(r._entry and r._entry.name or "")
                GameTooltip:AddLine("Клик — крупно", 0.4, 0.8, 1)
                GameTooltip:Show()
            end)
            r.model:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Три строки: имя НПЦ | иконка+способность | текст.
            r.npcName = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.npcName:SetPoint("TOPLEFT", r.model, "TOPRIGHT", 12, -8)
            r.npcName:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.npcName:SetJustifyH("LEFT")
            r.ability = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.ability:SetPoint("TOPLEFT", r.npcName, "BOTTOMLEFT", 0, -5)
            r.ability:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.ability:SetJustifyH("LEFT")
            r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.note:SetPoint("TOPLEFT", r.ability, "BOTTOMLEFT", 0, -5)
            r.note:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.note:SetJustifyH("LEFT"); r.note:SetWordWrap(true)
            -- Игровой тултип способности при наведении (как в большом окне НПЦ):
            -- прозрачная кнопка поверх строки способности → SetSpellByID (1.5.0).
            r.abHit = CreateFrame("Button", nil, r)
            r.abHit:SetPoint("TOPLEFT", r.ability, "TOPLEFT", 0, 3)
            r.abHit:SetPoint("BOTTOMRIGHT", r.ability, "BOTTOMRIGHT", 0, -3)
            r.abHit:SetScript("OnEnter", function(self)
                local e = r._entry
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if e and e.spell then
                    local ok = pcall(function() GameTooltip:SetSpellByID(e.spell) end)
                    if not ok then GameTooltip:SetText(e.ability or (e.spell and SpellName(e.spell)) or "") end
                else
                    GameTooltip:SetText((e and e.ability) or "")
                end
                GameTooltip:Show()
            end)
            r.abHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
            crows[i] = r
        end
        r._entry = e
        r:SetHeight(C_ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", host, "TOPLEFT", C_PAD, y)
        r:SetPoint("TOPRIGHT", host, "TOPRIGHT", -C_PAD, y)
        pcall(function()
            r.model:SetCreature(e.npc)
            r.model:SetCamDistanceScale(1.4)
            r.model:SetPortraitZoom(0.35)
        end)
        r.npcName:SetText(NpcName(e.npc, e.name))
        local abName = e.ability or (e.spell and SpellName(e.spell)) or ""
        local tex = e.icon or SpellTex(e.spell)
        local ic = tex and ("|T" .. tex .. ":16:16:0:0:64:64:5:59:5:59|t ") or ""
        r.ability:SetText(ic .. ns.C("71D5FF", abName or ""))
        r.note:SetText(e.note or "")
        r:Show()
        y = y - C_ROW_H
    end

    cwin:Show(); cwin:Raise()
end

-- -------------------------------------------------------------------------
-- Окно-деталь одного моба (клик по 3D-модели). Ширина как «Напоминание о
-- талантах», но выше — крупная модель. Заголовок = имя НПЦ, ниже «G …»,
-- потом способность (игровой тултип) и текст.
-- -------------------------------------------------------------------------
local nwin, nabs = nil, {}
-- ФИКС. размер окна (как раньше — идеальный). Модель фикс., способности под ней.
local N_W, N_H, N_TITLE, N_BOT, N_MODEL, N_AB = 340, 470, 26, 12, 300, 52

function TR.ShowNpc(e)
    if not e then return end
    -- собрать ВСЕ способности этого НПЦ из текущего списка (может быть несколько)
    local list = {}
    if curCounters then
        for _, x in ipairs(curCounters) do if x.npc == e.npc then list[#list + 1] = x end end
    end
    if #list == 0 then list = { e } end

    if not nwin then
        nwin = CreateFrame("Frame", "RainonUITalentNpc", UIParent, "ButtonFrameTemplate")
        nwin:SetFrameStrata("FULLSCREEN_DIALOG"); nwin:SetToplevel(true)
        nwin:SetMovable(true); nwin:EnableMouse(true); nwin:RegisterForDrag("LeftButton")
        nwin:SetClampedToScreen(true)
        TR_HookDrag(nwin, "talentnpc")
        table.insert(UISpecialFrames, "RainonUITalentNpc")
        nwin.host = nwin.Inset or nwin
        -- строка «G …» под заголовком (на фоне рамки)
        nwin.GLine = nwin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nwin.GLine:SetPoint("TOP", nwin, "TOP", 0, -(N_TITLE + 2))
        nwin.GLine:SetJustifyH("CENTER")
        -- крупная модель сверху инсета
        nwin.model = CreateFrame("PlayerModel", nil, nwin.host)
        nwin.model:SetPoint("TOPLEFT", nwin.host, "TOPLEFT", 10, -10)
        nwin.model:SetPoint("TOPRIGHT", nwin.host, "TOPRIGHT", -10, -10)
        nwin.model:SetHeight(N_MODEL)
    end
    local host = nwin.host

    -- заголовок = имя НПЦ (локализованное из клиента)
    local title = NpcName(e.npc, e.name)
    if nwin.SetTitle then pcall(nwin.SetTitle, nwin, title) end
    local titleFS = (nwin.TitleContainer and nwin.TitleContainer.TitleText) or nwin.TitleText
    if titleFS then
        titleFS:SetText(title)
        titleFS:ClearAllPoints(); titleFS:SetPoint("TOP", nwin, "TOP", 0, -6); titleFS:SetJustifyH("CENTER")
    end
    -- портрет рамки = иконка ПОДЗЕМЕЛЬЯ (способностей может быть несколько)
    pcall(function()
        local p = nwin.PortraitContainer and nwin.PortraitContainer.portrait or nwin.portrait
        if p then p:SetTexture(DungeonTex(e)); p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    nwin.GLine:SetText(ns.C("FFD100", "G ") .. (e.g or "?"))
    pcall(function()
        nwin.model:SetCreature(e.npc)
        nwin.model:SetCamDistanceScale(1.0)
        nwin.model:SetPortraitZoom(0)
    end)

    -- список способностей под моделью (иконка+способность c игровым тултипом + текст)
    for _, ab in ipairs(nabs) do ab.frame:Hide() end
    local ay = -10
    for i, x in ipairs(list) do
        local ab = nabs[i]
        if not ab then
            ab = {}
            ab.frame = CreateFrame("Button", nil, host)
            ab.frame:SetHeight(N_AB)
            ab.text = ab.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            ab.text:SetPoint("TOPLEFT", 0, 0); ab.text:SetJustifyH("LEFT")
            ab.note = ab.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            ab.note:SetPoint("TOPLEFT", ab.text, "BOTTOMLEFT", 0, -5)
            ab.note:SetPoint("RIGHT", ab.frame, "RIGHT", 0, 0)
            ab.note:SetJustifyH("LEFT"); ab.note:SetWordWrap(true)
            ab.frame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if ab._spell then
                    local ok = pcall(function() GameTooltip:SetSpellByID(ab._spell) end)
                    if not ok then GameTooltip:SetText(ab._name or "") end
                else GameTooltip:SetText(ab._name or "") end
                GameTooltip:Show()
            end)
            ab.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            nabs[i] = ab
        end
        ab.frame:ClearAllPoints()
        ab.frame:SetPoint("TOPLEFT", nwin.model, "BOTTOMLEFT", 0, ay)
        ab.frame:SetPoint("RIGHT", host, "RIGHT", -10, 0)
        local abName = x.ability or (x.spell and SpellName(x.spell)) or ""
        local tex = x.icon or SpellTex(x.spell)
        local ic = tex and ("|T" .. tex .. ":18:18:0:0:64:64:5:59:5:59|t ") or ""
        ab.text:SetText(ic .. ns.C("71D5FF", abName or ""))
        ab.note:SetText(x.note or "")
        ab._spell = x.spell; ab._name = abName
        ab.frame:Show()
        ay = ay - N_AB
    end

    -- ФИКСИРОВАННЫЙ размер окна (не подгоняем под контент).
    nwin:SetSize(N_W, N_H)
    TR_RestorePos(nwin, "talentnpc")
    if nwin.Inset then
        nwin.Inset:ClearAllPoints()
        nwin.Inset:SetPoint("TOPLEFT", nwin, "TOPLEFT", 4, -(N_TITLE + 22))
        nwin.Inset:SetPoint("BOTTOMRIGHT", nwin, "BOTTOMRIGHT", -6, N_BOT)
    end
    nwin:Show(); nwin:Raise()
end

-- -------------------------------------------------------------------------
-- Публичный показ
-- -------------------------------------------------------------------------
function TR.Show()
    -- Окно проверки талантов — только для паладина (1.5.0).
    if not IsPaladin() then
        if ns and ns.Print then ns.Print("Напоминание о талантах доступно только паладину.") end
        return
    end
    BuildWindow()
    Refresh()
    win:Show()
    win:Raise()
end

-- Тест из панели «Тестер»: всегда показываем окно (даже если всё изучено).
function TR.Test()
    TR.Show()
end

function TR.Toggle()
    BuildWindow()
    if win:IsShown() then win:Hide() else TR.Show() end
end

-- -------------------------------------------------------------------------
-- РЕЙД-режим (RAID_NAME/RAID_BOSSES/CurrentRaidBoss/TR.ShowRaid) перенесён
-- в Архив (1.5.0). Данные боссов и код — в Архив/RaidTalentReminder.lua.
-- -------------------------------------------------------------------------

-- -------------------------------------------------------------------------
-- Автопоказ ТОЛЬКО по проверке готовности (Ready Check) — не спамит на каждом
-- экране загрузки. Показываем, если модуль включён галкой и мы паладин.
-- -------------------------------------------------------------------------
-- Заход/смена зоны сбрасывает тест-фиксацию, чтобы она не липла в реальный дунж.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() TR.forcedInst = nil end)

ns.RegisterEvent("READY_CHECK", function()
    if not (ns.db and ns.db.features and ns.db.features.talentReminder) then return end
    if not IsPaladin() then return end
    if InCombatLockdown() then return end
    TR.forcedInst = nil   -- реальная проверка готовности = реальное текущее подземелье
    -- ДВА условия: в инстансе И тип. Подземелье → окно талантов; рейд → окно
    -- босса. Иначе (мир/бг/сценарий) — НЕ показываем (был баг: висло в рейде).
    local inInstance, itype = IsInInstance()
    if not inInstance then return end
    if itype == "party" then
        TR.Show()
    end
    -- (рейд-ветка перенесена в Архив, 1.5.0)
end)

-- -------------------------------------------------------------------------
-- Слэш + кнопка тестера
-- -------------------------------------------------------------------------
SLASH_RAINONTALENT1 = "/rstalent"
SlashCmdList.RAINONTALENT = function() TR.Toggle() end

-- -------------------------------------------------------------------------
-- Тест: сетка подземелий 4×4. Кнопка = аббревиатура (тултип — полное имя).
-- Клик фиксирует подземелье (`TR.forcedInst`) и открывает окно напоминания;
-- дальше клик по таланту показывает мобов ИМЕННО этого подземелья.
-- «Авто (текущее)» сбрасывает фиксацию.
-- -------------------------------------------------------------------------
-- Полный сезонный пул — в COUNTERS (в аддоне все 16). В ТЕСТ-сетке только
-- актуальные 8 подземелий M+ (те, по которым ведём страницы MDT_TOOLTIP_DUNGEON).
local DUNGEON_INST = {2993, 2825, 1762, 2813, 2521, 1877, 2859, 2923}
local DUNGEON_ABBR = {
    [2993] = "АК",  [2825] = "БН",  [1762] = "ГК",  [2813] = "ЗД",
    [2521] = "РО",  [1877] = "ХС",  [2859] = "СД",  [2923] = "АШБ",
    [2811] = "ТМ",  [2874] = "ПМ",  [2915] = "НКс", [2526] = "АА",
    [2805] = "ШВ",  [1753] = "ПТ",  [1209] = "ЗН",  [658]  = "ЯС",
}
local DUNGEON_NAME = {
    [2993] = "Алтарь Клыков",     [2825] = "Берлога Налоракка",  [1762] = "Гробница Королей",
    [2813] = "Закоулок Душегубов",[2521] = "Рубиновые Омуты",    [1877] = "Храм Сетралисс",
    [2859] = "Слепящая Долина",   [2923] = "Арена Шрама Бездны", [2811] = "Терраса Магистров",
    [2874] = "Пещеры Майсары",    [2915] = "Нексус-Пункт Ксенас",[2526] = "Академия Алгетара",
    [2805] = "Шпиль Ветрокрылых", [1753] = "Престол Триумвирата",[1209] = "Занебесье",
    [658]  = "Яма Сарона",
}
-- Имена берём из таблицы (ID = instanceID из GetInstanceInfo, EJ_GetInstanceInfo
-- с ними не работает). Фолбэк — «инст <id>».
local function DungeonName(inst)
    return DUNGEON_NAME[inst] or ("инст " .. tostring(inst))
end

local pickwin
local P_COLS, P_BW, P_BH, P_GAP, P_PADX, P_TOP = 4, 74, 26, 6, 12, 30
function TR.ShowDungeonPicker()
    if not pickwin then
        pcall(function() if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_EncounterJournal") end end)
        pickwin = CreateFrame("Frame", "RainonUITalentDungeons", UIParent, "ButtonFrameTemplate")
        pickwin:SetFrameStrata("DIALOG"); pickwin:SetToplevel(true)
        pickwin:SetMovable(true); pickwin:EnableMouse(true); pickwin:RegisterForDrag("LeftButton")
        pickwin:SetClampedToScreen(true)
        TR_HookDrag(pickwin, "talentdungeons")
        table.insert(UISpecialFrames, "RainonUITalentDungeons")
        -- без портрета-кружка: чистый бокс
        if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, pickwin) end
        if pickwin.PortraitContainer then pickwin.PortraitContainer:Hide() end
        if pickwin.portrait then pickwin.portrait:Hide() end
        if pickwin.SetTitle then pcall(pickwin.SetTitle, pickwin, "Утилити: подземелья") end
        local tfs = (pickwin.TitleContainer and pickwin.TitleContainer.TitleText) or pickwin.TitleText
        if tfs then tfs:SetText("Утилити: подземелья"); tfs:ClearAllPoints()
            tfs:SetPoint("TOP", pickwin, "TOP", 0, -6); tfs:SetJustifyH("CENTER") end

        local host = pickwin.Inset or pickwin
        local list = {}
        for _, id in ipairs(DUNGEON_INST) do list[#list + 1] = { inst = id, name = DungeonName(id) } end
        table.sort(list, function(a, b) return a.name < b.name end)

        for i, d in ipairs(list) do
            local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
            b:SetSize(P_BW, P_BH)
            local col  = (i - 1) % P_COLS
            local rowi = math.floor((i - 1) / P_COLS)
            b:SetPoint("TOPLEFT", host, "TOPLEFT", P_PADX + col * (P_BW + P_GAP), -(10 + rowi * (P_BH + P_GAP)))
            b:SetText(DUNGEON_ABBR[d.inst] or string.sub(d.name, 1, 6))
            b._inst, b._name = d.inst, d.name
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self._name); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self) TR.forcedInst = self._inst; TR.Show() end)
        end

        local nrows = math.ceil(#list / P_COLS)
        local reset = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
        reset:SetSize(P_COLS * P_BW + (P_COLS - 1) * P_GAP, P_BH)
        reset:SetPoint("TOPLEFT", host, "TOPLEFT", P_PADX, -(10 + nrows * (P_BH + P_GAP) + 4))
        reset:SetText("Текущее подземелье")
        reset:SetScript("OnClick", function() TR.forcedInst = nil; TR.Show() end)

        local W = P_PADX * 2 + P_COLS * P_BW + (P_COLS - 1) * P_GAP + 8
        local H = P_TOP + 10 + nrows * (P_BH + P_GAP) + (P_BH + 10) + 14
        pickwin:SetSize(W, H)
        if pickwin.Inset then
            pickwin.Inset:ClearAllPoints()
            pickwin.Inset:SetPoint("TOPLEFT", pickwin, "TOPLEFT", 4, -P_TOP)
            pickwin.Inset:SetPoint("BOTTOMRIGHT", pickwin, "BOTTOMRIGHT", -6, 8)
        end
    end
    TR_RestorePos(pickwin, "talentdungeons")
    pickwin:Show(); pickwin:Raise()
end

-- -------------------------------------------------------------------------
-- Диагностика зоны/босса (/rszone, /rsraid, ENCOUNTER_START-диаг) — часть
-- рейд-режима, перенесена в Архив (1.5.0). См. Архив/RaidTalentReminder.lua.
-- -------------------------------------------------------------------------

-- Кнопка в панели «Тестер» (вызвать ДО первого открытия панели — она ленивая).
if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Подземелья", "Напоминание о талантах", TR.Test)
    ns.Tester.Add("Подземелья", "Утилити: выбор подземелья", TR.ShowDungeonPicker)
end
