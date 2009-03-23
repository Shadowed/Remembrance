Remembrance = {}

local L = RemembranceLocals
local Orig_CanInspect, Orig_InspectFrame_Show
local inspectData = {timeOut = 1000000000000000}

function Remembrance:OnInitialize()
	RemembranceDB = RemembranceDB or {trees = false}
	
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		self:HookInspect()
	end
end

-- Send off a inspect request
local function sendInspectRequest(unit, type)
	-- For some reason, we can't do NotifyInspect on the player
	if( UnitIsUnit("player", unit) ) then
		return
	end
	
	local class, classToken = UnitClass(unit)
	local name, server = UnitName(unit)
	if( server == "" ) then
		server = nil
	end
	
	inspectData.sent = true
	inspectData.type = type or "manual"
	inspectData.name = name
	inspectData.server = server or GetRealmName()
	inspectData.class = class
	inspectData.classToken = classToken
	inspectData.timeOut = GetTime() + 3
	
	NotifyInspect(unit)
end

function Remembrance:INSPECT_TALENT_READY()
	if( inspectData.type == "manual" ) then
		self:SaveTalentInfo(inspectData.name, inspectData.server, inspectData.class, inspectData.classToken)
	end
	
	-- Reset
	-- In a few million years, we're fucked
	inspectData.sent = nil
	inspectData.timeOut = 1000000000000000
	inspectData.name = nil
	inspectData.type = nil
	
	-- Enable the inspect tab
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		PanelTemplates_EnableTab(InspectFrame, 3)
	end
end

function Remembrance:SaveTalentInfo(name, server, class, classToken)
	name = string.format("%s-%s", name, server)
	
	local firstName, _, firstPoints = GetTalentTabInfo(1, true)
	local secondName, _, secondPoints = GetTalentTabInfo(2, true)
	local thirdName, _, thirdPoints = GetTalentTabInfo(3, true)
	
	-- Output talent info
	if( inspectData.type ~= "inspect" ) then
		if( RemembranceDB.tree ) then
			self:Print(string.format("%s (%s): %s (%d), %s (%d), %s (%d)", name, class, firstName or L["Unknown"], firstPoints or 0, secondName or L["Unknown"], secondPoints or 0, thirdName or L["Unknown"], thirdPoints or 0))
		else
			self:Print(string.format("%s (%s): %d/%d/%d", name, class, firstPoints, secondPoints, thirdPoints))
		end
	end
end

-- Hook the inspection frame being shown, and the validation checks
function Remembrance:HookInspect()
	if( Orig_InspectFrame_Show ) then
		return
	end
	
	Orig_InspectFrame_Show = InspectFrame_Show
	InspectFrame_Show = function(...)
		inspectData.sent = true
		inspectData.name = nil
		inspectData.type = "inspect"

		PanelTemplates_DisableTab(InspectFrame, 3)
		
		Orig_InspectFrame_Show(...)
	end
end

-- Output (SHOCKING)
function Remembrance:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99Remembrance|r: " .. msg)
end

function Remembrance:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Slash command handling
-- Validate unit
function Remembrance:ValidateUnit(unit)
	unit = string.lower(string.trim(unit))
	if( UnitExists(unit) or unit == "mouseover" or unit == "player" or unit == "target" or unit == "focus" or string.match(unit, "party[1-4]") or string.match(unit, "raid[1-40]") ) then
		return true
	end
	
	return nil
end

-- Inspect to show the entire tree
SLASH_REMINSPECT1 = "/inspect"
SLASH_REMINSPECT2 = "/in"
SlashCmdList["REMINSPECT"] = function(unit)
	LoadAddOn("Blizzard_InspectUI")
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		unit = string.trim(unit or "")
		if( unit == "" ) then
			unit = "target"
		end

		if( not Remembrance:ValidateUnit(unit) ) then
			Remembrance:Print(string.format(L["Invalid unit id \"%s\" entered, required player, target, focus, mouseover, party1-4, raid1-40"], unit))
			return
		end		
	
		InspectFrame_Show(unit)
	else
		Remembrance:Print(L["Failed to load Blizzard_InspectUI."])
	end
end

-- Quick inspect to only get the talent information
SLASH_REMQUICKIN1 = "/reminspect"
SLASH_REMQUICKIN2 = "/remin"
SLASH_REMQUICKIN3 = "/remembranceinspect"
SlashCmdList["REMQUICKIN"] = function(unit)
	local self = Remembrance
	
	-- Can only send one request at a time
	if( inspectData.sent and inspectData.timeOut < GetTime() ) then
		if( inspectData.name and inspectData.server ) then
			self:Print(string.format(L["Request has already been sent for %s of %s, please wait for it to finish."], inspectData.name, inspectData.server))
		else
			self:Print(L["Request has already been sent, please wait for it to finish."])
		end
		return
	end

	unit = string.trim(unit or "")
	if( unit == "" ) then
		unit = "target"
	end

	-- Validate unitid
	if( not self:ValidateUnit(unit) ) then
		self:Print(string.format(L["Invalid unit id \"%s\" entered, required player, target, focus, mouseover, party1-4, raid1-40"], unit))
		return

	-- Make sure they can be inspected
	elseif( not UnitIsPlayer(unit) or not UnitExists(unit) or not CanInspect(unit) ) then
		self:Print(string.format(L["Cannot inspect unit \"%s\", you can only inspect players of the same faction, or other-faction players who aren't flagged/hostile and are within 30 yards."], unit))
		return
	end

	sendInspectRequest(unit, "manual")
end

-- Reset things
SLASH_REMEMBRANCE1 = "/rem"
SLASH_REMEMBRANCE2 = "/remembrance"
SlashCmdList["REMEMBRANCE"] = function(msg)
	local self = Remembrance
	if( msg == "tree" ) then
		RemembranceDB.tree = not RemembranceDB.tree
		
		if( RemembranceDB.tree ) then
			self:Print(L["Now showing full tree names instead of simply ##/##/##."])
		else
			self:Print(L["No longer showing full tree names."])
		end
	
	elseif( msg == "cancel" ) then
		self:Print(L["Sync canceled, if you still have issues please do a /console reloadui. It'll usually take a few seconds for results to come back however from /reminspect."])

		for k in pairs(inspectData) do
			inspectData[k] = nil
		end
	else
		self:Print(L["Slash commands"])
		self:Echo(L["/inspect <unit> - Inspect a player, allows you to see the full talent tree."])
		self:Echo(L["/reminspect <unit> - Gets quick talent information for a player, shows name, server and total points spent."])
		self:Echo(L["/remembrance tree - Toggles showing full tree names instead of simply ##/##/##"])
		self:Echo(L["/remembrance cancel - Cancels a sent /reminspect request (shouldn't need this)."])
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("INSPECT_TALENT_READY")
frame:SetScript("OnEvent", function(self, event, ...)
	if( event == "ADDON_LOADED" ) then
		if( select(1, ...) == "Remembrance" ) then
			Remembrance:OnInitialize()
		elseif( select(1, ...) == "Blizzard_InspectUI" ) then
			Remembrance:HookInspect()
		end
		return
	end
	
	Remembrance[event](Remembrance, event, ...)
end)
