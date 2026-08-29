-- =========================================================================
-- RainonUI / TestBar (ЭКСПЕРИМЕНТАЛЬНЫЙ, ТЕСТОВЫЙ модуль).
-- Полоса-таймер «Божественного резонанса» (танк-паладин) с засечками и иконкой.
-- Стиль — близардовский кастбар (как наша «полоса готовности»), цвет розовый.
--
-- Подход как в ArcUI и оригинальном WeakAura: ауру НЕ читаем («Резонанс» не
-- отдаётся ни как аура, ни через фрейм CDM — проверено), а ведём СВОЙ таймер по
-- СОБЫТИЮ: на КАСТ «Божественного благовеста» (свой каст, spellID НЕ секретный)
-- запускаем полоску фиксированной длительности. (ArcUI: UNIT_SPELLCAST_SUCCEEDED,
-- startCondition="onCast".)
--
-- Грузится ТОЛЬКО в спеке Защита + при взятом таланте «Резонанс».
-- Гейт-галка: features.testBar (ВЫКЛ). Двигается/размер — EditMode (key="testbar").
-- Тест/предпросмотр: /rstestbar + кнопка тестера «Тест».
-- =========================================================================
local _, ns = ...

ns.TestBar = ns.TestBar or {}
local TB = ns.TestBar

local TRIGGER_SPELL    = 375576   -- «Божественный благовест» (каст → «Резонанс»)
local RESONANCE_TALENT = 386738   -- талант «Божественный резонанс» (гейт загрузки)
local BUFF_ICON_ID     = 386730   -- иконка баффа для полоски
local PROT_SPEC        = 66       -- специализация «Защита» (паладин-танк)
local BUFF_DURATION    = 15       -- длительность «Резонанса», сек

local TICKS     = { 66, 33 }               -- засечки (0% убрали — там полоса и так пропадает)
local BAR_COLOR = { 0.957, 0.549, 0.729 }  -- розовый как в оригинальном WA

local bar
local previewUntil                          -- пока идёт предпросмотр — не прячем

-- Настройки из БД (с дефолтами).
local function Enabled() return ns.db and ns.db.features and ns.db.features.testBar end
local function BarW()    return (ns.db and ns.db.features and ns.db.features.testBarW) or 200 end
local function BarH()    return (ns.db and ns.db.features and ns.db.features.testBarH) or 25 end
local function IconOn()  return not (ns.db and ns.db.features and ns.db.features.testBarIcon == false) end

-- Грузим полосу только в танке (Защита) и при взятом таланте «Резонанс».
local function ShouldLoad()
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return false end
    local specID = GetSpecializationInfo and GetSpecializationInfo(spec)
    if specID ~= PROT_SPEC then return false end
    if IsPlayerSpell then
        return IsPlayerSpell(RESONANCE_TALENT) or IsPlayerSpell(TRIGGER_SPELL) or false
    end
    return true
end

-- Применить размеры/иконку/позиции засечек (ширина/высота из настроек).
local function ApplySize()
    if not bar then return end
    local w, h = BarW(), BarH()
    bar:SetSize(w, h)
    if bar.Icon then
        bar.Icon:SetSize(h, h)
        bar.Icon:SetShown(IconOn())
    end
    for i, t in ipairs(bar.ticks or {}) do
        t:SetSize(2, h)
        t:ClearAllPoints()
        t:SetPoint("LEFT", bar, "LEFT", w * ((TICKS[i] or 0) / 100), 0)
    end
end

-- -------------------------------------------------------------------------
-- Постройка полоски (один раз). Стиль — кастбар Blizzard.
-- -------------------------------------------------------------------------
local function BuildBar()
    if bar then return bar end
    bar = CreateFrame("StatusBar", "RainonUITestBar", UIParent)
    bar:SetSize(BarW(), BarH())
    bar:SetFrameStrata("HIGH")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")
    bar:SetStatusBarColor(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3], 1)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetAtlas("ui-castingbar-background")

    bar.FrameTex = bar:CreateTexture(nil, "OVERLAY")
    bar.FrameTex:SetAtlas("ui-castingbar-frame")
    bar.FrameTex:SetPoint("TOPLEFT", -4, 4)
    bar.FrameTex:SetPoint("BOTTOMRIGHT", 4, -4)

    -- иконка СПРАВА
    bar.Icon = bar:CreateTexture(nil, "OVERLAY")
    bar.Icon:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- остаток секунд по центру
    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.Text:SetPoint("CENTER")

    -- вертикальные засечки
    bar.ticks = {}
    for _ in ipairs(TICKS) do
        local t = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetBlendMode("ADD")
        bar.ticks[#bar.ticks + 1] = t
    end

    -- убывание остатка
    bar:SetScript("OnUpdate", function(self)
        if not self.expires then return end
        local rem = self.expires - GetTime()
        if rem <= 0 then
            if previewUntil and GetTime() < previewUntil then
                rem = 0
            else
                self.expires = nil
                self:Hide()
                return
            end
        end
        self:SetValue(rem)
        self.Text:SetFormattedText("%.1f", rem)
    end)

    -- позиция/размер — EditMode: вместо масштаба свои слайдеры «Ширина»/«Высота».
    if ns.EditMode and ns.EditMode.Register then
        local extra
        if ns.EditMode.SettingType then
            extra = {
                {
                    name = "Ширина", kind = ns.EditMode.SettingType.Slider,
                    default = 200, minValue = 100, maxValue = 600, valueStep = 5,
                    get = function() return BarW() end,
                    set = function(_, v) if ns.db and ns.db.features then ns.db.features.testBarW = v end; ApplySize() end,
                },
                {
                    name = "Высота", kind = ns.EditMode.SettingType.Slider,
                    default = 25, minValue = 10, maxValue = 60, valueStep = 1,
                    get = function() return BarH() end,
                    set = function(_, v) if ns.db and ns.db.features then ns.db.features.testBarH = v end; ApplySize() end,
                },
            }
        end
        ns.EditMode.Register(bar, {
            name = "RainonUI: Тест-полоска", key = "testbar",
            defaultX = 0, defaultY = -80, showInEditMode = true,
            noScale = true, extraSettings = extra, hideDefaultButton = true,
            -- В редакторе показываем «превью» заполненной полосы, чтобы её было
            -- видно и можно было двигать/менять размер БЕЗ запуска трекинга.
            onEditModeShow = function(f)
                f:SetMinMaxValues(0, BUFF_DURATION)
                f:SetValue(BUFF_DURATION)
                if f.Icon then f.Icon:SetTexture((ns.GetSpellTexture and ns.GetSpellTexture(BUFF_ICON_ID)) or 135895) end
                if f.Text then f.Text:SetText("15.0") end
                ApplySize()
            end,
            onEditModeHide = function(f)
                f.expires = nil
                if not (previewUntil and GetTime() < previewUntil) then f:Hide() end
            end,
        })
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
    end

    ApplySize()
    bar:Hide()
    return bar
end

local function ShowFor(duration, expires, icon)
    BuildBar()
    if not (duration and duration > 0) then duration = 1 end
    bar:SetMinMaxValues(0, duration)
    if icon then bar.Icon:SetTexture(icon) end
    ApplySize()
    bar.expires = expires
    bar:SetValue(expires - GetTime())
    bar:Show()
end

-- Запуск полоски по касту (свой таймер): фиксированные 15 сек «Резонанса».
local function StartBar()
    if not (Enabled() and ShouldLoad()) then return end
    previewUntil = nil
    local icon = (ns.GetSpellTexture and ns.GetSpellTexture(BUFF_ICON_ID)) or 135895
    ShowFor(BUFF_DURATION, GetTime() + BUFF_DURATION, icon)
end

-- Обновление: применить размеры/иконку; спрятать, если выкл или не тот спек/талант.
function TB.Refresh()
    if not bar then return end
    ApplySize()
    if (not Enabled() or not ShouldLoad()) and not (previewUntil and GetTime() < previewUntil) then
        bar:Hide()
    end
end

-- Триггер как в ArcUI/WA: по КАСТУ «Божественного благовеста» (свой каст —
-- spellID НЕ секретный) запускаем полоску.
ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" and spellID == TRIGGER_SPELL then StartBar() end
end)
ns.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() TB.Refresh() end)
ns.RegisterEvent("TRAIT_CONFIG_UPDATED", function() TB.Refresh() end)
ns.RegisterMessage("RAINON_REAPPLY", function() TB.Refresh() end)

-- Строим полосу ЗАРАНЕЕ (на входе), чтобы она была зарегистрирована в EditMode и
-- показывалась в редакторе для перемещения/размера БЕЗ предварительного запуска.
ns.RegisterEvent("PLAYER_LOGIN", function() BuildBar() end)
ns.RegisterMessage("RAINON_DB_READY", function() BuildBar() end)

-- -------------------------------------------------------------------------
-- Предпросмотр / тест: показать полоску на ~15с (без гейта спека, для проверки).
-- -------------------------------------------------------------------------
function TB.Test()
    BuildBar()
    previewUntil = GetTime() + BUFF_DURATION
    local icon = (ns.GetSpellTexture and ns.GetSpellTexture(BUFF_ICON_ID)) or 135895
    ShowFor(BUFF_DURATION, GetTime() + BUFF_DURATION, icon)
end

function TB.Toggle()
    if bar and bar:IsShown() then bar:Hide() else TB.Test() end
end

-- /rstestbar — предпросмотр полоски (реально показывается по касту «Благовеста»).
SLASH_RAINONTESTBAR1 = "/rstestbar"
SlashCmdList.RAINONTESTBAR = function() TB.Test() end

if ns.Tester and ns.Tester.Add then
    ns.Tester.Add("Тест", "Полоска Divine Resonance", function() TB.Test() end)
end
