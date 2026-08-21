-- =========================================================================
-- RainonUI / KeystonePoll (ЭКСПЕРИМЕНТАЛЬНЫЙ, тестовый модуль).
-- Опросник по эпохальным ключам группы.
--
-- Как работает:
--   • Ключи группы берём через LibKeystone (её тянет BigWigs; свою копию тоже
--     кладём в Libs). Любой в группе с LibKeystone отвечает своим ключом.
--   • Кнопка «Опрос» — рассылаем список ключей-кандидатов группе НАШИМ каналом.
--     У всех с RainonUI окно авто-открывается (только с кнопкой «Пофиг»).
--   • Голос по каждому ключу: ЛКМ — «за» (зелёная галка), ПКМ — «против»
--     (красный крест). Можно отметить несколько ключей. «Пофиг» — согласен на
--     любой (кроме тех, что явно перечеркнул). Голоса летят в PARTY — все видят
--     живой подсчёт «за».
--   • Пока окно открыто — слушаем ключи и обновляем строки; закрыли —
--     LibKeystone отписываем, модуль спит. Слушатель сообщений всегда активен.
--
-- Окно и 5 строк создаём ОДИН раз (в группе максимум 5 ключей).
-- =========================================================================
local _, ns = ...

ns.KeystonePoll = ns.KeystonePoll or {}
local KP = ns.KeystonePoll

local POLL_PREFIX = "RainonUIKP"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(POLL_PREFIX)
end

local LKS = LibStub and LibStub("LibKeystone", true)

-- Состояние ---------------------------------------------------------------
-- votes[player] = { any = bool, picks = { [mapID] = "y" | "n" } }
local keys   = {}
local votes  = {}
local active = false
local win

local MY_NAME = UnitName("player")

-- Голос «за» по ключу: явная галка ИЛИ «Пофиг» и не перечёркнут.
local function IsYes(v, mapID)
    if not v then return false end
    if v.picks and v.picks[mapID] == "y" then return true end
    if v.any and not (v.picks and v.picks[mapID] == "n") then return true end
    return false
end
local function IsNo(v, mapID)
    return v and v.picks and v.picks[mapID] == "n" or false
end

-- Помощники ---------------------------------------------------------------
local function DungeonName(mapID)
    local name, tex
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local n, _, _, t = C_ChallengeMode.GetMapUIInfo(mapID)
        name, tex = n, t
    end
    return name or ("Подземелье " .. tostring(mapID)), tex or 134400
end

-- Класс игрока по имени (перебор группы) → имя, окрашенное в цвет класса.
local function ClassColorName(name)
    local cf
    if name == MY_NAME then
        cf = select(2, UnitClass("player"))
    elseif ns.IterateGroup then
        for unit in ns.IterateGroup() do
            local un = UnitName(unit)
            if un == name then cf = select(2, UnitClass(unit)); break end
        end
    end
    local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    if c then return "|c" .. c.colorStr .. name .. "|r" end
    return name
end

-- Кандидаты: по одному на подземелье (mapID), наивысший уровень.
local function BuildCandidates()
    local byMap = {}
    for owner, k in pairs(keys) do
        local c = byMap[k.mapID]
        if not c or k.level > c.level then
            byMap[k.mapID] = { mapID = k.mapID, level = k.level, owner = owner }
        end
    end
    local list = {}
    for _, c in pairs(byMap) do list[#list + 1] = c end
    table.sort(list, function(a, b) return a.level > b.level end)
    return list
end

-- Число голосов «за» / «против» подземелье.
local function CountYes(mapID)
    local n = 0
    for _, v in pairs(votes) do if IsYes(v, mapID) then n = n + 1 end end
    return n
end
local function CountNo(mapID)
    local n = 0
    for _, v in pairs(votes) do if IsNo(v, mapID) then n = n + 1 end end
    return n
end

-- Списки «за» и «против» (имена в цвете класса) — для подсказки на цифре.
local function VotersFor(mapID)
    local yes, no = {}, {}
    for name, v in pairs(votes) do
        if IsNo(v, mapID) then no[#no + 1] = ClassColorName(name)
        elseif IsYes(v, mapID) then yes[#yes + 1] = ClassColorName(name) end
    end
    table.sort(yes); table.sort(no)
    return yes, no
end

-- (Де)сериализация моего голоса: "*;map:y,map:n" (звёздочка = «Пофиг»).
local function Serialize(v)
    local parts = {}
    for map, k in pairs(v.picks or {}) do parts[#parts + 1] = map .. ":" .. k end
    return (v.any and "*" or "") .. ";" .. table.concat(parts, ",")
end
local function Parse(payload)
    local star, rest = payload:match("^(%*?);(.*)$")
    local v = { any = star == "*", picks = {} }
    for tok in (rest or ""):gmatch("[^,]+") do
        local m, k = tok:match("^(%d+):([yn])$")
        if m then v.picks[tonumber(m)] = k end
    end
    return v
end

-- Рассылка нашим каналом (в группе).
local function Send(msg)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, POLL_PREFIX, msg, channel)
    end
end

-- -------------------------------------------------------------------------
-- Окно (ButtonFrameTemplate). Геометрия ФИКСИРОВАННАЯ: 5 строк.
-- -------------------------------------------------------------------------
local WIN_W  = 380
local PAD    = 14
local ROW_H  = 34
local ICON   = 28
local TITLEBAR   = 24
local BOTTOM_BAR = 40
local HINT_H     = 30
local INSET_TOPPAD = 10
local MAX_ROWS   = 5

local rows = {}
local Rebuild  -- fwd

local function MakeRow(host, i)
    local r = CreateFrame("Button", nil, host)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- отметка «мой голос»: зелёная галка (за) / красный крест (против)
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetSize(20, 20)
    r.mark:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.mark:Hide()

    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 28, 0)
    r.label:SetJustifyH("LEFT")

    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.count:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.count:SetJustifyH("RIGHT")

    -- зона наведения на цифру → подсказка со списком голосовавших
    r.countHover = CreateFrame("Frame", nil, r)
    r.countHover:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.countHover:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.countHover:SetWidth(56)
    r.countHover:EnableMouse(true)
    r.countHover:SetScript("OnEnter", function(self)
        if not r.mapID then return end
        local yes, no = VotersFor(r.mapID)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((select(1, DungeonName(r.mapID))))
        if #yes == 0 and #no == 0 then
            GameTooltip:AddLine("Никто не голосовал", 0.7, 0.7, 0.7)
        else
            if #yes > 0 then GameTooltip:AddLine("За: " .. table.concat(yes, ", "), 0.2, 1, 0.2, true) end
            if #no > 0 then GameTooltip:AddLine("Против: " .. table.concat(no, ", "), 1, 0.3, 0.3, true) end
        end
        GameTooltip:Show()
    end)
    r.countHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnClick", function(self, button)
        if not self.mapID then return end
        KP.Mark(self.mapID, button == "RightButton" and "n" or "y")
    end)
    r:Hide()
    return r
end

local function UpdateButtons()
    if not win then return end
    local by = (BOTTOM_BAR - 24) / 2
    if win.isReceiver then
        -- получателю кнопку «Опрос» не показываем — только «Пофиг» по центру.
        win.PollBtn:Hide()
        win.AnyBtn:ClearAllPoints()
        win.AnyBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, by)
    else
        win.PollBtn:Show()
        win.PollBtn:ClearAllPoints()
        win.PollBtn:SetPoint("BOTTOMLEFT", win, "BOTTOM", 4, by)
        win.AnyBtn:ClearAllPoints()
        win.AnyBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOM", -4, by)
    end
end

local function BuildWindow()
    if win then return win end
    win = CreateFrame("Frame", "RainonUIKeystonePoll", UIParent, "ButtonFrameTemplate")
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    table.insert(UISpecialFrames, "RainonUIKeystonePoll")

    if win.SetTitle then pcall(win.SetTitle, win, "Опрос ключей") end
    local titleFS = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
    if titleFS then
        titleFS:SetText("Опрос ключей")
        titleFS:ClearAllPoints()
        titleFS:SetPoint("TOP", win, "TOP", 0, -6)
        titleFS:SetJustifyH("CENTER")
    end

    pcall(function()
        local p = win.PortraitContainer and win.PortraitContainer.portrait or win.portrait
        if p then p:SetTexture(525134); p:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)

    local hintTop   = TITLEBAR + 6
    local insetTopY = -(hintTop + HINT_H + 6)
    win:SetSize(WIN_W, (hintTop + HINT_H + 6) + (INSET_TOPPAD + MAX_ROWS * ROW_H + 10) + BOTTOM_BAR)

    win.Hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.Hint:SetPoint("TOPLEFT", win, "TOPLEFT", 64, -hintTop)
    win.Hint:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -hintTop)
    win.Hint:SetJustifyH("LEFT")

    local host = win.Inset or win
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, insetTopY)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, BOTTOM_BAR)
    end

    for i = 1, MAX_ROWS do
        local r = MakeRow(host, i)
        r:ClearAllPoints()
        local yy = -INSET_TOPPAD - (i - 1) * ROW_H
        r:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, yy)
        r:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, yy)
        rows[i] = r
    end

    local pollBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    pollBtn:SetSize(150, 24)
    pollBtn:SetText("Опрос")
    pollBtn:SetScript("OnClick", function() KP.StartPoll() end)
    win.PollBtn = pollBtn

    local anyBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    anyBtn:SetSize(150, 24)
    anyBtn:SetText("Пофиг")
    anyBtn:SetScript("OnClick", function() KP.Any() end)
    win.AnyBtn = anyBtn

    win:SetScript("OnShow", function() KP.OnShow() end)
    win:SetScript("OnHide", function() KP.OnHide() end)

    win:Hide()
    return win
end

-- Обновить СОДЕРЖИМОЕ строк (геометрию не трогаем).
function Rebuild()
    if not win or not win:IsShown() then return end
    local cands = BuildCandidates()
    local mine = votes[MY_NAME]

    if #cands == 0 then
        win.Hint:SetText("Ключей в группе не видно. " ..
            (win.isReceiver and "Ждём ведущего." or ("Жми " .. ns.C("FFD100", "«Опрос»") ..
            " — нужен BigWigs/RainonUI у игроков.")))
    else
        win.Hint:SetText(ns.C("FFD100", "ЛКМ") .. " — за, " .. ns.C("FFD100", "ПКМ") ..
            " — против. Можно несколько. Наведи на цифру — кто голосовал.")
    end

    -- подсветка «Пофиг», если включён
    win.AnyBtn:SetText(mine and mine.any and "Пофиг ✓" or "Пофиг")

    for i = 1, MAX_ROWS do
        local r = rows[i]
        local c = cands[i]
        if c then
            local name, tex = DungeonName(c.mapID)
            r.icon:SetTexture(tex)
            r.mapID = c.mapID
            r.label:SetText(name .. "  " .. ns.C("FFD100", "+" .. c.level))
            -- Итог = «за» минус «против». Отрицательный — красным (с минусом),
            -- положительный — зелёным, ноль — серым.
            local net = CountYes(c.mapID) - CountNo(c.mapID)
            r.count:SetText(tostring(net))
            if net < 0 then r.count:SetTextColor(1, 0.25, 0.25)
            elseif net > 0 then r.count:SetTextColor(0.2, 1, 0.2)
            else r.count:SetTextColor(0.8, 0.8, 0.8) end
            if IsNo(mine, c.mapID) then
                r.mark:SetAtlas("common-icon-redx"); r.mark:Show()
            elseif IsYes(mine, c.mapID) then
                r.mark:SetAtlas("common-icon-checkmark"); r.mark:Show()
            else
                r.mark:Hide()
            end
            r:Show()
        else
            r.mapID = nil
            r:Hide()
        end
    end
end
KP.Rebuild = Rebuild

-- -------------------------------------------------------------------------
-- Сбор ключей (LibKeystone) — только пока окно открыто
-- -------------------------------------------------------------------------
local lksToken = {}
local function OnKeystone(level, mapID, rating, name, channel)
    if not active then return end
    -- Только ГРУППА: LibKeystone шлёт ещё и по гильдии (channel=="GUILD"),
    -- поэтому берём только party-ответы (иначе ловим чужие ключи вне группы).
    if channel ~= "PARTY" then return end
    if type(level) ~= "number" or type(mapID) ~= "number" then return end
    if level > 0 and mapID > 0 then
        keys[name] = { level = level, mapID = mapID }
        Rebuild()
    end
end

local function GatherKeys()
    keys = {}
    if C_MythicPlus then
        local lvl = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        if type(lvl) == "number" and type(map) == "number" and lvl > 0 and map > 0 then
            keys[MY_NAME] = { level = lvl, mapID = map }
        end
    end
    if LKS and LKS.Request then pcall(LKS.Request, "PARTY") end
end

-- -------------------------------------------------------------------------
-- Показ / скрытие
-- -------------------------------------------------------------------------
function KP.OnShow()
    active = true
    if LKS and LKS.Register then pcall(LKS.Register, lksToken, OnKeystone) end
    GatherKeys()
    Rebuild()
end

function KP.OnHide()
    active = false
    if LKS and LKS.Unregister then pcall(LKS.Unregister, lksToken) end
end

-- receiver=true → окно пришло по опросу (без кнопки «Опрос»).
function KP.Show(receiver)
    BuildWindow()
    win.isReceiver = receiver and true or false
    UpdateButtons()
    win:Show()
    win:Raise()
end

function KP.Toggle()
    BuildWindow()
    if win:IsShown() then win:Hide() else KP.Show() end
end

-- -------------------------------------------------------------------------
-- Голосование
-- -------------------------------------------------------------------------
local function MyVote()
    local v = votes[MY_NAME]
    if not v then v = { any = false, picks = {} }; votes[MY_NAME] = v end
    v.picks = v.picks or {}
    return v
end

-- ЛКМ «y» / ПКМ «n». Повторный тот же клик — снять отметку.
function KP.Mark(mapID, kind)
    local v = MyVote()
    if v.picks[mapID] == kind then v.picks[mapID] = nil else v.picks[mapID] = kind end
    Send("V:" .. Serialize(v))
    Rebuild()
end

-- «Пофиг» — тумблер «за всё» (кроме явно перечёркнутого).
function KP.Any()
    local v = MyVote()
    v.any = not v.any
    Send("V:" .. Serialize(v))
    Rebuild()
end

-- Старт/пересбор опроса ведущим: чистим голоса, собираем ключи, зовём группу.
function KP.StartPoll()
    votes = {}
    if not win or not win:IsShown() then KP.Show() end
    win.isReceiver = false; UpdateButtons()
    GatherKeys()
    C_Timer.After(1.0, function()
        local cands = BuildCandidates()
        local ids = {}
        for _, c in ipairs(cands) do ids[#ids + 1] = tostring(c.mapID) .. "." .. tostring(c.level) end
        Send("S:" .. table.concat(ids, ","))
        Rebuild()
    end)
end

-- -------------------------------------------------------------------------
-- Приём наших сообщений (слушатель ВСЕГДА активен — чтобы авто-открыть окно)
-- -------------------------------------------------------------------------
ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= POLL_PREFIX then return end
    local short = sender and Ambiguate(sender, "short") or sender
    local isMine = short == MY_NAME

    local kind, payload = msg:match("^(%a):(.*)$")
    if kind == "S" then
        local enabled = ns.db and ns.db.features and ns.db.features.keystonePoll
        if not isMine and enabled then
            votes = {}
            for pair in payload:gmatch("[^,]+") do
                local m, l = pair:match("^(%d+)%.(%d+)$")
                m, l = tonumber(m), tonumber(l)
                if m and l and not keys[m] then
                    keys["#" .. m] = { level = l, mapID = m }
                end
            end
            KP.Show(true)   -- получатель: окно без кнопки «Опрос»
        end
    elseif kind == "V" then
        if not isMine then
            votes[short] = Parse(payload)
            Rebuild()
        end
    end
end)

-- -------------------------------------------------------------------------
-- Слэш + кнопка тестера
-- -------------------------------------------------------------------------
SLASH_RAINONPOLL1 = "/rspoll"
SlashCmdList.RAINONPOLL = function() KP.Toggle() end

if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Подземелья", "Опрос ключей", function() KP.Show() end)
end
