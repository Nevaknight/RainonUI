-- =========================================================================
-- RainonUI / KeyReroll (ЭКСПЕРИМЕНТАЛЬНЫЙ, тестовый модуль).
-- «Напоминание: сменить ключ?» + окно голосования «Нужно / Не нужно» для
-- реролла ключей. Независимы от BigWigs: свой ключ читаем сами, чужие —
-- через LibKeystone (встроена в наши Libs), голоса реролла — свой аддон-канал.
--
-- Фича 1 — напоминание после ключа (двигаемый экранный текст, EditMode):
--   пройден В ТАЙМ и свой новый ключ ≤ пройденного уровня → «Сменить ключ: …».
-- Фича 2 — «Этот ключ не нужен группе!»: если подземелье твоего нового ключа
--   в общем голосовании помечено «не нужно» (никто не за И есть «против»).
-- Окно «Нужно / Не нужно»: владельцы аддона голосуют по подземельям сезона,
--   выбор хранится ДО дневного сброса (07:00 МСК) и рассылается группе.
-- =========================================================================
local _, ns = ...

ns.KeyReroll = ns.KeyReroll or {}
local KR = ns.KeyReroll

local PREFIX = "RainonUIRR"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local MY_NAME = UnitName("player")

-- «Игровой день» с границей 07:00 МСК (= 04:00 UTC).
local function DayId()
    local t = (GetServerTime and GetServerTime()) or time()
    return math.floor((t - 4 * 3600) / 86400)
end

-- -------------------------------------------------------------------------
-- Хранилище голосов
-- -------------------------------------------------------------------------
-- Своё (в БД, до сброса): ns.db.features.rerollMarks = { day, marks[mapID]="need"/"skip" }
local function MyStore()
    local f = ns.db and ns.db.features
    if not f then return { day = DayId(), marks = {} } end
    if not f.rerollMarks or f.rerollMarks.day ~= DayId() then
        f.rerollMarks = { day = DayId(), marks = {} }
    end
    return f.rerollMarks
end

-- Чужое (память сессии): peers[name] = { day, marks }
local peers = {}

local function Tally(mapID)
    local need, skip = 0, 0
    local function acc(store)
        if not store or store.day ~= DayId() then return end
        local m = store.marks[mapID]
        if m == "need" then need = need + 1 elseif m == "skip" then skip = skip + 1 end
    end
    acc(MyStore())
    for _, p in pairs(peers) do acc(p) end
    return need, skip
end

-- «Не нужен группе» = никто не «за» И есть хотя бы один «против».
local function NotNeeded(mapID)
    local need, skip = Tally(mapID)
    return need == 0 and skip >= 1
end

-- Имя игрока в цвете класса (перебор группы).
local function ClassColorName(name)
    local cf
    if name == MY_NAME then
        cf = select(2, UnitClass("player"))
    elseif ns.IterateGroup then
        for unit in ns.IterateGroup() do
            if UnitName(unit) == name then cf = select(2, UnitClass(unit)); break end
        end
    end
    local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    if c then return "|c" .. c.colorStr .. name .. "|r" end
    return name
end

-- Имена всех в группе (включая себя).
local function GroupNames()
    local out = {}
    if ns.IterateGroup then
        for unit in ns.IterateGroup() do
            local n = UnitName(unit)
            if n then out[n] = true end
        end
    end
    out[MY_NAME] = true
    return out
end

local function StoreFor(name)
    return (name == MY_NAME) and MyStore() or peers[name]
end

-- Списки проголосовавших по подземелью: «нужно» / «не нужно» (в цвете класса).
local function VotersReroll(mapID)
    local need, skip = {}, {}
    local function acc(name)
        local s = StoreFor(name)
        if not s or s.day ~= DayId() then return end
        local m = s.marks[mapID]
        if m == "need" then need[#need + 1] = ClassColorName(name)
        elseif m == "skip" then skip[#skip + 1] = ClassColorName(name) end
    end
    local seen = {}
    acc(MY_NAME); seen[MY_NAME] = true
    for name in pairs(peers) do if not seen[name] then acc(name); seen[name] = true end end
    table.sort(need); table.sort(skip)
    return need, skip
end

-- Кто ещё не отметил это подземелье (ни «нужно», ни «не нужно») — «Думают».
local function ThinkingReroll(mapID)
    local out = {}
    for name in pairs(GroupNames()) do
        local s = StoreFor(name)
        if not (s and s.day == DayId() and s.marks[mapID] ~= nil) then
            out[#out + 1] = ClassColorName(name)
        end
    end
    table.sort(out)
    return out
end

-- -------------------------------------------------------------------------
-- Обмен (наш канал)
-- -------------------------------------------------------------------------
local function Send(msg)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
    end
end

local function Serialize(s)
    local parts = {}
    for map, k in pairs(s.marks) do parts[#parts + 1] = map .. ":" .. (k == "need" and "n" or "s") end
    return s.day .. ";" .. table.concat(parts, ",")
end
local function Parse(payload)
    local day, rest = payload:match("^(%d+);(.*)$")
    local s = { day = tonumber(day), marks = {} }
    for tok in (rest or ""):gmatch("[^,]+") do
        local m, k = tok:match("^(%d+):([ns])$")
        if m then s.marks[tonumber(m)] = (k == "n" and "need" or "skip") end
    end
    return s
end

local function Broadcast() Send("M:" .. Serialize(MyStore())) end

-- -------------------------------------------------------------------------
-- Подземелья сезона
-- -------------------------------------------------------------------------
local function DungeonInfo(mapID)
    local name, tex
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local n, _, _, t = C_ChallengeMode.GetMapUIInfo(mapID)
        name, tex = n, t
    end
    return name or ("Подземелье " .. tostring(mapID)), tex or 134400
end

local function SeasonMaps()
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local t = C_ChallengeMode.GetMapTable()
        if type(t) == "table" then return t end
    end
    return {}
end

-- -------------------------------------------------------------------------
-- Двигаемый экранный текст (EditMode)
-- -------------------------------------------------------------------------
local overlay
local OV_TITLEH, OV_PADX, OV_PADY = 22, 18, 12  -- плашка заголовка / поля текста

-- Размер под текст (полупрозрачная плашка + текст, заголовок пустой + крестик).
local function SizeOverlay()
    local w = math.max(240, math.ceil(overlay.Text:GetStringWidth()) + OV_PADX * 2)
    local h = OV_TITLEH + math.ceil(overlay.Text:GetStringHeight()) + OV_PADY * 2
    overlay:SetSize(w, h)
end

local function BuildOverlay()
    if overlay then return overlay end
    -- Тот же стиль, что и главное окно аддона: DefaultPanelFlatTemplate
    -- (полупрозрачная плашка Blizzard). Заголовок пустой, но с крестиком.
    overlay = CreateFrame("Frame", "RainonUIKeyRerollMsg", UIParent, "DefaultPanelFlatTemplate")
    overlay:SetSize(300, 60)
    overlay:SetFrameStrata("HIGH")
    if overlay.SetTitle then overlay:SetTitle("") end

    local close = CreateFrame("Button", nil, overlay, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() overlay:Hide() end)

    local fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOP", overlay, "TOP", 0, -(OV_TITLEH + 4))
    fs:SetJustifyH("CENTER")
    overlay.Text = fs

    if ns.EditMode and ns.EditMode.Register then
        ns.EditMode.Register(overlay, {
            name = "Напоминание о ключе", key = "keyreroll",
            defaultX = 0, defaultY = -140, showInEditMode = true,
            onEditModeShow = function(f)
                f.Text:SetText(ns.C("FFD100", "Напоминание о ключе"))
                SizeOverlay()
            end,
        })
    end
    overlay:Hide()
    return overlay
end
ns.RegisterMessage("RAINON_DB_READY", BuildOverlay)

function KR.ShowMessage(text, seconds)
    BuildOverlay()
    overlay.Text:SetText(text)
    SizeOverlay()
    overlay:Show()
    overlay:Raise()
    if overlay._t then overlay._t:Cancel() end
    overlay._t = C_Timer.NewTimer(seconds or 10, function() overlay:Hide() end)
end

-- -------------------------------------------------------------------------
-- Логика после завершения ключа
-- -------------------------------------------------------------------------
local completion

-- Новый ключ прилетает не сразу после `CHALLENGE_MODE_COMPLETED` (API пустой,
-- предмет появляется чуть позже). Раньше был один таймер 1.5с — он часто не
-- успевал, и окно «Смени ключ» не показывалось. Ловим момент получения ключа
-- ТАК ЖЕ, как это делают BigWigs/LibKeystone: слушаем `ITEM_CHANGED`/`ITEM_PUSH`
-- (обмен ключа у НПЦ / выпадение из сундука) + держим несколько ретраев по
-- таймеру. Как только ключ прочитался — перепроверяем и снимаем слежку.
local keyWatch = CreateFrame("Frame")
local function WatchKey(on)
    if on then
        keyWatch:RegisterEvent("ITEM_CHANGED")
        keyWatch:RegisterEvent("ITEM_PUSH")
        keyWatch:RegisterEvent("PLAYER_LEAVING_WORLD")
    else
        keyWatch:UnregisterAllEvents()
    end
end
KR.WatchKey = WatchKey
keyWatch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then WatchKey(false); return end
    C_Timer.After(1, function() KR.CheckAfterRun() end)  -- дать API обновиться
end)

local function ScheduleKeyCheck()
    for _, d in ipairs({ 1.5, 3, 5, 8 }) do C_Timer.After(d, KR.CheckAfterRun) end
end

ns.RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
    if not (ns.db and ns.db.features and ns.db.features.keyReroll) then return end
    local level, onTime
    pcall(function()
        local _, lvl, _, ot = C_ChallengeMode.GetCompletionInfo()
        level, onTime = lvl, ot
    end)
    completion = { level = level, onTime = onTime }
    WatchKey(true)       -- слушаем получение нового ключа (как BigWigs/LibKeystone)
    ScheduleKeyCheck()   -- + ретраи по таймеру
end)

-- Скан сумок на эпохальный ключ (как в BigWigs): C_Container + IsItemKeystoneByID,
-- уровень/подземелье из itemLink (поля 4/5). Возвращает level, mapID.
local function ScanBagKeystone()
    local getSlots = C_Container and C_Container.GetContainerNumSlots
    local getID    = C_Container and C_Container.GetContainerItemID
    local getLink  = C_Container and C_Container.GetContainerItemLink
    local isKey    = C_Item and C_Item.IsItemKeystoneByID
    if not (getSlots and getID and getLink and isKey) then return end
    for bag = 0, 4 do
        local slots = getSlots(bag) or 0
        for slot = 1, slots do
            local itemID = getID(bag, slot)
            if itemID and isKey(itemID) then
                local link = getLink(bag, slot)
                if type(link) == "string" then
                    local _, _, _, m, l = strsplit(":", link)
                    m, l = tonumber(m), tonumber(l)
                    if m and l then return l, m end
                end
            end
        end
    end
end
KR.ScanBagKeystone = ScanBagKeystone

-- Свой ключ: сначала API, если пусто — скан сумки (API иногда пустой сразу
-- после прохождения).
local function ReadOwnedKeystone()
    local lvl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    local map = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if type(lvl) == "number" and type(map) == "number" and lvl > 0 and map > 0 then
        return lvl, map
    end
    return ScanBagKeystone()
end
KR.ReadOwnedKeystone = ReadOwnedKeystone

function KR.CheckAfterRun()
    if not (ns.db and ns.db.features and ns.db.features.keyReroll) then return end
    local lvl, map = ReadOwnedKeystone()
    if type(lvl) ~= "number" or type(map) ~= "number" or lvl <= 0 or map <= 0 then
        return  -- ключ ещё не прочитался → ждём следующий ITEM_*-триггер / ретрай
    end
    WatchKey(false)  -- ключ есть — решение принимаем сейчас, слежку снимаем

    -- Условие 1: пройдено В ТАЙМ и свой ключ в сумках ≤ уровня пройденного.
    if not (completion and completion.onTime) then return end
    if type(completion.level) ~= "number" or lvl > completion.level then return end

    local lines = {}
    local name = DungeonInfo(map)
    lines[#lines + 1] = ns.C("FFD100", "Можешь сменить ключ: ") ..
        name .. " " .. ns.C("FFD100", "+" .. lvl)
    -- Условие 2 (отдельно): есть опросник и ключ не нужен → дописываем.
    if NotNeeded(map) then
        lines[#lines + 1] = ns.C("FF5555", "Этот ключ не нужен группе!")
    end
    KR.ShowMessage(table.concat(lines, "\n"), 12)
end

-- -------------------------------------------------------------------------
-- Окно «Нужно / Не нужно»
-- -------------------------------------------------------------------------
local WIN_W, PAD, ROW_H, ICON = 440, 14, 32, 24
local TITLEBAR, BOTTOM_PAD, HINT_H, INSET_TOPPAD = 24, 40, 28, 8
local win, wrows

local function SetMark(mapID, kind)
    local s = MyStore()
    if s.marks[mapID] == kind then s.marks[mapID] = nil else s.marks[mapID] = kind end
    Broadcast()
    KR.RebuildWindow()
end
KR.SetMark = SetMark

-- Подсказка «кто голосовал» при наведении на кнопку «Нужно»/«Не нужно» (по
-- аналогии с окном «Опрос ключей»): показываем проголосовавших + кого ждём.
local function ShowVotersTip(anchor, mapID, which)
    local need, skip = VotersReroll(mapID)
    local think = ThinkingReroll(mapID)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:AddLine((DungeonInfo(mapID)))
    if which == "need" then
        GameTooltip:AddLine("Нужно: " .. (#need > 0 and table.concat(need, ", ") or "—"),
            0.25, 0.85, 0.25, true)
    else
        GameTooltip:AddLine("Не нужно: " .. (#skip > 0 and table.concat(skip, ", ") or "—"),
            1, 0.33, 0.33, true)
    end
    if #think > 0 then
        GameTooltip:AddLine("Думают: " .. table.concat(think, ", "), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function BuildWindow()
    if win then return win end
    win = CreateFrame("Frame", "RainonUIKeyRerollVote", UIParent, "ButtonFrameTemplate")
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    table.insert(UISpecialFrames, "RainonUIKeyRerollVote")

    if win.SetTitle then pcall(win.SetTitle, win, "Реролл: Нужно / Не нужно") end
    local titleFS = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
    if titleFS then
        titleFS:SetText("Реролл: Нужно / Не нужно")
        titleFS:ClearAllPoints(); titleFS:SetPoint("TOP", win, "TOP", 0, -6); titleFS:SetJustifyH("CENTER")
    end
    pcall(function()
        local p = win.PortraitContainer and win.PortraitContainer.portrait or win.portrait
        if p then p:SetTexture(525134); p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    local maps = SeasonMaps()
    local hintTop = TITLEBAR + 6
    local insetTopY = -(hintTop + HINT_H + 6)
    local n = math.max(1, #maps)
    win:SetSize(WIN_W, (hintTop + HINT_H + 6) + (INSET_TOPPAD + n * ROW_H + 10) + BOTTOM_PAD)

    win.Hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.Hint:SetPoint("TOPLEFT", win, "TOPLEFT", 64, -hintTop)
    win.Hint:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -hintTop)
    win.Hint:SetJustifyH("LEFT")
    win.Hint:SetText("Отметь подземелья: " .. ns.C("40D040", "Нужно") .. " / " ..
        ns.C("FF5555", "Не нужно") .. ". Хранится до сброса (07:00 МСК).")

    local host = win.Inset or win
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, insetTopY)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, BOTTOM_PAD)
    end

    wrows = {}
    for i, mapID in ipairs(maps) do
        local r = CreateFrame("Frame", nil, host)
        r:SetHeight(ROW_H)
        local yy = -INSET_TOPPAD - (i - 1) * ROW_H
        r:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, yy)
        r:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, yy)
        r.mapID = mapID

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ICON, ICON); r.icon:SetPoint("LEFT", 0, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name, tex = DungeonInfo(mapID)
        r.icon:SetTexture(tex)

        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetWidth(150); r.name:SetJustifyH("LEFT"); r.name:SetText(name)

        r.aggr = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.aggr:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.aggr:SetJustifyH("LEFT")

        r.no = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.no:SetSize(84, 22); r.no:SetPoint("RIGHT", 0, 0); r.no:SetText("Не нужно")
        r.no:SetScript("OnClick", function() SetMark(mapID, "skip") end)
        r.no:HookScript("OnEnter", function(self) ShowVotersTip(self, mapID, "skip") end)
        r.no:HookScript("OnLeave", function() GameTooltip:Hide() end)

        r.yes = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.yes:SetSize(72, 22); r.yes:SetPoint("RIGHT", r.no, "LEFT", -6, 0); r.yes:SetText("Нужно")
        r.yes:SetScript("OnClick", function() SetMark(mapID, "need") end)
        r.yes:HookScript("OnEnter", function(self) ShowVotersTip(self, mapID, "need") end)
        r.yes:HookScript("OnLeave", function() GameTooltip:Hide() end)

        wrows[i] = r
    end

    -- Кнопка «Опрос» — открыть это окно у остальных игроков группы.
    local pollBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    pollBtn:SetSize(160, 24)
    pollBtn:SetText("Опрос")
    pollBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, (BOTTOM_PAD - 24) / 2)
    pollBtn:SetScript("OnClick", function() KR.StartPoll() end)
    win.PollBtn = pollBtn

    win:Hide()
    return win
end

function KR.RebuildWindow()
    if not win or not win:IsShown() or not wrows then return end
    local s = MyStore()
    for _, r in ipairs(wrows) do
        local m = s.marks[r.mapID]
        if m == "need" then r.yes:LockHighlight() else r.yes:UnlockHighlight() end
        if m == "skip" then r.no:LockHighlight() else r.no:UnlockHighlight() end
        local need, skip = Tally(r.mapID)
        if NotNeeded(r.mapID) then
            r.aggr:SetText(ns.C("FF5555", "не нужен"))
        elseif need > 0 then
            r.aggr:SetText(ns.C("40D040", "нужен " .. need))
        else
            r.aggr:SetText("")
        end
    end
end

function KR.ShowWindow()
    BuildWindow()
    win:Show(); win:Raise()
    Send("R:")       -- попросить у группы их голоса (было "R" без ":" — не парсилось)
    Broadcast()      -- и отдать свои
    KR.RebuildWindow()
end
function KR.ToggleWindow()
    BuildWindow()
    if win:IsShown() then win:Hide() else KR.ShowWindow() end
end

-- «Опрос»: открыть окно у остальных в группе + собрать их голоса.
function KR.StartPoll()
    KR.ShowWindow()
    Send("O:")       -- получатели с включённым модулем откроют окно у себя
    Send("R:")       -- и попросим их голоса
    Broadcast()      -- отдадим свои
end

-- -------------------------------------------------------------------------
-- Приём голосов группы
-- -------------------------------------------------------------------------
ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= PREFIX then return end
    local short = sender and Ambiguate(sender, "short") or sender
    if short == MY_NAME then return end
    local kind, payload = msg:match("^(%a):(.*)$")
    if kind == "M" then
        peers[short] = Parse(payload)
        KR.RebuildWindow()
    elseif kind == "R" then
        Broadcast()
    elseif kind == "O" then
        -- ведущий просит открыть окно у нас (гейт по включённому модулю)
        if ns.db and ns.db.features and ns.db.features.keyReroll then KR.ShowWindow() end
    end
end)

-- -------------------------------------------------------------------------
-- Слэши + тестер
-- -------------------------------------------------------------------------
SLASH_RAINONREROLL1 = "/rsreroll"
SlashCmdList.RAINONREROLL = function() KR.ToggleWindow() end

if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Подземелья", "Сообщение: сменить ключ", function()
        KR.ShowMessage(ns.C("FFD100", "Сменить ключ: ") .. "Тестовое +10\n" ..
            ns.C("FF5555", "Этот ключ не нужен группе!"), 8)
    end)
    ns.Tester.Add("Подземелья", "Окно реролла ключей", function() KR.ShowWindow() end)
    -- Проверка чтения ключа из сумки: печатаем оба способа (API и скан сумки)
    -- и показываем результат на экране.
    ns.Tester.Add("Подземелья", "Ключ в сумке", function()
        local apiL = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local apiM = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local bagL, bagM = ScanBagKeystone()
        ns.Print("Ключ (API): уровень " .. tostring(apiL) .. ", map " .. tostring(apiM))
        ns.Print("Ключ (сумка): уровень " .. tostring(bagL) .. ", map " .. tostring(bagM))
        local L, M = ReadOwnedKeystone()
        if L and M then
            KR.ShowMessage(ns.C("FFD100", "Твой ключ: ") .. DungeonInfo(M) ..
                " " .. ns.C("FFD100", "+" .. L), 8)
        else
            KR.ShowMessage(ns.C("FF5555", "Ключ в сумке не найден"), 6)
        end
    end)
end
