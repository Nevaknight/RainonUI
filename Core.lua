-- =========================================================================
-- RainonUI / Core: база данных, события, общие помощники.
-- Адаптировано под WoW Midnight 12.1 (Interface 120100).
-- =========================================================================

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME

-- -------------------------------------------------------------------------
-- Значения по умолчанию
-- -------------------------------------------------------------------------
ns.defaults = {
    hide = {
        -- Рамка игрока
        holypower = false, essence = false, runeframe = false,
        warlockpower = false, stagger = false, monkbar = false,
        rogcombo = false, drucombo = false, arcanemage = false,
        combattext = true, totempanel = true, castbar = false,
        -- Индикатор личного ресурса
        holypowerbar = false, essencebar = false, runeframebar = false,
        warlockpowerbar = false, monkpersonalbar = false,
        rogcombobar = false, drucombobar = false, arcanemagebar = false,
        -- Разное
        targetspellbar = false, blizzdbm = true, talkinghead = false,
        actionbutton = false, zonebutton = false, expbar = false,
        bags = false, raidmanager = false, expansionbutton = false,
        durability = false, vehicle = false,
        -- Особые
        event = true, dailyquest = true, lootHide = true, ZoneHide = true,
        bossbanner = true,
    },
    tools = {
        -- Стикеры
        breaktimer = true, allready = true,
        feast = true, food = true, racechange = true,
        -- Тексты оповещений
        repair = true, cauldron = true, mail = true, healthstones = true,
        magetable = true, summon = true, mageeat = true,
        -- (consumables/delvemap — в Архиве, 30.07.2026)
        -- Оповещения
        leader = true, readybar = true, combatdrop = true,
        -- Иконки
        invispotion = true, engcloak = true,
        -- Профессии
        prof_phial = true, prof_essence = true,
        professions_enabled = false, -- мастер-выключатель всего по профессиям (по умолч. ВЫКЛ)
        phialQuality = 241312,      -- itemID выбранного флакона (для клика по иконке)
        shatterEssence = 236952,    -- itemID частицы для раскалывания
        -- Валюта
        curr_moxie = true,
        -- Прочее
        combattimer = true,
        -- Муверы окон Blizzard (галки во вкладке «Удобства» → «Общее»),
        -- по умолчанию ВЫКЛ — окна остаются на стандартных местах.
        bonusroll = false, keystone = false,
    },
    positions = {
        combattimer  = { x = 466, y = -226, scale = 1 },
        prof_phial   = { x = -50, y = 120,  scale = 1 },
        prof_essence = { x = 50,  y = 120,  scale = 1 },
        curr_moxie   = { x = 0,   y = 0,    scale = 1 },
        readybar     = { x = 0,   y = -180, scale = 1, width = 220 },
        bonusroll    = { x = 0,   y = -240, scale = 1 },
        keystone     = { x = 0,   y = 40,   scale = 1 },
        tankmark     = { x = 0,   y = 160,  scale = 1 },
        stickers     = { x = 0,   y = 300,  scale = 1 },
        dungeonannounce = { x = 0, y = -120, scale = 1 },
    },
    -- Мультиперсонажный ростер для окна знаний/зарядов (аккаунтный).
    -- [GUID] = { name, realm, classFile, lastUpdate, profs = {...},
    --            abundant = bool, charges = { [recipeID] = {cur, max} } }
    roster = {},
    -- Отдельные фичи (кнопка reload, иконка паладина, окно телепорта)
    features = {
        reloadMenuButton = true, -- кнопка «Перезагрузить интерфейс» в ESC-меню
        paladinWeapon = true,    -- иконка освящения оружия для паладина
        teleportPrompt = true,   -- окно телепорта при вступлении в группу ЛФГ
        teleportScale = 1.0,
        tankMark = false,        -- авто-метка танка при проверке готовности (только 5-ки)
        tankMarkIcon = 8,        -- индекс метки цели (8 = череп, 7 = крест, …)
        -- Трактат: подпись в подсказке + пиксельное свечение (раздельно)
        treatiseTooltip = true,
        treatiseGlow = true,
        -- Звук при предложении воскрешения (окно «Воскреснуть»)
        resurrectSoundOn = false,   -- звук, когда ТЕБЯ воскрешают (окно «Воскреснуть»)
        resurrectSound = nil,       -- ИМЯ звука из LibSharedMedia (nil → дефолт)
        resCastSoundOn = false,     -- звук, когда КТО-ТО в группе/рейде кастует воскрешение
        resCastSound = nil,         -- ИМЯ звука из LibSharedMedia (nil → дефолт)
        -- Звук при завершении события «Сбор изобилия» (дан-дан). 384 = плашка
        -- «ЗАВЕРШЕНО / Событие завершено!». Рядом других событий нет, точного ID хватает.
        abundanceSoundOn = true,     -- играть звук на завершении изобилия
        abundanceSound = nil,        -- ИМЯ звука из LibSharedMedia (nil → дефолт)
        abundanceEventToastID = 384, -- eventToastID плашки завершения
        abundanceWidgetSet = nil,    -- uiWidgetSetID (запасной идентификатор)
        -- «Подземелья»: анонс типа урона танку по таймерам BigWigs.
        -- Виджет (иконка танка | тип урона | цифры) появляется за 5 сек до удара.
        dungeonAnnounceOn      = true,  -- показывать виджет-анонс (галка «ВКЛ анонс»)
        dungeonAnnounceOtherRoles = false, -- анонс и для хила/дд (выкл = только танк)
        dungeonAnnounceSoundOn = true,  -- играть звук на анонсе (галка «Звук анонса»)
        dungeonAnnounceSound   = nil,   -- ИМЯ звука LSM (nil → «RainonUI: Босс (Alice)»)
        -- Интеграция с CraftSim (нужны CraftSim и Auctionator)
        craftAHButton = true,    -- кнопка «список покупок CraftSim» на аукционе
        -- Режим «крестики скрытия»: на скрываемых элементах UI показываются
        -- крестики; клик по крестику включает галку скрытия и прячет элемент.
        hideSetupMode = false,
        -- «Подземелья»: напоминание о талантах (ТЕСТОВЫЙ модуль, только паладин).
        -- Вкл — при входе в подземелье покажем окно с важными талантами, если
        -- чего-то не хватает. По умолчанию ВЫКЛ.
        talentReminder = false,
        -- «Подземелья»: опрос ключей группы (ТЕСТОВЫЙ модуль). Вкл — окно опроса
        -- авто-открывается, когда кто-то в группе запускает «Опрос». По умолч. ВЫКЛ.
        keystonePoll = true,
        -- «Подземелья»: напоминание «сменить ключ?» + окно реролла (ТЕСТОВЫЙ).
        -- По умолчанию ВЫКЛ. Голоса реролла — в rerollMarks (создаётся лениво).
        keyReroll = false,
    },
    -- Настройки окна знаний/зарядов
    knowledge = {
        locked = false,
        scale = 1.0,
        rows = 20,          -- строк в окне (10 или 20)
        sort = "name",      -- "name" или "conc"
        autoOpen = false,   -- открывать/закрывать вместе с окном профессии
        minimapAngle = 205,
        hideMinimap = false,
        columns = {
            prof1 = true, prof2 = true, abundant = true,
            weekly = true, treatise = true, darkmoon = true,
            herbs = true, wondrous = true,
        },
    },
}

ns.db = nil -- ссылки появятся после ADDON_LOADED

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.InitDB()
    RainonUIDB = RainonUIDB or {}
    local db = RainonUIDB
    -- миграция настроек со старого имени аддона (Rainon Scripts):
    -- если старая папка RainonScripts ещё установлена, забираем данные
    local oldDB = _G.RainonScriptsDB
    if db.hide == nil and type(oldDB) == "table" and oldDB.hide then
        for _, section in ipairs({ "hide", "tools", "positions" }) do
            if type(oldDB[section]) == "table" then
                db[section] = {}
                for k, v in pairs(oldDB[section]) do
                    if type(v) == "table" then
                        db[section][k] = { x = v.x, y = v.y, scale = v.scale }
                    else
                        db[section][k] = v
                    end
                end
            end
        end
    end
    -- миграция с версии 1.x (плоские ключи)
    if db.hide == nil and db.totempanel ~= nil then
        local old = {}
        for k, v in pairs(db) do old[k] = v; db[k] = nil end
        db.hide = old
    end
    CopyDefaults(ns.defaults, db)
    ns.db = db
end

-- Мастер-выключатель всего, что связано с профессиями (баффы крафта,
-- кнопка миникарты, авто-возможности окна знаний/зарядов).
function ns.ProfEnabled()
    return not (ns.db and ns.db.tools and ns.db.tools.professions_enabled == false)
end

-- -------------------------------------------------------------------------
-- Центральная шина событий
-- -------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}   -- [event] = { fn, fn, ... }

function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        -- pcall: в Midnight часть аргументов событий может приходить как
        -- Secret Values — любая попытка сравнения из аддона даёт ошибку.
        -- Ловим её тихо, чтобы не сыпать луа-ошибками в бою.
        local ok, err = pcall(list[i], ...)
        if not ok and ns.debug then
            print("|cFFFF3333RainonUI:|r", event, err)
        end
    end
end)

-- Внутренние сообщения (аналог WeakAuras.ScanEvents)
local msgHandlers = {}
function ns.RegisterMessage(msg, fn)
    msgHandlers[msg] = msgHandlers[msg] or {}
    table.insert(msgHandlers[msg], fn)
end
function ns.SendMessage(msg, ...)
    local list = msgHandlers[msg]
    if not list then return end
    for i = 1, #list do pcall(list[i], ...) end
end

-- -------------------------------------------------------------------------
-- Помощники
-- -------------------------------------------------------------------------
ns.FONT = STANDARD_TEXT_FONT

function ns.C(hex, text) return "|cFF" .. hex .. text .. "|r" end

function ns.Print(text)
    print("|cFF33937FRainonUI:|r " .. text)
end

-- Чекбокс в СОВРЕМЕННОМ стиле Blizzard (как в Настройках 12.0). Если шаблон
-- недоступен на клиенте — тихо откатываемся на классический UICheckButtonTemplate,
-- ничего не ломая. Гарантируем поле `.Text` (наш код местами на него рассчитывает,
-- а у нового шаблона своей подписи может не быть).
function ns.MakeCheckButton(parent)
    local cb
    local ok, made = pcall(CreateFrame, "CheckButton", nil, parent, "WowStyle1CheckButtonTemplate")
    if ok and made then cb = made else cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate") end
    if not cb.Text then
        cb.Text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cb.Text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    return cb
end

-- Проигрывание звука из файла (кастомная медиатека пользователя).
-- Если файла нет — тихо пропускаем.
function ns.PlayFile(path)
    if path and path ~= "" then
        pcall(PlaySoundFile, path, "Master")
    end
end

-- Сообщение в чат группы. В Midnight аддонам запрещено писать в чат
-- в инстансах — там выводим только себе на экран.
function ns.Announce(msg)
    local inInstance = IsInInstance()
    if not inInstance and IsInGroup() then
        local channel = IsInRaid() and "RAID" or "PARTY"
        pcall(SendChatMessage, msg, channel)
    else
        ns.Print(msg)
    end
end

-- Установка иконки с фолбэком (кастомные tga могут отсутствовать)
function ns.SetIcon(texture, icon)
    texture:SetTexture(134400) -- знак вопроса — фолбэк
    if icon then texture:SetTexture(icon) end
end

function ns.FormatSeconds(sec)
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
    end
    return string.format("%d", math.ceil(sec))
end

-- Совместимость API (12.0: многое переехало в C_* неймспейсы)
ns.GetItemCount = function(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) or 0 end
    if GetItemCount then return GetItemCount(itemID) or 0 end
    return 0
end

ns.GetSpellCooldown = function(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then return info.startTime, info.duration, info.isEnabled end
        return nil
    end
    if GetSpellCooldown then return GetSpellCooldown(spellID) end
    return nil
end

ns.GetSpellTexture = function(spellID)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
    if GetSpellTexture then return GetSpellTexture(spellID) end
    return nil
end

-- Аура игрока по spellID → таблица данных или nil
ns.GetPlayerAura = function(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end
    return nil
end

-- Поиск ауры по списку spellID на юните (медленный путь, с защитой)
ns.UnitHasAnyAura = function(unit, idSet)
    local found
    local ok = pcall(function()
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            local i = 1
            while true do
                local data = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
                if not data then break end
                if idSet[data.spellId] then found = data; return end
                i = i + 1
            end
        end
    end)
    if ok then return found end
    return nil
end

-- Перебор юнитов группы (включая игрока)
function ns.IterateGroup()
    local n = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local i = 0
    return function()
        i = i + 1
        if i == 1 and not isRaid then return "player" end
        if isRaid then
            if i <= n then return "raid" .. i end
        else
            if i <= n then return "party" .. (i - 1) end
        end
        return nil
    end
end

-- -------------------------------------------------------------------------
-- Слежение за кастами группы (замена CLEU-триггеров WeakAuras).
-- В Midnight 12.0 COMBAT_LOG_EVENT аддонам недоступен, а spellID ЧУЖОГО
-- каста в UNIT_SPELLCAST_SUCCEEDED — секретное значение (по нему нельзя
-- искать в таблице), поэтому старый способ «слушать юнитов группы» умер.
-- Решение (как у Northern Sky RT, но своим каналом, без внешних библиотек):
-- каждый ловит ТОЛЬКО свой каст (для 'player' spellID не секретный) и тихо
-- рассылает его группе аддон-сообщением; остальные с RainonUI ловят и
-- показывают стикер. Игрокам без аддона ничего не приходит, в чат — тоже.
-- -------------------------------------------------------------------------
local castWatchers = {}  -- [spellID] = { fn, ... }

function ns.WatchGroupCast(spellIDs, fn)
    for _, id in ipairs(spellIDs) do
        id = tonumber(id)
        if id then
            castWatchers[id] = castWatchers[id] or {}
            table.insert(castWatchers[id], fn)
        end
    end
end

local COMM_PREFIX = "RainonUI"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
end

local function FireWatchers(spellID)
    local list = castWatchers[spellID]
    if not list then return end
    for i = 1, #list do pcall(list[i], spellID) end
end

-- Свой каст → рассылаем группе (для 'player' spellID не секретный).
ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    spellID = tonumber(spellID)
    if not spellID or not castWatchers[spellID] then return end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then return end
    pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, tostring(spellID), channel)
end)

-- Приём от других игроков с RainonUI. Канал RAID/PARTY — приходит только от
-- своей группы. Своё же эхо отсекаем, чтобы не показывать себе свой каст.
ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= COMM_PREFIX then return end
    if sender and Ambiguate(sender, "short") == UnitName("player") then return end
    local spellID = tonumber(msg)
    if spellID then FireWatchers(spellID) end
end)

-- -------------------------------------------------------------------------
-- Старт
-- -------------------------------------------------------------------------
ns.RegisterEvent("ADDON_LOADED", function(name)
    if name == ADDON_NAME then
        ns.InitDB()
        ns.SendMessage("RAINON_DB_READY")
    elseif ns.db and type(name) == "string"
        and (name:find("^Blizzard_")           -- ленивые модули Blizzard
             or name:find("DBM") or name:find("BigWigs")) then
        -- Повторно применяем скрытие/хуки ТОЛЬКО когда догружаются модули
        -- Blizzard (в них лениво создаются наши целевые фреймы — профессии,
        -- эпохальный ключ, бонусный бросок) или босс-моды (для таймера
        -- перерыва). На ПОСТОРОННИЕ аддоны (WeeklyKnowledge и любые другие)
        -- мы не реагируем и в них не лезем.
        ns.SendMessage("RAINON_REAPPLY")
    end
end)

local greeted = false
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ns.SendMessage("RAINON_REAPPLY")
    if not greeted then
        greeted = true
        ns.Print("загружен. Настройки: " .. ns.C("FFFF00", "/rainon") ..
            " или " .. ns.C("FFFF00", "/rs"))
    end
end)