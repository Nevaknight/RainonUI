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
    -- Пути к файлам после перехода на единый формат RainonUI_*.ogg (1.4.3).
    allready     = MYSOUND .. "RainonUI_All_ready.ogg",           -- «Все готовы»
    breaktimer   = MYSOUND .. "break.ogg",                        -- «Перерыв» (свой звук!)
    feast        = MYSOUND .. "RainonUI_Food_Hearty_Well_Fed.ogg",-- сытная еда
    food         = MYSOUND .. "RainonUI_Food.ogg",               -- обычная еда
    racechange   = MYSOUND .. "RainonUI_Change_Race.ogg",        -- смена расы
    repair       = MYSOUND .. "RainonUI_Repair.ogg",             -- ремонт
    cauldron     = MYSOUND .. "RainonUI_Boiler.ogg",             -- котёл
    mail         = MYSOUND .. "RainonUI_Mail_Box.ogg",           -- почта
    healthstones = MYSOUND .. "RainonUI_Health_Stones.ogg",      -- камни здоровья
    magetable    = MYSOUND .. "RainonUI_Mage_table.ogg",         -- стол мага
    summon       = MYSOUND .. "RainonUI_Ritual_of_Summoning.ogg",-- шкаф сумона
    leader       = MYSOUND .. "RainonUI_Lead_group.ogg",         -- лидер группы
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

-- ---- Круг-счётчик (как у окна телепорта). Собран из двух круглых дисков
-- (масками): золотой внешний + тёмный внутренний = чистый золотой ободок, без
-- битых текстур-колец. Отдельный фрейм на ВЫСОКОЙ страте — рисуется ПОВЕРХ бокса
-- (иначе рамка перекрывает круг). Возвращает FontString для цифр.
local function AttachCounterCircle(parent, diameter)
    local D = diameter or 50
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(D, D)
    c:SetPoint("CENTER", parent, "TOPLEFT", 22, -18)   -- верхний-левый угол, внахлёст
    c:SetFrameStrata("HIGH")                           -- поверх рамки бокса
    c:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)

    -- Золотой внешний диск (круг через маску-портрет).
    local gold = c:CreateTexture(nil, "ARTWORK")
    gold:SetPoint("CENTER"); gold:SetSize(D, D)
    gold:SetColorTexture(0.85, 0.65, 0.13, 1)
    local m1 = c:CreateMaskTexture()
    m1:SetPoint("CENTER"); m1:SetSize(D, D)
    m1:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
                  "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    gold:AddMaskTexture(m1)

    -- Тёмный внутренний диск — оставляет золотой ободок по краю.
    local dark = c:CreateTexture(nil, "OVERLAY")
    dark:SetPoint("CENTER"); dark:SetSize(D - 7, D - 7)
    dark:SetColorTexture(0.05, 0.05, 0.06, 1)
    local m2 = c:CreateMaskTexture()
    m2:SetPoint("CENTER"); m2:SetSize(D - 7, D - 7)
    m2:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
                  "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    dark:AddMaskTexture(m2)

    -- Цифры — поверх дисков.
    local fs = MakeText(c, 18, { 1, 0.9, 0.4 })
    fs:SetDrawLayer("OVERLAY", 7)
    fs:SetPoint("CENTER", c, "CENTER", 0, 0)
    return fs
end

-- ---- Стикер (в стиле панели «RainonUI — Тестер»): бокс с заголовком-баром
-- (в нём имя стикера) + КВАДРАТНОЕ прозрачное тело, в которое РОВНО (симметрично)
-- вписан квадратный арт (без растяжения). Все стикеры на одном шаблоне
-- (DefaultPanelFlatTemplate). У «Перерыва» единственное отличие — золотой
-- круг-счётчик слева с таймером ПОВЕРХ бокса. Остальные — без цифр, гаснут сами.
--   opts.portraitTimer = true  → круг-счётчик (только «Перерыв»).
local function CreateSticker(row, iconPath, label, size, opts)
    opts = opts or {}
    size = size or 200          -- сторона КВАДРАТНОГО арта
    local PAD = 6                -- равные поля вокруг арта

    local f = Mix(CreateFrame("Frame", nil, row, "DefaultPanelFlatTemplate"))

    -- Имя стикера — в заголовок-бар бокса (не отдельным текстом).
    if f.SetTitle then f:SetTitle(label or "") end
    local titleBar = f.TitleContainer
    local titleFS = (titleBar and titleBar.TitleText) or f.TitleText
    if titleFS then
        titleFS:ClearAllPoints()
        titleFS:SetPoint("TOP", f, "TOP", 0, -6)
        titleFS:SetJustifyH("CENTER")
    end

    -- РЕАЛЬНАЯ высота заголовка-бара (у шаблона), чтобы арт встал ровно под ним.
    local th = (titleBar and titleBar.GetHeight and titleBar:GetHeight()) or 0
    if not th or th < 1 then th = 24 end

    -- Габариты: тело квадратное (арт size×size + поля PAD со всех сторон),
    -- сверху — заголовок-бар высотой th.
    local W = size + PAD * 2
    local H = th + size + PAD * 2
    f:SetSize(W, H)
    f.cellW, f.cellH = W, H
    f.row = row
    f:Hide()

    -- КВАДРАТНЫЙ арт: цепляем к фактическому НИЗУ заголовка-бара (а не к верху
    -- фрейма) — тогда он не съезжает при любой высоте бара; поля PAD равные.
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetSize(size, size)
    if titleBar then
        f.Icon:SetPoint("TOP", titleBar, "BOTTOM", 0, -PAD)
    else
        f.Icon:SetPoint("TOP", f, "TOP", 0, -(th + PAD))
    end
    ns.SetIcon(f.Icon, iconPath)

    if opts.portraitTimer then
        -- Только «Перерыв»: круг-счётчик слева поверх бокса, внутри — таймер.
        f.Timer = AttachCounterCircle(f, 50)
    end
    -- У остальных f.Timer нет: авто-скрытие по self.expires (Activate(duration)).

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
-- (consumRow «Памятка расходников» и «Карта вылазок» вынесены в Архив/ 30.07.2026)

-- =========================================================================
-- СТИКЕРЫ
-- =========================================================================
local stBreak    = CreateSticker(stickerRow, MYICON .. "break.tga",      "ПЕРЕРЫВ", nil,
                                 { portraitTimer = true })  -- круг слева с таймером
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

-- Сытная еда (пиршества), текущие ID Midnight (устаревшее TWW убрано).
-- Набор пиршеств сверен с Northern Sky RT + наше «Сытное королевское жаркое».
CastSticker("feast",      stFeast, { 1259657, 1278915, 1259658, 1278929,
                                     1237104, 1278909, 1259659, 1278895,
                                     1232065 }, 10,
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

-- condFn (необязательный) — вернуть false, чтобы НЕ показывать (напр. камни
-- при полном запасе). Проверяется у ПОЛУЧАТЕЛЯ, по его собственному состоянию.
local function CastText(key, entry, spells, duration, sound, condFn)
    ns.WatchGroupCast(spells, function()
        if not enabled(key) then return end
        if condFn and not condFn() then return end
        entry:Activate(duration)
        ns.PlayFile(sound)
    end)
end

CastText("repair",       txRepair, { 199109, 67826, 453942 }, 7,
         SOUND.repair)
-- Котёл: текущие ID Midnight (устаревшее TWW убрано), сверено с Northern Sky RT:
-- Мракозарный котел для зелий (1240267), Котел для син'дорайских настоев (1240195).
CastText("cauldron",     txCauldr, { 1240267, 1240195 }, 7,
         SOUND.cauldron)
-- Почта: старые ID сохранены, добавлены текущие (Midnight):
-- Межпространственный почтовый сигнал (1272463), МЯЛЛ-И (54710).
CastText("mail",         txMail, { 261602, 376664, 56472,
                                   1272463, 54710 }, 7,
         SOUND.mail)
-- Камни здоровья (колодец душ 29893): не показываем, если у нас уже 3 камня.
CastText("healthstones", txStones, { 29893 }, 7,
         SOUND.healthstones, function()
             return (C_Item.GetItemCount(5512, false, true) or 0) < 3
         end)
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

-- (АРХИВ 30.07.2026) «Памятка для расходников» и «Карта вылазок» вынесены в
-- папку Архив/ (Архив/Consumables_and_DelveMap.lua) — доделаем позже.

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
    m._label = label
    movers[key] = m
    return m
end

local function ShowMovers()
    -- Если подключена LibEditMode — боксы показывает она (родной Edit Mode),
    -- старый показ отключаем, чтобы не дублировать.
    if ns.EditMode and ns.EditMode.Available() then return end
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

-- Блок стикеров: двигаем весь ряд стикеров через мувер (в редакторе — как окно
-- телепорта). Мувер-прокси размером с область стикеров.
local function ApplyStickerPosition() PositionDisplay(stickerRow, "stickers") end
ApplyStickerPosition()
CreateMover("stickers", "Стикеры", 200, 200, ApplyStickerPosition)

ns.RegisterMessage("RAINON_DB_READY", function()
    for _, m in pairs(movers) do m.ApplyPosition() end
    HookEditMode()
    -- Новая логика: подключаем боксы муверов к родному Edit Mode (LibEditMode).
    -- Бокс — прокси: EditMode двигает его, а onChanged двигает реальную цель
    -- через applyFn (поэтому близард-фреймы и мульти-фреймы тоже безопасны).
    if ns.EditMode and ns.EditMode.Available() and ns.db and ns.db.positions then
        for key, m in pairs(movers) do
            m:SetScript("OnDragStart", nil)
            m:SetScript("OnDragStop", nil)
            m:EnableMouseWheel(false)
            -- прячем старую UI бокса (поля X/Y, подпись масштаба, верхнюю
            -- надпись «RainonUI») — теперь всё в окошке настроек Edit Mode
            if m.title then m.title:Hide() end
            if m.scaleLabel then m.scaleLabel:Hide() end
            if m.xBox and m.xBox:GetParent() then m.xBox:GetParent():Hide() end
            -- У полосы готовности — дополнительный слайдер «Ширина».
            local extra
            if key == "readybar" and ns.EditMode.SettingType then
                local mover = m
                extra = {
                    {
                        name = "Ширина",
                        kind = ns.EditMode.SettingType.Slider,
                        default = 220, minValue = 120, maxValue = 500, valueStep = 5,
                        get = function()
                            local p = ns.db.positions.readybar
                            return (p and p.width) or 220
                        end,
                        set = function(_, v)
                            ns.db.positions.readybar = ns.db.positions.readybar or {}
                            ns.db.positions.readybar.width = v
                            if mover.ApplyPosition then mover.ApplyPosition() end
                        end,
                        formatter = function(v) return tostring(math.floor((v or 0) + 0.5)) end,
                    },
                }
            end
            ns.EditMode.Register(m, {
                name = "RainonUI: " .. (m._label or key),
                key = key,
                showInEditMode = true,
                getCfg = function()
                    ns.db.positions[key] = ns.db.positions[key] or {}
                    return ns.db.positions[key]
                end,
                onChanged = m.ApplyPosition,
                extraSettings = extra,
            })
        end
    end
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

-- -------------------------------------------------------------------------
-- Клик по иконкам. Иконки показываются только при открытом окне профессии
-- (вне боя), поэтому атрибуты secure-кнопки обновляем безопасно при показе.
--   * Флакон — secure-кнопка type="item": выпивает выбранный флакон.
--   * Раскалывание — обычная кнопка: CraftRecipe(1235731) с подстановкой
--     выбранной частицы (окно наложения чар уже открыто → крафт срабатывает
--     по аппаратному событию клика).
-- -------------------------------------------------------------------------
local SHATTER_RECIPE = 1235731

local phialBtn = CreateFrame("Button", nil, phialIcon, "SecureActionButtonTemplate")
phialBtn:SetAllPoints()
phialBtn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
phialBtn:SetAttribute("type", "item")
local phialHL = phialBtn:CreateTexture(nil, "HIGHLIGHT")
phialHL:SetAllPoints(); phialHL:SetColorTexture(1, 1, 1, 0.2)
phialBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Харанирский флакон", 1, 1, 1)
    GameTooltip:AddLine("Клик — выпить выбранный флакон (выбор во вкладке «Профессии»).", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
phialBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdatePhialAttr()
    if InCombatLockdown() then return end
    local id = ns.db and ns.db.tools and ns.db.tools.phialQuality
    if id then phialBtn:SetAttribute("item", "item:" .. id) end
end

-- Раскалывание — secure-кнопка type="macro" с проверенным рабочим макросом:
--   /run C_TradeSkillUI.CraftRecipe(1235731)
--   /use item:<выбранная частица>
-- Макрос-текст обновляем вне боя (иконка видна только при открытом окне
-- профессии). Переключение рецепта в окне — часть механики, это ок.
local essenceBtn = CreateFrame("Button", nil, essenceIcon, "SecureActionButtonTemplate")
essenceBtn:SetAllPoints()
essenceBtn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
essenceBtn:SetAttribute("type", "macro")
local essHL = essenceBtn:CreateTexture(nil, "HIGHLIGHT")
essHL:SetAllPoints(); essHL:SetColorTexture(1, 1, 1, 0.2)
essenceBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Раскалывание сущности", 1, 1, 1)
    GameTooltip:AddLine("Клик — расколоть выбранную частицу (выбор во вкладке «Профессии»).", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
essenceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateShatterAttr()
    if InCombatLockdown() then return end
    local id = ns.db and ns.db.tools and ns.db.tools.shatterEssence
    if id then
        essenceBtn:SetAttribute("macrotext",
            "/run C_TradeSkillUI.CraftRecipe(" .. SHATTER_RECIPE .. ")\n/use item:" .. id)
    end
end

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

-- Иконки баффов показываем ТОЛЬКО когда открыто РОДНОЕ окно профессии Midnight
-- (Blizzard ProfessionsFrame). Другие аддоны могут открывать данные профессии в
-- своих окнах/фоном — на них не реагируем.
local function BlizzProfShown()
    local pf = _G.ProfessionsFrame
    return (pf and pf.IsShown and pf:IsShown()) and true or false
end

local function UpdateProfBuffs()
    -- Иконки флакона/сущности — родители secure-кнопок (phialBtn/essenceBtn).
    -- Show/Hide такого фрейма в бою заблокированы (ADDON_ACTION_BLOCKED), а
    -- аура-вотчер срабатывает и в бою — поэтому в бою НИЧЕГО не трогаем и
    -- откладываем пересинк до выхода из боя (PLAYER_REGEN_ENABLED ниже).
    -- Окно профессии в бою всё равно не открыть, так что мы ничего не теряем.
    if InCombatLockdown() then return end
    if not profOpen or not BlizzProfShown() or not ns.ProfEnabled() then
        phialIcon:Deactivate()
        essenceIcon:Deactivate()
        return
    end
    RefreshProfIcons()
    if enabled("prof_phial") and not ns.GetPlayerAura(PHIAL_SPELL) then
        UpdatePhialAttr()
        phialIcon:Activate(nil)
    else
        phialIcon:Deactivate()
    end
    if enabled("prof_essence") and isEnchanting
       and not ns.GetPlayerAura(ESSENCE_SPELL) then
        UpdateShatterAttr()
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

-- После боя пересинхронизируем иконки: в бою мы их не трогали (secure-родитель),
-- а окно профессии за это время наверняка закрылось — прячем аккуратно.
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() UpdateProfBuffs() end)

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

-- Тест полосы готовности (для тест-панели): показать её на N секунд, как при
-- реальной проверке готовности, но без самой проверки. (readyBar — upvalue выше.)
function ns.Tools.TestReadyBar(duration)
    duration = tonumber(duration) or 8
    readyBar:SetMinMaxValues(0, duration)
    readyBar.finish = GetTime() + duration
    readyBar:SetScript("OnUpdate", function(self)
        local remain = self.finish - GetTime()
        if remain <= 0 then self:SetScript("OnUpdate", nil); self:Hide(); return end
        self:SetValue(remain)
        self.Text:SetText(ns.FormatSeconds(remain))
    end)
    readyBar:Show()
end

-- ---- ТЕСТЕР СТИКЕРОВ (для отладки, панель /rstest) ----------------------
-- Показать стикер по ключу на несколько секунд, минуя обычные условия. Ключи
-- берём из registry. Список для панели — { {key=, label=}, ... }.
local STICKER_TESTS = {
    { key = "breaktimer", label = "Перерыв",         sound = SOUND.breaktimer },
    { key = "allready",   label = "Все готовы",      sound = SOUND.allready },
    { key = "feast",      label = "Сытная еда",      sound = SOUND.feast },
    { key = "food",       label = "Обычная еда",     sound = SOUND.food },
    { key = "racechange", label = "Смена расы",      sound = SOUND.racechange },
    { key = "leader",     label = "Ты лидер группы", sound = SOUND.leader },
    { key = "combatdrop", label = "Выход из боя" },
}
function ns.Tools.GetStickerTests() return STICKER_TESTS end
function ns.Tools.TestSticker(key, dur)
    local d = registry[key]
    if d and d.Activate then pcall(d.Activate, d, dur or 5) end
    -- проигрываем и звук стикера (как при реальном срабатывании)
    for _, s in ipairs(STICKER_TESTS) do
        if s.key == key and s.sound then ns.PlayFile(s.sound); break end
    end
end

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

-- Ярмарка новолуния: у каждой профессии есть месячное задание, доступное во
-- время Ярмарки (даёт очки знаний). Ключ — базовый ID линии профессии, значение
-- — questID задания Ярмарки. ID выверены по WeeklyKnowledge (Data/Objectives/
-- DarkmoonQuest.lua). Флаг сбрасывается сам при возвращении Ярмарки.
local DARKMOON_QUEST = {
    [171] = 29506,  -- Алхимия
    [164] = 29508,  -- Кузнечное дело
    [333] = 29510,  -- Наложение чар
    [202] = 29511,  -- Инженерное дело
    [182] = 29514,  -- Травничество
    [773] = 29515,  -- Начертание
    [755] = 29516,  -- Ювелирное дело
    [165] = 29517,  -- Кожевничество
    [186] = 29518,  -- Горное дело
    [393] = 29519,  -- Снятие шкур
    [197] = 29520,  -- Портняжное дело
}

-- Активна ли Ярмарка новолуния прямо сейчас (для автоскрытия столбца «Ярмарка»).
-- Определяем по календарю игры: у праздника фиксированный eventID = 479. Календарь
-- открываем сами в фоне (пользователю ничего открывать не нужно) — данные приходят
-- асинхронно (CALENDAR_UPDATE_EVENT_LIST), тогда пересканим. В инстансах календарь
-- может отдавать секреты — гвардим issecretvalue. Логика по образцу WeeklyKnowledge.
local DARKMOON_EVENT_ID = 479
local dmCalendarOpened, dmOpen, dmScanning = false, false, false

local function ScanDarkmoonCalendar()
    -- Защита от повторного входа: C_Calendar.SetAbsMonth СИНХРОННО шлёт
    -- CALENDAR_UPDATE_EVENT_LIST, на которое мы же и подписаны — без гварда это
    -- уходило в бесконечную рекурсию (C stack overflow), особенно вместе с другими
    -- аддонами-сканерами календаря (WeeklyKnowledge и т.п.).
    if dmScanning then return end
    if not (C_Calendar and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then return end
    local t = C_DateAndTime.GetCurrentCalendarTime()
    if not (t and t.monthDay) then return end

    dmScanning = true
    if not dmCalendarOpened and t.month and C_Calendar.OpenCalendar then
        dmCalendarOpened = true   -- ставим ДО вызовов, иначе синхронное событие войдёт повторно
        if C_Calendar.SetAbsMonth then pcall(C_Calendar.SetAbsMonth, t.month, t.year) end
        pcall(C_Calendar.OpenCalendar)
    end
    if C_Calendar.GetNumDayEvents then
        local num = C_Calendar.GetNumDayEvents(0, t.monthDay)
        if num then
            local sec = issecretvalue
            local open = false
            for i = 1, num do
                local ev = C_Calendar.GetDayEvent and C_Calendar.GetDayEvent(0, t.monthDay, i)
                if ev and (not sec or not sec(ev.eventID)) and ev.eventID == DARKMOON_EVENT_ID then
                    open = true; break
                end
            end
            dmOpen = open
        end
    end
    dmScanning = false
end
ns.Tools.RefreshDarkmoon = ScanDarkmoonCalendar
function ns.Tools.IsDarkmoonOpen() return dmOpen end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", ScanDarkmoonCalendar)
ns.RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", function()
    ScanDarkmoonCalendar()
    if ns.Knowledge and ns.Knowledge.Refresh then ns.Knowledge:Refresh() end
end)

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
                    darkmoonDone = IsQuestDone(DARKMOON_QUEST[skillLine]),
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
-- МЕТКА ТАНКА. Простая логика:
--   1) началась проверка готовности (READY_CHECK);
--   2) если я танк — показываем иконку выбранного значка с подписью
--      «Задать танку метку?»;
--   3) проверка готовности закончилась (READY_CHECK_FINISHED) — прячем.
-- Клик по иконке ставит значок на себя. В Midnight SetRaidTarget из кода
-- аддона игра игнорирует, поэтому ставим по клику через защищённую кнопку
-- type="macro" с нативной командой /tm — она идёт по разрешённому пути.
-- Иконку можно двигать/масштабировать в режиме редактирования.
-- =========================================================================
local TANKMARK_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local function TankMarkIndex()
    return (ns.db and ns.db.features and ns.db.features.tankMarkIcon) or 8
end

-- Иконка + подпись снизу «Задать танку метку?» (timer=false → без цифр).
local tankMark = CreateIconDisplay({ size = 48, x = 0, y = 160, strata = "HIGH",
                                     timer = false,
                                     label = "Задать танку метку?", labelSize = 15 })
tankMark.Icon:SetTexCoord(0, 1, 0, 1)  -- значки метки рисуем целиком, без обрезки
registry.tankmark = tankMark

local tankMarkBtn = CreateFrame("Button", nil, tankMark, "SecureActionButtonTemplate")
tankMarkBtn:SetAllPoints()
tankMarkBtn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
tankMarkBtn:SetAttribute("type", "macro")
local tmHL = tankMarkBtn:CreateTexture(nil, "HIGHLIGHT")
tmHL:SetAllPoints(); tmHL:SetColorTexture(1, 1, 1, 0.2)
tankMarkBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Метка танка", 1, 1, 1)
    GameTooltip:AddLine("Клик — поставить выбранный значок на себя. " ..
        "Значок выбирается во вкладке «Удобства».", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
tankMarkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Клик ставит значок на СЕБЯ (я — танк). Атрибут меняем только вне боя.
local function UpdateTankMarkAttr()
    if InCombatLockdown() then return end
    tankMarkBtn:SetAttribute("macrotext", "/tm [@player] " .. TankMarkIndex())
end

local function ApplyTankMarkPosition()
    PositionDisplay(tankMark, "tankmark")
end
CreateMover("tankmark", "Метка танка", 56, 56, ApplyTankMarkPosition)

-- Танк ли игрок: по назначенной роли или по специализации.
local function IsPlayerTank()
    if UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") == "TANK" then
        return true
    end
    local spec = GetSpecialization and GetSpecialization()
    if spec and GetSpecializationRole and GetSpecializationRole(spec) == "TANK" then
        return true
    end
    return false
end

-- Скрытие безопасно: защищённую кнопку нельзя прятать в бою — откладываем
-- до выхода из боя (PLAYER_REGEN_ENABLED).
local hidePending = false
local function HideTankPrompt()
    if InCombatLockdown() then hidePending = true; return end
    hidePending = false
    tankMark:Deactivate()
end

-- Проверка готовности началась: если включено и я танк — показываем окно.
local function ShowTankPrompt()
    if InCombatLockdown() then return end
    if not (ns.db and ns.db.features and ns.db.features.tankMark) then return end
    if not IsPlayerTank() then return end
    tankMark.Icon:SetTexture(TANKMARK_TEX:format(TankMarkIndex()))
    UpdateTankMarkAttr()
    tankMark:Activate(nil)
end

ns.RegisterEvent("READY_CHECK", ShowTankPrompt)
ns.RegisterEvent("READY_CHECK_FINISHED", function() HideTankPrompt() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if hidePending then HideTankPrompt() end
end)

-- Смена галочки/значка в «Удобствах».
ns.Tools.RefreshTankMark = function()
    if not (ns.db and ns.db.features and ns.db.features.tankMark) then
        HideTankPrompt(); return
    end
    if tankMark.active and not InCombatLockdown() then
        tankMark.Icon:SetTexture(TANKMARK_TEX:format(TankMarkIndex()))
        UpdateTankMarkAttr()
    end
end

-- =========================================================================
-- ПОЛОСА ГОТОВНОСТИ и БОНУСНАЯ ДОБЫЧА: муверы (двигать/размер/X-Y)
-- =========================================================================
local READYBAR_BASE_W = 220
local function ReadyBarWidth()
    local p = ns.db and ns.db.positions and ns.db.positions.readybar
    return (p and p.width) or READYBAR_BASE_W
end
local function ApplyReadyBarPosition()
    local w = ReadyBarWidth()
    readyBar:SetWidth(w)                       -- ширину задаём отдельно от масштаба
    PositionDisplay(readyBar, "readybar")      -- масштаб + позиция центра
    -- Бокс-прокси Edit Mode подгоняем по ширине (его собственный масштаб
    -- умножит визуально так же, как у полосы) — чтобы превью совпадало.
    local m = movers.readybar
    if m then m:SetWidth(w) end
end
CreateMover("readybar", "Полоса готовности", READYBAR_BASE_W, 24, ApplyReadyBarPosition)

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
end

-- =========================================================================
-- ЗВУК ВОСКРЕШЕНИЯ: когда на тебя применили воскрешение (появилось окно
-- «Воскреснуть») — проигрываем выбранный звук. Звук выбирается в настройках
-- (вкладка «Удобства»). RESURRECT_REQUEST срабатывает на предложение
-- воскрешения (не self-res у духа).
--
-- Звуки берём из LibSharedMedia-3.0 — стандартный способ, как в BigWigs/DBM:
-- общий список содержит и наши голосовые файлы, и стандартные игровые звуки,
-- и звуки любых других аддонов, зарегистрированных в общей медиатеке. Выбор
-- хранится по ИМЕНИ звука (строка), а не по индексу.
-- =========================================================================
-- LSM резолвим ЛЕНИВО (не один раз при загрузке файла): если медиатека ещё не
-- готова в момент загрузки Tools.lua или её подгружает другой аддон позже —
-- всё равно подхватим её при первом обращении (открытие настроек и т.д.).
-- Иначе список «схлопывался» в 3 запасных звука, если LSM не успела к загрузке.
local LSM_SOUND = "sound"
-- Наши звуки: голоса Рейнона (.ogg) + горсть стандартных игровых (FileDataID).
local OUR_SOUNDS = {
    { "RainonUI: Boss Feed (Alice)", MYSOUND .. "RainonUI_Boss_Feed.ogg" },
    { "RainonUI: Patty Cake (Ладушки) (Alice)", MYSOUND .. "RainonUI_Patty_Cake.ogg" },
    { "RainonUI: Агро (Alice)", MYSOUND .. "RainonUI_Agro.ogg" },
    { "RainonUI: Аддсы (Alice)", MYSOUND .. "RainonUI_Adds.ogg" },
    { "RainonUI: Антимагическая зона (Alice)", MYSOUND .. "RainonUI_Anti_Magic_Zone.ogg" },
    { "RainonUI: Антимагическая зона (англ.) (Alice)", MYSOUND .. "RainonUI_Anti_Magic_Zone_Eng.ogg" },
    { "RainonUI: АоЕ (Alice)", MYSOUND .. "RainonUI_AoE.ogg" },
    { "RainonUI: Барьер (Alice)", MYSOUND .. "RainonUI_Barrier.ogg" },
    { "RainonUI: Бей (Alice)", MYSOUND .. "RainonUI_Hit.ogg" },
    { "RainonUI: Берсерк (Alice)", MYSOUND .. "RainonUI_Berserk.ogg" },
    { "RainonUI: Благословение жертвенности (Alice)", MYSOUND .. "RainonUI_Blessing_of_Sacrifice.ogg" },
    { "RainonUI: Благословение защиты (Alice)", MYSOUND .. "RainonUI_Blessing_of_Protection.ogg" },
    { "RainonUI: Благословение свободы (Alice)", MYSOUND .. "RainonUI_Blessing_of_Freedom.ogg" },
    { "RainonUI: Бомбардировка (Alice)", MYSOUND .. "RainonUI_Bombardment.ogg" },
    { "RainonUI: Бомбы (Alice)", MYSOUND .. "RainonUI_Bombs.ogg" },
    { "RainonUI: Босс (Alice)", MYSOUND .. "RainonUI_Boss.ogg" },
    { "RainonUI: Босс уязвим (Alice)", MYSOUND .. "RainonUI_Boss_Vulnerable.ogg" },
    { "RainonUI: Бочка (Alice)", MYSOUND .. "RainonUI_Barrel.ogg" },
    { "RainonUI: Вампирические объятия (Alice)", MYSOUND .. "RainonUI_Vampiric_Embrace.ogg" },
    { "RainonUI: Внимание (Alice)", MYSOUND .. "RainonUI_Attention.ogg" },
    { "RainonUI: Волна (Alice)", MYSOUND .. "RainonUI_Wave.ogg" },
    { "RainonUI: Все готовы (Alice)", MYSOUND .. "RainonUI_All_ready.ogg" },
    { "RainonUI: Выходи (Alice)", MYSOUND .. "RainonUI_Go_out.ogg" },
    { "RainonUI: Героизм (Alice)", MYSOUND .. "RainonUI_Heroism.ogg" },
    { "RainonUI: Дебафф спал (Alice)", MYSOUND .. "RainonUI_Debuff_disappeared.ogg" },
    { "RainonUI: Дух-хранитель (Alice)", MYSOUND .. "RainonUI_Guardian_Spirit.ogg" },
    { "RainonUI: Дыхание (Alice)", MYSOUND .. "RainonUI_Breath.ogg" },
    { "RainonUI: Еда (Alice)", MYSOUND .. "RainonUI_Food.ogg" },
    { "RainonUI: Железная кора (Alice)", MYSOUND .. "RainonUI_Ironbark.ogg" },
    { "RainonUI: Замедление времени (Alice)", MYSOUND .. "RainonUI_Time_Dilation.ogg" },
    { "RainonUI: Зелье (Alice)", MYSOUND .. "RainonUI_Potion.ogg" },
    { "RainonUI: Зелёный (Overlord)", MYSOUND .. "RainonUI_Green.ogg" },
    { "RainonUI: Зефир (Alice)", MYSOUND .. "RainonUI_Zephyr.ogg" },
    { "RainonUI: Зефир (англ.) (Alice)", MYSOUND .. "RainonUI_Zephyr_Eng.ogg" },
    { "RainonUI: Иди в портал (Alice)", MYSOUND .. "RainonUI_Go_to_portal.ogg" },
    { "RainonUI: Идите в ближний бой (Alice)", MYSOUND .. "RainonUI_Come_to_Melee.ogg" },
    { "RainonUI: Идите к боссу (Alice)", MYSOUND .. "RainonUI_Come_to_the_Boss.ogg" },
    { "RainonUI: Камни здоровья (Alice)", MYSOUND .. "RainonUI_Health_Stones.ogg" },
    { "RainonUI: Каст (Alice)", MYSOUND .. "RainonUI_Cast.ogg" },
    { "RainonUI: Каст контроля (Alice)", MYSOUND .. "RainonUI_Cast_CC.ogg" },
    { "RainonUI: Каст — перебей (Alice)", MYSOUND .. "RainonUI_Cast_Kick.ogg" },
    { "RainonUI: Каст — перебей босса (Alice)", MYSOUND .. "RainonUI_Cast_Kick_Boss.ogg" },
    { "RainonUI: Клив (Alice)", MYSOUND .. "RainonUI_Cleave.ogg" },
    { "RainonUI: Клинки фазы (TWW) (Alice)", MYSOUND .. "RainonUI_TWW_Phase_Blades.ogg" },
    { "RainonUI: Кокон жизни (Alice)", MYSOUND .. "RainonUI_Life_Cocoon.ogg" },
    { "RainonUI: Коричневый (Overlord)", MYSOUND .. "RainonUI_Brown.ogg" },
    { "RainonUI: Котёл (Alice)", MYSOUND .. "RainonUI_Boiler.ogg" },
    { "RainonUI: Красный (Overlord)", MYSOUND .. "RainonUI_Red.ogg" },
    { "RainonUI: Крик (Alice)", MYSOUND .. "RainonUI_Scream.ogg" },
    { "RainonUI: Ледяной барьер (Alice)", MYSOUND .. "RainonUI_Ice_Barrier.ogg" },
    { "RainonUI: Лети (Alice)", MYSOUND .. "RainonUI_Fly.ogg" },
    { "RainonUI: Луч (Alice)", MYSOUND .. "RainonUI_Beam.ogg" },
    { "RainonUI: Мана (Alice)", MYSOUND .. "RainonUI_Mana.ogg" },
    { "RainonUI: Массовая невидимость (Alice)", MYSOUND .. "RainonUI_Mass_Invisibility.ogg" },
    { "RainonUI: Мастерство ауры (Alice)", MYSOUND .. "RainonUI_Aura_Mastery.ogg" },
    { "RainonUI: Наведение (misdirect) (Alice)", MYSOUND .. "RainonUI_Misdirection.ogg" },
    { "RainonUI: Направление предков (Alice)", MYSOUND .. "RainonUI_Ancestral_Guidance.ogg" },
    { "RainonUI: Немота (Alice)", MYSOUND .. "RainonUI_Silence.ogg" },
    { "RainonUI: Ободряющий крик (Alice)", MYSOUND .. "RainonUI_Rallying_Cry.ogg" },
    { "RainonUI: Оглушение (Alice)", MYSOUND .. "RainonUI_Stun.ogg" },
    { "RainonUI: Отойди от игроков (Alice)", MYSOUND .. "RainonUI_Go_out_from_ppl.ogg" },
    { "RainonUI: Пелена (Alice)", MYSOUND .. "RainonUI_Shroud.ogg" },
    { "RainonUI: Перебей контроль (Alice)", MYSOUND .. "RainonUI_Kick_CC.ogg" },
    { "RainonUI: Перебей крик (Alice)", MYSOUND .. "RainonUI_Scream_Kick.ogg" },
    { "RainonUI: Перебей немотой (Alice)", MYSOUND .. "RainonUI_Silence_Kick.ogg" },
    { "RainonUI: Перебей оглушением (Alice)", MYSOUND .. "RainonUI_Stun_Kick.ogg" },
    { "RainonUI: Перебей страх (Alice)", MYSOUND .. "RainonUI_Fear_Kick.ogg" },
    { "RainonUI: Перебей хил (Alice)", MYSOUND .. "RainonUI_Heal_Kick.ogg" },
    { "RainonUI: Перебей щит (Alice)", MYSOUND .. "RainonUI_Shield_Kick.ogg" },
    { "RainonUI: Перебей яд (Alice)", MYSOUND .. "RainonUI_Poison_Kick.ogg" },
    { "RainonUI: Передай дебафф (Alice)", MYSOUND .. "RainonUI_Pass_it_on_Debuff.ogg" },
    { "RainonUI: Перемотка (Alice)", MYSOUND .. "RainonUI_Rewind.ogg" },
    { "RainonUI: Поглощение (Alice)", MYSOUND .. "RainonUI_Absorb.ogg" },
    { "RainonUI: Подавление боли (Alice)", MYSOUND .. "RainonUI_Pain_Suppression.ogg" },
    { "RainonUI: Поделись (Alice)", MYSOUND .. "RainonUI_Share.ogg" },
    { "RainonUI: Почта (Alice)", MYSOUND .. "RainonUI_Mail_Box.ogg" },
    { "RainonUI: Призыв (Alice)", MYSOUND .. "RainonUI_Summon.ogg" },
    { "RainonUI: Призыв аддов (Alice)", MYSOUND .. "RainonUI_Adds_Summon.ogg" },
    { "RainonUI: Провокация (Alice)", MYSOUND .. "RainonUI_Taunt.ogg" },
    { "RainonUI: Провокация (оттолкни) (Alice)", MYSOUND .. "RainonUI_Taunt_push.ogg" },
    { "RainonUI: Путин (Rainon)", MYSOUND .. "RainonUI_Putin.ogg" },
    { "RainonUI: Разбегайтесь (Alice)", MYSOUND .. "RainonUI_Runaways.ogg" },
    { "RainonUI: Развейся сам (Alice)", MYSOUND .. "RainonUI_Dispell_Yourself.ogg" },
    { "RainonUI: Раздели дебафф (Alice)", MYSOUND .. "RainonUI_Share_Debuff.ogg" },
    { "RainonUI: Разойдитесь (Alice)", MYSOUND .. "RainonUI_Spread.ogg" },
    { "RainonUI: Ремонт (Alice)", MYSOUND .. "RainonUI_Repair.ogg" },
    { "RainonUI: Ритуал призыва (Alice)", MYSOUND .. "RainonUI_Ritual_of_Summoning.ogg" },
    { "RainonUI: Рывок (Alice)", MYSOUND .. "RainonUI_Charge.ogg" },
    { "RainonUI: Сбей стрелы (Alice)", MYSOUND .. "RainonUI_Kick_Arrows.ogg" },
    { "RainonUI: Священный оплот (Alice)", MYSOUND .. "RainonUI_Holy_Bulwark.ogg" },
    { "RainonUI: Синий (Overlord)", MYSOUND .. "RainonUI_Blue.ogg" },
    { "RainonUI: Смена расы (Alice)", MYSOUND .. "RainonUI_Change_Race.ogg" },
    { "RainonUI: Смена танков (Alice)", MYSOUND .. "RainonUI_Tank_Switch.ogg" },
    { "RainonUI: Смена фазы (Alice)", MYSOUND .. "RainonUI_Phase_change.ogg" },
    { "RainonUI: Спасай Кактуса (Alice)", MYSOUND .. "RainonUI_Save_Kaktys.ogg" },
    { "RainonUI: Стаки (Alice)", MYSOUND .. "RainonUI_Stacks.ogg" },
    { "RainonUI: Стол мага (Alice)", MYSOUND .. "RainonUI_Mage_table.ogg" },
    { "RainonUI: Страх (Alice)", MYSOUND .. "RainonUI_Fear.ogg" },
    { "RainonUI: Стреляй (Alice)", MYSOUND .. "RainonUI_Shoot.ogg" },
    { "RainonUI: Сытная еда (Alice)", MYSOUND .. "RainonUI_Food_Hearty_Well_Fed.ogg" },
    { "RainonUI: Танковое комбо (Alice)", MYSOUND .. "RainonUI_Tank_Combo.ogg" },
    { "RainonUI: Тащи паука (Alice)", MYSOUND .. "RainonUI_Drag_the_Spider.ogg" },
    { "RainonUI: Толкай (Alice)", MYSOUND .. "RainonUI_Push.ogg" },
    { "RainonUI: Тотем (Alice)", MYSOUND .. "RainonUI_Totem.ogg" },
    { "RainonUI: Тотем духовной связи (Alice)", MYSOUND .. "RainonUI_Spirit_Link_Totem.ogg" },
    { "RainonUI: Тотем духовной связи (англ.) (Alice)", MYSOUND .. "RainonUI_Spirit_Link_Totem_Eng.ogg" },
    { "RainonUI: Тотем каменной кожи (Alice)", MYSOUND .. "RainonUI_Stoneskin_Totem.ogg" },
    { "RainonUI: Ты лидер группы (Alice)", MYSOUND .. "RainonUI_Lead_group.ogg" },
    { "RainonUI: Тьма (Alice)", MYSOUND .. "RainonUI_Darkness.ogg" },
    { "RainonUI: Тьма (англ.) (Alice)", MYSOUND .. "RainonUI_Darkness_Eng.ogg" },
    { "RainonUI: Убегай (Alice)", MYSOUND .. "RainonUI_Run_away.ogg" },
    { "RainonUI: Угадайка (Alice)", MYSOUND .. "RainonUI_Guessing_Game.ogg" },
    { "RainonUI: Уклоняйся (Alice)", MYSOUND .. "RainonUI_Dodge.ogg" },
    { "RainonUI: Фаза луча (Alice)", MYSOUND .. "RainonUI_Beam_Phase.ogg" },
    { "RainonUI: Фиксейт на тебе (Alice)", MYSOUND .. "RainonUI_Fixate_on_you.ogg" },
    { "RainonUI: Хватит соакать (Alice)", MYSOUND .. "RainonUI_Stop_soak.ogg" },
    { "RainonUI: Хил (Alice)", MYSOUND .. "RainonUI_Heal.ogg" },
    { "RainonUI: Щит (Alice)", MYSOUND .. "RainonUI_Shield.ogg" },
    { "RainonUI: Перерыв", SOUND.breaktimer },
    { "RainonUI: Тревога", 567397 },  -- Raid Warning
    { "RainonUI: Флаг",    569200 },  -- PVP Flag Taken
    { "RainonUI: Беги (HoodWolf)", 552035 },  -- игровой голос
}
local OUR_NAME_SET = {}
for _, s in ipairs(OUR_SOUNDS) do OUR_NAME_SET[s[1]] = true end

local _lsm, _lsmRegistered
local function GetLSM()
    if not _lsm then
        _lsm = (LibStub and LibStub("LibSharedMedia-3.0", true)) or nil
        if _lsm then
            LSM_SOUND = (_lsm.MediaType and _lsm.MediaType.SOUND) or "sound"
        end
    end
    -- Наши звуки регистрируем один раз, как только LSM есть.
    if _lsm and not _lsmRegistered then
        _lsmRegistered = true
        for _, s in ipairs(OUR_SOUNDS) do _lsm:Register(LSM_SOUND, s[1], s[2]) end
    end
    return _lsm
end

-- Полный список имён звуков для селектора: из медиатеки (наши + игровые +
-- звуки других аддонов), отсортированный. Без библиотеки — минимальный запас.
function ns.Tools.GetSoundNames()
    local LSM = GetLSM()
    if LSM then
        local list = LSM:List(LSM_SOUND) or {}
        local names = {}
        for _, n in ipairs(list) do names[#names + 1] = n end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end
    return { "RainonUI: Все готовы", "RainonUI: Лидер", "RainonUI: Призыв" }
end

-- Диагностика звука: печатает состояние медиатеки, что из аддонов загружено и
-- какие звуки реально зарегистрированы (наши / чужие / примеры имён). Помогает
-- понять, ПОЧЕМУ список короткий: не загрузилась либа? не загружен звуковой пак?
function ns.Tools.SoundDiag()
    local LSM = GetLSM()
    local names = ns.Tools.GetSoundNames() or {}
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local function ld(a) return (isLoaded and isLoaded(a)) and "да" or "нет" end

    local mine, none, foreign = 0, 0, 0
    local sample = {}
    for _, n in ipairs(names) do
        if OUR_NAME_SET[n] then mine = mine + 1
        elseif n == "None" then none = none + 1
        else foreign = foreign + 1 end
    end
    for i = 1, math.min(14, #names) do sample[i] = names[i] end

    ns.Print("|cFFFFD100=== Диагностика звука ===|r")
    ns.Print("LibSharedMedia: " .. (LSM and "ЕСТЬ" or "НЕТ") .. "  |  всего звуков: " .. #names)
    ns.Print(("наши=%d, None=%d, ЧУЖИХ (паки/аддоны)=%d"):format(mine, none, foreign))
    ns.Print("Загружено — BigWigs: " .. ld("BigWigs") .. ", DBM-Core: " .. ld("DBM-Core") ..
        ", SharedMedia: " .. ld("SharedMedia"))
    ns.Print("Примеры: " .. (table.concat(sample, ", ")))
    if foreign == 0 then
        ns.Print("|cFFFF5555Чужих звуков 0 — значит звуковой пак сейчас НЕ загружен/не зарегистрировал звуки. Это не RainonUI: любой аддон-пак пишет в ту же медиатеку, мы просто читаем её.|r")
    end
end

SLASH_RAINONSOUND1 = "/rssound"
SlashCmdList.RAINONSOUND = function() ns.Tools.SoundDiag() end

-- Имя по умолчанию: сначала «Boss Warning» (точное совпадение, затем частичное
-- без учёта регистра — имена в голосовых паках бывают с префиксами/суффиксами),
-- потом наш голос, иначе первый не-"None".
function ns.Tools.DefaultSoundName()
    local names = ns.Tools.GetSoundNames()
    for _, n in ipairs(names) do if n == "Boss Warning" then return n end end
    for _, n in ipairs(names) do if n:lower():find("boss warning", 1, true) then return n end end
    for _, n in ipairs(names) do if n == "RainonUI: Все готовы (Alice)" then return n end end
    for _, n in ipairs(names) do if n ~= "None" then return n end end
    return names[1] or "None"
end

-- Текущее выбранное имя по ключу (миграция со старого числового индекса +
-- фолбэк на дефолт, если имя пропало из медиатеки).
local function CurrentNameForKey(key)
    local f = ns.db and ns.db.features
    local v = f and f[key]
    if type(v) == "string" and v ~= "" then return v end
    local def = ns.Tools.DefaultSoundName()
    if f then f[key] = def end
    return def
end
-- Звук «меня воскресили».
function ns.Tools.CurrentSoundName() return CurrentNameForKey("resurrectSound") end

local function PlaySoundByName(name)
    local LSM = GetLSM()
    if not (name and LSM) then return end
    local media = LSM:Fetch(LSM_SOUND, name, true) -- true = без дефолта
    if media then pcall(PlaySoundFile, media, "Master") end -- принимает путь и FileDataID
end
ns.Tools.PlaySoundByName = PlaySoundByName

-- Предпросмотр для селектора.
ns.Tools.PlayResurrectPreview = function() PlaySoundByName(ns.Tools.CurrentSoundName()) end

-- Когда воскрешают ТЕБЯ — окно «Воскреснуть».
ns.RegisterEvent("RESURRECT_REQUEST", function()
    if ns.db and ns.db.features and ns.db.features.resurrectSoundOn then
        PlaySoundByName(ns.Tools.CurrentSoundName())
    end
end)

-- =========================================================================
-- АРХИВ (2026): «Звук воскрешения союзника» (resCast) убран. В рейде эти события
-- (UNIT_SPELLCAST_SUCCEEDED по спеллам воскрешения) не ловятся, поэтому фича не
-- работала. Список спеллов и обработчик — в истории git. Вернёмся к ним позже.
-- =========================================================================