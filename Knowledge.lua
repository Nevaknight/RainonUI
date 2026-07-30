-- =========================================================================
-- RainonUI / Knowledge: окно-таблица «Недельные знания и заряды».
-- Нативное окно Blizzard (ButtonFrameTemplate) со скроллом. Одна строка на
-- персонажа (данные из ns.Roster). Столбцы:
--   Имя | Профессии (2 иконки) | Изобилие | Квест | Трактат | БТ | ЧС
-- Квест/Трактат — статус по каждой профессии (галочки в порядке иконок).
-- БТ = Букет трав, ЧС = Чудесный синергетик — заряды рецептов алхимии
-- (Available Crafts); полное название — в подсказке при наведении.
-- Данные центрируются по столбцам, имя — по левому краю.
--
-- Управление (в полосе под заголовком окна): слева «Закрепить», справа
-- «Столбцы» и кнопки -/+ (масштаб). Открытие: кнопка миникарты, кнопка во
-- вкладке «Профессии», команда /rsk.
-- =========================================================================
local _, ns = ...

local C = ns.C
local READY_TEX    = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY_TEX = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local ROW_H     = 22
local HEADER_H  = 22
local LEFT_PAD  = 12
local MAX_ROWS  = 10   -- окно рассчитано на ~10 строк, дальше скролл

-- Столбцы: key, заголовок, ширина, скрываемость, tip — подсказка на заголовке
local COLUMNS = {
    { key = "name",     title = "Имя",     width = 100, toggle = false },
    { key = "prof1",    title = "Проф.1",  width = 60,  toggle = true },
    { key = "prof2",    title = "Проф.2",  width = 60,  toggle = true },
    { key = "abundant", title = "Изоб.",   width = 46,  toggle = true,
      tip = function()
          local n = C_QuestLog and C_QuestLog.GetTitleForQuestID
              and C_QuestLog.GetTitleForQuestID(89507)
          return (n and n ~= "" and n) or "Изобилие подношений"
      end },
    { key = "weekly",   title = "Квест",   width = 50,  toggle = true,
      tip = "Недельные задания у стола профессий." },
    { key = "treatise", title = "Трактат", width = 56,  toggle = true },
    { key = "darkmoon", title = "Ярмарка", width = 60,  toggle = true,
      tip = "Задание профессии на Ярмарке новолуния (раз в месяц, во время события)." },
    { key = "herbs",    title = "БТ",      width = 44,  toggle = true,
      tip = "Букет трав — заряды" },
    { key = "wondrous", title = "ЧС",      width = 46,  toggle = true,
      tip = "Чудесный синергетик — заряды" },
}

local Knowledge = {}
ns.Knowledge = Knowledge

local frame
local autoOpened = false -- окно открыто автоматически вместе с профессией
local rowPool = {}
local headerCells = {}

-- ------- помощники --------------------------------------------------------
local function MiniCheck(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(14, 14)
    return t
end

local function VisibleColumns()
    local cols = ns.db.knowledge.columns
    -- «Ярмарка» показывается только когда идёт Ярмарка новолуния (автоскрытие).
    local dmOpen = ns.Tools and ns.Tools.IsDarkmoonOpen and ns.Tools.IsDarkmoonOpen()
    local out = {}
    for _, c in ipairs(COLUMNS) do
        if c.key == "darkmoon" then
            if cols.darkmoon and dmOpen then out[#out + 1] = c end
        elseif not c.toggle or cols[c.key] then
            out[#out + 1] = c
        end
    end
    return out
end

-- Сортировка по имени: сначала кириллица А-Я, затем латиница A-Z.
local function ByName(a, b)
    local an, bn = a.name or "", b.name or ""
    local ca = (an:byte(1) or 0) >= 0x80
    local cb = (bn:byte(1) or 0) >= 0x80
    if ca ~= cb then return ca end
    return strcmputf8i(an, bn) < 0
end

local function ClassColorName(e)
    local name = e.name or "?"
    local cf = e.classFile
    if cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf] then
        local col = RAID_CLASS_COLORS[cf]
        if col.WrapTextInColorCode then return col:WrapTextInColorCode(name) end
    end
    return name
end

local CHARGE_PERIOD = 18 * 3600 -- запасной период, если max неизвестен
-- Период заряда считаем ЖИВЬЁМ по макс. числу зарядов записи (а не по
-- сохранённому period): так старые записи с устаревшим периодом всё равно
-- показываются правильно. 4/4 → 9ч10м, 2/2 → 12ч50м, 1/1 → 18ч.
local function PeriodForMax(maxCharges)
    if maxCharges == 4 then return 9 * 3600 + 10 * 60 end
    if maxCharges == 2 then return 12 * 3600 + 50 * 60 end
    if maxCharges == 1 then return 18 * 3600 end
    return CHARGE_PERIOD
end
local function now() return (GetServerTime and GetServerTime()) or 0 end

-- Граница последнего недельного сброса (обновляется в Render). Недельные
-- объективы (изобилие, недельный квест, трактат), записанные в снапшот ДО
-- этого момента, после сброса снова невыполнены — даже если оффлайн-персонаж
-- об этом ещё «не знает». Показываем их как невыполненные, пока персонаж не
-- пересканируется (зайдёшь на него — обновится).
local weeklyResetBoundary
local function LastWeeklyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, s = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and s and s > 0 then
            return now() + s - 7 * 24 * 3600
        end
    end
    return nil
end
local function WeeklyStale(e)
    return weeklyResetBoundary ~= nil and (e.lastUpdate or 0) < weeklyResetBoundary
end

local VOIDLIGHT_MARL = 3316 -- Мракозарный мергель (варбанд-валюта)

local function FmtNum(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n or 0) end
    return tostring(n or 0)
end

-- Общий счёт варбанд-валюты по аккаунту: текущий персонаж + остальные.
-- Данные по остальным персонажам приходят асинхронно (см. запрос ниже).
-- Возвращает total, iconFileID, charQuantity.
local function AccountCurrencyTotal(id)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return 0, nil, 0 end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then return 0, nil, 0 end
    local charQ = info.quantity or 0
    local total = charQ
    if info.isAccountTransferable
       and C_CurrencyInfo.IsAccountCharacterCurrencyDataReady
       and C_CurrencyInfo.IsAccountCharacterCurrencyDataReady()
       and C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters then
        local list = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(id)
        if list then
            for _, cd in ipairs(list) do total = total + (cd.quantity or 0) end
        end
    end
    return total, info.iconFileID, charQ
end

local function RequestAccountCurrency()
    if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then
        pcall(C_CurrencyInfo.RequestCurrencyDataForAccountCharacters)
    end
end

-- Оценка зарядов по времени: снимок cur/max + прошедшее время.
local function EstCharges(c)
    if not c then return nil, nil end
    local cur, max = c.cur or 0, c.max or 0
    if cur >= max then return cur, max end
    local period = PeriodForMax(max)
    local elapsed = now() - (c.ts or 0)
    if elapsed < 0 then elapsed = 0 end
    local extra
    if c.cd and c.cd > 0 then
        if elapsed < c.cd then extra = 0
        else extra = 1 + math.floor((elapsed - c.cd) / period) end
    else
        extra = math.floor(elapsed / period)
    end
    return math.min(max, cur + extra), max
end

-- Оценка концентрации: cur + накопление по циклу валюты, до максимума.
local function EstConc(c)
    if not c then return 0 end
    local est = c.cur or 0
    if c.cycleMs and c.cycleMs > 0 and c.perCycle and c.perCycle > 0 then
        local elapsed = now() - (c.ts or 0)
        if elapsed > 0 then
            est = est + (elapsed / (c.cycleMs / 1000)) * c.perCycle
        end
    end
    return math.min(math.floor(est + 0.5), c.max or est)
end

local function ConcTimeToFull(c, est)
    if not c or not c.max then return nil end
    if (est or 0) >= c.max then return 0 end
    if not (c.cycleMs and c.cycleMs > 0 and c.perCycle and c.perCycle > 0) then return nil end
    local perSec = c.perCycle / (c.cycleMs / 1000)
    if perSec <= 0 then return nil end
    return (c.max - est) / perSec
end

-- Абсолютное время «когда будет полным»: дата и время, а не длительность.
local function FormatWhenFull(secs)
    return date("%d.%m %H:%M", now() + math.floor(secs or 0))
end

-- Через сколько секунд ВСЕ заряды будут восстановлены.
local function ChargesTimeToFull(c)
    if not c then return nil end
    local cur0, max = c.cur or 0, c.max or 0
    if cur0 >= max then return 0 end
    local period = PeriodForMax(max)
    local fullAt
    if c.cd and c.cd > 0 then
        fullAt = (c.ts or 0) + c.cd + (max - cur0 - 1) * period
    else
        fullAt = (c.ts or 0) + (max - cur0) * period
    end
    return math.max(0, fullAt - now())
end

local function ProfTooltip(self)
    local p = self.pdata
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(p.name or "Профессия", 1, 1, 1)
    if p.conc then
        local est = EstConc(p.conc)
        GameTooltip:AddDoubleLine("Концентрация:", format("%d / %d", est, p.conc.max or 0),
            1, 1, 1, 1, 1, 1)
        local tf = ConcTimeToFull(p.conc, est)
        if tf and tf > 0 then
            GameTooltip:AddDoubleLine("Полная:", FormatWhenFull(tf), 1, 1, 1, 1, 1, 1)
        elseif tf == 0 then
            GameTooltip:AddLine("Концентрация полная", 0.4, 1, 0.4)
        end
    else
        GameTooltip:AddLine("Концентрация: нет данных", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function ChargeTooltip(self)
    local c, label = self.cdata, self.clabel
    -- У персонажа без алхимии зарядов быть не может — тултип не показываем,
    -- в ячейке просто «-».
    if not c and not self.hasAlch then
        GameTooltip:Hide()
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(label or "Заряды", 1, 1, 1)
    if not c then
        GameTooltip:AddLine("Нет данных (открой алхимию на этом персонаже).",
            0.6, 0.6, 0.6, true)
    else
        local cur, max = EstCharges(c)
        GameTooltip:AddDoubleLine("Заряды:", format("%d / %d", cur, max), 1, 1, 1, 1, 1, 1)
        local tf = ChargesTimeToFull(c)
        if tf and tf > 0 then
            GameTooltip:AddDoubleLine("Все заряды:", FormatWhenFull(tf), 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine("Заряды полные", 0.4, 1, 0.4)
        end
    end
    GameTooltip:Show()
end
local function HideTooltip() GameTooltip:Hide() end

-- Подсказка по трактату: по каждой профессии — использован он или нет.
-- Учитывает недельный сброс (после сброса — «НЕ использован»).
local function TreatiseTooltip(self)
    local e = self.tdata
    if not (e and e.profs) then GameTooltip:Hide(); return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Талассийский трактат", 1, 1, 1)
    local stale = WeeklyStale(e)
    for _, p in ipairs(e.profs) do
        local done = p.treatiseDone and not stale
        GameTooltip:AddDoubleLine(p.name or "?",
            done and "использован" or "НЕ использован",
            1, 1, 1,
            done and 0.4 or 1, done and 1 or 0.45, done and 0.4 or 0.45)
    end
    GameTooltip:Show()
end

-- Подсказка по имени: имя в цвете класса + сервер (ники бывают одинаковые
-- на разных серверах — сервер снимает путаницу).
local function NameTooltip(self)
    local e = self.ndata
    if not e then GameTooltip:Hide(); return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ClassColorName(e), 1, 1, 1)
    local realm = e.realm
    if realm and realm ~= "" then
        GameTooltip:AddLine("Сервер: " .. realm, 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("Сервер: —", 0.55, 0.55, 0.55)
    end
    GameTooltip:Show()
end

-- Максимальная оценка концентрации у персонажа (для сортировки).
local function CharConc(e)
    local best = -1
    if e.profs then
        for _, p in ipairs(e.profs) do
            if p.conc then
                local est = EstConc(p.conc)
                if est > best then best = est end
            end
        end
    end
    return best
end

local function ByConc(a, b)
    local ca, cb = CharConc(a), CharConc(b)
    if ca ~= cb then return ca > cb end
    return ByName(a, b)
end

local function ChargeText(c)
    if not c then return C("808080", "-") end
    local cur, max = EstCharges(c)
    local hex = "FFFFFF"
    if max > 0 and cur >= max then hex = "40FF40"
    elseif cur == 0 then hex = "FF5555" end
    return C(hex, format("%d/%d", cur, max))
end

-- ------- пул строк --------------------------------------------------------
local function AcquireRow(parent, i)
    if rowPool[i] then return rowPool[i] end
    local r = {}
    r.frame = CreateFrame("Frame", nil, parent)
    r.frame:SetHeight(ROW_H)
    if i % 2 == 0 then
        local bg = r.frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end
    -- Подсветка строки текущего персонажа: нейтральный мягкий тон, чтобы
    -- сразу было видно «это я», но не мешало читать строку.
    r.hl = r.frame:CreateTexture(nil, "BORDER")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(0.55, 0.75, 1.0, 0.12)
    r.hl:Hide()
    r.hlbar = r.frame:CreateTexture(nil, "ARTWORK")
    r.hlbar:SetPoint("TOPLEFT", r.frame, "TOPLEFT", 0, 0)
    r.hlbar:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, 0)
    r.hlbar:SetWidth(2)
    r.hlbar:SetColorTexture(0.6, 0.8, 1.0, 0.85)
    r.hlbar:Hide()
    r.name = r.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetJustifyH("LEFT")
    -- Прозрачная кнопка над именем — подсказка с сервером.
    r.namebtn = CreateFrame("Button", nil, r.frame)
    r.namebtn:SetScript("OnEnter", NameTooltip)
    r.namebtn:SetScript("OnLeave", HideTooltip)
    r.prof1 = r.frame:CreateTexture(nil, "ARTWORK"); r.prof1:SetSize(18, 18)
    r.prof2 = r.frame:CreateTexture(nil, "ARTWORK"); r.prof2:SetSize(18, 18)
    r.prof1conc = r.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.prof2conc = r.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.prof1btn = CreateFrame("Button", nil, r.frame)
    r.prof2btn = CreateFrame("Button", nil, r.frame)
    r.prof1btn:SetScript("OnEnter", ProfTooltip)
    r.prof1btn:SetScript("OnLeave", HideTooltip)
    r.prof2btn:SetScript("OnEnter", ProfTooltip)
    r.prof2btn:SetScript("OnLeave", HideTooltip)
    r.abundant = MiniCheck(r.frame); r.abundant:SetSize(15, 15)
    r.weekly = { MiniCheck(r.frame), MiniCheck(r.frame) }
    r.treatise = { MiniCheck(r.frame), MiniCheck(r.frame) }
    r.darkmoon = { MiniCheck(r.frame), MiniCheck(r.frame) }
    r.herbs = r.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.wondrous = r.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.herbsbtn = CreateFrame("Button", nil, r.frame)
    r.wondrousbtn = CreateFrame("Button", nil, r.frame)
    r.herbsbtn:SetScript("OnEnter", ChargeTooltip)
    r.herbsbtn:SetScript("OnLeave", HideTooltip)
    r.wondrousbtn:SetScript("OnEnter", ChargeTooltip)
    r.wondrousbtn:SetScript("OnLeave", HideTooltip)
    -- Прозрачная кнопка над столбцом «Трактат» — подсказка по каждой профессии.
    r.treatisebtn = CreateFrame("Button", nil, r.frame)
    r.treatisebtn:SetScript("OnEnter", TreatiseTooltip)
    r.treatisebtn:SetScript("OnLeave", HideTooltip)
    rowPool[i] = r
    return r
end

local function HideAllRegions(r)
    r.name:Hide()
    if r.namebtn then r.namebtn:Hide() end
    r.prof1:Hide(); r.prof2:Hide()
    r.prof1conc:Hide(); r.prof2conc:Hide()
    r.prof1btn:Hide(); r.prof2btn:Hide()
    r.abundant:Hide()
    r.weekly[1]:Hide(); r.weekly[2]:Hide()
    r.treatise[1]:Hide(); r.treatise[2]:Hide()
    r.darkmoon[1]:Hide(); r.darkmoon[2]:Hide()
    r.herbs:Hide(); r.wondrous:Hide()
    r.herbsbtn:Hide(); r.wondrousbtn:Hide()
    if r.treatisebtn then r.treatisebtn:Hide() end
end

-- Заполнить одну ячейку. x — левый край столбца; всё по центру столбца
-- (кроме имени — по левому краю).
local function FillCell(r, col, x, e)
    local center = x + col.width / 2
    if col.key == "name" then
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r.frame, "LEFT", x + 6, 0)
        r.name:SetWidth(col.width - 8)
        r.name:SetText(ClassColorName(e))
        r.name:Show()
        if r.namebtn then
            r.namebtn.ndata = e
            r.namebtn:ClearAllPoints()
            r.namebtn:SetPoint("LEFT", r.frame, "LEFT", x, 0)
            r.namebtn:SetSize(col.width, ROW_H)
            r.namebtn:Show()
        end
    elseif col.key == "prof1" or col.key == "prof2" then
        local slot = (col.key == "prof1") and 1 or 2
        local p = e.profs and e.profs[slot]
        if p and p.icon then
            local tex = r[col.key]
            tex:ClearAllPoints()
            tex:SetPoint("LEFT", r.frame, "LEFT", x + 4, 0)
            tex:SetTexture(p.icon)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            tex:Show()
            -- Концентрация справа от иконки (оценка на текущий момент)
            if p.conc then
                local est = EstConc(p.conc)
                local full = est >= (p.conc.max or 0)
                local cfs = r[col.key .. "conc"]
                cfs:ClearAllPoints()
                cfs:SetPoint("LEFT", tex, "RIGHT", 3, 0)
                cfs:SetWidth(col.width - 26)
                cfs:SetJustifyH("LEFT")
                cfs:SetText(C(full and "40FF40" or "FFD200", tostring(est)))
                cfs:Show()
            end
            -- Прозрачная кнопка для тултипа концентрации
            local btn = r[col.key .. "btn"]
            btn.pdata = p
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", r.frame, "LEFT", x, 0)
            btn:SetSize(col.width, ROW_H)
            btn:Show()
        end
    elseif col.key == "abundant" then
        r.abundant:ClearAllPoints()
        r.abundant:SetPoint("CENTER", r.frame, "LEFT", center, 0)
        local abDone = e.abundant and not WeeklyStale(e)
        r.abundant:SetTexture(abDone and READY_TEX or NOTREADY_TEX)
        r.abundant:Show()
    elseif col.key == "weekly" or col.key == "treatise" or col.key == "darkmoon" then
        local checks = r[col.key]
        local profs = e.profs or {}
        local n = (profs[1] and 1 or 0) + (profs[2] and 1 or 0)
        -- Ярмарка — месячная (не недельная), поэтому недельный сброс к ней не применяем.
        local stale = (col.key ~= "darkmoon") and WeeklyStale(e) or false
        local S, idx = 16, 0
        for j = 1, 2 do
            local p = profs[j]
            if p then
                idx = idx + 1
                local done
                if col.key == "weekly" then done = p.weeklyDone
                elseif col.key == "treatise" then done = p.treatiseDone
                else done = p.darkmoonDone end
                if stale then done = false end
                local t = checks[j]
                local cx = center + (idx - (n + 1) / 2) * S
                t:ClearAllPoints()
                t:SetPoint("CENTER", r.frame, "LEFT", cx, 0)
                t:SetTexture(done and READY_TEX or NOTREADY_TEX)
                t:Show()
            end
        end
        -- Прозрачная кнопка-подсказка на столбце «Трактат» (только он).
        if col.key == "treatise" and r.treatisebtn then
            r.treatisebtn.tdata = e
            r.treatisebtn:ClearAllPoints()
            r.treatisebtn:SetPoint("LEFT", r.frame, "LEFT", x, 0)
            r.treatisebtn:SetSize(col.width, ROW_H)
            r.treatisebtn:Show()
        end
    elseif col.key == "herbs" or col.key == "wondrous" then
        local rid = (col.key == "herbs") and ns.Roster.HERBS_RECIPE
            or ns.Roster.WONDROUS_RECIPE
        local c = e.charges and e.charges[rid]
        local fs = r[col.key]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", r.frame, "LEFT", x, 0)
        fs:SetWidth(col.width)
        fs:SetJustifyH("CENTER")
        fs:SetText(ChargeText(c))
        fs:Show()
        -- Прозрачная кнопка для тултипа зарядов (со временем восстановления)
        local hasAlch = false
        if e.profs then
            for _, p in ipairs(e.profs) do
                if p.base == 171 then hasAlch = true; break end
            end
        end
        local btn = r[col.key .. "btn"]
        btn.cdata = c
        btn.hasAlch = hasAlch
        btn.clabel = (col.key == "herbs") and "Букет трав" or "Чудесный синергетик"
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", r.frame, "LEFT", x, 0)
        btn:SetSize(col.width, ROW_H)
        btn:Show()
    end
end

-- ------- заголовок --------------------------------------------------------
local function GetHeaderCell(i)
    local h = headerCells[i]
    if not h then
        h = CreateFrame("Button", nil, frame.Header)
        h:SetHeight(HEADER_H)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetTextColor(0.88, 0.65, 0.15)
        headerCells[i] = h
    end
    return h
end

local function SetHeaderTip(h, tip)
    if tip then
        h:EnableMouse(true)
        h:SetScript("OnEnter", function()
            local text = (type(tip) == "function") and tip() or tip
            GameTooltip:SetOwner(h, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        h:EnableMouse(false)
        h:SetScript("OnEnter", nil)
        h:SetScript("OnLeave", nil)
    end
end

-- Клик по заголовку — сортировка ("name" по имени, "conc" по концентрации).
local function SetHeaderSort(h, mode)
    if mode then
        h:EnableMouse(true)
        h:RegisterForClicks("LeftButtonUp")
        h:SetScript("OnClick", function()
            ns.db.knowledge.sort = mode
            Knowledge:Render()
        end)
    else
        h:SetScript("OnClick", nil)
    end
end

-- ------- построение таблицы ----------------------------------------------
function Knowledge:Render()
    if not frame then return end
    weeklyResetBoundary = LastWeeklyReset()  -- граница сброса на момент отрисовки
    local vis = VisibleColumns()

    local xOff, total = {}, 0
    for i, c in ipairs(vis) do
        xOff[i] = total
        total = total + c.width
    end

    local sortMode = ns.db.knowledge.sort or "name"
    local function ColorHeader(h, active)
        if active then h.text:SetTextColor(1, 1, 1)
        else h.text:SetTextColor(0.88, 0.65, 0.15) end
    end

    -- Заголовок: соседние столбцы профессий объединяем в один «Профессии».
    -- Клик по «Имя» — сортировка по имени, по «Профессии» — по концентрации.
    for _, h in pairs(headerCells) do h:Hide() end
    local i = 1
    while i <= #vis do
        local c = vis[i]
        local h = GetHeaderCell(i)
        h:ClearAllPoints()
        h.text:ClearAllPoints()
        if c.key == "prof1" or c.key == "prof2" then
            local endI = i
            while endI + 1 <= #vis
                and (vis[endI + 1].key == "prof1" or vis[endI + 1].key == "prof2") do
                endI = endI + 1
            end
            local startX = xOff[i]
            local endX = xOff[endI] + vis[endI].width
            h:SetPoint("LEFT", frame.Header, "LEFT", startX, 0)
            h:SetWidth(endX - startX)
            h.text:SetAllPoints()
            h.text:SetJustifyH("CENTER")
            h.text:SetText("Профессии")
            SetHeaderTip(h, nil)
            SetHeaderSort(h, "conc")
            ColorHeader(h, sortMode == "conc")
            h:Show()
            i = endI + 1
        else
            h:SetPoint("LEFT", frame.Header, "LEFT", xOff[i], 0)
            h:SetWidth(c.width)
            if c.key == "name" then
                h.text:SetPoint("LEFT", h, "LEFT", 6, 0)
                h.text:SetPoint("RIGHT", h, "RIGHT", 0, 0)
                h.text:SetJustifyH("LEFT")
            else
                h.text:SetAllPoints()
                h.text:SetJustifyH("CENTER")
            end
            h.text:SetText(c.title)
            SetHeaderTip(h, c.tip)
            if c.key == "name" then
                SetHeaderSort(h, "name")
                ColorHeader(h, sortMode == "name")
            else
                SetHeaderSort(h, nil)
                ColorHeader(h, false)
            end
            h:Show()
            i = i + 1
        end
    end

    -- Данные: берём всех, но выключенных (e.hidden) в таблице не показываем
    -- (они остаются в меню «Персонажи», чтобы можно было вернуть).
    local chars = {}
    for _, e in ipairs(ns.Roster and ns.Roster.GetAll() or {}) do
        if not e.hidden then chars[#chars + 1] = e end
    end
    table.sort(chars, sortMode == "conc" and ByConc or ByName)
    -- Текущий персонаж — всегда первой строкой (на нём и открыли окно).
    local selfGUID = UnitGUID and UnitGUID("player")
    if selfGUID then
        for i, e in ipairs(chars) do
            if e.guid == selfGUID then
                if i > 1 then table.remove(chars, i); table.insert(chars, 1, e) end
                break
            end
        end
    end
    for _, r in ipairs(rowPool) do r.frame:Hide() end

    if #chars == 0 then
        frame.Empty:Show()
    else
        frame.Empty:Hide()
        local myGUID = UnitGUID and UnitGUID("player")
        for idx, e in ipairs(chars) do
            local r = AcquireRow(frame.Content, idx)
            r.frame:ClearAllPoints()
            r.frame:SetPoint("TOPLEFT", frame.Content, "TOPLEFT", 0, -(idx - 1) * ROW_H)
            r.frame:SetWidth(total)
            HideAllRegions(r)
            for k, c in ipairs(vis) do
                FillCell(r, c, xOff[k], e)
            end
            if r.hl then
                local mine = myGUID and e.guid == myGUID
                if mine then r.hl:Show(); r.hlbar:Show()
                else r.hl:Hide(); r.hlbar:Hide() end
            end
            r.frame:Show()
        end
    end

    -- Мергель (варбанд-валюта): иконка + общий счёт по аккаунту
    if frame.Marl then
        local mtotal, micon = AccountCurrencyTotal(VOIDLIGHT_MARL)
        frame.Marl.icon:SetTexture(micon or 133784)
        frame.Marl.text:SetText(FmtNum(mtotal))
    end

    frame.Content:SetSize(math.max(total, 10), math.max(#chars * ROW_H, 1))
    frame.Header:SetWidth(total)
    -- Ширина под столбцы + место для скролла внутри бокса; высота на MAX_ROWS
    -- (полоса управления 20 + шапка + строки + отступы под шаблон окна)
    local rows = ns.db.knowledge.rows or 20
    frame:SetWidth(LEFT_PAD + total + 44)
    frame:SetHeight(72 + HEADER_H + rows * ROW_H)
end

function Knowledge:Refresh()
    if frame and frame:IsShown() then self:Render() end
end

-- ------- окно -------------------------------------------------------------
local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.db.knowledge.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestorePosition()
    local p = ns.db.knowledge.pos
    frame:ClearAllPoints()
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

local function ApplyScale()
    frame:SetScale(ns.db.knowledge.scale or 1)
end

local function ChangeScale(delta)
    local s = (ns.db.knowledge.scale or 1) + delta
    s = math.max(0.6, math.min(1.6, s))
    ns.db.knowledge.scale = s
    ApplyScale()
end

local function OpenColumnsMenu(anchor)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle("Столбцы")
        for _, c in ipairs(COLUMNS) do
            if c.toggle then
                root:CreateCheckbox(c.title,
                    function() return ns.db.knowledge.columns[c.key] end,
                    function()
                        ns.db.knowledge.columns[c.key] = not ns.db.knowledge.columns[c.key]
                        Knowledge:Render()
                        return MenuResponse and MenuResponse.Refresh
                    end)
            end
        end
        root:CreateDivider()
        root:CreateTitle("Строк в окне")
        for _, n in ipairs({ 10, 20 }) do
            root:CreateRadio(tostring(n),
                function() return (ns.db.knowledge.rows or 20) == n end,
                function()
                    ns.db.knowledge.rows = n
                    Knowledge:Render()
                    return MenuResponse and MenuResponse.Refresh
                end)
        end
    end)
end

-- Меню «Персонажи»: у каждого — подменю с галкой «Показывать» и «Удалить».
local function OpenCharsMenu(anchor)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle("Персонажи")
        local list = ns.Roster and ns.Roster.GetAll() or {}
        if #list == 0 then
            root:CreateButton("Нет персонажей")
            return
        end
        for _, e in ipairs(list) do
            local guid = e.guid
            local sub = root:CreateButton(ClassColorName(e))
            sub:CreateCheckbox("Показывать",
                function()
                    local re = ns.db.roster and ns.db.roster[guid]
                    return not (re and re.hidden)
                end,
                function()
                    local re = ns.db.roster and ns.db.roster[guid]
                    if re then re.hidden = not re.hidden end
                    Knowledge:Render()
                    return MenuResponse and MenuResponse.Refresh
                end)
            sub:CreateButton("Удалить из списка", function()
                if ns.Roster and ns.Roster.Delete then ns.Roster.Delete(guid) end
                Knowledge:Render()
                return MenuResponse and MenuResponse.Close
            end)
        end
    end)
end

local function CreateWindow()
    local f = CreateFrame("Frame", "RainonUIKnowledge", UIParent, "ButtonFrameTemplate")
    f:SetSize(480, 320)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if not ns.db.knowledge.locked then f:StartMoving() end
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePosition()
    end)
    if f.SetTitle then f:SetTitle("RainonUI — Знания и заряды") end
    -- Без портрета — окно чистое и прямоугольное
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if f.PortraitContainer then f.PortraitContainer:Hide() end
    if f.portrait then f.portrait:Hide() end
    table.insert(UISpecialFrames, "RainonUIKnowledge")

    -- Ужимаем верхний прямоугольник под заголовком: двигаем инсет (тёмный
    -- бокс таблицы) вверх, чтобы кнопки помещались в полосе над ним, а
    -- пустого места было меньше.
    if f.Inset then
        f.Inset:ClearAllPoints()
        f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -50)
        f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    end

    local host = f.Inset or f

    -- Кнопки в верхнем боксе (над инсетом), все на одном уровне по вертикали
    -- (TOOL_Y). Порядок Столбцы / - / + / замок / шестерёнка; шестерёнка — у
    -- правой границы, мергель — у левой, зеркально и на том же уровне.
    local BTN_GAP = 4
    local TOOL_Y = 14 -- центр по вертикали в полосе над таблицей

    -- Шестерёнка (крайняя справа, у границы) — открывает окно /rs
    local gearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gearBtn:SetSize(24, 20)
    gearBtn:SetPoint("RIGHT", host, "TOPRIGHT", -6, TOOL_Y)
    local gearTex = gearBtn:CreateTexture(nil, "ARTWORK")
    gearTex:SetSize(14, 14)
    gearTex:SetPoint("CENTER")
    gearTex:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    gearBtn:SetScript("OnClick", function()
        if SlashCmdList and SlashCmdList.RAINONUI then SlashCmdList.RAINONUI() end
    end)
    gearBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(gearBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Настройки RainonUI", 1, 1, 1)
        GameTooltip:AddLine("Открыть окно настроек (/rs).", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Замок
    local lockBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    lockBtn:SetSize(24, 20)
    lockBtn:SetPoint("RIGHT", gearBtn, "LEFT", -BTN_GAP, 0)
    local lockIcon = lockBtn:CreateTexture(nil, "ARTWORK")
    lockIcon:SetSize(12, 14)
    lockIcon:SetPoint("CENTER")
    lockIcon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    local function UpdateLockIcon()
        if ns.db.knowledge.locked then
            lockIcon:SetDesaturated(false)
            lockIcon:SetVertexColor(1, 0.85, 0.3)
            lockIcon:SetAlpha(1)
        else
            lockIcon:SetDesaturated(true)
            lockIcon:SetVertexColor(1, 1, 1)
            lockIcon:SetAlpha(0.45)
        end
    end
    UpdateLockIcon()
    lockBtn:SetScript("OnClick", function()
        ns.db.knowledge.locked = not ns.db.knowledge.locked
        UpdateLockIcon()
    end)
    lockBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(lockBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText(ns.db.knowledge.locked and "Окно закреплено"
            or "Окно откреплено", 1, 1, 1)
        GameTooltip:AddLine("Клик — закрепить или открепить окно.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    plus:SetSize(22, 20)
    plus:SetPoint("RIGHT", lockBtn, "LEFT", -BTN_GAP, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() ChangeScale(0.1) end)

    local minus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    minus:SetSize(22, 20)
    minus:SetPoint("RIGHT", plus, "LEFT", -BTN_GAP, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() ChangeScale(-0.1) end)

    local colsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    colsBtn:SetSize(74, 20)
    colsBtn:SetPoint("RIGHT", minus, "LEFT", -BTN_GAP, 0)
    colsBtn:SetText("Столбцы")
    colsBtn:SetScript("OnClick", function() OpenColumnsMenu(colsBtn) end)

    -- «Персонажи» — слева от «Столбцы»: включать/выключать и удалять персонажей.
    local charsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    charsBtn:SetSize(84, 20)
    charsBtn:SetPoint("RIGHT", colsBtn, "LEFT", -BTN_GAP, 0)
    charsBtn:SetText("Персонажи")
    charsBtn:SetScript("OnClick", function() OpenCharsMenu(charsBtn) end)

    -- (Галка «Открывать с профессией» перенесена в окно настроек, вкладка
    --  «Профессии», рядом с кнопкой «Недельные знания…».)

    -- Мергель слева (варбанд-валюта): иконка у левой границы зеркально
    -- шестерёнке и на том же уровне (TOOL_Y); текст — относительно иконки.
    local marl = CreateFrame("Button", nil, f)
    marl:SetSize(130, 20)
    marl.icon = marl:CreateTexture(nil, "ARTWORK")
    marl.icon:SetSize(18, 18)
    marl.icon:SetPoint("LEFT", host, "TOPLEFT", 6, TOOL_Y)
    marl:SetPoint("LEFT", marl.icon, "LEFT", 0, 0)
    marl.text = marl:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    marl.text:SetPoint("LEFT", marl.icon, "RIGHT", 4, 0)
    marl:SetScript("OnEnter", function()
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo(VOIDLIGHT_MARL)
        GameTooltip:SetOwner(marl, "ANCHOR_BOTTOM")
        GameTooltip:SetText(info and info.name or "Мракозарный мергель", 1, 1, 1)
        local total, _, charQ = AccountCurrencyTotal(VOIDLIGHT_MARL)
        GameTooltip:AddDoubleLine("На всех персонажах:", FmtNum(total), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("У этого персонажа:", FmtNum(charQ), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    marl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.Marl = marl

    -- Шапка таблицы
    local header = CreateFrame("Frame", nil, host)
    header:SetPoint("TOPLEFT", host, "TOPLEFT", LEFT_PAD, -8)
    header:SetHeight(HEADER_H)
    f.Header = header
    local hline = header:CreateTexture(nil, "ARTWORK")
    hline:SetColorTexture(1, 1, 1, 0.12)
    hline:SetPoint("BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", 0, 0)
    hline:SetHeight(1)

    -- Прокрутка: заполняет тёмный бокс на всю высоту (стрелки — в границах).
    local scroll = CreateFrame("ScrollFrame", nil, host, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", LEFT_PAD, -(8 + HEADER_H))
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    f.Scroll = scroll
    f.Content = content

    f.Empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.Empty:SetPoint("TOPLEFT", 4, -8)
    f.Empty:SetWidth(380)
    f.Empty:SetJustifyH("LEFT")
    f.Empty:SetText("Пока нет данных.\n\nЗайди на персонажа и открой окно" ..
        " профессии — он появится в таблице. Заряды подтянутся при открытии" ..
        " алхимии.")
    f.Empty:Hide()

    f:SetScript("OnShow", function()
        RequestAccountCurrency()
        Knowledge:Render()
    end)

    frame = f
    RestorePosition()
    ApplyScale()
    f:Hide()
    return f
end

function Knowledge:Toggle()
    autoOpened = false -- ручной вызов — не закрываем вместе с профессией
    -- Уже открыто — закрыть можно всегда (в т.ч. в бою).
    if frame and frame:IsShown() then frame:Hide(); return end
    -- Не создаём/не открываем окно в бою (безопасность от случайных ошибок).
    if InCombatLockdown() then
        ns.Print("окно знаний недоступно в бою — открой после боя.")
        return
    end
    if not frame then CreateWindow() end
    frame:Show()
end

function Knowledge:Open()
    if InCombatLockdown() then return end
    if ns.Tools and ns.Tools.RefreshDarkmoon then ns.Tools.RefreshDarkmoon() end
    if not frame then CreateWindow() end
    frame:Show()
end

-- Обновление таблицы, пока окно открыто (данные приходят из Roster-событий).
local function refreshIfShown() Knowledge:Refresh() end
ns.RegisterEvent("QUEST_LOG_UPDATE", refreshIfShown)
ns.RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", refreshIfShown)
ns.RegisterEvent("CURRENCY_DISPLAY_UPDATE", refreshIfShown)
ns.RegisterMessage("RAINON_REAPPLY", refreshIfShown)

-- Открытие/скрытие вместе с окном профессии (по галочке «Открывать с профессией»)
ns.RegisterEvent("TRADE_SKILL_SHOW", function()
    if not (ns.db and ns.db.knowledge.autoOpen) then return end
    if not frame or not frame:IsShown() then
        Knowledge:Open()
        autoOpened = true
    end
end)
ns.RegisterEvent("TRADE_SKILL_CLOSE", function()
    if autoOpened and frame then
        frame:Hide()
        autoOpened = false
    end
end)

-- Слэш-команда
SLASH_RAINONUIKNOWLEDGE1 = "/rsk"
SLASH_RAINONUIKNOWLEDGE2 = "/rainonknowledge"
SlashCmdList.RAINONUIKNOWLEDGE = function() Knowledge:Toggle() end