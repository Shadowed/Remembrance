Remembrance = {}

local L = RemembranceLocals

local notifyTalents
local notifyDifference
local sentPlayerServer
local sentPlayerName
local sentPlayerClass
local requestSent

local inspectQueue = {}
local alreadyQueued = {}

function Remembrance:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

function Remembrance:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99Remembrance|r: " .. msg)
end

function Remembrance:INSPECT_TALENT_READY()
	requestSent = nil
		

	-- Request sent through Remembrance
	if( sentPlayerName and sentPlayerServer ) then
		self:SaveTalentInfo(sentPlayerName, sentPlayerServer, sentPlayerClass)
		
		sentPlayerName = nil
		sentPlayerServer = nil
		sentPlayerClass = nil
	
	-- Request sent through Blizzards inspect frame
	elseif( InspectFrame and InspectFrame.unit ) then
		local name, server = UnitName(InspectFrame.unit)
		if( not server or server == "" ) then
			server = GetRealmName()
		end

		self:SaveTalentInfo(name, server, (UnitClass(InspectFrame.unit)))
	end

	-- Now enable the tab
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		PanelTemplates_EnableTab(InspectFrame, 3)
	end
end

-- Save the information by name/server
function Remembrance:SaveTalentInfo(name, server, class)
	name = name .. "-" .. server
	local talent = (select(3, GetTalentTabInfo(1, true)) or 0) .. "/" ..  (select(3, GetTalentTabInfo(2, true)) or 0) .. "/" ..  (select(3, GetTalentTabInfo(3, true)) or 0)
	
	if( ( notifyDifference and RemembranceTalents[name] ~= talent) or notifyTalents ) then
		self:Print(name .. " (" .. class .. "): " .. talent)
	end
	
	RemembranceTalents[name] = talent
	
	notifyDifference = nil
	notifyTalents = nil
end

-- USE THIS INSTEAD OF CALLING THE SV TABLE
function Remembrance:GetTalents(name, server)
	if( not RemembranceTalents[name .. "-" .. server] ) then
		return nil, nil, nil
	end
	
	local tree1, tree2, tree3 = string.split("/", RemembranceTalents[name .. "-" .. server])
	
	return tonumber(tree1) or 0, tonumber(tree2) or 0, tonumber(tree3) or 0
end

-- Clear all of our information since it's a manual request
function Remembrance:InspectFrame_Show()
	requestSent = true
	notifyTalents = nil
	sentPlayerName = nil
	sentPlayerServer = nil
	sentPlayerClass = nil
	
	PanelTemplates_DisableTab(InspectFrame, 3)
end

-- /whistle
-- This isn't exactly a good method for this, but it's quick and easy
-- May change it later, maybe add a range check. Not sure yet.
local Orig_CanInspect
function Remembrance:HookCanInspect()
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
end

-- Validate unit
function Remembrance:ValidateUnit(unit)
	unit = string.lower(string.trim(unit))
	
	if( unit == "mouseover" or unit == "player" or unit == "target" or unit == "focus" or string.match(unit, "party[1-4]") or string.match(unit, "raid[1-40]") ) then
		return true
	end
	
	return nil
end

-- Deal with caching people
function Remembrance:ScanUnit(unit)
	-- Already have a request pending, exit quickly
	if( select(2, IsInInstance()) ~= "arena" or requestSent or not UnitIsVisible(unit) or not UnitIsPlayer(unit) or not UnitIsEnemy("player", unit) ) then
		return

	end
	

	local name, server = UnitName(unit)
	if( not server or server == "" ) then
		server = GetRealmName()
	end
	
	local fullName = name .. "-" .. server
	
	-- Only inspect them once per a season
	if( alreadyQueued[fullName] ) then
		return
	end
	
	alreadyQueued[fullName] = true
	
	requestSent = true
	notifyTalents = nil
	notifyDifference = true
	sentPlayerName = name
	sentPlayerServer = server
	sentPlayerClass = (UnitClass(unit))
	
	NotifyInspect(unit)
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
	if( requestSent ) then
		if( sentPlayerName and sentPlayerServer ) then
			self:Print(string.format(L["Request has already been sent for %s of %s, please wait for it to finish."], sentPlayerName, sentPlayerServer))
		else
			self:Print(L["Request has already been sent, please wait for it to finish."])
		end
		return
	end

	unit = string.trim(unit or "")

	-- Default to target
	if( unit == "" ) then
		unit = "target"
	end

	-- Validate it
	if( not self:ValidateUnit(unit) ) then
		self:Print(string.format(L["Invalid unit id \"%s\" entered, required player, target, focus, mouseover, party1-4, raid1-40"], unit))
		return
	end

	-- Make sure we can actually inspect them
	if( not UnitIsPlayer(unit) or not UnitExists(unit) ) then
		self:Print(string.format(L["Cannot inspect unit \"%s\", you can only inspect players, and people who are within visible range (100 yards) of you."], unit))
		return
	end

	-- Flag it up
	requestSent = true
	notifyTalents = true

	-- Since we can't rely on the unit id being the same by the time it arrives
	sentPlayerClass = (UnitClass(unit))
	sentPlayerName, sentPlayerServer = UnitName(unit)
	if( not sentPlayerServer or sentPlayerServer == "" ) then
		sentPlayerServer = GetRealmName()
	end
	
	-- Send it off
	NotifyInspect(unit)
end

-- Reset things
SLASH_REMEMBRANCE1 = "/rem"
SLASH_REMEMBRANCE2 = "/remembrance"
SlashCmdList["REMEMBRANCE"] = function(msg)
	local self = Remembrance
	
	if( msg == "reset" ) then
		self:Print(L["All saved data has been reset"])

		RemembranceTalents = {}
	
	elseif( msg == "info" ) then
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
	
	elseif( msg == "auto" ) then
		RemembranceDB.autoInspect = not RemembranceDB.autoInspect
		
		if( RemembranceDB.autoInspect ) then
			self:Print(L["Now auto inspecting enemies inside arenas."])
		else
			self:Print(L["No longer auto inspecting enemies inside arenas."])
		end
		
	elseif( msg == "cancel" ) then
		self:Print(L["Sync canceled, if you still have issues please do a /console reloadui. It'll usually take a few seconds for results to come back however from /reminspect."])

		requestSent = nil
		notifyTalents = nil
		sentPlayerName = nil
		sentPlayerServer = nil
	else
		self:Echo(L["/inspect <unit> - Inspect a player, allows you to see the full talent tree."])
		self:Echo(L["/reminspect <unit> - Gets quick talent information for a player, shows name, server and total points spent."])
		self:Echo(L["/remembrance cancel - Cancels a sent /reminspect request (shouldn't need this)."])
		self:Echo(L["/remembrance reset - Resets saved talent information"])
		self:Echo(L["/remembrance auto - Toggles automatic inspection in arenas"])
		self:Echo("")
		self:Echo(L["Both /inspect and /reminspect work regardless of player faction, and range as long as they're within 100 yards. You still cannot get the gear of a player from an enemy faction however."])
	end
end

-- For loading of course
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("INSPECT_TALENT_READY")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:SetScript("OnEvent", function(self, event, addon)
	if( event == "ADDON_LOADED" and addon == "Remembrance" ) then
		-- Load our hook if the InspectUI was already loaded by another addon
		if( IsAddOnLoaded("Blizzard_InspectUI") ) then
			Remembrance:HookCanInspect()
			hooksecurefunc("InspectFrame_Show", Remembrance.InspectFrame_Show)
		end
			
		-- Talents haven't been saved yet
		if( not RemembranceTalents ) then
			RemembranceTalents = {}
		end
		
		-- DB
		if( not RemembranceDB ) then
			RemembranceDB = { autoInspect = true }
		end

	-- Inspect loaded, load our hook
	elseif( event == "ADDON_LOADED" and addon == "Blizzard_InspectUI" ) then
		Remembrance:HookCanInspect()
		hooksecurefunc("InspectFrame_Show", Remembrance.InspectFrame_Show)
		
	-- Talents loaded
	elseif( event == "INSPECT_TALENT_READY" ) then
		Remembrance.INSPECT_TALENT_READY(Remembrance)
	elseif( event == "PLAYER_TARGET_CHANGED" and RemembranceDB.autoInspect ) then
		Remembrance:ScanUnit("target")
	elseif( event == "UPDATE_MOUSEOVER_UNIT" and RemembranceDB.autoInspect ) then
		Remembrance:ScanUnit("mouseover")
	end
end)