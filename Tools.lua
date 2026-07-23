-- =========================================================================
-- RainonUI / Tools: порт WeakAuras «РЕЙНОН -- ИГРОВЫЕ ИНСТРУМЕНТЫ».
--
-- Отличия от WA, вынужденные ограничениями Midnight (12.0):
--   * COMBAT_LOG_EVENT недоступен аддонам — триггеры «Spell Cast Succeeded»
--     и «Combat Log» заменены на UNIT_SPELLCAST_* по юнитам группы;
--   * в инстансах аддонам нельзя писать в чат — авто-сообщения («Я не
--     готов!», «Invis activated») там выводятся только себе на экран;
--   * данные чужих юнитов в бою могут быть «секретными» — все обработчики
--     обёрнуты в pcall и тихо пропускают недоступное;
--   * функции, которым нужны боевые данные чужих юнитов («Баттл рес»,
--     «Не вставай!», «Воскрешение союзников»), в Midnight не работают
--     и по решению пользователя УДАЛЕНЫ из аддона.
--
-- Медиа лежит внутри аддона: Media\Icons (стикеры) и Media\Sounds
-- (звуки); если файла нет — иконка-фолбэк и тишина.
-- =========================================================================

local _, ns = ...

-- Медиа внутри аддона: папки Media\Icons и Media\Sounds.
-- Стикеры — заглушки *.tga (256x256): замена файла с тем же именем
-- меняет оформление без правки кода. Звуки кладутся в Media\Sounds
-- с именами из таблицы ниже; нет файла — тишина без ошибок.
local MYSOUND = "Interface\\AddOns\\RainonUI\\Media\\Sounds\\"
local MYICON  = "Interface\\AddOns\\RainonUI\\Media\\Icons\\"

local SOUND = {
    allready     = MYSOUND .. "allready.ogg",     -- «Все готовы»
    breaktimer   = MYSOUND .. "break.ogg",        -- «Перерыв» (свой звук!)
    feast        = MYSOUND .. "feast.ogg",        -- сытная еда
    food         = MYSOUND .. "food.ogg",         -- обычная еда
    racechange   = MYSOUND .. "racechange.ogg",   -- смена расы
    repair       = MYSOUND .. "repair.ogg",       -- ремонт
    cauldron     = MYSOUND .. "cauldron.ogg",     -- котёл
    mail         = MYSOUND .. "mail.ogg",         -- почта
    healthstones = MYSOUND .. "healthstones.ogg", -- камни здоровья
    magetable    = MYSOUND .. "magetable.ogg",    -- стол мага
    summon       = MYSOUND .. "summon.ogg",       -- шкаф сумона
    leader       = MYSOUND .. "leader.ogg",       -- лидер группы
}

local function enabled(key)
    return ns.db and ns.db.tools and ns.db.tools[key]
end

local registry = {}  -- [key] = display (для скрытия при выключении галочки)

-- =========================================================================
-- Дисплеи
-- =========================================================================

local UPDATE_PERIOD = 0.1

-- Общий тикер обновления таймеров на активных дисплеях
local ticking = {}
local tickerFrame = CreateFrame("Frame")
tickerFrame:Hide()
local elapsedAcc = 0
tickerFrame:SetScript("OnUpdate", function(_, elapsed)
    elapsedAcc = elapsedAcc + elapsed
    if elapsedAcc < UPDATE_PERIOD then return end
    elapsedAcc = 0
    local any = false
    for item in pairs(ticking) do
        any = true
        item:UpdateTimer()
    end
    if not any then tickerFrame:Hide() end
end)

local function StartTicking(item)
    ticking[item] = true
    tickerFrame:Show()
end
local function StopTicking(item)
    ticking[item] = nil
end

-- ---- Примесь общего поведения элемента --------------------------------
local ItemMixin = {}

function ItemMixin:UpdateTimer()
    local remain
    if self.expires then
        remain = self.expires - GetTime()
        if remain <= 0 then
            self:Deactivate()
            return
        end
    end
    if self.Timer then
        self.Timer:SetText(remain and ns.FormatSeconds(remain) or "")
    end
end

function ItemMixin:Activate(duration)
    self.active = true
    self.expires = duration and (GetTime() + duration) or nil
    if self.expires or self.Timer then StartTicking(self) end
    if self.row then self.row:Layout() else self:Show() end
    self:UpdateTimer()
end

function ItemMixin:Deactivate()
    self.active = false
    self.expires = nil
    StopTicking(self)
    if self.row then self.row:Layout() else self:Hide() end
end

local function Mix(frame)
    for k, v in pairs(ItemMixin) do frame[k] = v end
    return frame
end

local function MakeText(parent, size, color, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.FONT, size, outline or "OUTLINE")
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    return fs
end

-- ---- Ряды (аналог dynamic group WA) ------------------------------------
local function CreateRow(opts)
    local row = CreateFrame("Frame", nil, UIParent)
    row:SetSize(1, 1)
    row:SetPoint(opts.selfPoint or "CENTER", UIParent, "CENTER", opts.x or 0, opts.y or 0)
    row:SetFrameStrata(opts.strata or "MEDIUM")
    row.items = {}
    row.spacing = opts.spacing or 2
    row.vertical = opts.vertical

    function row:Layout()
        local shown = {}
        for _, item in ipairs(self.items) do
            if item.active then table.insert(shown, item) end
        end
        local total = 0
        for _, item in ipairs(shown) do
            total = total + (self.vertical and item.cellH or item.cellW)
        end
        total = total + math.max(0, #shown - 1) * self.spacing
        local offset = 0
        for _, item in ipairs(shown) do
            item:ClearAllPoints()
            if self.vertical then
                item:SetPoint("TOP", self, "TOP", 0, -offset)
                offset = offset + item.cellH + self.spacing
            else
                item:SetPoint("LEFT", self, "LEFT", offset - total / 2, 0)
                offset = offset + item.cellW + self.spacing
            end
        end
        for _, item in ipairs(self.items) do
            item:SetShown(item.active)
        end
    end
    return row
end

-- ---- Стикер: большая иконка + подпись + таймер --------------------------
local function CreateSticker(row, iconPath, label, size)
    size = size or 200
    local f = Mix(CreateFrame("Frame", nil, row))
    f:SetSize(size, size + 30)
    f.cellW, f.cellH = size, size + 30
    f.row = row
    f:Hide()

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetSize(size, size)
    f.Icon:SetPoint("TOP")
    ns.SetIcon(f.Icon, iconPath)

    f.Label = MakeText(f, 24)
    f.Label:SetPoint("TOP", f.Icon, "BOTTOM", 0, -2)
    f.Label:SetText(label or "")

    f.Timer = MakeText(f, 40)
    f.Timer:SetPoint("CENTER", f.Icon, "CENTER")

    table.insert(row.items, f)
    return f
end

-- ---- Строка текста в вертикальном списке --------------------------------
local function CreateTextEntry(row, text, size, color)
    size = size or 24
    local f = Mix(CreateFrame("Frame", nil, row))
    f.row = row
    f:Hide()
    f.Label = MakeText(f, size, color)
    f.Label:SetPoint("CENTER")
    f.Label:SetText(text)
    f:SetSize(math.max(60, f.Label:GetStringWidth() + 10), size + 6)
    f.cellW, f.cellH = f:GetWidth(), f:GetHeight()
    f.SetTextValue = function(self, t)
        self.Label:SetText(t)
        self.cellW = math.max(60, self.Label:GetStringWidth() + 10)
    end
    table.insert(row.items, f)
    return f
end

-- ---- Одиночная иконка в фиксированной позиции ---------------------------
local function CreateIconDisplay(opts)
    local f = Mix(CreateFrame("Frame", nil, UIParent))
    local size = opts.size or 64
    f:SetSize(size, size)
    f:SetPoint(opts.selfPoint or "CENTER", UIParent, "CENTER", opts.x or 0, opts.y or 0)
    f:SetFrameStrata(opts.strata or "MEDIUM")
    f:Hide()

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.SetIcon(f.Icon, opts.icon)

    if opts.label then
        f.Label = MakeText(f, opts.labelSize or 16)
        f.Label:SetPoint("TOP", f, "BOTTOM", 0, -2)
        f.Label:SetText(opts.label)
    end
    if opts.timer ~= false then
        f.Timer = MakeText(f, opts.timerSize or 16, { 1, 0.996, 0 })
        f.Timer:SetPoint("CENTER")
    end
    return f
end

-- ---- Одиночный текст в фиксированной позиции ----------------------------
local function CreateTextDisplay(opts)
    local f = Mix(CreateFrame("Frame", nil, UIParent))
    f:SetSize(10, (opts.size or 24) + 6)
    f:SetPoint(opts.selfPoint or "BOTTOM", UIParent, "CENTER", opts.x or 0, opts.y or 0)
    f:SetFrameStrata(opts.strata or "HIGH")
    f:Hide()
    f.Label = MakeText(f, opts.size or 24, opts.color)
    f.Label:SetPoint(opts.selfPoint or "BOTTOM")
    f.Label:SetText(opts.text or "")
    f.SetTextValue = function(self, t) self.Label:SetText(t) end
    return f
end

-- =========================================================================
-- Контейнеры (позиции из WeakAuras)
-- =========================================================================
local stickerRow  = CreateRow({ x = 0, y = 300, spacing = 2 })            -- ОПОВЕЩЕНИЯ - СТИКЕРЫ
local textStack   = CreateRow({ x = 0, y = 80, spacing = 10,
                                vertical = true, selfPoint = "TOP" })      -- ОПОВЕЩЕНИЯ - ТЕКСТ
local consumRow   = CreateRow({ x = 0, y = 430, spacing = 4 })             -- Памятка для расходников

-- =========================================================================
-- СТИКЕРЫ
-- =========================================================================
local stBreak    = CreateSticker(stickerRow, MYICON .. "break.tga",      "ПЕРЕРЫВ")
local stAllReady = CreateSticker(stickerRow, MYICON .. "allready.tga",   "ВСЕ ГОТОВЫ")
local stFeast    = CreateSticker(stickerRow, MYICON .. "feast.tga",      "СЫТНАЯ ЕДА")
local stFood     = CreateSticker(stickerRow, MYICON .. "food.tga",       "ОБЫЧНАЯ ЕДА")
local stRace     = CreateSticker(stickerRow, MYICON .. "racechange.tga", "СМЕНА РАСЫ")

registry.breaktimer = stBreak
registry.allready   = stAllReady
registry.feast      = stFeast
registry.food       = stFood
registry.racechange = stRace

-- Еда / сытная еда / смена расы: касты в группе
local function CastSticker(key, sticker, spells, duration, sound)
    ns.WatchGroupCast(spells, function()
        if not enabled(key) then return end
        sticker:Activate(duration)
        ns.PlayFile(sound)
    end)
end

CastSticker("feast",      stFeast, { 462212, 462213, 462211, 457487 }, 10,
            SOUND.feast)
CastSticker("food",       stFood,  { 457285, 457283, 457302, 455960 }, 7,
            SOUND.food)
CastSticker("racechange", stRace,  { 384911 }, 7,
            SOUND.racechange)

-- Полоса проверки готовности в стиле кастбара Blizzard 12.0
-- (атласы ui-castingbar-*: тёмная подложка, жёлтая заливка, рамка,
-- слева иконка проверки готовности). Позиция/размер — через мувер.
local readyBar = CreateFrame("StatusBar", nil, UIParent)
readyBar:SetSize(220, 18)
readyBar:SetFrameStrata("HIGH")
readyBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
readyBar:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")
readyBar.bg = readyBar:CreateTexture(nil, "BACKGROUND")
readyBar.bg:SetAllPoints()
readyBar.bg:SetAtlas("ui-castingbar-background")
readyBar.FrameTex = readyBar:CreateTexture(nil, "OVERLAY")
readyBar.FrameTex:SetAtlas("ui-castingbar-frame")
readyBar.FrameTex:SetPoint("TOPLEFT", -4, 4)
readyBar.FrameTex:SetPoint("BOTTOMRIGHT", 4, -4)
readyBar.ReadyIcon = readyBar:CreateTexture(nil, "OVERLAY")
readyBar.ReadyIcon:SetSize(24, 24)
readyBar.ReadyIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
readyBar.ReadyIcon:SetPoint("RIGHT", readyBar, "LEFT", -6, 0)
readyBar.Text = MakeText(readyBar, 13)
readyBar.Text:SetPoint("CENTER")
readyBar:Hide()
registry.readybar = Mix(readyBar)

local allReadyFired = false
local readyCheckStartedAt = 0  -- «Все готовы» валидно только рядом с
                               -- настоящей проверкой готовности

ns.RegisterEvent("READY_CHECK", function(initiator, duration)
    allReadyFired = false
    readyCheckStartedAt = GetTime()
    duration = tonumber(duration) or 35
    stAllReady:Deactivate()

    if enabled("readybar") then
        readyBar:SetMinMaxValues(0, duration)
        readyBar.finish = GetTime() + duration
        readyBar:SetScript("OnUpdate", function(self)
            local remain = self.finish - GetTime()
            if remain <= 0 then self:Hide() return end
            self:SetValue(remain)
            self.Text:SetText(ns.FormatSeconds(remain))
        end)
        readyBar:Show()
    end
end)

ns.RegisterEvent("START_PLAYER_COUNTDOWN", function()
    stAllReady:Deactivate()
end)

local function FireAllReady()
    if allReadyFired or not enabled("allready") then return end
    allReadyFired = true
    stAllReady:Activate(5)
    ns.PlayFile(SOUND.allready)
end

-- Основной триггер «Все готовы»: событие окончания проверки готовности
-- + опрос статусов (надёжно и не зависит от текста системного сообщения,
-- который в 12.0 изменился — поэтому старый триггер по чату молчал).
ns.RegisterEvent("READY_CHECK_FINISHED", function(preempted)
    readyBar:Hide()
    if preempted or not IsInGroup() then return end
    local allReady = true
    local ok = pcall(function()
        for unit in ns.IterateGroup() do
            if GetReadyCheckStatus(unit) ~= "ready" then
                allReady = false
                return
            end
        end
    end)
    if ok and allReady then
        FireAllReady()
    end
end)

-- Запасной триггер по системному сообщению (поиск подстроки).
-- Срабатывает только в течение 2 минут после старта проверки
-- готовности — иначе посторонние сообщения (например, от босс-модов
-- при запуске перерыва) не смогут показать стикер.
ns.RegisterEvent("CHAT_MSG_SYSTEM", function(msg)
    if type(msg) ~= "string" then return end
    if msg:find("Все готовы") or msg:find("All ready") then
        if GetTime() - readyCheckStartedAt < 120 then
            FireAllReady()
        end
    elseif (ERR_NEW_LEADER_YOU and msg == ERR_NEW_LEADER_YOU)
        or msg:find("Теперь вы лидер группы") then
        if enabled("leader") then
            registry.leader:Activate(6)
            ns.PlayFile(SOUND.leader)
        end
    end
end)

-- Перерыв (таймер босс-мода DBM / BigWigs)
local bossModHooked = false
local function HookBossMods()
    if bossModHooked then return end
    local function StartBreak(seconds)
        if not enabled("breaktimer") then return end
        stBreak:Activate(tonumber(seconds))
        ns.PlayFile(SOUND.breaktimer)
    end
    if _G.DBM and _G.DBM.RegisterCallback then
        bossModHooked = true
        _G.DBM:RegisterCallback("DBM_TimerStart", function(_, id, msg, timer)
            local sId, sMsg = tostring(id or ""), tostring(msg or "")
            if sId:lower():find("break") or sMsg:find("Break") or sMsg:find("Перерыв") then
                StartBreak(timer)
            end
        end)
        _G.DBM:RegisterCallback("DBM_TimerStop", function(_, id)
            if tostring(id or ""):lower():find("break") then stBreak:Deactivate() end
        end)
    end
    if _G.BigWigsLoader and _G.BigWigsLoader.RegisterMessage then
        bossModHooked = true
        _G.BigWigsLoader.RegisterMessage({}, "BigWigs_StartBreak", function(_, _, seconds)
            StartBreak(seconds)
        end)
    end
end
ns.RegisterMessage("RAINON_REAPPLY", HookBossMods)

-- =========================================================================
-- ТЕКСТЫ ОПОВЕЩЕНИЙ (вертикальный список по центру)
-- =========================================================================
local txRepair  = CreateTextEntry(textStack, "РЕМОНТ")
local txCauldr  = CreateTextEntry(textStack, "КОТЁЛ")
local txMail    = CreateTextEntry(textStack, "ПОЧТА")
local txStones  = CreateTextEntry(textStack, "КАМНИ ЗДОРОВЬЯ", 24, { 0.67, 0.94, 0.42 })
local txTable   = CreateTextEntry(textStack, "СТОЛ МАГА", 24, { 0.25, 0.78, 0.92 })
local txSummon  = CreateTextEntry(textStack, "ШКАФ", 24, { 0.53, 0.53, 0.93 })
local txMageEat = CreateTextEntry(textStack, "КУШАЙ ЕДУ МАГА", 24)

registry.repair = txRepair;  registry.cauldron = txCauldr
registry.mail = txMail;      registry.healthstones = txStones
registry.magetable = txTable; registry.summon = txSummon
registry.mageeat = txMageEat

local function CastText(key, entry, spells, duration, sound)
    ns.WatchGroupCast(spells, function()
        if not enabled(key) then return end
        entry:Activate(duration)
        ns.PlayFile(sound)
    end)
end

CastText("repair",       txRepair, { 199109, 67826, 453942 }, 7,
         SOUND.repair)
CastText("cauldron",     txCauldr, { 433293, 433294, 433292, 432877, 432878, 432879 }, 7,
         SOUND.cauldron)
CastText("mail",         txMail, { 261602, 376664, 56472 }, 7,
         SOUND.mail)
CastText("healthstones", txStones, { 29893 }, 7,
         SOUND.healthstones)
CastText("magetable",    txTable, { 190336 }, 7,
         SOUND.magetable)
CastText("summon",       txSummon, { 698 }, 7,
         SOUND.summon)

-- «Кушай еду мага»: в рейде, жив, ХП < 60%, еда мага (113509) есть в группе
local MAGE_FOOD_ITEM = 113509
local function UpdateMageEat()
    if not enabled("mageeat") or not IsInRaid() or UnitIsDeadOrGhost("player") then
        txMageEat:Deactivate()
        return
    end
    local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
    local count = ns.GetItemCount(MAGE_FOOD_ITEM)
    if hpMax > 0 and hp / hpMax < 0.6 and count > 0 and not InCombatLockdown() then
        txMageEat:SetTextValue(("КУШАЙ (%d)"):format(count))
        txMageEat:Activate(nil)
    else
        txMageEat:Deactivate()
    end
end
ns.RegisterEvent("UNIT_HEALTH", function(unit)
    if unit == "player" then UpdateMageEat() end
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() UpdateMageEat() end)

-- =========================================================================
-- НАПОМИНАНИЯ
-- =========================================================================

-- Памятка для расходников (показывается на отдыхе)
local CONSUMABLES = {
    { key = "hp",     item = 211880, need = 5, icon = 134756 },  -- лечебное зелье
    { key = "invis",  item = 191395, need = 5, icon = 134798 },  -- зелье невидимости
    { key = "drums",  item = 193470, need = 5, icon = 4559221 }, -- барабаны
    { key = "vantus", item = 226036, need = 1, icon = 4555025 }, -- вантийская руна
    { key = "hammer", item = 132514, need = 2, icon = 132281 },  -- авто-молоток
}
for _, c in ipairs(CONSUMABLES) do
    c.frame = CreateSticker(consumRow, c.icon, "", 64)
    c.frame.Timer:SetFont(ns.FONT, 30, "OUTLINE")
    c.frame.cellH = 64 + 6
end
registry.consumables = consumRow

local function UpdateConsumables()
    for _, c in ipairs(CONSUMABLES) do
        local show = enabled("consumables") and IsResting()
        if show then
            local count = ns.GetItemCount(c.item)
            if count < c.need then
                c.frame.Label:SetText(tostring(count))
                c.frame.active = true
            else
                c.frame.active = false
            end
        else
            c.frame.active = false
        end
        c.frame.expires = nil
    end
    consumRow:Layout()
end
ns.RegisterEvent("PLAYER_UPDATE_RESTING", UpdateConsumables)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() UpdateConsumables() end)

-- Карта вылазок (только в вылазках, difficultyID 208)
local delveMap = CreateIconDisplay({ size = 64, x = 0, y = 200, icon = 1064187,
                                     label = "Используй\nкарту", labelSize = 16 })
registry.delvemap = delveMap
local DELVE_ITEM, DELVE_AURA = 227784, 460831

local function UpdateDelveMap()
    local show = false
    if enabled("delvemap") then
        local _, _, difficultyID = GetInstanceInfo()
        if difficultyID == 208 and ns.GetItemCount(DELVE_ITEM) > 0
           and not ns.GetPlayerAura(DELVE_AURA) then
            show = true
        end
    end
    if show then delveMap:Activate(nil) else delveMap:Deactivate() end
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", UpdateDelveMap)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() UpdateDelveMap() end)

-- =========================================================================
-- ОПОВЕЩЕНИЯ (тексты в фиксированных позициях)
-- =========================================================================
registry.leader = CreateTextDisplay({ text = "ТЕПЕРЬ ТЫ ЛИДЕР ГРУППЫ", size = 38,
                                      x = 0, y = 260, color = { 1, 0.33, 0.2 } })

local combatDrop = CreateTextDisplay({ text = "Бой спал", size = 20, x = 0, y = 10 })
registry.combatdrop = combatDrop

local inEncounter = false
ns.RegisterEvent("ENCOUNTER_START", function() inEncounter = true end)
ns.RegisterEvent("ENCOUNTER_END", function() inEncounter = false end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if enabled("combatdrop") and IsInGroup() and not UnitIsDeadOrGhost("player") then
        combatDrop:Activate(1)
    end
end)

ns.RegisterEvent("UNIT_AURA", function(unit)
    if unit == "player" then
        ns.SendMessage("RAINON_PLAYER_AURA_CHANGED", unit)
    end
end)

-- =========================================================================
-- ЗЕЛЬЯ И ИКОНКИ (ауры игрока / кулдауны)
-- =========================================================================

-- Универсальный наблюдатель аур игрока
local playerAuraWatchers = {}
local function WatchPlayerAuras(fn) table.insert(playerAuraWatchers, fn) end

local playerAuraQueued = false
ns.RegisterMessage("RAINON_PLAYER_AURA_CHANGED", function(unit)
    if unit ~= "player" or playerAuraQueued then return end
    playerAuraQueued = true
    C_Timer.After(0.2, function()
        playerAuraQueued = false
        for _, fn in ipairs(playerAuraWatchers) do pcall(fn) end
    end)
end)

local function FirstPlayerAura(ids)
    for _, id in ipairs(ids) do
        local data = ns.GetPlayerAura(id)
        if data then return data end
    end
end

-- Зелья невидимости
local invisIcon = CreateIconDisplay({ size = 64, x = 0, y = 100, icon = 4497570,
                                      timerSize = 26 })
registry.invispotion = invisIcon
local invisWasActive = false
WatchPlayerAuras(function()
    if not enabled("invispotion") then invisIcon:Deactivate() return end
    local data = FirstPlayerAura({ 307195, 371124 })
    if data then
        if not invisWasActive then
            invisWasActive = true
            ns.Announce("== Invis activated ==")
        end
        if data.icon then invisIcon.Icon:SetTexture(data.icon) end
        invisIcon.expires = data.expirationTime
        invisIcon.active = true
        invisIcon:Show()
        StartTicking(invisIcon)
    else
        invisWasActive = false
        invisIcon:Deactivate()
    end
end)

-- Инженерный плащ (кулдаун слота экипировки)
local function SlotCooldownWatcher(key, slot, x, y)
    local icon = CreateIconDisplay({ size = 42, x = x, y = y, strata = "HIGH" })
    registry[key] = icon
    local function Update()
        if not enabled(key) then icon:Deactivate() return end
        local start, duration = GetInventoryItemCooldown("player", slot)
        if start and duration and duration > 2 and start > 0 then
            local tex = GetInventoryItemTexture("player", slot)
            if tex then icon.Icon:SetTexture(tex) end
            icon.expires = start + duration
            icon.active = true
            icon:Show()
            StartTicking(icon)
        else
            icon:Deactivate()
        end
    end
    ns.RegisterEvent("SPELL_UPDATE_COOLDOWN", Update)
    ns.RegisterEvent("UNIT_INVENTORY_CHANGED", function(unit)
        if unit == "player" then Update() end
    end)
end
SlotCooldownWatcher("engcloak", 15, -340, 200)

-- =========================================================================
-- МУВЕРЫ: боксы «Rainon UI», появляются в режиме редактирования Blizzard
-- (Esc → Настройка интерфейса), таскаются мышью, позиции сохраняются в
-- RainonUIDB.positions.
-- =========================================================================
local movers = {}

local function GetSavedPos(key)
    local pos = ns.db and ns.db.positions and ns.db.positions[key]
    local x = (pos and pos.x) or 0
    local y = (pos and pos.y) or 0
    local s = (pos and pos.scale) or 1
    if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
    return x, y, s
end

-- Ставит дисплей на сохранённую позицию с учётом масштаба. Отступы якоря
-- делятся на масштаб: SetPoint считает их в координатах самого фрейма,
-- иначе при изменении размера дисплей уезжал бы в сторону.
local function PositionDisplay(frame, key)
    local x, y, s = GetSavedPos(key)
    frame:SetScale(s)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
end

local function CreateMover(key, label, w, h, applyFn)
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetSize(w, h)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetMovable(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetClampedToScreen(true)
    m:Hide()

    local border = m:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.85, 1, 0.9)
    local bg = m:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0.55, 0.85, 0.45)

    m.title = MakeText(m, 11, { 1, 0.82, 0 })
    m.title:SetPoint("BOTTOM", m, "TOP", 0, 3)
    m.title:SetText("RainonUI")

    m.label = MakeText(m, 12)
    m.label:SetPoint("CENTER")
    m.label:SetText(label)

    -- размер: колесо мыши над боксом, шаг 10%, пределы 50–200%
    m.scaleLabel = MakeText(m, 10, { 0.75, 0.9, 1 })
    m.scaleLabel:SetPoint("TOP", m, "BOTTOM", 0, -2)

    -- точные координаты: поля X / Y под боксом (Enter — применить)
    local coords = CreateFrame("Frame", nil, m)
    coords:SetSize(150, 20)
    coords:SetPoint("TOP", m.scaleLabel, "BOTTOM", 0, -4)

    local function MakeCoordBox(labelText, offsetX, setVal)
        local lbl = coords:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", coords, "LEFT", offsetX, 0)
        lbl:SetText(labelText)
        local box = CreateFrame("EditBox", nil, coords, "InputBoxTemplate")
        box:SetSize(46, 18)
        box:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        box:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v and ns.db and ns.db.positions then
                local pos = ns.db.positions[key]
                if not pos then pos = {}; ns.db.positions[key] = pos end
                setVal(pos, math.floor(v + 0.5))
                m.Refresh()
                applyFn()
            end
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            m.Refresh()
        end)
        return box
    end
    m.xBox = MakeCoordBox("X", 0, function(pos, v) pos.x = v end)
    m.yBox = MakeCoordBox("Y", 76, function(pos, v) pos.y = v end)

    m.Refresh = function()
        local x, y, s = GetSavedPos(key)
        m:SetSize(w * s, h * s)
        m:ClearAllPoints()
        m:SetPoint("CENTER", UIParent, "CENTER", x, y)
        m.scaleLabel:SetText(math.floor(s * 100 + 0.5) .. "% — колесо мыши")
        if not m.xBox:HasFocus() then m.xBox:SetText(tostring(x)) end
        if not m.yBox:HasFocus() then m.yBox:SetText(tostring(y)) end
    end

    m:SetScript("OnDragStart", function(self) self:StartMoving() end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux and ns.db and ns.db.positions then
            local pos = ns.db.positions[key]
            if not pos then pos = {}; ns.db.positions[key] = pos end
            pos.x = math.floor(cx - ux + 0.5)
            pos.y = math.floor(cy - uy + 0.5)
            m.Refresh()
            applyFn()
        end
    end)

    m:EnableMouseWheel(true)
    m:SetScript("OnMouseWheel", function(_, delta)
        if not (ns.db and ns.db.positions) then return end
        local pos = ns.db.positions[key]
        if not pos then pos = {}; ns.db.positions[key] = pos end
        local s = (pos.scale or 1) + delta * 0.1
        if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
        pos.scale = s
        m.Refresh()
        applyFn()
    end)

    m.ApplyPosition = applyFn
    movers[key] = m
    return m
end

local function ShowMovers()
    if not ns.db then return end
    for _, m in pairs(movers) do
        m.Refresh()
        m:Show()
    end
end

local function HideMovers()
    for _, m in pairs(movers) do m:Hide() end
end

local editModeHooked = false
local function HookEditMode()
    if editModeHooked then return end
    local em = _G.EditModeManagerFrame
    if not em or not em.HookScript then return end
    editModeHooked = true
    em:HookScript("OnShow", ShowMovers)
    em:HookScript("OnHide", HideMovers)
end

-- =========================================================================
-- ТАЙМЕР БОЯ (белые цифры с тенью; позиция — через режим редактирования)
-- =========================================================================
local combatTimer = CreateTextDisplay({ text = "00:00", size = 18, x = 466, y = -226,
                                        selfPoint = "CENTER",
                                        color = { 1, 1, 1, 1 } })
combatTimer.Label:SetFont(ns.FONT, 18, "")            -- без грязного контура
combatTimer.Label:SetShadowColor(0, 0, 0, 0.9)        -- аккуратная тень
combatTimer.Label:SetShadowOffset(1, -1)
registry.combattimer = combatTimer

local function ApplyTimerPosition()
    PositionDisplay(combatTimer, "combattimer")
end

CreateMover("combattimer", "Таймер боя", 90, 26, ApplyTimerPosition)

ns.RegisterMessage("RAINON_DB_READY", function()
    for _, m in pairs(movers) do m.ApplyPosition() end
    HookEditMode()
end)
ns.RegisterMessage("RAINON_REAPPLY", HookEditMode)
local combatStart = nil
local combatTicker = nil

-- Как в WeakAura: после боя таймер не пропадает, а тускнеет и
-- замирает на моменте окончания боя.
local function StopCombatTimer()
    if combatTicker then combatTicker:Cancel() combatTicker = nil end
    if combatStart then
        local t = GetTime() - combatStart
        combatTimer:SetTextValue(string.format("%02d:%02d",
            math.floor(t / 60), math.floor(t % 60)))
    end
    combatStart = nil
    combatTimer.Label:SetTextColor(0.62, 0.62, 0.62, 0.5)
end

local function StartCombatTimer()
    if not enabled("combattimer") then return end
    combatStart = GetTime()
    combatTimer.Label:SetTextColor(1, 1, 1, 1)
    combatTimer:SetTextValue("00:00")
    combatTimer:Activate(nil)
    if combatTicker then combatTicker:Cancel() end
    combatTicker = C_Timer.NewTicker(0.5, function()
        if not combatStart then return end
        local t = GetTime() - combatStart
        combatTimer:SetTextValue(string.format("%02d:%02d", math.floor(t / 60), math.floor(t % 60)))
    end)
end

ns.RegisterEvent("ENCOUNTER_START", StartCombatTimer)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not combatStart then StartCombatTimer() end
end)
ns.RegisterEvent("ENCOUNTER_END", function()
    if not InCombatLockdown() then StopCombatTimer() end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not inEncounter then StopCombatTimer() end
end)

-- =========================================================================
-- ПРОФЕССИИ: напоминания о баффах крафта при открытом окне профессии.
-- Проверка строго по spellID:
--   * Haranir Phial of Ingenuity (1239755) — для всех профессий;
--   * Shattered Essence (1235733) — дополнительно для наложения чар.
-- Нет баффа → иконка с glow-эффектом. Позиции — через режим редактирования.
-- =========================================================================
local PHIAL_SPELL   = 1239755
local ESSENCE_SPELL = 1235733
-- Иконки берём у самих заклинаний (C_Spell.GetSpellTexture) — hardcode
-- IconID из тултипа оказался битым (зелёный квадрат). Фолбэки на случай,
-- если данные заклинания ещё не подгружены.
local PHIAL_FALLBACK   = 134756  -- фиал
local ESSENCE_FALLBACK = 7548988 -- расколотая сущность (этот ID рабочий)

local function AddGlow(f)
    -- стандартный proc-глоу Blizzard + пульсация
    local glow = f:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    local pad = f:GetWidth() * 0.28
    glow:SetPoint("TOPLEFT", -pad, pad)
    glow:SetPoint("BOTTOMRIGHT", pad, -pad)

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0.35)
    alpha:SetDuration(0.7)

    f:HookScript("OnShow", function() ag:Play() end)
    f:HookScript("OnHide", function() ag:Stop() end)
end

local phialIcon = CreateIconDisplay({ size = 48, x = -50, y = 120, icon = PHIAL_FALLBACK,
                                      strata = "HIGH", timer = false })
AddGlow(phialIcon)
registry.prof_phial = phialIcon

local essenceIcon = CreateIconDisplay({ size = 48, x = 50, y = 120, icon = ESSENCE_FALLBACK,
                                        strata = "HIGH", timer = false })
AddGlow(essenceIcon)
registry.prof_essence = essenceIcon

local function RefreshProfIcons()
    local t = ns.GetSpellTexture(PHIAL_SPELL)
    if t then phialIcon.Icon:SetTexture(t) end
    t = ns.GetSpellTexture(ESSENCE_SPELL)
    if t then essenceIcon.Icon:SetTexture(t) end
end

local function ApplyPhialPosition()
    PositionDisplay(phialIcon, "prof_phial")
end

local function ApplyEssencePosition()
    PositionDisplay(essenceIcon, "prof_essence")
end

CreateMover("prof_phial",   "Флакон",   56, 56, ApplyPhialPosition)
CreateMover("prof_essence", "Сущность", 56, 56, ApplyEssencePosition)

local profOpen = false
local isEnchanting = false

local function DetectEnchanting()
    isEnchanting = false
    pcall(function()
        local info
        if C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfo then
            info = C_TradeSkillUI.GetChildProfessionInfo()
        end
        if (not info or not info.profession)
           and C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
            info = C_TradeSkillUI.GetBaseProfessionInfo()
        end
        if info and info.profession and Enum and Enum.Profession then
            isEnchanting = (info.profession == Enum.Profession.Enchanting)
        end
    end)
end

local function UpdateProfBuffs()
    if not profOpen or not ns.ProfEnabled() then
        phialIcon:Deactivate()
        essenceIcon:Deactivate()
        return
    end
    RefreshProfIcons()
    if enabled("prof_phial") and not ns.GetPlayerAura(PHIAL_SPELL) then
        phialIcon:Activate(nil)
    else
        phialIcon:Deactivate()
    end
    if enabled("prof_essence") and isEnchanting
       and not ns.GetPlayerAura(ESSENCE_SPELL) then
        essenceIcon:Activate(nil)
    else
        essenceIcon:Deactivate()
    end
end

ns.RegisterEvent("TRADE_SKILL_SHOW", function()
    profOpen = true
    DetectEnchanting()
    UpdateProfBuffs()
    -- данные профессии могут доехать чуть позже открытия окна
    C_Timer.After(0.5, function()
        if profOpen then DetectEnchanting(); UpdateProfBuffs() end
    end)
end)

ns.RegisterEvent("TRADE_SKILL_CLOSE", function()
    profOpen = false
    UpdateProfBuffs()
end)

ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
    if profOpen then DetectEnchanting(); UpdateProfBuffs() end
end)

-- Подстраховка: окно профессий может закрываться и без события
local profFrameHooked = false
local function HookProfessionsFrame()
    if profFrameHooked then return end
    local pf = _G.ProfessionsFrame
    if not pf or not pf.HookScript then return end
    profFrameHooked = true
    pf:HookScript("OnShow", function()
        profOpen = true
        DetectEnchanting()
        UpdateProfBuffs()
    end)
    pf:HookScript("OnHide", function()
        profOpen = false
        UpdateProfBuffs()
    end)
end
ns.RegisterMessage("RAINON_REAPPLY", HookProfessionsFrame)

WatchPlayerAuras(UpdateProfBuffs)

ns.Tools = ns.Tools or {}
ns.Tools.UpdateProfBuffs = UpdateProfBuffs

-- =========================================================================
-- НЕДЕЛЬНЫЕ ЗНАНИЯ: недельный квест профессии + Талассийский трактат.
-- Оба дают очки знаний и обновляются раз в неделю. Отслеживаем по флагу
-- выполнения недельных/скрытых квестов (C_QuestLog.IsQuestFlaggedCompleted):
--   * недельный квест профессии в Луносвете (у собирателей — ротация из
--     нескольких, активен один; засчитываем выполнение любого из набора);
--   * трактат — при изучении срабатывает заклинание «Studying», которое
--     помечает скрытый недельный квест профессии (treatiseQuest).
-- Ключ таблицы — базовый ID линии профессии (7-й возврат GetProfessionInfo).
-- Все ID выверены по Wowhead для Midnight (12.0).
-- =========================================================================
local WEEKLY_KNOWLEDGE = {
    [171] = { treatiseQuest = 95127, weekly = { 93690 } },  -- Алхимия
    [164] = { treatiseQuest = 95128, weekly = { 93691 } },  -- Кузнечное дело
    [333] = { treatiseQuest = 95129, weekly = { 93697 } },  -- Наложение чар
    [202] = { treatiseQuest = 95138, weekly = { 93692 } },  -- Инженерное дело
    [773] = { treatiseQuest = 95131, weekly = { 93693 } },  -- Начертание
    [755] = { treatiseQuest = 95133, weekly = { 93694 } },  -- Ювелирное дело
    [165] = { treatiseQuest = 95134, weekly = { 93695 } },  -- Кожевничество
    [197] = { treatiseQuest = 95137, weekly = { 93696 } },  -- Портняжное дело
    [182] = { treatiseQuest = 95130,                        -- Травничество
              weekly = { 93700, 93701, 93702, 93703, 93704 } },
    [186] = { treatiseQuest = 95135,                        -- Горное дело
              weekly = { 93705, 93706, 93707, 93708, 93709 } },
    [393] = { treatiseQuest = 95136,                        -- Снятие шкур
              weekly = { 93710, 93711, 93712, 93713, 93714 } },
}

-- Общие недельные объективы (важны для всех профессий, не привязаны к одной).
-- «Abundant Offerings» (89507) — недельный мета-квест Midnight; на первом
-- принятии есть скрытый флаг 94952 — учитываем оба (готово, если любой).
-- Название берём живьём из игры (локализовано), fallback — англ.
local GLOBAL_KNOWLEDGE = {
    { fallback = "Abundant Offerings",
      atlas = "questlog-questtypeicon-Recurring",
      quests = { 89507, 94952 } },
}

local function IsQuestDone(id)
    if not id then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    end
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(id) and true or false
    end
    return false
end

-- Список изученных игроком первичных профессий с недельным статусом:
--   { { name = "Алхимия", weeklyDone = bool, treatiseDone = bool }, ... }
-- Профессии без данных (кулинария, рыбалка, археология) не попадают.
function ns.Tools.GetWeeklyKnowledge()
    local out = {}
    if not GetProfessions or not GetProfessionInfo then return out end
    local slots = { GetProfessions() } -- prof1, prof2, археология, рыбалка, кулинария
    for i = 1, 2 do
        local idx = slots[i]
        if idx then
            local name, icon, _, _, _, _, skillLine = GetProfessionInfo(idx)
            local data = skillLine and WEEKLY_KNOWLEDGE[skillLine]
            if data then
                local weeklyDone = false
                for _, q in ipairs(data.weekly) do
                    if IsQuestDone(q) then weeklyDone = true; break end
                end
                out[#out + 1] = {
                    name = name or ("#" .. tostring(skillLine)),
                    icon = icon,
                    base = skillLine,
                    weeklyDone = weeklyDone,
                    treatiseDone = IsQuestDone(data.treatiseQuest),
                }
            end
        end
    end
    return out
end

-- Общие объективы (Abundant Offerings и т.п.) со статусом выполнения:
--   { { name = "...", done = bool, atlas = "..." }, ... }
function ns.Tools.GetGlobalKnowledge()
    local out = {}
    for _, g in ipairs(GLOBAL_KNOWLEDGE) do
        local done = false
        for _, q in ipairs(g.quests) do
            if IsQuestDone(q) then done = true; break end
        end
        local title
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            title = C_QuestLog.GetTitleForQuestID(g.quests[1])
        end
        out[#out + 1] = {
            name = (title and title ~= "" and title) or g.fallback,
            done = done,
            atlas = g.atlas,
        }
    end
    return out
end

-- =========================================================================
-- ВАЛЮТА РЕМЕСЛА: «Купи сумку!»
-- Если валюты Moxie больше 600 — глоу-иконка (по умолчанию в центре
-- экрана) с текстом «Купи сумку!». Двигается и масштабируется в режиме
-- редактирования, как остальные боксы Rainon UI.
-- =========================================================================
local MOXIE_CURRENCIES = {
    3256, -- Алхимия
    3257, -- Кузнечное дело
    3258, -- Наложение чар
    3259, -- Инженерное дело
    3260, -- Травничество
    3261, -- Начертание
    3262, -- Ювелирное дело
    3263, -- Кожевничество
    3264, -- Горное дело
    3265, -- Снятие шкур
    3266, -- Портняжное дело
}
local MOXIE_CAP = 600 -- сумку можно купить за 600, поэтому порог «>= 600»

local bagIcon = CreateIconDisplay({ size = 48, x = 0, y = 0,
                                    icon = "Interface\\Icons\\INV_Misc_Bag_08",
                                    label = "Купи сумку!", labelSize = 20,
                                    strata = "HIGH", timer = false })
AddGlow(bagIcon)
registry.curr_moxie = bagIcon

local function ApplyBagPosition()
    PositionDisplay(bagIcon, "curr_moxie")
end
CreateMover("curr_moxie", "Купи сумку", 56, 56, ApplyBagPosition)

local function UpdateMoxie()
    if not enabled("curr_moxie") then
        bagIcon:Deactivate()
        return
    end
    local found
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for _, id in ipairs(MOXIE_CURRENCIES) do
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
            if ok and info and (info.quantity or 0) >= MOXIE_CAP then
                found = info
                break
            end
        end
    end
    if found then
        if found.iconFileID then bagIcon.Icon:SetTexture(found.iconFileID) end
        bagIcon:Activate(nil)
    else
        bagIcon:Deactivate()
    end
end

ns.RegisterEvent("CURRENCY_DISPLAY_UPDATE", function() UpdateMoxie() end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", UpdateMoxie)
ns.Tools.UpdateMoxie = UpdateMoxie

-- =========================================================================
-- ПОЛОСА ГОТОВНОСТИ и БОНУСНАЯ ДОБЫЧА: муверы (двигать/размер/X-Y)
-- =========================================================================
local function ApplyReadyBarPosition()
    PositionDisplay(readyBar, "readybar")
end
CreateMover("readybar", "Полоса готовности", 220, 24, ApplyReadyBarPosition)

-- Универсальный перенос окна Blizzard на позицию мувера. Blizzard
-- переанкоривает такие окна при каждом показе — возвращаем на место
-- пользователя (HookScript OnShow + hooksecurefunc SetPoint с защитой
-- от зацикливания). Фреймы из ленивых аддонов подхватываются через
-- RAINON_REAPPLY (срабатывает на каждом ADDON_LOADED).
local function SetupBlizzardFrameMover(frameName, posKey, enableKey)
    local applying = false
    local function Apply()
        local f = _G[frameName]
        if not f or not enabled(enableKey) then return end
        applying = true
        local x, y, s = GetSavedPos(posKey)
        f:SetScale(s)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
        applying = false
    end
    local hooked = false
    ns.RegisterMessage("RAINON_REAPPLY", function()
        if hooked then return end
        local f = _G[frameName]
        if not f or not f.HookScript then return end
        hooked = true
        f:HookScript("OnShow", Apply)
        hooksecurefunc(f, "SetPoint", function()
            if not applying then Apply() end
        end)
        Apply()
    end)
    return Apply
end

-- Бонусная добыча: окно броска (BonusRollFrame), окно выигранного
-- предмета (BonusRollLootWonFrame) и окно выигранного золота
-- (BonusRollMoneyWonFrame) — ОДИН бокс, все три рамки автоматически
-- подтягивают его координаты.
local ApplyBonusRoll = SetupBlizzardFrameMover("BonusRollFrame", "bonusroll", "bonusroll")
local ApplyBonusLootWon = SetupBlizzardFrameMover("BonusRollLootWonFrame", "bonusroll", "bonusroll")
local ApplyBonusMoneyWon = SetupBlizzardFrameMover("BonusRollMoneyWonFrame", "bonusroll", "bonusroll")

local function ApplyBonusAll()
    ApplyBonusRoll()
    ApplyBonusLootWon()
    ApplyBonusMoneyWon()
end

CreateMover("bonusroll", "Бонусная добыча", 130, 44, ApplyBonusAll)
registry.bonusroll = {
    Deactivate = function()
        ns.Print("позиция бонусной добычи вернётся к стандартной после " ..
            ns.C("FFFF00", "/reload") .. ".")
    end,
}

-- Окно эпохального ключа («Вставьте эпохальный ключ»,
-- ChallengesKeystoneFrame из Blizzard_ChallengesUI — грузится лениво).
local ApplyKeystone = SetupBlizzardFrameMover("ChallengesKeystoneFrame", "keystone", "keystone")
CreateMover("keystone", "Эпохальный ключ", 130, 50, ApplyKeystone)
registry.keystone = {
    Deactivate = function()
        ns.Print("позиция окна эпохального ключа вернётся к стандартной после " ..
            ns.C("FFFF00", "/reload") .. ".")
    end,
}

-- =========================================================================
-- Выключение галочки — мгновенно прячем дисплей
-- =========================================================================
ns.Tools = ns.Tools or {}
function ns.Tools.OnToggle(key, state)
    -- Мастер-выключатель профессий: применяем сразу к баффам и миникарте.
    if key == "professions_enabled" then
        UpdateProfBuffs()
        if ns.Roster and ns.Roster.UpdateMinimap then ns.Roster.UpdateMinimap() end
        return
    end
    if state then
        if key == "consumables" then UpdateConsumables() end
        if key == "delvemap" then UpdateDelveMap() end
        if key == "prof_phial" or key == "prof_essence" then UpdateProfBuffs() end
        if key == "curr_moxie" then UpdateMoxie() end
        if key == "bonusroll" then ApplyBonusAll() end
        if key == "keystone" then ApplyKeystone() end
        return
    end
    local display = registry[key]
    if not display then return end
    if display.Deactivate then
        display:Deactivate()
    elseif display.items then
        for _, item in ipairs(display.items) do item.active = false end
        display:Layout()
    elseif display.Hide then
        display:Hide()
    end
    if key == "consumables" then UpdateConsumables() end
end

ns.RegisterMessage("RAINON_DB_READY", function()
    UpdateConsumables()
end)