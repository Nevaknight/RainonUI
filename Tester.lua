-- =========================================================================
-- RainonUI / Tester: отладочная панель с кнопками-тестами. Вызов: /rstest.
--
-- Панель — просто набор кнопок по секциям. Чтобы ДОБАВИТЬ новый тест в будущем,
-- достаточно либо дописать его в CollectTests() ниже, либо из любого файла
-- вызвать:  ns.Tester.Add("Секция", "Название кнопки", function() ... end)
-- (вызвать нужно до первого открытия панели — она строится лениво).
-- =========================================================================
local _, ns = ...

ns.Tester = ns.Tester or {}
local extra = {}   -- пользовательские тесты: { {section=, label=, fn=}, ... }

-- Публичное: добавить кнопку-тест из любого модуля.
function ns.Tester.Add(section, label, fn)
    extra[#extra + 1] = { section = section or "Прочее", label = label, fn = fn }
end

-- Собрать тесты: порядок секций + кнопки в каждой (встроенные + добавленные).
local function CollectTests()
    local order, bySection = {}, {}
    local function ensure(sec)
        if not bySection[sec] then bySection[sec] = {}; order[#order + 1] = sec end
        return bySection[sec]
    end

    -- ── Телепорт ──
    table.insert(ensure("Телепорт"), {
        label = "Показать окно телепорта",
        fn = function()
            if ns.Teleport and ns.Teleport.Test then ns.Teleport.Test()
            else ns.Print("тест телепорта недоступен") end
        end,
    })

    -- ── Стикеры ── (список берём из Tools)
    local stickers = (ns.Tools and ns.Tools.GetStickerTests and ns.Tools.GetStickerTests()) or {}
    for _, s in ipairs(stickers) do
        table.insert(ensure("Стикеры"), {
            label = s.label,
            fn = function()
                if ns.Tools and ns.Tools.TestSticker then ns.Tools.TestSticker(s.key, 5) end
            end,
        })
    end

    -- ── Добавленные из других модулей ──
    for _, e in ipairs(extra) do
        table.insert(ensure(e.section), { label = e.label, fn = e.fn })
    end

    return order, bySection
end

-- -------------------------------------------------------------------------
local panel

local PANEL_W = 250
local BTN_W   = 214
local PAD_X   = 18

local function BuildPanel()
    if panel then return panel end

    panel = CreateFrame("Frame", "RainonUITester", UIParent, "DefaultPanelFlatTemplate")
    panel:SetSize(PANEL_W, 100)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if panel.SetTitle then panel:SetTitle("RainonUI — Тестер") end
    table.insert(UISpecialFrames, "RainonUITester")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)

    local order, bySection = CollectTests()

    local y = -34
    for _, sec in ipairs(order) do
        -- Заголовок секции (жёлтый, как в настройках)
        local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hdr:SetPoint("TOPLEFT", PAD_X, y)
        hdr:SetText("|cFFFFD100" .. sec .. "|r")
        y = y - 24

        for _, t in ipairs(bySection[sec]) do
            local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            b:SetSize(BTN_W, 24)
            b:SetPoint("TOP", panel, "TOP", 0, y)
            b:SetText(t.label)
            b:SetScript("OnClick", t.fn)
            y = y - 28
        end
        y = y - 6
    end

    panel:SetHeight(-y + 16)
    panel:Hide()
    return panel
end

function ns.Tester.Toggle()
    BuildPanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

SLASH_RAINONTEST1 = "/rstest"
SlashCmdList.RAINONTEST = function() ns.Tester.Toggle() end
