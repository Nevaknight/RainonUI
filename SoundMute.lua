-- =========================================================================
-- RainonUI / SoundMute: приглушение отдельных звуковых эффектов.
--
-- Работает через встроенные функции движка MuteSoundFile(fileDataID) /
-- UnmuteSoundFile(fileDataID) — это НЕ правка чужих фреймов, тэйнта нет.
-- Приглушение действует на ВСЕХ персонажей аккаунта (движок глушит файл
-- по его FileDataID глобально) и запоминается в SavedVariables (ns.db.soundMute),
-- поэтому при следующем входе выбранные звуки снова приглушаются автоматически.
--
-- Только стабильные, заранее заданные пресеты (никакого ручного ввода ID в игре):
-- по просьбе новые звуки добавляем сюда в PRESETS. FileDataID берутся с
-- wago.tools/sounds.
--
-- Вкладка «Звуки» в главном окне (см. Options.lua) вызывает Sound.BuildPanel().
-- =========================================================================
local _, ns = ...

local Sound = {}
ns.SoundMute = Sound

-- ── Безопасные обёртки над функциями движка ───────────────────────────────
local function DoMute(id)
    if id and type(MuteSoundFile) == "function" then pcall(MuteSoundFile, id) end
end
local function DoUnmute(id)
    if id and type(UnmuteSoundFile) == "function" then pcall(UnmuteSoundFile, id) end
end

-- ── Пресеты: label — подпись, icon — иконка (FileDataID или путь),
--    ids — список FileDataID звуков (глушим все), section — раздел окна,
--    spell — id способности (для подсказки), pending — ID ещё не задан. ──────
local PRESETS = {
    -- ── Общее ──
    {
        key = "mapPing", section = "Общее",
        label = "Клик по миникарте",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        ids = { 567416, 893809 },
        desc = "Звук, который проигрывается, когда кто-то ставит пинг-метку на карте или миникарте.",
    },
    -- ── Паладин ──
    {
        key = "pal_shieldRighteous", section = "Паладин",
        label = "Щит праведника",
        icon = 236265, spell = 53600,
        ids = { 568492, 569710, 569541, 569249,
                1353864, 1353865, 1353866, 1353867, 1353868,
                1395700, 1395701, 1395702, 1395703,
                1413278, 1413279, 1413280 },
        desc = "Звуки удара «Щита праведника».",
    },
    {
        key = "pal_avengerShield", section = "Паладин",
        label = "Щит мстителя",
        icon = 135874, spell = 31935,
        ids = { 1360121, 1360122, 1360123, 1360124, 1360125,
                1360126, 1360127, 1360128, 1360129, 1360130,
                567957, 1362393, 1362394, 1362395, 1362396 },
        desc = "Звуки удара и полёта «Щита мстителя».",
    },
    {
        key = "pal_blessedHammer", section = "Паладин",
        label = "Благословенный молот",
        icon = 535595, spell = 204019,
        ids = { 1376079, 1376080, 1376081, 1376082, 1376083,
                1376089, 1376090 },
        desc = "Звуки «Благословенного молота».",
    },
}

-- Порядок разделов в окне
local SECTIONS = { "Общее", "Паладин" }

-- ── Хранилище состояния (лениво, не трогаем Core.lua) ─────────────────────
local function DB()
    if not ns.db then return nil end
    ns.db.soundMute = ns.db.soundMute or {}
    return ns.db.soundMute
end

-- ── Применение пресета ────────────────────────────────────────────────────
local function ApplyPreset(p, on)
    local db = DB()
    if db then db[p.key] = on and true or false end
    for _, id in ipairs(p.ids) do
        if on then DoMute(id) else DoUnmute(id) end
    end
end

-- Приглушить всё выбранное (вызывается при входе в мир).
local function ApplyAllFromDB()
    local db = DB()
    if not db then return end
    for _, p in ipairs(PRESETS) do
        if db[p.key] then
            for _, id in ipairs(p.ids) do DoMute(id) end
        end
    end
end

-- Вернуть ВСЕ звуки (снять все приглушения).
local checks = {}      -- key → CheckButton (для обновления галочек)
local function UnmuteAll()
    for _, p in ipairs(PRESETS) do
        ApplyPreset(p, false)
        local cb = checks[p.key]
        if cb then cb:SetChecked(false) end
    end
    if ns.Print then ns.Print("все приглушённые звуки возвращены.") end
end

Sound.ApplyPreset = ApplyPreset
Sound.UnmuteAll   = UnmuteAll

-- ── Панель для вкладки «Звуки» в главном окне ─────────────────────────────
local function C(hex, s) return (ns.C and ns.C(hex, s)) or s end

function Sound.BuildPanel(container)
    local db = DB()
    local panel = CreateFrame("Frame", nil, container)
    panel:SetSize(520, 360)

    -- Верхнее пояснение
    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", 12, -10)
    info:SetPoint("TOPRIGHT", -12, -10)
    info:SetJustifyH("LEFT")
    info:SetText("Модуль " .. C("FFD100", "отключает звуки") .. " способностей и событий.")

    local y = -46

    local function AddSectionHeader(title)
        local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        h:SetPoint("TOPLEFT", 12, y)
        h:SetText(C("FFD100", title))
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.15)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 12, y - 20)
        line:SetPoint("TOPRIGHT", -12, y - 20)
        y = y - 30
    end

    local function AddRow(p)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 14, y)
        cb:SetChecked(db and db[p.key] and true or false)
        checks[p.key] = cb

        local ic = panel:CreateTexture(nil, "ARTWORK")
        ic:SetSize(22, 22)
        ic:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        ic:SetTexture(p.icon)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", ic, "RIGHT", 8, 0)
        lbl:SetText(p.label)

        cb:SetScript("OnClick", function(self)
            ApplyPreset(p, self:GetChecked())
        end)

        local function OnEnter(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(p.label, 1, 1, 1)
            if p.desc then GameTooltip:AddLine(p.desc, 0.8, 0.8, 0.8, true) end
            if #p.ids > 0 then
                GameTooltip:AddLine("FileDataID: " .. table.concat(p.ids, ", "), 0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end
        cb:SetScript("OnEnter", OnEnter)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

        y = y - 30
    end

    for _, section in ipairs(SECTIONS) do
        AddSectionHeader(section)
        for _, p in ipairs(PRESETS) do
            if p.section == section then AddRow(p) end
        end
        y = y - 8
    end

    -- Кнопка «Вернуть все звуки»
    local unmute = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unmute:SetSize(200, 26)
    unmute:SetPoint("TOPLEFT", 14, y - 6)
    unmute:SetText("Вернуть все звуки")
    unmute:SetScript("OnClick", UnmuteAll)
    unmute:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Вернуть все звуки", 1, 1, 1)
        GameTooltip:AddLine("Снимает приглушение со всех звуков из этого списка.",
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    unmute:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel:SetHeight(-y + 40)
    return panel
end

-- ── Приглушаем выбранное при входе в мир (ns.db уже готова) ───────────────
local applied = false
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if applied then return end
    applied = true
    ApplyAllFromDB()
end)
