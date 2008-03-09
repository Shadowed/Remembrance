Remembrance = LibStub("AceAddon-3.0"):NewAddon("Remembrance", "AceEvent-3.0")

local L = RemembranceLocals

local Orig_CanInspect
local Orig_InspectFrame_Show

local DEEP_THRESHOLD = 30

local instanceType
local alreadyInspected = {}
local inspectData = {timeOut = 1000000000000}
local talentCallback = {}

function Remembrance:OnInitialize()
	if( not RemembranceTalents ) then
		RemembranceTalents = {}	
	end
	
	if( not RemembranceTrees ) then
		RemembranceTrees = {}
	end
	
	if( not RemembranceDB ) then
		RemembranceDB = {
			auto = true,
			tree = false,
		}
	end

	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		self:HookInspect()
	end
end

function Remembrance:OnEnable()
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("INSPECT_TALENT_READY")

	if( RemembranceDB.auto ) then
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA")
	end
end

function Remembrance:OnDisable()
	self:UnregisterAllEvents()
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
	-- Sent through opening the inspection window
	if( inspectData.type == "inspect" and InspectFrame.unit and not UnitIsUnit("player", InspectFrame.unit) ) then
		local class, classToken = UnitClass(InspectFrame.unit)
		local name, server = UnitName(InspectFrame.unit)
		if( not server or server == "" ) then
			server = GetRealmName()
		end
		
		self:SaveTalentInfo(name, server, class, classToken)
	
	-- Manually sent through /rem, or it's an auto inspect
	elseif( inspectData.type == "manual" or inspectData.type == "auto" ) then
		self:SaveTalentInfo(inspectData.name, inspectData.server, inspectData.class, inspectData.classToken)
	end
	
	-- Reset
	-- In a few million years, we're fucked
	inspectData.sent = nil
	inspectData.timeOut = 1000000000000
	inspectData.name = nil
	inspectData.type = nil
	
	-- Enable the inspect tab
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		PanelTemplates_EnableTab(InspectFrame, 3)
	end
end

function Remembrance:SaveTalentInfo(name, server, class, classToken)
	name = name .. "-" .. server
	
	local firstName, _, firstPoints = GetTalentTabInfo(1, true)
	local secondName, _, secondPoints = GetTalentTabInfo(2, true)
	local thirdName, _, thirdPoints = GetTalentTabInfo(3, true)
	
	if( not RemembranceTrees[classToken] ) then
		RemembranceTrees[classToken] = {}
	end
	
	RemembranceTrees[classToken][1] = firstName
	RemembranceTrees[classToken][2] = secondName
	RemembranceTrees[classToken][3] = thirdName

	-- Compress the entire tree into 63 char or so format, the same one used by Blizzards talent calculator
	local compressedTree = ""
	for tab=1, GetNumTalentTabs(true) do
		for talent=1, GetNumTalents(tab, true) do
			local name, path, tier, column, currentRank, maxRank = GetTalentInfo(tab, talent, true)
			compressedTree = compressedTree .. (currentRank or 0)
		end
	end
	
	local talent = string.format("%d/%d/%d/%s/%s", firstPoints or 0, secondPoints or 0, thirdPoints or 0, classToken or "", compressedTree)
	local oldTree = RemembranceTalents[name]

	RemembranceTalents[name] = talent
	
	-- Output talent info
	if( ( inspectData.type == "auto" and oldTree ~= talent ) or inspectData.type ~= "inspect" ) then
		if( RemembranceDB.tree ) then
			self:Print(string.format("%s (%s): %s (%d), %s (%d), %s (%d)", name, class, firstName or L["Unknown"], firstPoints or 0, secondName or L["Unknown"], secondPoints or 0, thirdName or L["Unknown"], thirdPoints or 0))
		else
			self:Print(string.format("%s (%s): %d/%d/%d", name, class, firstPoints, secondPoints, thirdPoints))
		end
	end
	
	-- Callback support for other addons that want notification when a request goes through
	for func, handler in pairs(talentCallback) do
		if( type(handler) == "table" and type(func) == "string" ) then
			handler[func](handler, inspectData.type, name, firstName, firstPoints, secondName, secondPoints, thirdName, thirdPoints)
		elseif( handler == true and type(func) == "string" ) then
			getglobal(func)(inspectData.type, name, firstName, firstPoints, secondName, secondPoints, thirdName, thirdPoints)
		else
			func(inspectData.type, name, firstName, firstPoints, secondName, secondPoints, thirdName, thirdPoints)
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

-- Inspect is LoD, so catch it here
function Remembrance:ADDON_LOADED(event, addon)
	if( addon == "Blizzard_InspectUI" ) then
		self:HookInspect()
		self:UnregisterEvent("ADDON_LOADED")
	end
end

-- For doing auto inspection inside arenas
function Remembrance:ZONE_CHANGED_NEW_AREA(event)
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
		for k in pairs(alreadyInspected) do
			alreadyInspected[k] = nil
		end
	end
	
	instanceType = type
end

function Remembrance:ScanUnit(unit)
	if( ( inspectData.sent and inspectData.timeOut < GetTime() ) or not UnitIsVisible(unit) or not UnitIsPlayer(unit) or not UnitIsEnemy("player", unit) ) then
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
	sendInspectRequest(unit, "auto")
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

-- PUBLIC APIS
--[[
	:GetTalents(name, server) - Returns the talents of a person if possible
	Returns: tree1 (int), tree2 (int), tree3 (int)
]]
function Remembrance:GetTalents(name, server)
	if( server ) then
		name = name .. "-" .. server
	end
	
	if( not RemembranceTalents[name] ) then
		return nil
	end
	
	local tree1, tree2, tree3, classToken, rawTalents = string.split("/", RemembranceTalents[name])
	return tonumber(tree1) or 0, tonumber(tree2) or 0, tonumber(tree3) or 0, classToken, rawTalents
end

--[[
	:GetSpecName(name, server, showHybrid) - Returns the tree the person has the most points in, will return "Hybrid" if more then one tree has 30 points in it
	Returns: Tree name if possible, or ##/##/## if not
]]
function Remembrance:GetSpecName(name, server, showHybrid)
	local tree1, tree2, tree3, classToken = self:GetTalents(name, server)
	if( not tree1 or not classToken ) then
		if( tree1 and tree2 and tree3 ) then
			return string.format("%d/%d/%d", tree1, tree2, tree3)
		else
			return nil
		end
	end
	
	-- Make sure we've saved data for this class
	local talentNames = RemembranceTrees[classToken]
	if( not talentNames ) then
		return string.format("%d/%d/%d", tree1, tree2, tree3)
	end

	if( showHybrid ) then
		-- Check for a hybrid spec
		local deepTrees = 0
		if( tree1 >= DEEP_THRESHOLD ) then
			deepTrees = deepTrees + 1
		end
		if( tree2 >= DEEP_THRESHOLD ) then
			deepTrees = deepTrees + 1
		end
		if( tree3 >= DEEP_THRESHOLD ) then
			deepTrees = deepTrees + 1
		end

		if( deepTrees > 1 ) then
			return L["Hybrid"]
		end
	end
		
	-- Now check specifics
	if( tree1 > tree2 and tree1 > tree3 ) then
		return talentNames[1]
	elseif( tree2 > tree1 and tree2 > tree3 ) then
		return talentNames[2]
	elseif( tree3 > tree1 and tree3 > tree2 ) then
		return talentNames[3]
	end
	
	return L["Unknown"]
end

--[[
	:GetRawTalents(name, server) - Returns the raw unparsed talent format along with the classToken it's for, nil is no data is found
	Returns: rawTalents (String), classToken (String)
]]

function Remembrance:GetRawTalents(name, server)
	if( server ) then
		name = name .. "-" .. serve
	end
	
	local _, _, _, classToken, rawTalents = self:GetTalents(name)
	if( not classToken or not rawTalents ) then
		return nil
	end
	
	return rawTalents, classToken
end

--[[
	:InspectUnit(unit) - Sends an inspect request if possible through Remembrance
	Returns: 1 if the request was sent, -1 if a request is being processed still, -2 is it's a bad unit
]]
function Remembrance:InspectUnit(unit)
	if( not UnitExists(unit) or not UnitIsPlayer(unit) ) then
		return -2
	elseif( inspectData.sent and inspectData.timeOut < Gettime() ) then
		return -1
	end

	sendInspectRequest(unit)
	
	return 1
end

-- Registering callback for auto inspect data
function Remembrance:RegisterCallback(handler, func)
	if( func ) then
		talentCallback[func] = handler
	else
		talentCallback[func] = true
	end
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
