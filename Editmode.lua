-- =========================================================================
-- RainonUI / EditMode: обёртка над LibEditMode.
-- Регистрирует наши фреймы в родном Edit Mode Blizzard (превью-перетаскивание)
-- и добавляет близард-окошко настроек с координатами X/Y и размером (%).
--
-- Позиция — ПИКСЕЛИ: смещение центра фрейма от центра экрана (0,0 = центр;
-- +X вправо, +Y вверх). Размер — множитель масштаба (SetScale).
--
-- Хранилище конфигурации: по умолчанию ns.db.features[key.."EM"], но можно
-- задать своё через opts.getCfg (муверы используют общий ns.db.positions[key]).
-- opts.onChanged вызывается после применения (муверы двигают через него свою
-- реальную цель, а зарегистрированный фрейм — это бокс-прокси).
--
-- Библиотеки нет → модуль тихо отключается, фреймы используют запасной способ.
-- =========================================================================
local _, ns = ...

local LEM = LibStub and LibStub("LibEditMode", true)

ns.EditMode = ns.EditMode or {}
local registered = {}   -- [frame] = { opts = }

-- Тип настроек LibEditMode (Slider/Checkbox/Dropdown/…) — чтобы модули могли
-- собирать свои доп. слайдеры (opts.extraSettings), напр. «Ширина».
ns.EditMode.SettingType = LEM and LEM.SettingType or nil

function ns.EditMode.Available()
    return LEM ~= nil
end

-- Активен ли сейчас режим редактирования Blizzard (через LibEditMode).
function ns.EditMode.IsEditing()
    return LEM ~= nil and LEM.IsInEditMode and LEM:IsInEditMode() and true or false
end

local function cfgFor(key)
    if not (ns.db and ns.db.features) then return nil end
    ns.db.features[key .. "EM"] = ns.db.features[key .. "EM"] or {}
    return ns.db.features[key .. "EM"]
end

local function ConfigOf(opts)
    if opts.getCfg then return opts.getCfg() end
    return cfgFor(opts.key)
end

-- Применить позицию (координаты X/Y от центра) и масштаб
local function ApplyLayout(frame, opts)
    local c = ConfigOf(opts)
    if not c then return end
    local x = c.x or opts.defaultX or 0
    local y = c.y or opts.defaultY or 0
    local scale = c.scale or 1.0
    if scale <= 0 then scale = 1.0 end
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
    if opts.onChanged then pcall(opts.onChanged) end
end

-- Сохранить позицию из текущего положения фрейма (после перетаскивания)
local function SaveFromFrame(frame, opts)
    local c = ConfigOf(opts)
    if not c then return end
    local fcx, fcy = frame:GetCenter()
    if not fcx then return end
    local s = frame:GetScale() or 1
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    c.x = fcx * s - uw / 2
    c.y = fcy * s - uh / 2
    if opts.onChanged then pcall(opts.onChanged) end
end

-- -------------------------------------------------------------------------
-- Плёнка редактора: голубая полупрозрачная заливка + тонкая рамка (как у наших
-- муверов). Кроет ВЕСЬ фрейм, сама интерактивна (высокая страта, чтобы окна с
-- SetToplevel не выпихнули кнопки выше). Клик открывает диалог настроек
-- (проксируем в onMouseDown области выделения LibEditMode), драг двигает.
-- -------------------------------------------------------------------------
local function EnsureFilm(frame)
    if frame._emFilm then return frame._emFilm end
    local film = CreateFrame("Frame", nil, frame)
    film:SetAllPoints(frame)
    film:SetFrameStrata("FULLSCREEN_DIALOG")
    film:SetFrameLevel(200)
    film:EnableMouse(true)
    film:RegisterForDrag("LeftButton")

    local fill = film:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0.55, 0.85, 0.45)
    local edge = film:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.3, 0.85, 1, 0.35)

    film:SetScript("OnMouseDown", function()
        local sel = LEM.frameSelections and LEM.frameSelections[frame]
        if sel then
            local h = sel:GetScript("OnMouseDown")
            if h then pcall(h, sel) end
        end
    end)
    film:SetScript("OnDragStart", function()
        if not InCombatLockdown() and frame:IsMovable() then frame:StartMoving() end
    end)
    film:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local d = registered[frame]
        if d then SaveFromFrame(frame, d.opts) end
        if LEM.RefreshFrameSettings then LEM:RefreshFrameSettings(frame) end
    end)

    frame._emFilm = film
    film:Hide()
    return film
end

-- Глобальные колбэки Edit Mode регистрируем один раз
local hookedGlobals = false
local function EnsureGlobalCallbacks()
    if hookedGlobals or not LEM then return end
    hookedGlobals = true

    LEM:RegisterCallback("layout", function()
        for frame, d in pairs(registered) do
            ApplyLayout(frame, d.opts)
        end
    end)
    LEM:RegisterCallback("enter", function()
        for frame, d in pairs(registered) do
            if d.opts.showInEditMode and not frame:IsShown() then
                frame._emForced = true
                if d.opts.onEditModeShow then pcall(d.opts.onEditModeShow, frame) end
                frame:Show()
            end
            EnsureFilm(frame):Show()
        end
    end)
    LEM:RegisterCallback("exit", function()
        for frame, d in pairs(registered) do
            if frame._emFilm then frame._emFilm:Hide() end
            if frame._emForced then
                frame._emForced = nil
                frame:Hide()
                if d.opts.onEditModeHide then pcall(d.opts.onEditModeHide, frame) end
            end
        end
    end)
end

-- Форматтеры
local function CoordFmt(v) return tostring(math.floor((v or 0) + 0.5)) end
local function PctScale(v)
    if FormatPercentage then return FormatPercentage(v, true) end
    return string.format("%d%%", math.floor((v or 1) * 100 + 0.5))
end

-- Публичная регистрация фрейма.
-- opts = { name, key, defaultX, defaultY, minScale, maxScale,
--          getCfg, onChanged, showInEditMode, onEditModeShow, onEditModeHide }
function ns.EditMode.Register(frame, opts)
    if not LEM or not frame or registered[frame] then
        if LEM and registered[frame] then ApplyLayout(frame, opts) end
        return LEM ~= nil
    end

    local c = ConfigOf(opts)
    if not c then return false end
    if c.x == nil then c.x = opts.defaultX or 0 end
    if c.y == nil then c.y = opts.defaultY or 0 end
    c.scale = c.scale or 1.0

    EnsureGlobalCallbacks()

    LEM:AddFrame(frame, function()
        SaveFromFrame(frame, opts)
        LEM:RefreshFrameSettings(frame)
    end, { point = "CENTER", x = 0, y = 0 }, opts.name)

    -- пределы координат по размеру экрана (± половина экрана от центра)
    local uw = UIParent:GetWidth() or 1920
    local uh = UIParent:GetHeight() or 1080
    local maxX = math.floor(uw / 2)
    local maxY = math.floor(uh / 2)

    local settings = {
        {
            name = "Координата X",
            kind = LEM.SettingType.Slider,
            default = 0, minValue = -maxX, maxValue = maxX, valueStep = 1,
            get = function() return c.x end,
            set = function(_, v) c.x = v; ApplyLayout(frame, opts) end,
            formatter = CoordFmt,
        },
        {
            name = "Координата Y",
            kind = LEM.SettingType.Slider,
            default = 0, minValue = -maxY, maxValue = maxY, valueStep = 1,
            get = function() return c.y end,
            set = function(_, v) c.y = v; ApplyLayout(frame, opts) end,
            formatter = CoordFmt,
        },
        {
            name = "Размер",
            kind = LEM.SettingType.Slider,
            default = 1.0,
            minValue = opts.minScale or 0.5,
            maxValue = opts.maxScale or 2.0,
            valueStep = 0.05,
            get = function() return c.scale end,
            set = function(_, v) c.scale = v; ApplyLayout(frame, opts) end,
            formatter = PctScale,
        },
    }
    -- Доп. настройки модуля (например слайдер «Ширина» у полосы готовности).
    if opts.extraSettings then
        for _, s in ipairs(opts.extraSettings) do settings[#settings + 1] = s end
    end
    LEM:AddFrameSettings(frame, settings)

    registered[frame] = { opts = opts }
    ApplyLayout(frame, opts)
    return true
end

-- Сохранить позицию зарегистрированного фрейма из его текущего положения
-- (для свободного перетаскивания в обычной игре — координаты попадут в тот же
-- конфиг, что и слайдеры X/Y редактора). Без библиотеки — тихо ничего.
function ns.EditMode.SaveFrame(frame)
    local d = frame and registered[frame]
    if d then SaveFromFrame(frame, d.opts) end
end