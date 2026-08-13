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

-- =========================================================================
-- «Недельный маршрут» → импорт в MDT «как Поделиться».
--
-- MDT приватный (нет _G.MDT), импорт в публичный API не вынесен. Но его кнопка
-- «Поделиться» работает так: строка маршрута рассылается по каналу связи MDT
-- (AceComm, префикс "MDTPreset") и КЕШИРУЕТСЯ у получателя
-- (MDT.transmissionCache), а в чат падает кликабельная ссылка
-- `garrmission:mdt-<имя>+<реалм>`; клик достаёт пресет из кеша и импортирует
-- (MDT хукает SetItemRef → HandleChatLink).
--
-- Повторяем это для СЕБЯ: (1) шлём строку себе (self-whisper на "MDTPreset") —
-- MDT кеширует; (2) печатаем ту же ссылку. Клик — маршрут загружен.
-- Строку !~MDT2~ читаем сами штатным Blizzard `C_EncodingUtil` (base64→deflate
-- →CBOR), как `MDT:StringToTable`, чтобы взять подземелье и имя маршрута для
-- ссылки. Внешние либы не нужны; AceComm берём из LibStub (его грузит MDT).
--
-- ХРУПКО: это приватный протокол MDT (префикс/формат строки/формат ссылки).
-- Обновление MDT может это сломать — чиним здесь.
-- =========================================================================
local mdtComm

local function GetMDTComm()
    if mdtComm then return mdtComm end
    local AceComm = LibStub and LibStub("AceComm-3.0", true)
    if not AceComm then return nil end
    mdtComm = {}
    AceComm:Embed(mdtComm)
    return mdtComm
end

local function DecodeRoute(str)
    if type(str) ~= "string" or str:sub(1, 7) ~= "!~MDT2~" then return nil end
    if not (C_EncodingUtil and C_EncodingUtil.DecodeBase64) then return nil end
    local ok, preset = pcall(function()
        local dec = C_EncodingUtil.DecodeBase64(str:sub(8))
        if not dec then return nil end
        local dcmp = C_EncodingUtil.DecompressString(dec, Enum.CompressionMethod.Deflate)
        if not dcmp then return nil end
        return C_EncodingUtil.DeserializeCBOR(dcmp)
    end)
    return ok and preset or nil
end

-- routeString — строка !~MDT2~ маршрута конкретного подземелья.
function ns.Integrations.ShareMDTRoute(routeString)
    if not AddonOn("MythicDungeonTools") then
        ns.Print("Включите или установите аддон MDT, ссылку можно найти в разделе подземелий RainonUI.")
        return
    end
    if type(routeString) ~= "string" or routeString == "" then
        ns.Print("для этого подземелья маршрут ещё не задан.")
        return
    end
    local preset = DecodeRoute(routeString)
    local api = _G.MythicDungeonToolsAPI
    if not (type(preset) == "table" and preset.value and preset.text and api and api.GetDungeonName) then
        ns.Print("не удалось разобрать строку маршрута.")
        return
    end
    local dungeon = api:GetDungeonName(preset.value.currentDungeonIdx, true)
    if not dungeon then
        ns.Print("MDT не знает это подземелье (строка от другой версии MDT?).")
        return
    end
    local displayName = dungeon .. ": " .. preset.text

    local comm = GetMDTComm()
    if not comm then
        ns.Print("MDT: канал связи (AceComm) недоступен.")
        return
    end

    local name, realm = UnitFullName("player")
    if not (name and realm) then
        ns.Print("не удалось определить имя персонажа.")
        return
    end
    name = UnitFullName(name)  -- нормализуем регистр имени (как это делает MDT)

    -- (1) сеем строку в кеш MDT (self-whisper на его префикс)
    comm:SendCommMessage("MDTPreset", routeString, "WHISPER", name, "BULK")

    -- (2) печатаем кликабельную ссылку с задержкой — кеш наполняется асинхронно
    C_Timer.After(0.5, function()
        local link = "|cffe6cc80|Hgarrmission:mdt-" .. name .. "+" .. realm ..
            "|h[" .. displayName .. "]|h|r"
        ns.Print(link .. " Нажми, чтобы загрузить в MDT")
    end)
end
