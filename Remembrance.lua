Remembrance = {}

local L = RemembranceLocals

local notifyTalents = true
local sentPlayerServer
local sentPlayerName
local requestSent

function Remembrance:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99Remembrance|r: " .. msg)
end

function Remembrance:INSPECT_TALENT_READY()
	requestSent = nil
	
	-- Request sent through Remembrance
	if( sentPlayerName and sentPlayerServer ) then
		self:SaveTalentInfo(sentPlayerName, sentPlayerServer)
		
		sentPlayerName = nil
		sentPlayerServer = nil
	
	-- Request sent through Blizzards inspect frame
	elseif( InspectFrame and InspectFrame.unit ) then
		local name, server = UnitName(InspectFrame.unit)
		if( not server or server == "" ) then
			server = GetRealmName()
		end

		self:SaveTalentInfo(name, server)
	end

	-- Now enable the tab
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		PanelTemplates_EnableTab(InspectFrame, 3)
	end
end

-- Save the information by name/server
function Remembrance:SaveTalentInfo(name, server)
	local spentPoints = {}
	for i=1, GetNumTalentTabs(true) do
		local _, _, points = GetTalentTabInfo(i, true)
		
		table.insert(spentPoints, points)
	end
	
	RemembranceTalents[name .. "-" .. server] = table.concat(spentPoints, "/")
	
	if( notifyTalents ) then
		self:Print(name .. "-" .. server .. ": " .. RemembranceTalents[name .. "-" .. server])
		notifyTalents = nil
	end
end

-- USE THIS INSTEAD OF CALLING THE SV TABLE
function Remembrance:GetTalents(name, server)
	if( not RemembranceTalents[name .. "-" .. server] ) then
		return nil
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
	
	PanelTemplates_DisableTab(InspectFrame, 3)
end

-- /whistle
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

-- Inspect to show the entire tree
SLASH_REMINSPECT1 = "/inspect"
SLASH_REMINSPECT2 = "/in"
SlashCmdList["REMINSPECT"] = function()
	LoadAddOn("Blizzard_InspectUI")
	if( IsAddOnLoaded("Blizzard_InspectUI") ) then
		InspectFrame_Show("target")
	end
end

-- Quick inspect to only get the talent information
SLASH_REMQUICKIN1 = "/reminspect"
SLASH_REMQUICKIN2 = "/remin"
SLASH_REMQUICKIN3 = "/remembranceinspect"
SlashCmdList["REMQUICKIN"] = function(unit)
	-- Can only send one request at a time
	if( requestSent ) then
		if( sentPlayerName and sentPlayerServer ) then
			Remembrance:Print(string.format(L["Request has already been sent for %s of %s, please wait for it to finish."], sentPlayerName, sentPlayerServer))
		else
			Remembrance:Print(L["Request has already been sent, please wait for it to finish."])
		end
		return
	end

	unit = string.trim(unit or "")

	-- Default to target
	if( unit == "" ) then
		unit = "target"
	end

	-- Valid it
	if( unit ~= "mouseover" and unit ~= "player" and unit ~= "target" and unit ~= "focus" and not string.match(unit, "party[1-4]") and not string.match(unit, "raid[1-40]") ) then
		Remembrance:Print(string.format(L["Invalid unit \"%s\" entered, required player, target, focus, mouseover, party1-4, raid1-40"], unit))
		return
	end

	-- Make sure we can actually inspect it
	if( not UnitIsPlayer(unit) or not UnitExists(unit) ) then
		Remembrance:Print(string.format(L["Cannot inspect unit \"%s\", you can only inspect players, and people who are within visible range (100 yards) of you."], unit))
		return
	end

	-- Flag it up
	requestSent = true
	notifyTalents = true

	-- Since we can't rely on the unit id being the same by the time it arrives
	sentPlayerName, sentPlayerServer = UnitName(unit)
	if( not sentPlayerServer or sentPlayerServer == "" ) then
		sentPlayerServer = GetRealmName()
	end

	-- Send it off
	NotifyInspect(unit)
end

-- For loading of course
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("INSPECT_TALENT_READY")
frame:SetScript("OnEvent", function(self, event, addon)
	-- We loaded
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
	
	-- Inspect loaded, load our hooks
	elseif( event == "ADDON_LOADED" and addon == "Blizzard_InspectUI" ) then
		Remembrance:HookCanInspect()
		hooksecurefunc("InspectFrame_Show", Remembrance.InspectFrame_Show)
		
	-- Talents loaded
	elseif( event == "INSPECT_TALENT_READY" ) then
		Remembrance.INSPECT_TALENT_READY(Remembrance)
	end
end)