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
ns.RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
    if not (ns.db and ns.db.features and ns.db.features.keyReroll) then return end
    local level, onTime
    pcall(function()
        local _, lvl, _, ot = C_ChallengeMode.GetCompletionInfo()
        level, onTime = lvl, ot
    end)
    completion = { level = level, onTime = onTime }
    -- ключ в сумках обновляется чуть позже
    C_Timer.After(1.5, KR.CheckAfterRun)
end)

function KR.CheckAfterRun()
    if not (ns.db and ns.db.features and ns.db.features.keyReroll) then return end
    local lvl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    local map = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if type(lvl) ~= "number" or type(map) ~= "number" or lvl <= 0 or map <= 0 then return end

    local lines = {}
    if completion and completion.onTime and type(completion.level) == "number" and lvl <= completion.level then
        local name = DungeonInfo(map)
        lines[#lines + 1] = ns.C("FFD100", "Сменить ключ: ") .. name .. " " .. ns.C("FFD100", "+" .. lvl)
    end
    if NotNeeded(map) then
        lines[#lines + 1] = ns.C("FF5555", "Этот ключ не нужен группе!")
    end
    if #lines > 0 then KR.ShowMessage(table.concat(lines, "\n"), 12) end
end

-- -------------------------------------------------------------------------
-- Окно «Нужно / Не нужно»
-- -------------------------------------------------------------------------
local WIN_W, PAD, ROW_H, ICON = 440, 14, 32, 24
local TITLEBAR, BOTTOM_PAD, HINT_H, INSET_TOPPAD = 24, 12, 28, 8
local win, wrows

local function SetMark(mapID, kind)
    local s = MyStore()
    if s.marks[mapID] == kind then s.marks[mapID] = nil else s.marks[mapID] = kind end
    Broadcast()
    KR.RebuildWindow()
end
KR.SetMark = SetMark

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

        r.yes = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.yes:SetSize(72, 22); r.yes:SetPoint("RIGHT", r.no, "LEFT", -6, 0); r.yes:SetText("Нужно")
        r.yes:SetScript("OnClick", function() SetMark(mapID, "need") end)

        wrows[i] = r
    end

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
    Send("R")        -- попросить у группы их голоса
    Broadcast()      -- и отдать свои
    KR.RebuildWindow()
end
function KR.ToggleWindow()
    BuildWindow()
    if win:IsShown() then win:Hide() else KR.ShowWindow() end
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
end
