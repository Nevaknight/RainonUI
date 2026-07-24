-- =========================================================================
-- RainonUI / GameMenu: кнопка «Перезагрузить интерфейс» сверху ESC-меню.
--
-- Пул кнопок игрового меню (GameMenuFrame.buttonPool) Blizzard раскладывает
-- заново при каждом открытии через метод Layout. Мы вешаем хук на Layout,
-- сдвигаем родные кнопки вниз и вставляем свою кнопку в самый верх, увеличив
-- высоту рамки. ReloadUI() — не защищённая функция, но саму раскладку в бою
-- не трогаем (перемещать чужие кнопки в бою рискованно), поэтому в бою просто
-- прячем свою кнопку.
-- =========================================================================
local _, ns = ...

local function Enabled()
    return not (ns.db and ns.db.features and ns.db.features.reloadMenuButton == false)
end

local reloadBtn
local baseHeight

local function Layout()
    if not reloadBtn then return end
    if not Enabled() or InCombatLockdown() then
        reloadBtn:Hide()
        return
    end
    local pool = GameMenuFrame and GameMenuFrame.buttonPool
    if not (pool and pool.EnumerateActive) then return end

    -- Самая верхняя активная кнопка меню (по ней берём размер и точку вставки)
    local ref, topY
    for b in pool:EnumerateActive() do
        local t = b:GetTop()
        if t and (not topY or t > topY) then topY = t; ref = b end
    end
    if not ref then reloadBtn:Hide(); return end

    local w, h = ref:GetWidth(), ref:GetHeight()
    if w and w > 0 then reloadBtn:SetSize(w, h or 35) end
    local extraH = (h or 35) + 12

    -- Сдвигаем ВСЕ родные кнопки вниз, освобождая верхний слот
    for b in pool:EnumerateActive() do
        local p, rel, rp, x, y = b:GetPoint(1)
        if p then
            b:ClearAllPoints()
            b:SetPoint(p, rel, rp, x, (y or 0) - extraH)
        end
    end

    -- Наша кнопка встаёт на бывшее место самой верхней
    reloadBtn:ClearAllPoints()
    reloadBtn:SetPoint("BOTTOM", ref, "TOP", 0, 12)
    reloadBtn:Show()

    if not baseHeight then baseHeight = GameMenuFrame:GetHeight() end
    GameMenuFrame:SetHeight(baseHeight + extraH)
end

local function EnsureButton()
    if reloadBtn or not GameMenuFrame then return end
    reloadBtn = CreateFrame("Button", "RainonUI_ReloadMenuButton",
        GameMenuFrame, "MainMenuFrameButtonTemplate")
    reloadBtn:SetSize(200, 35)
    reloadBtn:SetText("Перезагрузить UI")
    reloadBtn:SetScript("OnClick", function()
        HideUIPanel(GameMenuFrame)
        ReloadUI()
    end)
    hooksecurefunc(GameMenuFrame, "Layout", Layout)
end

if GameMenuFrame then
    EnsureButton()
else
    ns.RegisterEvent("PLAYER_LOGIN", EnsureButton)
end