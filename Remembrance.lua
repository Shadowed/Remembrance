Remembrance = LibStub("AceAddon-3.0"):NewAddon("Remembrance", "AceEvent-3.0")

local L = RemembranceLocals

local Orig_CanInspect

local instanceType
local alreadyInspected = {}
local inspectData = {}

function Remembrance:OnInitialize()
	-- Talent DB
	if( not RemembranceTalents ) then
		RemembranceTalents = {}	
	end
	
	-- Check if we've upgraded
	if( RemembranceDB and RemembranceDB.auto == nil ) then
		RemembranceDB = nil
		self:Print(L["Upgraded Remembrance DB, settings have been reset."])
	end

	-- Config DB
	if( not RemembranceDB ) then
		RemembranceDB = {
			auto = true,
			tree = false,
		}
	end
	
	-- Check if inspection is loaded by another addon
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		self:HookInspect()
	end
end

function Remembrance:OnEnable()
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("INSPECT_TALENT_READY")
	

	if( RemembranceDB.auto ) then
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "ZONE_CHANGED_NEW_AREA")

		self:ZONE_CHANGED_NEW_AREA()
	end
end

function Remembrance:OnDisable()
	self:UnregisterAllEvents()
end

function Remembrance:INSPECT_TALENT_READY()
	-- Sent through opening the inspection window
	if( inspectData.type == "inspect" and InspectFrame.unit ) then
		local name, server = UnitName(InspectFrame.unit)
		if( not server or server == "" ) then
			server = GetRealmName()
		end
		
		self:SaveTalentInfo(name, server, (UnitClass(InspectFrame.unit)))
	

	-- Manually sent through /rem, or it's an auto inspect
	elseif( inspectData.type == "manual" or inspectData.type == "auto" ) then
		self:SaveTalentInfo(inspectData.name, inspectData.server, inspectData.class)
	end
	
	-- Reset
	inspectData.sent = nil
	inspectData.name = nil
	inspectData.type = nil
	
	-- Enable the inspect tab
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		PanelTemplates_EnableTab(InspectFrame, 3)
	end
end

function Remembrance:SaveTalentInfo(name, server, class)
	name = name .. "-" .. server
	local talent = (select(3, GetTalentTabInfo(1, true)) or 0) .. "/" ..  (select(3, GetTalentTabInfo(2, true)) or 0) .. "/" ..  (select(3, GetTalentTabInfo(3, true)) or 0)
	
	-- Auto inspect + no change
	if( inspectData.type == "auto" and ( RemembranceTalents[name] == talent ) ) then
		return
	end

	RemembranceTalents[name] = talent
	
	-- /inspect don't bother outputting, but we still want to save
	if( inspectData.type == "inspect" ) then
		return
	end
	
	-- Output the full trees
	if( RemembranceDB.tree ) then
		local firstName, _, firstPoints = GetTalentTabInfo(1, true)
		local secondName, _, secondPoints = GetTalentTabInfo(2, true)
		local thirdName, _, thirdPoints = GetTalentTabInfo(3, true)
		
		self:Print(string.format("%s (%s): %s (%d), %s (%d), %s (%d)", name, class, firstName or L["Unknown"], firstPoints or 0, secondName or L["Unknown"], secondPoints or 0, thirdName or L["Unknown"], thirdPoints or 0))
	else
		self:Print(string.format("%s (%s): %s", name, class, talent))
	end

end

-- USE THIS INSTEAD OF CALLING THE SV TABLE
function Remembrance:GetTalents(name, server)
	-- Bad data passed

	if( not name or not server ) then

		return
	end
	
	name = name .. "-" .. server
	if( not RemembranceTalents[name] ) then
		return nil
	end
	
	local tree1, tree2, tree3 = string.split("/", RemembranceTalents[name])
	return tonumber(tree1) or 0, tonumber(tree2) or 0, tonumber(tree3) or 0
end

-- Inspection window was shown, reset data
function Remembrance:InspectFrame_Show()
	inspectData.sent = true
	inspectData.name = nil
	inspectData.type = "inspect"

	PanelTemplates_DisableTab(InspectFrame, 3)
end

-- Hook the inspection frame being shown, and the validation checks
function Remembrance:HookInspect()
	if( Orig_CanInspect ) then
		return
	end
	
	Orig_CanInspect = CanInspect
	CanInspect = function(unit, ...)
		if( UnitIsPlayer(unit) ) then
			return true
		end

		return Orig_CanInspect(unit, ...)
	end

	hooksecurefunc("InspectFrame_Show", self.InspectFrame_Show)
end

-- Inspect is LoD, so catch it here
function Remembrance:ADDON_LOADED(event, addon)
	if( addon == "Blizzard_InspectUI" ) then
		self:HookInspect()
		self:UnregisterEvent("ADDON_LOADED")
	end
end

-- For doing auto inspection inside arenas
function Remembrance:ZONE_CHANGED_NEW_AREA()
	local type = select(2, IsInInstance())
	-- Inside an arena, but wasn't already
	if( type == "arena" and type ~= instanceType ) then
		self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("PLAYER_FOCUS_CHANGED")
		
	-- Was in an arena, but left it
	elseif( type ~= "arena" and instanceType == "arena" ) then
		self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
		self:UnregisterEvent("PLAYER_TARGET_CHANGED")
		self:UnregisterEvent("PLAYER_FOCUS_CHANGED")
		
		-- Wipe our already inspected DB
		for i=#(alreadyInspected), 1, -1 do
			table.remove(alreadyInspected, i)
		end
	end
	
	instanceType = type
end

function Remembrance:ScanUnit(unit)
	if( inspectData.sent or not UnitIsVisible(unit) or not UnitIsPlayer(unit) or not UnitIsEnemy("player", unit) ) then
		return
	end
	
	local name, server = UnitName(unit)

	-- Already inspected them, don't bother again
	if( alreadyInspected[name] ) then
		return
	end

	if( not server or server == "" ) then
		server = GetRealmName()
	end
	
	alreadyInspected[name] = true

	inspectData.sent = true
	inspectData.type = "auto"
	inspectData.name = name
	inspectData.server = server
	inspectData.class = UnitClass(unit)
	
	NotifyInspect(unit)
end

-- For auto inspection
function Remembrance:PLAYER_TARGET_CHANGED()
	self:ScanUnit("target")
end

function Remembrance:UPDATE_MOUSEOVER_UNIT()
	self:ScanUnit("mouseover")
end

function Remembrance:PLAYER_FOCUS_CHANGED()
	self:ScanUnit("focus")
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
	if( unit == "mouseover" or unit == "player" or unit == "target" or unit == "focus" or string.match(unit, "party[1-4]") or string.match(unit, "raid[1-40]") ) then
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
	if( inspectData.sent ) then
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
	elseif( not UnitIsPlayer(unit) or not UnitExists(unit) ) then
		self:Print(string.format(L["Cannot inspect unit \"%s\", you can only inspect players, and people who are within visible range (100 yards) of you."], unit))
		return
	end

	-- We can't rely on the unitid being the same by the time the actual results arrive, we store the info ahead of time

	local name, server = UnitName(unit)
	if( not server or server == "" ) then
		server = GetRealmName()
	end

	inspectData.sent = true
	inspectData.type = "manual"
	inspectData.class = (UnitClass(unit))
	inspectData.name = name
	inspectData.server = server
	
	-- Send it off
	NotifyInspect(unit)
end

-- Reset things
SLASH_REMEMBRANCE1 = "/rem"
SLASH_REMEMBRANCE2 = "/remembrance"
SlashCmdList["REMEMBRANCE"] = function(msg)
	local self = Remembrance
	if( msg == "info" ) then
		local servers = {}
		local total = 0
		for player, talent in pairs(RemembranceTalents) do
			local name, server = string.split("-", player)
			servers[server] = (servers[server] or 0 ) + 1
			total = total + 1
		end
		
		self:Print(string.format(L["Total players saved %d"], total))
		
		for server, total in pairs(servers) do
			self:Echo(string.format(L["%s (%d)"], server, total))
		end
	
	elseif( msg == "tree" ) then
		RemembranceDB.tree = not RemembranceDB.tree
		
		if( RemembranceDB.tree ) then
			self:Print(L["Now showing full tree names instead of simply ##/##/##."])
		else
			self:Print(L["No longer showing full tree names."])
		end
	
	elseif( msg == "auto" ) then
		RemembranceDB.auto = not RemembranceDB.auto
		
		if( RemembranceDB.auto ) then
			self:Print(L["Now auto inspecting enemies inside arenas."])
		else
			self:Print(L["No longer auto inspecting enemies inside arenas."])
		end
		
		self:OnDisable()
		self:OnEnable()
		
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
		self:Echo(L["/remembrance auto - Toggles automatic inspection in arenas"])
		self:Echo(L["/remembrance cancel - Cancels a sent /reminspect request (shouldn't need this)."])
		self:Echo("")
		self:Echo(L["Both /inspect and /reminspect work regardless of player faction, and range as long as they're within 100 yards. You still cannot get the gear of a player from an enemy faction however."])
	end
end