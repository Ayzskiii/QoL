local addonName = ...
local QoL = CreateFrame("Frame")

-- =========================
-- Default Settings
-- =========================
local defaults = {
    autoSell = false,
    autoRepair = false,
    autoQuest = false,
    autoReagentSort = false,
    autoRelease = false,
    skipCinematics = false,
    rareAlert = false,
    bagWarning = false,
    minimapAngle = 45,
}

-- =========================
-- Utility / Print
-- =========================
local function StatusColor(value)
    return value and "|cff26c914ENABLED|r" or "|cffc91414DISABLED|r"
end

local function Print(msg)
    print("|cffd83d1e[QoL+]|r " .. msg)
end

local function GetSetting(key)
    if not QoL_Settings then return defaults[key] end
    if QoL_Settings[key] == nil then return defaults[key] end
    return QoL_Settings[key]
end

-- =========================
-- Bag Check
-- =========================
local function HasFreeBagSpace()
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            if not GetContainerItemLink(bag, slot) then
                return true
            end
        end
    end
    return false
end

-- =========================
-- Throttle
-- =========================
local lastQuestAction = 0
local function CanDoQuestAction()
    if GetTime() - lastQuestAction > 0.2 then
        lastQuestAction = GetTime()
        return true
    end
    return false
end

-- =========================
-- Auto Sell Junk
-- =========================
local function AutoSell()
    if not GetSetting("autoSell") then return end

    local total = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
                if quality == 0 and price and price > 0 then
                    local _, count = GetContainerItemInfo(bag, slot)
                    UseContainerItem(bag, slot)
                    total = total + (price * count)
                end
            end
        end
    end

    if total > 0 then
        Print("Sold junk for " .. GetCoinTextureString(total))
    end
end

-- =========================
-- Auto Repair
-- =========================
local function AutoRepair()
    if not GetSetting("autoRepair") then return end
    if not CanMerchantRepair() then return end

    local cost = GetRepairAllCost()
    if cost and cost > 0 then
        if IsInGuild() and CanGuildBankRepair() then
            RepairAllItems(true)
            Print("Repaired using Guild Funds.")
        else
            RepairAllItems(false)
            Print("Repaired for " .. GetCoinTextureString(cost))
        end
    end
end

-- =========================
-- Auto Quest
-- =========================
local function AutoQuestHandler(event)
    if not GetSetting("autoQuest") then return end
    if not HasFreeBagSpace() then return end

    if event == "QUEST_DETAIL" then
        if not CanDoQuestAction() then return end
        
        local activeGossip = { GetGossipActiveQuests() }
        local hasActiveGossip = false
        if #activeGossip > 0 then
            for i = 1, #activeGossip, 6 do
                if activeGossip[i + 3] then
                    hasActiveGossip = true
                    break
                end
            end
        end

        local hasActiveGreeting = (GetNumActiveQuests() > 0)

        if hasActiveGossip or hasActiveGreeting then
            DeclineQuest() 
            return
        end

        AcceptQuest()

    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable() then
            CompleteQuest()
        end

    elseif event == "QUEST_COMPLETE" then
        if not CanDoQuestAction() then return end
        
        if GetNumQuestChoices() <= 1 then
            GetQuestReward(1)
        end
    end
end

-- =========================
-- Auto Gossip
-- =========================
local function AutoGossip()
    if not GetSetting("autoQuest") then return end

    local active = { GetGossipActiveQuests() }
    if #active > 0 then
        for i = 1, #active, 6 do
            local isComplete = active[i + 3]
            if isComplete then
                if not CanDoQuestAction() then return end
                SelectGossipActiveQuest((i + 5) / 6)
                return
            end
        end
    end

    local available = { GetGossipAvailableQuests() }
    if #available > 0 then
        if not CanDoQuestAction() then return end
        SelectGossipAvailableQuest(1)
        return
    end
end

-- =========================
-- Auto Reagent
-- =========================
local function AutoReagent()
    if not GetSetting("autoReagentSort") then return end
    if IsReagentBankUnlocked() then
        DepositReagentBank()
        Print("Reagents deposited.")
    end
end

-- =========================
-- Rare Tracking
-- =========================
local rareCache = {}
local RARE_COOLDOWN = 60
local MAX_ALERTS = 3

local function IsRare(unit)
    if not UnitExists(unit) then return false end
    local classification = UnitClassification(unit)
    return classification == "rare" or classification == "rareelite"
end

local function HandleRare(unit)
    if not GetSetting("rareAlert") then return end
    if not IsRare(unit) then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local now = GetTime()
    if not rareCache[guid] then
        rareCache[guid] = {count = 0, lastSeen = 0}
    end

    local data = rareCache[guid]
    if now - data.lastSeen < RARE_COOLDOWN then return end
    if data.count >= MAX_ALERTS then return end

    data.count = data.count + 1
    data.lastSeen = now

    local name = UnitName(unit)
    Print("Rare detected nearby: " .. name)
    PlaySound(8959, "Master")
end

-- =========================
-- Inventory Warning
-- =========================
local function BagWarning()
    if not GetSetting("bagWarning") then return end
    if not HasFreeBagSpace() then
        Print("Inventory is full.")
    end
end

-- =========================
-- Panel
-- =========================
local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", addonName .. "OptionsPanel", InterfaceOptionsFramePanelContainer)
    panel.name = "QoL+"

    local yOffset = -20

    local function AddTitle(text, size, iconPath)
        local iconSize = 20
        local xOffset = 20

        local icon
        if iconPath then
            icon = panel:CreateTexture(nil, "ARTWORK")
            icon:SetSize(iconSize, iconSize)
            icon:SetPoint("TOPLEFT", xOffset, yOffset - 2)
            icon:SetTexture(iconPath)
            xOffset = xOffset + iconSize + 6
        end

        local fs = panel:CreateFontString(nil, "OVERLAY", size or "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", xOffset, yOffset)
        fs:SetText(text)

        yOffset = yOffset - 30
        return fs
    end

    local function AddDivider()
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetHeight(2)
        line:SetPoint("TOPLEFT", 20, yOffset)
        line:SetPoint("TOPRIGHT", -20, yOffset)
        line:SetColorTexture(0.847, 0.239, 0.118, 0.85)
        yOffset = yOffset - 20
    end

    local function AddSection(text)
        local section = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        section:SetPoint("TOPLEFT", 20, yOffset)
        section:SetText("|cffe3891b" .. text .. "|r")
        yOffset = yOffset - 25
    end

    local function AddCheckbox(label, desc, key)
        local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, yOffset)
        cb.Text:SetText(label)

        cb:SetScript("OnClick", function(self)
            local value = self:GetChecked()
            QoL_Settings[key] = value

            local status = value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
            print("|cffd83d1e[QoL+]|r " .. label .. " is now " .. status)
        end)

        local descText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        descText:SetPoint("TOPLEFT", 40, yOffset - 18)
        descText:SetText("|cff757575" .. desc .. "|r")

        yOffset = yOffset - 45

        cb.key = key
        return cb
    end

    AddTitle("|cFFD83D1EQoL+|r", "GameFontNormalLarge")
    AddTitle("|cffaaaaaaQuality of Life | Version 3.0 | Made by Ayzi", "GameFontHighlightSmall")
    AddDivider()

    AddSection("Automation")
    local cbAutoSell = AddCheckbox("Auto Sell Junk", "Automatically sells grey items at vendors.", "autoSell")
    local cbAutoRepair = AddCheckbox("Auto Repair", "Repairs gear automatically.", "autoRepair")
    local cbAutoQuest = AddCheckbox("Auto Accept/Turn-in Quests", "Automatically accepts and completes quests.", "autoQuest")
    local cbSkipCinematics = AddCheckbox("Skip Cinematics", "Automatically skips cutscenes.", "skipCinematics")
    local cbAutoRelease = AddCheckbox("Auto Release Spirit", "Automatically releases after death.", "autoRelease")

    AddSection("Tracking")
    local cbRare = AddCheckbox("Rare Mob Alert", "Alerts when rare enemies appear nearby.", "rareAlert")

    AddSection("Utility")
    local cbBagWarning = AddCheckbox("Bag Space Warning", "Warns when bag space is low.", "bagWarning")

    AddTitle("|cffaaaaaaUpdated 30.05 - Any issues report on discord: realvelu", "GameFontHighlightSmall", "Interface\\Icons\\INV_Misc_Gear_01")

    panel.refresh = function()
        cbAutoSell:SetChecked(GetSetting("autoSell"))
        cbAutoRepair:SetChecked(GetSetting("autoRepair"))
        cbRare:SetChecked(GetSetting("rareAlert"))
        cbAutoQuest:SetChecked(GetSetting("autoQuest"))
        cbSkipCinematics:SetChecked(GetSetting("skipCinematics"))
        cbAutoRelease:SetChecked(GetSetting("autoRelease"))
        cbBagWarning:SetChecked(GetSetting("bagWarning"))
    end

    InterfaceOptions_AddCategory(panel)
end

-- =========================
-- Minimap Button
-- =========================
local function CreateMinimapButton()
    local btn = CreateFrame("Button", "QoLPlusMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    btn:EnableMouse(true)
    btn:SetMovable(true)

    local background = btn:CreateTexture(nil, "BACKGROUND")
    background:SetSize(25, 25)
    background:SetPoint("CENTER", btn, "CENTER", 0, 0)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(31, 31)
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetTexCoord(0.0, 0.6, 0.0, 0.6)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(31, 31)
    highlight:SetPoint("CENTER", btn, "CENTER", 0, 0)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    btn:SetHighlightTexture(highlight)

    local pushed = btn:CreateTexture(nil, "OVERLAY")
    pushed:SetSize(31, 31)
    pushed:SetPoint("CENTER", btn, "CENTER", 1, -1)
    pushed:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    pushed:SetBlendMode("ADD")
    btn:SetPushedTexture(pushed)

    btn:SetPushedTextOffset(1, -1)

    local angle = GetSetting("minimapAngle") or 45
    local function UpdatePosition()
        local radius = 80 
        btn:ClearAllPoints()
        btn:SetPoint(
            "CENTER",
            Minimap,
            "CENTER",
            math.cos(math.rad(angle)) * radius,
            math.sin(math.rad(angle)) * radius
        )
    end
    UpdatePosition()

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if InterfaceOptionsFrame:IsShown() then
                InterfaceOptionsFrameCancel:Click()
            else
                InterfaceOptionsFrame_OpenToCategory("QoL+")
                InterfaceOptionsFrame_OpenToCategory("QoL+")
            end
        elseif button == "RightButton" then
            print("|cffd83d1eQoL+:|r Use /qol to view current settings.")
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffd83d1eQoL+|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left Click: Open/Close Settings", 1, 1, 1)
        GameTooltip:AddLine("Right Click: Help", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move Button", 1, 1, 1)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            if mx and my and scale and scale > 0 then
                mx = mx / scale
                my = my / scale
                local cx, cy = Minimap:GetCenter()
                if cx and cy then
                    angle = math.deg(math.atan2(my - cy, mx - cx))
                    if QoL_Settings then QoL_Settings.minimapAngle = angle end
                    UpdatePosition()
                end
            end
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

-- =========================
-- Events
-- =========================
QoL:RegisterEvent("ADDON_LOADED")
QoL:RegisterEvent("MERCHANT_SHOW")
QoL:RegisterEvent("QUEST_DETAIL")
QoL:RegisterEvent("QUEST_PROGRESS")
QoL:RegisterEvent("QUEST_COMPLETE")
QoL:RegisterEvent("GOSSIP_SHOW")
QoL:RegisterEvent("QUEST_GREETING")
QoL:RegisterEvent("BANKFRAME_OPENED")
QoL:RegisterEvent("PLAYER_DEAD")
QoL:RegisterEvent("CINEMATIC_START")
QoL:RegisterEvent("PLAY_MOVIE")
QoL:RegisterEvent("NAME_PLATE_UNIT_ADDED")
QoL:RegisterEvent("BAG_UPDATE_DELAYED")

QoL:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == addonName then
            QoL_Settings = QoL_Settings or {}
            for k, v in pairs(defaults) do
                if QoL_Settings[k] == nil then QoL_Settings[k] = v end
            end
            CreateOptionsPanel()
            CreateMinimapButton()
            Print("Loaded successfully. Open settings via Minimap button or /qol")
        end

    elseif event == "MERCHANT_SHOW" then
        AutoSell()
        AutoRepair()

    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        AutoQuestHandler(event)

    elseif event == "GOSSIP_SHOW" then
        AutoGossip()

    elseif event == "QUEST_GREETING" then
        if not GetSetting("autoQuest") then return end
        
        local numActive = GetNumActiveQuests()
        if numActive > 0 then
            for i = 1, numActive do
                if not CanDoQuestAction() then return end
                SelectActiveQuest(i)
                return
            end
        end

        local numAvailable = GetNumAvailableQuests()
        if numAvailable > 0 then
            if not CanDoQuestAction() then return end
            SelectAvailableQuest(1)
            return
        end

    elseif event == "BANKFRAME_OPENED" then
        AutoReagent()

    elseif event == "PLAYER_DEAD" then
        if GetSetting("autoRelease") then
            C_Timer.After(2, function()
                if UnitIsDeadOrGhost("player") then RepopMe() end
            end)
        end

    elseif event == "CINEMATIC_START" then
        if GetSetting("skipCinematics") then CinematicFrame_CancelCinematic() end
    
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        HandleRare(unit)

    elseif event == "PLAY_MOVIE" then
        if GetSetting("skipCinematics") then MovieFrame:StopMovie() end

    elseif event == "BAG_UPDATE_DELAYED" then
        BagWarning()
    end
end)

-- =========================
-- Slash Command
-- =========================
SLASH_QOL1 = "/qol"
SlashCmdList["QOL"] = function()
    Print("Current Settings:")
    for k, v in pairs(defaults) do
        if k ~= "minimapAngle" then
            print("  " .. k .. ": " .. StatusColor(GetSetting(k)))
        end
    end
end