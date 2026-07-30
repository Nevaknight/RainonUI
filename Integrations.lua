-- =========================================================================
-- RainonUI / Integrations: мост к CraftSim.
--
-- ВАЖНО: CraftSim держит всё в ПРИВАТНОЙ таблице аддона (local CraftSim =
-- select(2, ...)) — глобала `CraftSim`, публичного API и именованных окон он
-- НЕ выставляет. Поэтому напрямую вызвать его функции или прочитать «профит
-- сессии» снаружи нельзя (без правки самого CraftSim, а его мы не трогаем).
--
-- Единственная легальная точка входа — его ГЛОБАЛЬНАЯ слэш-команда:
--   /craftsim craftqueue createshoppinglist  → CreateAuctionatorShoppingList()
-- Её и дёргаем по кнопке на аукционе (SlashCmdList["CRAFTSIM"]).
--
-- «Окно профита сессии» тут НЕ делаем: CraftSim не отдаёт это значение наружу.
-- =========================================================================
local _, ns = ...

local function AddonOn(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if IsAddOnLoaded then return IsAddOnLoaded(name) end
    return false
end

-- CraftSim готов, если зарегистрирован его глобальный слэш-обработчик.
local function CraftSimReady()
    return SlashCmdList and SlashCmdList["CRAFTSIM"] ~= nil
end

local function AuctionatorOn()
    return _G.Auctionator ~= nil or AddonOn("Auctionator")
end

-- =========================================================================
-- Кнопка «Список покупок CraftSim» на аукционе
-- =========================================================================
local ahBtn

local function AHEnabled()
    return not (ns.db and ns.db.features and ns.db.features.craftAHButton == false)
end

local function TriggerShoppingList()
    if not CraftSimReady() then
        ns.Print("CraftSim не найден (или ещё не загрузился) — список покупок недоступен.")
        return
    end
    if not AuctionatorOn() then
        ns.Print("нужен Auctionator — CraftSim собирает список покупок в нём.")
        return
    end
    -- Глобальная слэш-команда CraftSim: собрать список покупок по очереди крафта.
    local ok = pcall(SlashCmdList["CRAFTSIM"], "craftqueue createshoppinglist")
    if ok then
        ns.Print("запрос в CraftSim отправлен. Список строится из ОЧЕРЕДИ крафта" ..
            " CraftSim — если он вышел пустым, значит очередь пуста или всё уже есть в сумках.")
    else
        ns.Print("не удалось вызвать CraftSim.")
    end
end

local function BuildAHButton()
    if ahBtn then return end
    local ah = _G.AuctionHouseFrame
    if not ah then return end
    ahBtn = CreateFrame("Button", "RainonUICraftShopBtn", ah, "UIPanelButtonTemplate")
    ahBtn:SetSize(210, 22)
    ahBtn:SetText("Список покупок CraftSim")
    ahBtn:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", -4, 2)  -- плавающая над окном АХ
    ahBtn:SetFrameStrata("HIGH")
    ahBtn:SetScript("OnClick", TriggerShoppingList)
    ahBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Список покупок CraftSim", 1, 1, 1)
        GameTooltip:AddLine("Просит CraftSim собрать список покупок для его ОЧЕРЕДИ" ..
            " крафта в Auctionator — не открывая сам CraftSim. Сначала добавь" ..
            " рецепты в очередь CraftSim.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateAHButton()
    -- Кнопку показываем только если включено, есть CraftSim и Auctionator.
    if not (AHEnabled() and CraftSimReady() and AuctionatorOn()) then
        if ahBtn then ahBtn:Hide() end
        return
    end
    BuildAHButton()
    if ahBtn then
        local ah = _G.AuctionHouseFrame
        ahBtn:SetShown(ah and ah:IsShown() and true or false)
    end
end

ns.RegisterEvent("AUCTION_HOUSE_SHOW", UpdateAHButton)
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    if ahBtn then ahBtn:Hide() end
end)

-- Публичный доступ для опций (переключатель в «Удобствах»).
ns.Integrations = {
    RefreshAH = UpdateAHButton,
}
