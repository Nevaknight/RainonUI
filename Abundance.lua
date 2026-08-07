-- =========================================================================
-- RainonUI / Abundance: звук при завершении события «Сбор изобилия».
--
-- Плашку-итог (EventToastManagerFrame) можно прятать в HideUI (hide.event),
-- поэтому цепляемся не к её видимости, а к методу показа тоста
-- (hooksecurefunc(EventToastManagerFrame, "DisplayToast")). После вызова данные
-- лежат в .currentDisplayingToast.toastInfo: title/subtitle/eventToastID/
-- uiWidgetSetID/displayType.
--
-- Звук срабатывает ТОЛЬКО по точному числовому идентификатору завершения
-- (ns.db.features.abundanceEventToastID = 384, запасной — uiWidgetSetID).
-- Включение и выбор звука — во вкладке «Удобства» окна настроек.
-- =========================================================================
local _, ns = ...

local _issecret = issecretvalue or function() return false end

local function C(hex, s) return (ns.C and ns.C(hex, s)) or s end

-- ── Выбор звука (по образцу воскрешения в Tools.lua) ──────────────────────
local function CurrentSoundName()
    local f = ns.db and ns.db.features
    local v = f and f.abundanceSound
    if type(v) == "string" and v ~= "" then return v end
    local def = (ns.Tools and ns.Tools.DefaultSoundName and ns.Tools.DefaultSoundName()) or "None"
    if f then f.abundanceSound = def end
    return def
end

local function PlaySound_()
    if ns.Tools and ns.Tools.PlaySoundByName then
        ns.Tools.PlaySoundByName(CurrentSoundName())
    end
end

-- ── Данные текущего тоста ─────────────────────────────────────────────────
local function GetToastInfo(mgr)
    mgr = mgr or _G.EventToastManagerFrame
    local toast = mgr and mgr.currentDisplayingToast
    local info = toast and (toast.toastInfo or toast.data)
    if not info and _G.C_EventToastManager and C_EventToastManager.GetNextToastToDisplay then
        local ok, res = pcall(C_EventToastManager.GetNextToastToDisplay)
        if ok then info = res end
    end
    return info
end

local function Field(info, key)
    local ok, v = pcall(function() return info[key] end)
    if not ok or v == nil or _issecret(v) then return nil end
    return v
end

-- Плашка завершения изобилия — по точному eventToastID (или uiWidgetSetID).
local function IsCompletionToast(info)
    if type(info) ~= "table" then return false end
    local f = ns.db and ns.db.features
    if not f then return false end
    local wantEvent = f.abundanceEventToastID
    if wantEvent then
        local id = Field(info, "eventToastID")
        if id and id == wantEvent then return true end
    end
    local wantWidget = f.abundanceWidgetSet
    if wantWidget then
        local wid = Field(info, "uiWidgetSetID")
        if wid and wid == wantWidget then return true end
    end
    return false
end

-- ── Хук показа тоста: звук по точному ID ──────────────────────────────────
local lastToast, lastTime = nil, 0

local function OnDisplayToast(mgr)
    local info = GetToastInfo(mgr)
    if not info then return end
    if not (ns.db and ns.db.features and ns.db.features.abundanceSoundOn) then return end
    if not IsCompletionToast(info) then return end

    -- защита от двойного вызова на одном показе
    local now = GetTime and GetTime() or 0
    local cur = mgr and mgr.currentDisplayingToast
    if lastToast == cur and (now - lastTime) < 1 then return end
    lastToast, lastTime = cur, now
    PlaySound_()
end

local hookInstalled = false
local function InstallHook()
    if hookInstalled then return end
    local mgr = _G.EventToastManagerFrame
    if mgr and type(mgr.DisplayToast) == "function" then
        hooksecurefunc(mgr, "DisplayToast", function(self) pcall(OnDisplayToast, self) end)
        hookInstalled = true
    end
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    InstallHook()
    if not hookInstalled then C_Timer.After(3, InstallHook) end
end)

-- ── Публичное API ─────────────────────────────────────────────────────────
ns.Abundance = {
    CurrentSoundName = CurrentSoundName,
    PlayPreview      = PlaySound_,
}

-- Слэш /rsabund — короткая справка + превью выбранного звука
SLASH_RAINONABUND1 = "/rsabund"
SlashCmdList.RAINONABUND = function()
    PlaySound_()
    ns.Print("изобилие: звук проигран (превью). Включение и выбор — " ..
        C("FFFF00", "/rainon") .. " → «Удобства» → «Изобилие».")
end
