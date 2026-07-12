
AuctionatorVersion = "???";		-- set from toc upon loading
AuctionatorAuthor  = "Zirco";

local AuctionatorInited = false;

local addonName, addonTable = ...;
local zc = addonTable.zc;

-----------------------------------------

local recommendElements			= {};

AUCTIONATOR_ENABLE_ALT		= 1;
AUCTIONATOR_OPEN_ALL_BAGS	= 1;
AUCTIONATOR_SHOW_ST_PRICE	= 0;
AUCTIONATOR_ROMOVE_BLOOFORGED = 1;
AUCTIONATOR_ROMOVE_SUFFIX = 1;
AUCTIONATOR_SHOW_TIPS		= 1;
AUCTIONATOR_DEF_DURATION	= "N";		-- none
AUCTIONATOR_V_TIPS			= 1;
AUCTIONATOR_A_TIPS			= 1;
AUCTIONATOR_D_TIPS			= 1;
AUCTIONATOR_SHIFT_TIPS		= 1;
AUCTIONATOR_DE_DETAILS_TIPS	= 4;		-- off by default
AUCTIONATOR_DEFTAB			= 1;

AUCTIONATOR_DB_MAXITEM_AGE	= 180;
AUCTIONATOR_DB_MAXHIST_AGE	= 21;	-- obsolete - just needed for migration
AUCTIONATOR_DB_MAXHIST_DAYS	= 5;
AUCTIONATOR_HIDE_BIDONLY	= 0;
AUCTIONATOR_CHAIN_BUY		= 0;
AUCTIONATOR_MATCH_RARITY	= 0;

AUCTIONATOR_OPEN_FIRST		= 0;	-- obsolete - just needed for migration
AUCTIONATOR_OPEN_BUY		= 0;	-- obsolete - just needed for migration

local SELL_TAB		= 1;
local MORE_TAB		= 2;
local BUY_TAB 		= 3;

local MODE_LIST_ACTIVE	= 1;
local MODE_LIST_ALL		= 2;


-- saved variables - amounts to undercut

local auctionator_savedvars_defaults =
	{
	["_5000000"]			= 10000;	-- amount to undercut buyouts over 500 gold
	["_1000000"]			= 2500;
	["_200000"]				= 1000;
	["_50000"]				= 500;
	["_10000"]				= 200;
	["_2000"]				= 100;
	["_500"]				= 5;
	["STARTING_DISCOUNT"]	= 5;	-- PERCENT
	};


-----------------------------------------

local auctionator_orig_AuctionFrameTab_OnClick;
local auctionator_orig_ContainerFrameItemButton_OnModifiedClick;
local auctionator_orig_AuctionFrameAuctions_Update;
local auctionator_orig_CanShowRightUIPanel;
local auctionator_orig_ChatEdit_InsertLink;
local auctionator_orig_ChatFrame_OnEvent;
local auctionator_orig_FriendsFrame_OnEvent;

local gAtr_ClickAuctionSell = false;

local gOpenAllBags  	= AUCTIONATOR_OPEN_ALL_BAGS;
local gTimeZero;
local gTimeTightZero;

local gAutoSingleton = 0;

local gJustPosted_ItemName = nil;		-- set to the last item posted, even after the posting so that message and icon can be displayed
local gJustPosted_ItemLink;
local gJustPosted_BuyoutPrice;
local gJustPosted_StackSize;
local gJustPosted_NumInBagsAtStart;
local gJustPosted_NumStacks;


local kBagIDs = {};

local Atr_Confirm_Proc_Yes = nil;

local gHentryTryAgain		= nil;
local gCondensedThisSession = {};

local ITEM_HIST_NUM_LINES = 20;

local gActiveAuctions = {};

local gHlistNeedsUpdate = false;

local gSellPane;
local gMorePane;
local gShopPane;

local gCurrentPane;

local gHistoryItemList = {};

local ATR_CACT_NULL							= 0;
local ATR_CACT_READY						= 1;
local ATR_CACT_PROCESSING					= 2;
local ATR_CACT_WAITING_ON_CANCEL_CONFIRM	= 3;


local gItemPostingInProgress = false;
local gQuietWho = 0;
local gSendZoneMsgs = false;
local gAtr_CheckingActive_NumUndercuts	= 0;
local gAtr_CheckingActive_State			= ATR_CACT_NULL;

Atr_ptime = nil;		-- a more precise timer but may not be updated very frequently

gAtr_ScanDB			= nil;

-----------------------------------------

ATR_SK_GLYPHS		= "*_glyphs";
ATR_SK_GEMS_CUT		= "*_gemscut";
ATR_SK_GEMS_UNCUT	= "*_gemsuncut";
ATR_SK_ITEM_ENH		= "*_itemenh";
ATR_SK_POT_ELIX		= "*_potelix";
ATR_SK_FLASKS		= "*_flasks";
ATR_SK_HERBS		= "*_herbs";

-----------------------------------------

local roundPriceDown, ToTightTime, FromTightTime, monthDay;

-----------------------------------------

function Atr_RegisterEvents(self)

	self:RegisterEvent("VARIABLES_LOADED");
	self:RegisterEvent("ADDON_LOADED");

	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE");
	self:RegisterEvent("AUCTION_OWNED_LIST_UPDATE");

	self:RegisterEvent("AUCTION_MULTISELL_START");
	self:RegisterEvent("AUCTION_MULTISELL_UPDATE");
	self:RegisterEvent("AUCTION_MULTISELL_FAILURE");

	self:RegisterEvent("AUCTION_HOUSE_SHOW");
	self:RegisterEvent("AUCTION_HOUSE_CLOSED");

	self:RegisterEvent("NEW_AUCTION_UPDATE");
	self:RegisterEvent("CHAT_MSG_ADDON");
	self:RegisterEvent("WHO_LIST_UPDATE");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");

end

-----------------------------------------

function Atr_EventHandler()

--	zc.md (event);

	if (event == "VARIABLES_LOADED")			then	Atr_OnLoad(); 					end;
	if (event == "ADDON_LOADED")				then	Atr_OnAddonLoaded(); 			end;
	if (event == "AUCTION_ITEM_LIST_UPDATE")	then	Atr_OnAuctionUpdate(); 			end;
	if (event == "AUCTION_OWNED_LIST_UPDATE")	then	Atr_OnAuctionOwnedUpdate(); 	end;

	if (event == "AUCTION_MULTISELL_START")		then	Atr_OnAuctionMultiSellStart(); 	end;
	if (event == "AUCTION_MULTISELL_UPDATE")	then	Atr_OnAuctionMultiSellUpdate(); end;
	if (event == "AUCTION_MULTISELL_FAILURE")	then	Atr_OnAuctionMultiSellFailure(); end;

	if (event == "AUCTION_HOUSE_SHOW")			then	Atr_OnAuctionHouseShow(); 		end;
	if (event == "AUCTION_HOUSE_CLOSED")		then	Atr_OnAuctionHouseClosed(); 	end;
	if (event == "NEW_AUCTION_UPDATE")			then	Atr_OnNewAuctionUpdate(); 		end;
	if (event == "CHAT_MSG_ADDON")				then	Atr_OnChatMsgAddon(); 			end;
	if (event == "WHO_LIST_UPDATE")				then	Atr_OnWhoListUpdate(); 			end;
	if (event == "PLAYER_ENTERING_WORLD")		then	Atr_OnPlayerEnteringWorld(); 	end;

end

-----------------------------------------

function Atr_SetupHookFunctionsEarly ()

	auctionator_orig_FriendsFrame_OnEvent = FriendsFrame_OnEvent;
	FriendsFrame_OnEvent = Atr_FriendsFrame_OnEvent;

end


-----------------------------------------

function Atr_SetupHookFunctions ()

	auctionator_orig_AuctionFrameTab_OnClick = AuctionFrameTab_OnClick;
	AuctionFrameTab_OnClick = Atr_AuctionFrameTab_OnClick;

	auctionator_orig_ContainerFrameItemButton_OnModifiedClick = ContainerFrameItemButton_OnModifiedClick;
	ContainerFrameItemButton_OnModifiedClick = Atr_ContainerFrameItemButton_OnModifiedClick;

	auctionator_orig_AuctionFrameAuctions_Update = AuctionFrameAuctions_Update;
	AuctionFrameAuctions_Update = Atr_AuctionFrameAuctions_Update;

	auctionator_orig_CanShowRightUIPanel = CanShowRightUIPanel;
	CanShowRightUIPanel = auctionator_CanShowRightUIPanel;

	auctionator_orig_ChatEdit_InsertLink = ChatEdit_InsertLink;
	ChatEdit_InsertLink = auctionator_ChatEdit_InsertLink;

	auctionator_orig_ChatFrame_OnEvent = ChatFrame_OnEvent;
	ChatFrame_OnEvent = auctionator_ChatFrame_OnEvent;
end

-----------------------------------------

local gItemLinkCache = {};
local gA2IC_prevName = "";

-----------------------------------------

function Atr_AddToItemLinkCache (itemName, itemLink)

	if (itemName == gA2IC_prevName) then		-- for performance reasons only
		return;
	end

	gA2IC_prevName = itemName;

	gItemLinkCache[string.lower(itemName)] = itemLink;
end

-----------------------------------------

function Atr_GetItemLink (itemName)
	if (itemName == nil or itemName == "") then
		return nil;
	end

	local itemLink = gItemLinkCache[string.lower(itemName)];

	if (itemLink == nil) then
		_, itemLink = GetItemInfo (itemName);
		if (itemLink) then
			Atr_AddToItemLinkCache (itemName, itemLink);
		end
	end

	return itemLink;

end

-----------------------------------------

local checkVerString		= nil;
local versionReminderCalled	= false;	-- make sure we don't bug user more than once

-----------------------------------------

local function CheckVersion (verString)

	if (checkVerString == nil) then
		checkVerString = AuctionatorVersion;
	end

	local a,b,c = strsplit (".", verString);

	if (tonumber(a) == nil or tonumber(b) == nil or tonumber(c) == nil) then
		return false;
	end

	if (verString > checkVerString) then
		checkVerString = verString;
		return true;	-- out of date
	end

	return false;
end

-----------------------------------------

function Atr_VersionReminder ()
	if (not versionReminderCalled) then
		versionReminderCalled = true;

		zc.msg_atr (ZT("There is a more recent version of Auctionator: VERSION").." "..checkVerString);
	end
end



-----------------------------------------

local VREQ_sent = 0;

-----------------------------------------

function Atr_SendAddon_VREQ (type, target)

	VREQ_sent = time();

	SendAddonMessage ("ATR", "VREQ_"..AuctionatorVersion, type, target);

end

-----------------------------------------

function Atr_OnChatMsgAddon ()

	local	prefix			= arg1;
	local	msg				= arg2;
	local	distribution	= arg3;
	local	sender			= arg4;

	if (arg1 == "ATR") then

		if (zc.StringStartsWith (msg, "VREQ_")) then
			SendAddonMessage ("ATR", "V_"..AuctionatorVersion, "WHISPER", sender);
		end

		if (zc.StringStartsWith (msg, "V_") and time() - VREQ_sent < 5) then

			local herVerString = string.sub (msg, 3);
			zc.md ("version found:", herVerString, "   ", sender, "     delta", time() - VREQ_sent);
			local outOfDate = CheckVersion (herVerString);
			if (outOfDate) then
				zc.AddDeferredCall (3, "Atr_VersionReminder", nil, nil, "VR");
			end
		end
	end
end


-----------------------------------------

function Atr_GetAuctionatorMemString(msg)		-- global: ported Atr_PruneScanDB (AuctionatorScan.lua) calls this

	UpdateAddOnMemoryUsage();

	local mem  = GetAddOnMemoryUsage("Auctionator");
	return string.format ("%6i KB", math.floor(mem));
end

-----------------------------------------

local function Atr_SlashCmdFunction(msg)

	local cmd, param1u, param2u, param3u = zc.words (msg);

	if (cmd == nil or type (cmd) ~= "string") then
		return;
	end

		  cmd    = cmd     and cmd:lower()    or nil;
	local param1 = param1u and param1u:lower() or nil;
	local param2 = param2u and param2u:lower() or nil;
	local param3 = param3u and param3u:lower() or nil;

	if (cmd == "mem") then

		UpdateAddOnMemoryUsage();

		for i = 1, GetNumAddOns() do
			local mem  = GetAddOnMemoryUsage(i);
			local name = GetAddOnInfo(i);
			if (mem > 0) then
				local s = string.format ("%6i KB   %s", math.floor(mem), name);
				zc.msg_yellow (s);
			end
		end

	elseif (cmd == "locale") then
		Atr_PickLocalizationTable (param1u);

	elseif (cmd == "uidebug") then

		Atr_UIDebug();

	elseif (cmd == "catdump") then

		Atr_CategoryDump();

	elseif (cmd == "fsc") then

		if (param1) then
			AUCTIONATOR_FS_CHUNK = tonumber(param1);
		end

		if (AUCTIONATOR_FS_CHUNK == nil) then
			zc.msg_atr ("full scan chunk size: ", gDefaultFullScanChunkSize, " (default)");
		else
			zc.msg_atr ("full scan chunk size: ", AUCTIONATOR_FS_CHUNK);
		end

	elseif (cmd == "clear") then

		zc.msg_atr ("memory usage: "..Atr_GetAuctionatorMemString());

		if (param1 == "fullscandb") then
			gAtr_ScanDB = nil;
			AUCTIONATOR_PRICE_DATABASE = nil;
			Atr_InitScanDB();
			zc.msg_atr (ZT("full scan database cleared"));

		elseif (param1 == "posthistory") then
			AUCTIONATOR_PRICING_HISTORY = {};
			zc.msg_atr (ZT("pricing history cleared"));
		end

		collectgarbage  ("collect");

		zc.msg_atr ("memory usage: "..Atr_GetAuctionatorMemString());

	elseif (Atr_HandleDevCommands and Atr_HandleDevCommands (cmd, param1, param2)) then
		-- do nothing
	else
		zc.msg_atr (ZT("unrecognized command"));
	end
end


-----------------------------------------

function Atr_InitScanDB()

	local realm_Faction = GetRealmName();		-- NOTE: realm-only key (no faction split) to preserve this fork's existing data

	if (AUCTIONATOR_PRICE_DATABASE and AUCTIONATOR_PRICE_DATABASE["__dbversion"] == nil) then	-- migrate version 1 to version 2

		local temp = {};

		zc.CopyDeep (temp, AUCTIONATOR_PRICE_DATABASE);

		AUCTIONATOR_PRICE_DATABASE = {};
		AUCTIONATOR_PRICE_DATABASE["__dbversion"] = 2;

		AUCTIONATOR_PRICE_DATABASE[realm_Faction] = {};
		zc.CopyDeep (AUCTIONATOR_PRICE_DATABASE[realm_Faction], temp);

		temp = {};
	end

	if (AUCTIONATOR_PRICE_DATABASE and AUCTIONATOR_PRICE_DATABASE["__dbversion"] == 2) then		-- migrate version 2 to version 3

		local temp_price_db = {};

		for realm_fac, data in pairs (AUCTIONATOR_PRICE_DATABASE) do

			if (type(data) == "table") then

				temp_price_db[realm_fac] = {};

				zc.msg_atr ("migrating Auctionator db to version 3 for:", realm_fac);

				local name, price;
				local count = 0;

				for name, price in pairs (data) do

					if (type(price) == "table") then		-- this is to fix the bug where I didn't set the dbversion correctly for NEW dbs
						temp_price_db[realm_fac][name] = price;
					else
						Atr_UpdateScanDBprice (name, price, temp_price_db[realm_fac]);
					end
					count = count + 1;
				end

				zc.msg_atr (count, "entries migrated");
			end
		end

		AUCTIONATOR_PRICE_DATABASE = temp_price_db;
		AUCTIONATOR_PRICE_DATABASE["__dbversion"] = 3;
	end

	-- migrate version 3 to version 4

	if (AUCTIONATOR_PRICE_DATABASE and AUCTIONATOR_PRICE_DATABASE["__dbversion"] == 3) then
		for realm_fac, data in pairs (AUCTIONATOR_PRICE_DATABASE) do
			if (type(data) == "table") then
				zc.msg_atr ("migrating Auctionator db to version 4 for:", realm_fac);
				local name, itemInfo;
				for name, itemInfo in pairs (data) do
					if (type(itemInfo) == "table") then
						itemInfo["po"] = 1;		-- flag for deletion after the first full scan
					end
				end
			end
		end
		AUCTIONATOR_PRICE_DATABASE["__dbversion"] = 4;
	end

	if (AUCTIONATOR_PRICE_DATABASE == nil) then
		AUCTIONATOR_PRICE_DATABASE = {};
		AUCTIONATOR_PRICE_DATABASE["__dbversion"] = 4;
	end

	if (AUCTIONATOR_PRICE_DATABASE[realm_Faction] == nil) then
		AUCTIONATOR_PRICE_DATABASE[realm_Faction] = {};
	end

	gAtr_ScanDB = AUCTIONATOR_PRICE_DATABASE[realm_Faction];

	Atr_PruneScanDB ();
	Atr_PrunePostDB ();

	Atr_Broadcast_DBupdated (Atr_GetDBsize(), "dbinited");

end


-----------------------------------------

function Atr_OnLoad()

	AuctionatorVersion = GetAddOnMetadata("Auctionator", "Version");

	gTimeZero		= time({year=2000, month=1, day=1, hour=0});
	gTimeTightZero	= time({year=2008, month=8, day=1, hour=0});

	local x;
	for x = 0, NUM_BAG_SLOTS do
		kBagIDs[x+1] = x;
	end

	kBagIDs[NUM_BAG_SLOTS+2] = KEYRING_CONTAINER;

	AuctionatorLoaded = true;

	SlashCmdList["Auctionator"] = Atr_SlashCmdFunction;

	SLASH_Auctionator1 = "/auctionator";
	SLASH_Auctionator2 = "/atr";

	Atr_InitScanDB ();

	if (AUCTIONATOR_PRICING_HISTORY == nil) then	-- the old history of postings
		AUCTIONATOR_PRICING_HISTORY = {};
	end

	if (AUCTIONATOR_TOONS == nil) then
		AUCTIONATOR_TOONS = {};
	end

	if (AUCTIONATOR_STACKING_PREFS == nil) then
		Atr_StackingPrefs_Init();
	end


	local playerName = UnitName("player");

	if (not AUCTIONATOR_TOONS[playerName]) then
		AUCTIONATOR_TOONS[playerName] = {};
		AUCTIONATOR_TOONS[playerName].firstSeen		= time();
		AUCTIONATOR_TOONS[playerName].firstVersion	= AuctionatorVersion;
	end

	AUCTIONATOR_TOONS[playerName].guid = UnitGUID ("player");

	if (AUCTIONATOR_SCAN_MINLEVEL == nil) then
		AUCTIONATOR_SCAN_MINLEVEL = 1;			-- poor (all) items
	end

	if (AUCTIONATOR_SHOW_TIPS == 0) then
		AUCTIONATOR_A_TIPS = 0;
		AUCTIONATOR_D_TIPS = 0;

		AUCTIONATOR_SHOW_TIPS = 2;
	end

	if (AUCTIONATOR_OPEN_FIRST < 2) then	-- set to 2 to indicate it's been migrated
		if		(AUCTIONATOR_OPEN_FIRST == 1)	then AUCTIONATOR_DEFTAB = 1;
		elseif	(AUCTIONATOR_OPEN_BUY == 1)		then AUCTIONATOR_DEFTAB = 2;
		else										 AUCTIONATOR_DEFTAB = 0; end;

		AUCTIONATOR_OPEN_FIRST = 2;
	end


	Atr_SetupHookFunctionsEarly();

	------------------

	CreateFrame( "GameTooltip", "AtrScanningTooltip" ); -- Tooltip name cannot be nil
	AtrScanningTooltip:SetOwner( WorldFrame, "ANCHOR_NONE" );
	-- Allow tooltip SetX() methods to dynamically add new lines based on these
	AtrScanningTooltip:AddFontStrings(
	AtrScanningTooltip:CreateFontString( "$parentTextLeft1", nil, "GameTooltipText" ),
	AtrScanningTooltip:CreateFontString( "$parentTextRight1", nil, "GameTooltipText" ) );

	------------------

	Atr_InitDETable();

	if ( IsAddOnLoaded("Blizzard_AuctionUI") ) then		-- need this for AH_QuickSearch since that mod forces Blizzard_AuctionUI to load at a startup
		Atr_Init();
	end
end

-----------------------------------------

function Atr_OnAddonLoaded()
	local addonName = arg1;

	if (zc.StringSame (addonName, "blizzard_auctionui")) then
		Atr_Init();
	end

	if (zc.StringSame (addonName, "lilsparkysWorkshop")) then

		local LSW_version = GetAddOnMetadata("lilsparkysWorkshop", "Version");

		if (LSW_version and (LSW_version == "0.72" or LSW_version == "0.90" or LSW_version == "0.91")) then

			if (LSW_itemPrice) then
				zc.msg ("** |cff00ffff"..ZT("Auctionator provided an auction module to LilSparky's Workshop."), 0, 1, 0);
				zc.msg ("** |cff00ffff"..ZT("Ignore any ERROR message to the contrary below."), 0, 1, 0);
				LSW_itemPrice = Atr_LSW_itemPriceGetAuctionBuyout;
			end
		end
	end

	Atr_Check_For_Conflicts (addonName);
end


-----------------------------------------

function Atr_OnPlayerEnteringWorld()
	Atr_InitOptionsPanels();
end

-----------------------------------------

function Atr_LSW_itemPriceGetAuctionBuyout(link)

    local sellPrice = Atr_GetAuctionBuyout(link)
    if sellPrice then
        return sellPrice, false
    else
        return 0, true
    end
 end

-----------------------------------------

function Atr_Init()

	if (AuctionatorInited) then
		return;
	end

--	zc.msg("Auctionator Initialized");

	AuctionatorInited = true;

	if (AUCTIONATOR_SAVEDVARS == nil) then
		Atr_ResetSavedVars();
	end


	if (AUCTIONATOR_SHOPPING_LISTS == nil) then
		AUCTIONATOR_SHOPPING_LISTS = {};
		Atr_SList.create (ZT("Recent Searches"), true);

		if (zc.IsEnglishLocale()) then
			local slist = Atr_SList.create ("Sample Shopping List #1");
			slist:AddItem ("Greater Cosmic Essence");
			slist:AddItem ("Infinite Dust");
			slist:AddItem ("Dream Shard");
			slist:AddItem ("Abyss Crystal");
		end
	else
		Atr_ShoppingListsInit();
	end

	gShopPane	= Atr_AddSellTab (ZT("Buy"),			BUY_TAB);
	gSellPane	= Atr_AddSellTab (ZT("Sell"),			SELL_TAB);
	gMorePane	= Atr_AddSellTab (ZT("More").."...",	MORE_TAB);

	Atr_AddMainPanel ();

	Atr_CreateBagPanel ();

	Atr_FixupButtons ();

	Atr_SetupHookFunctions ();

	recommendElements[1] = _G["Atr_Recommend_Text"];
	recommendElements[2] = _G["Atr_RecommendPerItem_Text"];
	recommendElements[3] = _G["Atr_RecommendPerItem_Price"];
	recommendElements[4] = _G["Atr_RecommendPerStack_Text"];
	recommendElements[5] = _G["Atr_RecommendPerStack_Price"];
	recommendElements[6] = _G["Atr_Recommend_Basis_Text"];
	recommendElements[7] = _G["Atr_RecommendItem_Tex"];

	-- create the lines that appear in the item history scroll pane

	local line, n;

	for n = 1, ITEM_HIST_NUM_LINES do
		local y = -5 - ((n-1)*16);
		line = CreateFrame("BUTTON", "AuctionatorHEntry"..n, Atr_Hlist, "Atr_HEntryTemplate");
		line:SetPoint("TOPLEFT", 0, y);
	end

	Atr_ShowHide_StartingPrice();

	Atr_LocalizeFrames();

end

-----------------------------------------

function Atr_ShowHide_StartingPrice()

	if (AUCTIONATOR_SHOW_ST_PRICE == 1) then
		Atr_StartingPriceText:Show();
		Atr_StartingPrice:Show();
		Atr_StartingPriceDiscountText:Hide();
		Atr_Duration_Text:SetPoint ("TOPLEFT", 10, -307);
	else
		Atr_StartingPriceText:Hide();
		Atr_StartingPrice:Hide();
		Atr_StartingPriceDiscountText:Show();
		Atr_Duration_Text:SetPoint ("TOPLEFT", 10, -304);
	end
end


-----------------------------------------

function Atr_GetSellItemInfo ()

	local auctionItemName, auctionTexture, auctionCount = GetAuctionSellItemInfo();

	if (auctionItemName == nil) then
		auctionItemName = "";
		auctionCount	= 0;
	end

	local auctionItemLink = nil;
	local exact = true;
	local bloodforged = false;
	-- only way to get sell itemlink that I can figure
	if (auctionItemName ~= "") then
		AtrScanningTooltip:SetAuctionSellItem();

		_, auctionItemLink = AtrScanningTooltip:GetItem();

		if AuctionatorOption_Remove_Bloodforge_CB:GetChecked() then
			if (string.find(auctionItemName, "Bloodforged")) == 1 then
				auctionItemName = auctionItemName:gsub("Bloodforged ", "")
				exact = false
				bloodforged = true;
			end
		end
		if AuctionatorOption_Remove_Suffix_CB:GetChecked() then
			local itemSuffixs = {
				"of the Tiger",
				"of the Bear",
				"of the Gorilla",
				"of the Boar",
				"of the Monkey",
				"of the Falcon",
				"of the Wolf",
				"of the Eagle",
				"of the Whale",
				"of the Owl",
			}
			for _, suffix in ipairs(itemSuffixs) do
				auctionItemName = auctionItemName:gsub(" "..suffix, "")
			end
		end

		if (auctionItemLink == nil) then
			return "",0,nil;
		else
			Atr_AddToItemLinkCache (auctionItemName, auctionItemLink);
		end

	end

	return auctionItemName, auctionCount, auctionItemLink, exact, bloodforged;

end


-----------------------------------------

function Atr_ResetSavedVars ()
	AUCTIONATOR_SAVEDVARS = zc.CopyDeep (auctionator_savedvars_defaults);
end


--------------------------------------------------------------------------------
-- don't reference these directly; use the function below instead

local _AUCTIONATOR_SELL_TAB_INDEX = 0;
local _AUCTIONATOR_MORE_TAB_INDEX = 0;
local _AUCTIONATOR_BUY_TAB_INDEX = 0;

--------------------------------------------------------------------------------

function Atr_FindTabIndex (whichTab)

	if (_AUCTIONATOR_SELL_TAB_INDEX == 0) then

		local i = 4;
		while (true)  do
			local tab = _G['AuctionFrameTab'..i];
			if (tab == nil) then
				break;
			end

			if (tab.auctionatorTab) then
				if (tab.auctionatorTab == SELL_TAB)		then _AUCTIONATOR_SELL_TAB_INDEX = i; end;
				if (tab.auctionatorTab == MORE_TAB)		then _AUCTIONATOR_MORE_TAB_INDEX = i; end;
				if (tab.auctionatorTab == BUY_TAB)		then _AUCTIONATOR_BUY_TAB_INDEX = i; end;
			end

			i = i + 1;
		end
	end

	if (whichTab == SELL_TAB)	then return _AUCTIONATOR_SELL_TAB_INDEX ; end;
	if (whichTab == MORE_TAB)	then return _AUCTIONATOR_MORE_TAB_INDEX; end;
	if (whichTab == BUY_TAB)	then return _AUCTIONATOR_BUY_TAB_INDEX; end;

	return 0;
end

-----------------------------------------

local function Atr_SwitchTo_OurItemOnClick ()

--	if (gOrig_ContainerFrameItemButton_OnClick == nil) then
--		gOrig_ContainerFrameItemButton_OnClick = ContainerFrameItemButton_OnClick;
--		ContainerFrameItemButton_OnClick = Atr_ContainerFrameItemButton_OnClick;
--	end

end

-----------------------------------------

local function Atr_SwitchTo_BlizzItemOnClick ()

--	if (gOrig_ContainerFrameItemButton_OnClick) then
--		ContainerFrameItemButton_OnClick = gOrig_ContainerFrameItemButton_OnClick;
--		gOrig_ContainerFrameItemButton_OnClick = nil;
--	end

end

-----------------------------------------


function Atr_AuctionFrameTab_OnClick (self, index, down)

	if ( index == nil or type(index) == "string") then
		index = self:GetID();
	end

	_G["Atr_Main_Panel"]:Hide();

	Atr_BuyState = ATR_BUY_NULL;			-- just in case
	gItemPostingInProgress = false;		-- just in case

	auctionator_orig_AuctionFrameTab_OnClick (self, index, down);

	if (index == 1 or index == 2 or Atr_IsAuctionatorTab(index)) then
		Atr_SwitchTo_OurItemOnClick();
	else
		Atr_SwitchTo_BlizzItemOnClick();
	end


	if (not Atr_IsAuctionatorTab(index)) then
		Atr_HideAllDialogs();
		AuctionFrameMoneyFrame:Show();

		if (Atr_BagPanel) then
			Atr_BagPanel:Hide();
		end

		if (AP_Bid_MoneyFrame) then		-- for the addon 'Auction Profit'
			if (AP_ShowBid)	then	AP_ShowHide_Bid_Button(1);	end;
			if (AP_ShowBO)	then	AP_ShowHide_BO_Button(1);	end;
		end


	elseif (Atr_IsAuctionatorTab(index)) then

		AuctionFrameAuctions:Hide();
		AuctionFrameBrowse:Hide();
		AuctionFrameBid:Hide();
		PlaySound("igCharacterInfoTab");

		Atr_FixupButtons ();		-- re-assert geometry; UI skins re-anchor buttons they know by name

		PanelTemplates_SetTab(AuctionFrame, index);

		AuctionFrameTopLeft:SetTexture	("Interface\\AddOns\\Auctionator\\Images\\Atr_topleft");
		AuctionFrameBotLeft:SetTexture	("Interface\\AddOns\\Auctionator\\Images\\Atr_botleft");
		AuctionFrameTop:SetTexture		("Interface\\AddOns\\Auctionator\\Images\\Atr_top");
		AuctionFrameTopRight:SetTexture	("Interface\\AddOns\\Auctionator\\Images\\Atr_topright");
		AuctionFrameBot:SetTexture		("Interface\\AddOns\\Auctionator\\Images\\Atr_bot");
		AuctionFrameBotRight:SetTexture	("Interface\\AddOns\\Auctionator\\Images\\Atr_botright");

		if (index == Atr_FindTabIndex(SELL_TAB))	then gCurrentPane = gSellPane; end;
		if (index == Atr_FindTabIndex(BUY_TAB))		then gCurrentPane = gShopPane; end;
		if (index == Atr_FindTabIndex(MORE_TAB))	then gCurrentPane = gMorePane; end;

		if (index == Atr_FindTabIndex(SELL_TAB))	then AuctionatorTitle:SetText ("Auctionator - "..ZT("Sell"));			end;
		if (index == Atr_FindTabIndex(BUY_TAB))		then AuctionatorTitle:SetText ("Auctionator - "..ZT("Buy"));			end;
		if (index == Atr_FindTabIndex(MORE_TAB))	then AuctionatorTitle:SetText ("Auctionator - "..ZT("More").."...");	end;

		Atr_ClearHlist();
		Atr_SellControls:Hide();
		Atr_Hlist:Hide();
		Atr_Hlist_ScrollFrame:Hide();
		Atr_Search_Box:Hide();
		Atr_Search_Button:Hide();
		Atr_Adv_Search_Button:Hide();
		Atr_Exact_Search_Button:Hide();
		Atr_AddToSListButton:Hide();
		Atr_RemFromSListButton:Hide();
		Atr_NewSListButton:Hide();
		Atr_DelSListButton:Hide();
		Atr_SrchSListButton:Hide();
		Atr_MngSListsButton:Hide();
		Atr_SaveThisList_Button:Hide();
		Atr_ActiveItems_Text:Hide();
		Atr_Chain_Buy_Button:Hide();
		Atr_MatchRarity_Button:Hide();
		Atr_DropDown1:Hide();
		Atr_DropDownSL:Hide();
		Atr_CheckActiveButton:Hide();
		Atr_Back_Button:Hide()

		AuctionFrameMoneyFrame:Hide();

		if (index == Atr_FindTabIndex(SELL_TAB)) then
			Atr_SellControls:Show();
			Atr_MatchRarity_Button:Show();
			if (Atr_BagPanel) then
				Atr_BagPanel:Show();
			end
		else
			Atr_Hlist:Show();
			Atr_Hlist_ScrollFrame:Show();
			if (Atr_BagPanel) then
				Atr_BagPanel:Hide();
			end
			if (gJustPosted_ItemName) then
				gJustPosted_ItemName = nil;
				gSellPane:ClearSearch ();
			end
		end


		if (index == Atr_FindTabIndex(MORE_TAB)) then
			FauxScrollFrame_SetOffset (Atr_Hlist_ScrollFrame, gCurrentPane.hlistScrollOffset);
			Atr_DisplayHlist();
			Atr_DropDown1:Show();

			if (UIDropDownMenu_GetSelectedValue(Atr_DropDown1) == MODE_LIST_ACTIVE) then
				Atr_CheckActiveButton:Show();
				Atr_ActiveItems_Text:Show();
			end
		end


		if (index == Atr_FindTabIndex(BUY_TAB)) then
			Atr_Search_Box:Show();
			Atr_Search_Button:Show();
			Atr_Adv_Search_Button:Show();
			Atr_Exact_Search_Button:Show();
			AuctionFrameMoneyFrame:Show();
			Atr_BuildGlobalHistoryList(true);
			Atr_AddToSListButton:Show();
			Atr_RemFromSListButton:Show();
			Atr_NewSListButton:Show();
			Atr_DelSListButton:Show();
			Atr_SrchSListButton:Show();
			Atr_MngSListsButton:Show();
			Atr_Chain_Buy_Button:Show();
			Atr_DropDownSL:Show();
			Atr_Hlist:SetHeight (252);
			Atr_Hlist_ScrollFrame:SetHeight (252);
		else
			Atr_Hlist:SetHeight (335);
			Atr_Hlist_ScrollFrame:SetHeight (335);
		end

		if (index == Atr_FindTabIndex(BUY_TAB) or index == Atr_FindTabIndex(SELL_TAB)) then
			Atr_Buy1_Button:Show();
			Atr_Buy1_Button:Disable();
		end

		Atr_HideElems (recommendElements);

		_G["Atr_Main_Panel"]:Show();

		gCurrentPane.UINeedsUpdate = true;

		if (gOpenAllBags == 1) then
			OpenAllBags(true);
			gOpenAllBags = 0;
		end

	end

end

-----------------------------------------

function Atr_StackSize ()
	return Atr_Batch_Stacksize:GetNumber();
end

-----------------------------------------

function Atr_SetStackSize (n)
	return Atr_Batch_Stacksize:SetText(n);
end

-----------------------------------------

function Atr_SelectPane (whichTab)

	local index = Atr_FindTabIndex(whichTab);
	local tab   = _G['AuctionFrameTab'..index];

	Atr_AuctionFrameTab_OnClick (tab, index);

end

-----------------------------------------

function Atr_IsModeCreateAuction ()
	return (Atr_IsTabSelected(SELL_TAB));
end


-----------------------------------------

function Atr_IsModeBuy ()
	return (Atr_IsTabSelected(BUY_TAB));
end

-----------------------------------------

function Atr_IsModeActiveAuctions ()
	return (Atr_IsTabSelected(MORE_TAB) and UIDropDownMenu_GetSelectedValue(Atr_DropDown1) == MODE_LIST_ACTIVE);
end

-----------------------------------------

function Atr_ClickAuctionSellItemButton (self, button)
	gAtr_ClickAuctionSell = true;
	ClickAuctionSellItemButton(self, button);
end


-----------------------------------------

function Atr_OnDropItem (self, button)

	if (GetCursorInfo() ~= "item") then
		return;
	end

	if (not Atr_IsTabSelected(SELL_TAB)) then
		Atr_SelectPane (SELL_TAB);		-- then fall through
	end

	Atr_ClickAuctionSellItemButton (self, button);
	ClearCursor();
end

-----------------------------------------

function Atr_SellItemButton_OnClick (self, button, ...)
	Atr_ClickAuctionSellItemButton (self, button);
end

-----------------------------------------

function Atr_SellItemButton_OnEvent (self, event, ...)
	if ( event == "NEW_AUCTION_UPDATE") then
		local name, texture, count, quality, canUse, price = GetAuctionSellItemInfo();
		Atr_SellControls_Tex:SetNormalTexture(texture);
	end
end
local gPrevSellItemLink;
-----------------------------------------

local function Atr_LoadContainerItemToSellPane()

	local bagID  = this:GetParent():GetID();
	local slotID = this:GetID();

	if (not Atr_IsTabSelected(SELL_TAB)) then
		Atr_SelectPane (SELL_TAB);
	end

	if (IsControlKeyDown()) then
		gAutoSingleton = time();
	end

	PickupContainerItem(bagID, slotID);

	local infoType = GetCursorInfo()

	if (infoType == "item") then
		Atr_ClearAll();
		Atr_ClickAuctionSellItemButton ();
		ClearCursor();
	end


end

-----------------------------------------

function Atr_ContainerFrameItemButton_OnClick (self, button)
	if (AuctionFrame and AuctionFrame:IsShown() and zc.StringSame (button, "RightButton")) then

		local selectedTab = PanelTemplates_GetSelectedTab (AuctionFrame);

		if (selectedTab == 1 or selectedTab == 2 or Atr_IsAuctionatorTab(selectedTab)) then
			Atr_LoadContainerItemToSellPane ();
		end
	end
end

-----------------------------------------

function Atr_ContainerFrameItemButton_OnModifiedClick (self, button)
	if (AUCTIONATOR_ENABLE_ALT ~= 0 and	AuctionFrame:IsShown() and IsAltKeyDown()) then

		Atr_LoadContainerItemToSellPane();
		return;
	end

	return auctionator_orig_ContainerFrameItemButton_OnModifiedClick (self, button);
end




-----------------------------------------

function Atr_CreateAuction_OnClick ()

	gJustPosted_ItemName			= gCurrentPane.activeScan.itemName;
	gJustPosted_ItemLink			= gCurrentPane.activeScan.itemLink;
	gJustPosted_BuyoutPrice			= MoneyInputFrame_GetCopper(Atr_StackPrice);
	gJustPosted_StackSize			= Atr_StackSize();
	gJustPosted_NumInBagsAtStart	= Atr_GetNumItemInBags(gJustPosted_ItemName);
	gJustPosted_NumStacks			= Atr_Batch_NumAuctions:GetNumber();

	local duration				= UIDropDownMenu_GetSelectedValue(Atr_Duration);
	local stackStartingPrice	= MoneyInputFrame_GetCopper(Atr_StartingPrice);
	local stackBuyoutPrice		= MoneyInputFrame_GetCopper(Atr_StackPrice);

	if (gJustPosted_StackSize == 1 and gCurrentPane.fullStackSize > 1) then

		local scan = gCurrentPane.activeScan;

		if (scan and scan.numYourSingletons + gJustPosted_NumStacks > 40) then
			local s = ZT("You may have at most 40 single-stack (x1)\nauctions posted for this item.\n\nYou already have %d such auctions and\nyou are trying to post %d more.");
			Atr_Error_Display (string.format (s, scan.numYourSingletons, gJustPosted_NumStacks));
			return;
		end
	end

	Atr_Memorize_Stacking_If();

	StartAuction (stackStartingPrice, stackBuyoutPrice, duration, gJustPosted_StackSize, gJustPosted_NumStacks);
end


-----------------------------------------

local gMS_stacksPrev;

-----------------------------------------

function Atr_OnAuctionMultiSellStart()

	gMS_stacksPrev = 0;

end

-----------------------------------------

function Atr_OnAuctionMultiSellUpdate()
	local stacksSoFar  = arg1;
	local stacksTotal  = arg2;

	local delta = stacksSoFar - gMS_stacksPrev;

--zc.md ("stacksSoFar: ", stacksSoFar, "stacksTotal: ", stacksTotal, "delta: ", delta);

	gMS_stacksPrev = stacksSoFar;

	Atr_AddToScan (gJustPosted_ItemName, gJustPosted_StackSize, gJustPosted_BuyoutPrice, delta);

	if (stacksSoFar == stacksTotal) then
		Atr_LogMsg (gJustPosted_ItemLink, gJustPosted_StackSize, gJustPosted_BuyoutPrice, stacksTotal);
		Atr_AddHistoricalPrice (gJustPosted_ItemName, gJustPosted_BuyoutPrice / gJustPosted_StackSize, gJustPosted_StackSize, gJustPosted_ItemLink);
	end

end

-----------------------------------------

function Atr_OnAuctionMultiSellFailure()

	-- add one more.  no good reason other than it just seems to work
	Atr_AddToScan (gJustPosted_ItemName, gJustPosted_StackSize, gJustPosted_BuyoutPrice, 1);

	Atr_LogMsg (gJustPosted_ItemLink, gJustPosted_StackSize, gJustPosted_BuyoutPrice, gMS_stacksPrev + 1);
	Atr_AddHistoricalPrice (gJustPosted_ItemName, gJustPosted_BuyoutPrice / gJustPosted_StackSize, gJustPosted_StackSize, gJustPosted_ItemLink);

	if (gCurrentPane.activeScan) then
		gCurrentPane.activeScan.whenScanned = 0;
	end
end


-----------------------------------------

function Atr_AuctionFrameAuctions_Update()

	auctionator_orig_AuctionFrameAuctions_Update();

end


-----------------------------------------

function Atr_LogMsg (itemlink, itemcount, price, numstacks)
	if itemlink then
		local logmsg = string.format (ZT("Auction created for %s"), itemlink);

		if (numstacks > 1) then
			logmsg = string.format (ZT("%d auctions created for %s"), numstacks, itemlink);
		end

		if (itemcount > 1) then
			logmsg = logmsg.."|cff00ddddx"..itemcount.."|r";
		end

		logmsg = logmsg.."   "..zc.priceToString(price);

		if (numstacks > 1 and itemcount > 1) then
			logmsg = logmsg.."  per stack";
		end

		zc.msg_yellow (logmsg);
	end
end

-----------------------------------------

function Atr_OnAuctionOwnedUpdate ()

	gItemPostingInProgress = false;

	if (Atr_IsModeActiveAuctions()) then
		gHlistNeedsUpdate = true;
	end

	if (not Atr_IsTabSelected()) then
		Atr_ClearScanCache();		-- if not our tab, we have no idea what happened so must flush all caches
		return;
	end;

	gActiveAuctions = {};		-- always flush this cache

	if (gJustPosted_ItemName) then

		if (gJustPosted_NumStacks == 1) then
			Atr_LogMsg (gJustPosted_ItemLink, gJustPosted_StackSize, gJustPosted_BuyoutPrice, 1);
			Atr_AddHistoricalPrice (gJustPosted_ItemName, gJustPosted_BuyoutPrice / gJustPosted_StackSize, gJustPosted_StackSize, gJustPosted_ItemLink);
			Atr_AddToScan (gJustPosted_ItemName, gJustPosted_StackSize, gJustPosted_BuyoutPrice, 1);
		end
	end


end

-----------------------------------------

function Atr_ResetDuration()

	if (AUCTIONATOR_DEF_DURATION == "S") then UIDropDownMenu_SetSelectedValue(Atr_Duration, 1); end;
	if (AUCTIONATOR_DEF_DURATION == "M") then UIDropDownMenu_SetSelectedValue(Atr_Duration, 2); end;
	if (AUCTIONATOR_DEF_DURATION == "L") then UIDropDownMenu_SetSelectedValue(Atr_Duration, 3); end;

end

-----------------------------------------

function Atr_AddToScan (itemName, stackSize, buyoutPrice, numAuctions)

	local scan = Atr_FindScan (itemName);

	local quality = gJustPosted_ItemLink and select (3, GetItemInfo (gJustPosted_ItemLink)) or gSellPane.sellItemQuality;

	scan:AddScanItem (itemName, stackSize, buyoutPrice, UnitName("player"), numAuctions, nil, quality);

	scan:CondenseAndSort ();

	gCurrentPane.UINeedsUpdate = true;
end

-----------------------------------------

function AuctionatorSubtractFromScan (itemName, stackSize, buyoutPrice, howMany)

	if (howMany == nil) then
		howMany = 1;
	end

	local scan = Atr_FindScan (itemName);

	local x;
	for x = 1, howMany do
		scan:SubtractScanItem (itemName, stackSize, buyoutPrice);
	end

	scan:CondenseAndSort ();

	gCurrentPane.UINeedsUpdate = true;
end


-----------------------------------------

function auctionator_ChatEdit_InsertLink(text)

	if (AuctionFrame:IsShown() and IsShiftKeyDown() and Atr_IsTabSelected(BUY_TAB)) then
		local item;
		if ( strfind(text, "item:", 1, true) ) then
			item = GetItemInfo(text);
		end
		if ( item ) then
			Atr_Search_Box:SetText (item);
			Atr_Search_Onclick ();
			return true;
		end
	end

	return auctionator_orig_ChatEdit_InsertLink(text);

end

-----------------------------------------

function auctionator_ChatFrame_OnEvent(self, event, ...)

	if (event == "CHAT_MSG_SYSTEM") then
		if (arg1 == ERR_AUCTION_STARTED) then		-- absorb the Auction Created message
			return;
		end
		if (arg1 == ERR_AUCTION_REMOVED) then		-- absorb the Auction Created message
			return;
		end
	end

	return auctionator_orig_ChatFrame_OnEvent (self, event, ...);

end




-----------------------------------------

function auctionator_CanShowRightUIPanel(frame)

	if (zc.StringSame (frame:GetName(), "TradeSkillFrame")) then
		return 1;
	end;

	return auctionator_orig_CanShowRightUIPanel(frame);

end

-----------------------------------------

function Atr_AddMainPanel ()

	local frame = CreateFrame("FRAME", "Atr_Main_Panel", AuctionFrame, "Atr_Sell_Template");
	frame:Hide();

	UIDropDownMenu_SetWidth (Atr_DropDownSL, 150);
	UIDropDownMenu_JustifyText (Atr_DropDownSL, "CENTER");

	UIDropDownMenu_SetWidth (Atr_Duration, 95);

end

-----------------------------------------

function Atr_AddSellTab (tabtext, whichTab)

	local n = AuctionFrame.numTabs+1;

	local framename = "AuctionFrameTab"..n;

	local frame = CreateFrame("Button", framename, AuctionFrame, "AuctionTabTemplate");

	frame:SetID(n);
	frame:SetText(tabtext);

	frame:SetNormalFontObject(_G["AtrFontOrange"]);

	frame.auctionatorTab = whichTab;

	frame:SetPoint("LEFT", _G["AuctionFrameTab"..n-1], "RIGHT", -8, 0);

	PanelTemplates_SetNumTabs (AuctionFrame, n);
	PanelTemplates_EnableTab  (AuctionFrame, n);

	return AtrPane.create (whichTab);
end

-----------------------------------------

function Atr_HideElems (tt)

	if (not tt) then
		return;
	end

	for i,x in ipairs(tt) do
		x:Hide();
	end
end

-----------------------------------------

function Atr_ShowElems (tt)

	for i,x in ipairs(tt) do
		x:Show();
	end
end




-----------------------------------------

function Atr_OnAuctionUpdate ()

	if (gAtr_FullScanState == ATR_FS_STARTED) then
		Atr_FullScanBeginAnalyzePhase();	-- analyzed chunk-by-chunk in the idle loop so the client never freezes
		return;
	end

	if (gAtr_FullScanState == ATR_FS_SLOW_QUERY_SENT) then
		Atr_FullScanBeginAnalyzePhase();
		Atr_FullScanAnalyze();				-- handle here since it's just one page
		return;
	end

	if (not Atr_IsTabSelected()) then
		Atr_ClearScanCache();		-- if not our tab, we have no idea what happened so must flush all caches
		return;
	end;

	if (Atr_Buy_OnAuctionUpdate()) then
		return;
	end

	if (gCurrentPane.activeSearch) then
		gCurrentPane.activeSearch:OnListUpdate();		-- capture page, check for bad/duplicate data, analyze
	end

end

-----------------------------------------

function Atr_OnSearchComplete ()

	gCurrentPane.sortedHist = nil;

	local count = gCurrentPane.activeSearch:NumScans();
	if (count == 1) then
		gCurrentPane.activeScan = gCurrentPane.activeSearch:GetFirstScan();
	end

	if (Atr_IsModeCreateAuction()) then

		Atr_SetToShowCurrent();

		if (#gCurrentPane.activeScan.scanData == 0) then

			-- no current auctions: fall back to the scan DB's daily history,
			-- or to hints + posting history if the item has never been scanned

			if (gAtr_ScanDB[gCurrentPane.activeScan.itemName]) then
				Atr_SetToShowHistory();
				Atr_BuildSortedScanHistoryList (gCurrentPane.activeScan.itemName);
				gCurrentPane.histIndex = 1;
			else
				local hints = Atr_BuildHints (gCurrentPane.activeScan.itemName);
				if (#hints > 0) then
					Atr_SetToShowHints();
					Atr_Build_PostingsList ();
					gCurrentPane.histIndex = 1;
				end
			end

		end

		if (Atr_IsSelectedTab_Current()) then
			Atr_FindBestCurrentAuction ();
		end

		Atr_UpdateRecommendation(true);
	else
		if (Atr_IsModeActiveAuctions()) then
			Atr_DisplayHlist();
		end

		Atr_FindBestCurrentAuction ();
	end

	if (Atr_IsModeBuy()) then
		Atr_Shop_OnFinishScan ();
	end

	Atr_CheckingActive_OnSearchComplete();

	gCurrentPane.UINeedsUpdate = true;

end

-----------------------------------------

function Atr_ClearTop ()
	Atr_HideElems (recommendElements);

	if (AuctionatorMessageFrame) then
		AuctionatorMessageFrame:Hide();
		AuctionatorMessage2Frame:Hide();
	end
end

-----------------------------------------

function Atr_ClearList ()

	Atr_Col1_Heading:Hide();
	Atr_Col3_Heading:Hide();
	Atr_Col4_Heading:Hide();

	Atr_Col1_Heading_Button:Hide();
	Atr_Col3_Heading_Button:Hide();

	local line;							-- 1 through 12 of our window to scroll

	FauxScrollFrame_Update (AuctionatorScrollFrame, 0, 12, 16);

	for line = 1,12 do
		local lineEntry = _G["AuctionatorEntry"..line];
		lineEntry:Hide();
	end

end

-----------------------------------------

function Atr_ClearAll ()

	if (AuctionatorMessageFrame) then	-- just to make sure xml has been loaded

		Atr_ClearTop();
		Atr_ClearList();
	end
end

-----------------------------------------

function Atr_SetMessage (msg)
	Atr_HideElems (recommendElements);

	if (gCurrentPane.activeSearch.searchText) then

		Atr_ShowItemNameAndTexture (gCurrentPane.activeSearch.searchText);

		AuctionatorMessage2Frame:SetText (msg);
		AuctionatorMessage2Frame:Show();

	else
		AuctionatorMessageFrame:SetText (msg);
		AuctionatorMessageFrame:Show();
		AuctionatorMessage2Frame:Hide();
	end
end

-----------------------------------------

function Atr_ShowItemNameAndTexture(itemName)

	AuctionatorMessageFrame:Hide();
	AuctionatorMessage2Frame:Hide();

	local scn = gCurrentPane.activeScan;

	local color = "";
	if (scn and not scn:IsNil()) then
		color = "|cff"..zc.RGBtoHEX (scn.itemTextColor[1], scn.itemTextColor[2], scn.itemTextColor[3]);
		itemName = scn.itemName;
	end

	Atr_Recommend_Text:Show ();
	Atr_Recommend_Text:SetText (color..itemName);

	Atr_SetTextureButton ("Atr_RecommendItem_Tex", 1, gCurrentPane.activeScan.itemLink);
end



-----------------------------------------

function Atr_SortHistoryData (x, y)

	return x.when > y.when;

end

-----------------------------------------

function BuildHtag (type, y, m, d)

	local t = time({year=y, month=m, day=d, hour=0});

	return tostring (ToTightTime(t))..":"..type;
end

-----------------------------------------

function ParseHtag (tag)
	local when, type = strsplit(":", tag);

	if (type == nil) then
		type = "hx";
	end

	when = FromTightTime (tonumber (when));

	return when, type;
end

-----------------------------------------

function ParseHist (tag, hist)

	local when, type = ParseHtag(tag);

	local price, count	= strsplit(":", hist);

	price = tonumber (price);

	local stacksize, numauctions;

	if (type == "hx") then
		stacksize	= tonumber (count);
		numauctions	= 1;
	else
		stacksize = 0;
		numauctions	= tonumber (count);
	end

	return when, type, price, stacksize, numauctions;

end

-----------------------------------------

function CalcAbsTimes (when, whent)

	local absYear	= whent.year - 2000;
	local absMonth	= (absYear * 12) + whent.month;
	local absDay	= floor ((when - gTimeZero) / (60*60*24));

	return absYear, absMonth, absDay;

end

-----------------------------------------

function Atr_Condense_History (itemname)

	if (AUCTIONATOR_PRICING_HISTORY[itemname] == nil) then
		return;
	end

	local tempHistory = {};

	local now			= time();
	local nowt			= date("*t", now);

	local absNowYear, absNowMonth, absNowDay = CalcAbsTimes (now, nowt);

	local n = 1;
	local tag, hist, newtag, stacksize, numauctions;
	for tag, hist in pairs (AUCTIONATOR_PRICING_HISTORY[itemname]) do
		if (tag ~= "is") then

			local when, type, price, stacksize, numauctions = ParseHist (tag, hist);

			local whnt = date("*t", when);

			local absYear, absMonth, absDay	= CalcAbsTimes (when, whnt);

			if (absNowYear - absYear >= 3) then
				newtag = BuildHtag ("hy", whnt.year, 1, 1);
			elseif (absNowMonth - absMonth >= 2) then
				newtag = BuildHtag ("hm", whnt.year, whnt.month, 1);
			elseif (absNowDay - absDay >= 2) then
				newtag = BuildHtag ("hd", whnt.year, whnt.month, whnt.day);
			else
				newtag = tag;
			end

			tempHistory[n] = {};
			tempHistory[n].price		= price;
			tempHistory[n].numauctions	= numauctions;
			tempHistory[n].stacksize	= stacksize;
			tempHistory[n].when			= when;
			tempHistory[n].newtag		= newtag;
			n = n + 1;
		end
	end

	-- clear all the existing history

	local is = AUCTIONATOR_PRICING_HISTORY[itemname]["is"];

	AUCTIONATOR_PRICING_HISTORY[itemname] = {};
	AUCTIONATOR_PRICING_HISTORY[itemname]["is"] = is;

	-- repopulate the history

	local x;

	for x = 1,#tempHistory do

		local thist		= tempHistory[x];
		local newtag	= thist.newtag;

		if (AUCTIONATOR_PRICING_HISTORY[itemname][newtag] == nil) then

			local when, type = ParseHtag (newtag);

			local count = thist.numauctions;
			if (type == "hx") then
				count = thist.stacksize;
			end

			AUCTIONATOR_PRICING_HISTORY[itemname][newtag] = tostring(thist.price)..":"..tostring(count);

		else

			local hist = AUCTIONATOR_PRICING_HISTORY[itemname][newtag];

			local when, type, price, stacksize, numauctions = ParseHist (newtag, hist);

			local newNumAuctions = numauctions + thist.numauctions;
			local newPrice		 = ((price * numauctions) + (thist.price * thist.numauctions)) / newNumAuctions;

			AUCTIONATOR_PRICING_HISTORY[itemname][newtag] = tostring(newPrice)..":"..tostring(newNumAuctions);
		end
	end

end

-----------------------------------------

function Atr_Process_Historydata ()

	-- Condense the data if needed - only once per session for each item

	if (gCurrentPane:IsScanNil()) then
		return;
	end

	local itemName = gCurrentPane.activeScan.itemName;

	if (gCondensedThisSession[itemName] == nil) then

		gCondensedThisSession[itemName] = true;

		Atr_Condense_History(itemName);
	end

	-- build the sorted history list

	gCurrentPane.sortedHist = {};

	if (AUCTIONATOR_PRICING_HISTORY[itemName]) then
		local n = 1;
		local tag, hist;
		for tag, hist in pairs (AUCTIONATOR_PRICING_HISTORY[itemName]) do
			if (tag ~= "is") then
				local when, type, price, stacksize, numauctions = ParseHist (tag, hist);

				if (stacksize == 0) then
					stacksize = numauctions;
				end

				gCurrentPane.sortedHist[n]				= {};
				gCurrentPane.sortedHist[n].itemPrice	= price;
				gCurrentPane.sortedHist[n].buyoutPrice	= price * stacksize;
				gCurrentPane.sortedHist[n].stackSize	= stacksize;
				gCurrentPane.sortedHist[n].when			= when;
				gCurrentPane.sortedHist[n].yours		= true;
				gCurrentPane.sortedHist[n].type			= type;

				n = n + 1;
			end
		end
	end

	table.sort (gCurrentPane.sortedHist, Atr_SortHistoryData);

	if (#gCurrentPane.sortedHist > 0) then
		return gCurrentPane.sortedHist[1].itemPrice;
	end

end

-----------------------------------------

function Atr_GetMostRecentSale (itemName)

	local recentPrice;
	local recentWhen = 0;

	if (AUCTIONATOR_PRICING_HISTORY and AUCTIONATOR_PRICING_HISTORY[itemName]) then
		local n = 1;
		local tag, hist;
		for tag, hist in pairs (AUCTIONATOR_PRICING_HISTORY[itemName]) do
			if (tag ~= "is") then
				local when, type, price = ParseHist (tag, hist);

				if (when > recentWhen) then
					recentPrice = price;
					recentWhen  = when;
				end
			end
		end
	end

	return recentPrice;

end


-----------------------------------------

function Atr_ShowingSearchSummary ()

	if (gCurrentPane.activeSearch and gCurrentPane.activeSearch.searchText ~= "" and gCurrentPane:IsScanNil() and gCurrentPane.activeSearch:NumScans() > 0) then
		return true;
	end

	return false;
end

-----------------------------------------

-- the selected Atr_ListTabs tab is the single source of truth for which list is shown
-- (ported from ver 3.2.6; replaces the old per-pane showWhich mechanism)

function Atr_IsSelectedTab_Current ()

	return (PanelTemplates_GetSelectedTab (Atr_ListTabs) == 1);
end

-----------------------------------------

function Atr_IsSelectedTab_History ()

	return (PanelTemplates_GetSelectedTab (Atr_ListTabs) == 2);
end

-----------------------------------------

function Atr_IsSelectedTab_Hints ()

	return (PanelTemplates_GetSelectedTab (Atr_ListTabs) == 3);
end

-----------------------------------------

function Atr_SetToShowTab (which)

	if (PanelTemplates_GetSelectedTab (Atr_ListTabs) == which) then
		return;
	end

	PanelTemplates_SetTab(Atr_ListTabs, which);
	gCurrentPane.UINeedsUpdate = true;
end

-----------------------------------------

function Atr_SetToShowCurrent ()
	Atr_SetToShowTab (1);
end

-----------------------------------------

function Atr_SetToShowHistory ()
	Atr_SetToShowTab (2);
end

-----------------------------------------

function Atr_SetToShowHints ()
	Atr_SetToShowTab (3);
end

-----------------------------------------

function Atr_ClearHistory ()

	gCurrentPane.sortedHist = nil;
end

-----------------------------------------

function Atr_ShowingCurrentAuctions ()

	return Atr_IsSelectedTab_Current();
end

-----------------------------------------

function Atr_ShowingHistory ()

	return Atr_IsSelectedTab_History();
end

-----------------------------------------

function Atr_ShowingHints ()

	return Atr_IsSelectedTab_Hints();
end



-----------------------------------------

function Atr_UpdateRecommendation (updatePrices)

	if (gCurrentPane == gSellPane and gJustPosted_ItemLink and GetAuctionSellItemInfo() == nil) then
		return;
	end

	local scn = gCurrentPane.activeScan;
	if (scn == nil) then
		scn = Atr_FindScan (nil);
	end

	local basedata;

	if (Atr_ShowingSearchSummary()) then

	elseif (Atr_IsSelectedTab_Current()) then

		if (gCurrentPane:GetProcessingState() ~= KM_NULL_STATE) then
			return;
		end

		if (#scn.sortedData == 0) then
			Atr_SetMessage (ZT("No current auctions found"));
			return;
		end

		if (not gCurrentPane.currIndex) then
			if (scn.numMatches == 0) then
				Atr_SetMessage (ZT("No current auctions found\n\n(related auctions shown)"));
			elseif (scn.numMatchesWithBuyout == 0) then
				Atr_SetMessage (ZT("No current auctions with buyouts found"));
			else
				Atr_SetMessage ("");
			end
			return;
		end

		basedata = scn.sortedData[gCurrentPane.currIndex];

	else	-- History and Other sub-tabs both read the sortedHist list

		basedata = zc.GetArrayElemOrFirst (gCurrentPane.sortedHist, gCurrentPane.histIndex);

		if (basedata == nil) then
			Atr_SetMessage (ZT("Auctionator has yet to record any auctions for this item"));
			return;
		end
	end

	if (Atr_StackSize() == 0) then
		return;
	end

	local new_Item_BuyoutPrice;

	if (gItemPostingInProgress and gCurrentPane.itemLink == gJustPosted_ItemLink) then	-- handle the unusual case where server is still in the process of creating the last auction

		new_Item_BuyoutPrice = gJustPosted_BuyoutPrice / gJustPosted_StackSize;

	elseif (basedata) then			-- the normal case

		new_Item_BuyoutPrice = basedata.itemPrice;

		if (not basedata.yours and not basedata.altname) then
			new_Item_BuyoutPrice = Atr_CalcUndercutPrice (new_Item_BuyoutPrice);
		end
	end

	if (new_Item_BuyoutPrice == nil or gCurrentPane ~= gSellPane) then
		return;
	end

	local new_Item_StartPrice = Atr_CalcStartPrice (new_Item_BuyoutPrice);

	Atr_ShowElems (recommendElements);
	AuctionatorMessageFrame:Hide();
	AuctionatorMessage2Frame:Hide();

	Atr_Recommend_Text:SetText (ZT("Recommended Buyout Price"));
	Atr_RecommendPerStack_Text:SetText (string.format (ZT("for your stack of %d"), Atr_StackSize()));

	Atr_SetTextureButton ("Atr_RecommendItem_Tex", Atr_StackSize(), scn.itemLink);

	MoneyFrame_Update ("Atr_RecommendPerItem_Price",  zc.round(new_Item_BuyoutPrice));
	MoneyFrame_Update ("Atr_RecommendPerStack_Price", zc.round(new_Item_BuyoutPrice * Atr_StackSize()));

	if (updatePrices) then
		MoneyInputFrame_SetCopper (Atr_StackPrice,		new_Item_BuyoutPrice * Atr_StackSize());
		MoneyInputFrame_SetCopper (Atr_StartingPrice, 	new_Item_StartPrice * Atr_StackSize());
		MoneyInputFrame_SetCopper (Atr_ItemPrice,		new_Item_BuyoutPrice);
	end

	local cheapestStack
	if (scn.bestPrices) then
		cheapestStack = scn.bestPrices[Atr_StackSize()];
	end

	Atr_Recommend_Basis_Text:SetTextColor (1,1,1);

	if (not Atr_IsSelectedTab_Current() and basedata.whenText) then
		Atr_Recommend_Basis_Text:SetTextColor (.8,.8,1);
		Atr_Recommend_Basis_Text:SetText ("("..ZT("based on").." "..basedata.whenText..")");
	elseif (scn.absoluteBest and basedata.stackSize == scn.absoluteBest.stackSize and basedata.buyoutPrice == scn.absoluteBest.buyoutPrice) then
		Atr_Recommend_Basis_Text:SetText ("("..ZT("based on cheapest current auction")..")");
	elseif (cheapestStack and basedata.stackSize == cheapestStack.stackSize and basedata.buyoutPrice == cheapestStack.buyoutPrice) then
		Atr_Recommend_Basis_Text:SetText ("("..ZT("based on cheapest stack of the same size")..")");
	else
		Atr_Recommend_Basis_Text:SetText ("("..ZT("based on selected auction")..")");
	end

end


-----------------------------------------

function Atr_StackPriceChangedFunc ()

	local new_Stack_BuyoutPrice = MoneyInputFrame_GetCopper (Atr_StackPrice);
	local new_Item_BuyoutPrice  = math.floor (new_Stack_BuyoutPrice / Atr_StackSize());
	local new_Item_StartPrice   = Atr_CalcStartPrice (new_Item_BuyoutPrice);

	local calculatedStackPrice = MoneyInputFrame_GetCopper(Atr_ItemPrice) * Atr_StackSize();

	-- check to prevent looping

	if (calculatedStackPrice ~= new_Stack_BuyoutPrice) then
		MoneyInputFrame_SetCopper (Atr_ItemPrice,		new_Item_BuyoutPrice);
		MoneyInputFrame_SetCopper (Atr_StartingPrice,	new_Item_StartPrice * Atr_StackSize());
	end
	Atr_SetDepositText()
end

-----------------------------------------

function Atr_ItemPriceChangedFunc ()

	local new_Item_BuyoutPrice = MoneyInputFrame_GetCopper (Atr_ItemPrice);
	local new_Item_StartPrice  = Atr_CalcStartPrice (new_Item_BuyoutPrice);

	local calculatedItemPrice = math.floor (MoneyInputFrame_GetCopper (Atr_StackPrice) / Atr_StackSize());

	-- check to prevent looping

	if (calculatedItemPrice ~= new_Item_BuyoutPrice) then
		MoneyInputFrame_SetCopper (Atr_StackPrice, 		new_Item_BuyoutPrice * Atr_StackSize());
		MoneyInputFrame_SetCopper (Atr_StartingPrice,	new_Item_StartPrice  * Atr_StackSize());
	end
	Atr_SetDepositText()
end

-----------------------------------------

function Atr_StackSizeChangedFunc ()

	local item_BuyoutPrice		= MoneyInputFrame_GetCopper (Atr_ItemPrice);
	local new_Item_StartPrice   = Atr_CalcStartPrice (item_BuyoutPrice);

	MoneyInputFrame_SetCopper (Atr_StackPrice, 		item_BuyoutPrice * Atr_StackSize());
	MoneyInputFrame_SetCopper (Atr_StartingPrice,	new_Item_StartPrice  * Atr_StackSize());

--	Atr_MemorizeButton:Show();

	gSellPane.UINeedsUpdate = true;
	Atr_SetDepositText()
end

-----------------------------------------

function Atr_NumAuctionsChangedFunc (x)

--	Atr_MemorizeButton:Show();

	gSellPane.UINeedsUpdate = true;
end

-----------------------------------------

function Atr_SellSetMaxStacksize ()

	if (gCurrentPane and gCurrentPane.fullStackSize and gCurrentPane.fullStackSize > 0) then

		-- cap at what you actually own divided by the number of stacks, not the
		-- item's full stack size (16 linen as 2 stacks -> stack size of 8)

		local maxSS     = gCurrentPane.fullStackSize;
		local numStacks = Atr_Batch_NumAuctions:GetNumber();

		if (numStacks > 0 and gCurrentPane.totalItems) then
			maxSS = math.min (maxSS, math.floor (gCurrentPane.totalItems / numStacks));
		end

		if (maxSS < 1) then
			maxSS = 1;
		end

		Atr_SetStackSize (maxSS);		-- fires Atr_StackSizeChangedFunc, which refreshes the max-auctions hint
	end
end

-----------------------------------------

function Atr_SellSetMaxAuctions ()

	local ss = Atr_StackSize();

	if (gCurrentPane and gCurrentPane.totalItems and ss and ss > 0) then
		Atr_Batch_NumAuctions:SetText (math.floor (gCurrentPane.totalItems / ss));
	end
end


-----------------------------------------

function Atr_SetTextureButton (elementName, count, itemlink)

	local texture = GetItemIcon (itemlink);

	local textureElement = _G[elementName];

	if (texture) then
		textureElement:Show();
		textureElement:SetNormalTexture (texture);
		Atr_SetTextureButtonCount (elementName, count);
	else
		Atr_SetTextureButtonCount (elementName, 0);
	end

end

-----------------------------------------

function Atr_SetTextureButtonCount (elementName, count)

	local countElement   = _G[elementName.."Count"];

	if (count > 1) then
		countElement:SetText (count);
		countElement:Show();
	else
		countElement:Hide();
	end

end

-----------------------------------------

function Atr_ShowRecTooltip ()

	local link = gCurrentPane.activeScan.itemLink;
	local num  = Atr_StackSize();

	if (not link) then
		link = gJustPosted_ItemLink;
		num  = gJustPosted_StackSize;
	end

	if (link) then
		if (num < 1) then num = 1; end;

		GameTooltip:SetOwner(Atr_RecommendItem_Tex, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink (link, num);
		gCurrentPane.tooltipvisible = true;
	end

end

-----------------------------------------

function Atr_HideRecTooltip ()

	gCurrentPane.tooltipvisible = nil;
	GameTooltip:Hide();

end


-----------------------------------------

function Atr_OnAuctionHouseShow()

	gOpenAllBags = AUCTIONATOR_OPEN_ALL_BAGS;

	if (AUCTIONATOR_DEFTAB == 1) then		Atr_SelectPane (SELL_TAB);	end
	if (AUCTIONATOR_DEFTAB == 2) then		Atr_SelectPane (BUY_TAB);	end
	if (AUCTIONATOR_DEFTAB == 3) then		Atr_SelectPane (MORE_TAB);	end

	Atr_ResetDuration();

	gJustPosted_ItemName = nil;
	gSellPane:ClearSearch();

	if (gCurrentPane) then
		gCurrentPane.UINeedsUpdate = true;
	end
end

-----------------------------------------

function Atr_OnAuctionHouseClosed()

	Atr_SwitchTo_BlizzItemOnClick();

	Atr_HideAllDialogs();

	if (Atr_FullScan_OnAHClosed) then
		Atr_FullScan_OnAHClosed();		-- abort any running full scan
	end

	Atr_CheckingActive_Finish ();

	Atr_ClearScanCache();

	gSellPane:ClearSearch();
	gShopPane:ClearSearch();
	gMorePane:ClearSearch();

end

-----------------------------------------

function Atr_HideAllDialogs()

	Atr_CheckActives_Frame:Hide();
	Atr_Error_Frame:Hide();
	Atr_Buy_Confirm_Frame:Hide();
	Atr_FullScanFrame:Hide();
	Atr_Mask:Hide();

end



-----------------------------------------

function Atr_BasicOptionsUpdate(self, elapsed)

	self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + elapsed;

	if (self.TimeSinceLastUpdate > 0.25) then

		self.TimeSinceLastUpdate = 0;

		if (AuctionatorOption_Def_Duration_CB:GetChecked()) then
			AuctionatorOption_Durations:Show();
		else
			AuctionatorOption_Durations:Hide();
		end

	end
end


-----------------------------------------

function Atr_OnWhoListUpdate()

	if (gSendZoneMsgs) then
		gSendZoneMsgs = false;

		local numWhos, totalCount = GetNumWhoResults();
		local i;

		zc.md (numWhos.." out of "..totalCount.." users found");

		for i = 1,numWhos do
			local name, guildname, level = GetWhoInfo(i);
			Atr_SendAddon_VREQ ("WHISPER", name);
			if (Atr_Guildinfo) then
				Atr_Guildinfo[name] = guildname;
			end
			if (Atr_Levelinfo) then
				Atr_Levelinfo[name] = level;
			end

		end
	end
end

-----------------------------------------

function Atr_OnUpdate(self, elapsed)

	-- update the global "precision" timer

	Atr_ptime = Atr_ptime and Atr_ptime + elapsed or 0;


	-- check deferred call queue

	if (zc.periodic (self, "dcq_lastUpdate", 0.05, elapsed)) then
		zc.CheckDeferredCall();
	end

	-- pending scan soft-retries need sub-0.2s timing, so check every frame

	if (gCurrentPane and gCurrentPane.activeSearch and gCurrentPane.activeSearch.softRetryAt) then
		gCurrentPane.activeSearch:CheckSoftRetry();
	end

	-- make sure all dusts and essences are in the local cache

	if (gAtr_dustCacheIndex > 0 and zc.periodic (self, "dust_lastUpdate", 0.1, elapsed)) then
		Atr_GetNextDustIntoCache();
	end

	-- special idle routine for the full scan analyze phase gets called every frame
	-- (nil check: AuctionatorScanFull.lua is missing if the addon was updated without restarting WoW)

	local handled = Atr_FullScanFrameIdle and Atr_FullScanFrameIdle();
	if (handled) then
		return;
	end

	-- the core Idle routine

	if (zc.periodic (self, "idle_lastUpdate", 0.2, elapsed)) then
		Atr_Idle (self, elapsed);
	end
end


-----------------------------------------
local verCheckMsgState = 0;
-----------------------------------------

function Atr_Idle(self, elapsed)


	if (gCurrentPane and gCurrentPane.tooltipvisible) then
		Atr_ShowRecTooltip();
	end

	if (gCurrentPane and Atr_IsModeBuy()) then
		Atr_Shop_Idle();		-- keeps the Exact Match checkbox in sync with quoted search text
	end


	if (verCheckMsgState == 0) then
		verCheckMsgState = time();
	end

	if (verCheckMsgState > 1 and time() - verCheckMsgState > 5) then	-- wait 5 seconds
		verCheckMsgState = 1;

		local guildname = GetGuildInfo ("player");
		if (guildname) then
			Atr_SendAddon_VREQ ("GUILD");
		end
	end

	if (not Atr_IsTabSelected() or AuctionatorMessageFrame == nil) then
		return;
	end

	if (gHentryTryAgain) then
		Atr_HEntryOnClick();
		return;
	end

	if (gCurrentPane.activeSearch and gCurrentPane.activeSearch.processing_state == KM_PREQUERY) then		------- check whether to send a new auction query to get the next page -------
		gCurrentPane.activeSearch:Continue();
	end

	if (gCurrentPane.activeSearch) then		------- detect a dropped AUCTION_ITEM_LIST_UPDATE (stuck query) -------
		gCurrentPane.activeSearch:CheckTimeout();
	end

	Atr_UpdateUI ();

	Atr_CheckingActiveIdle();

	Atr_Buy_Idle();

	if (gHideAPFrameCheck == nil) then	-- for the addon 'Auction Profit' (flags for efficiency so we only check one time)
		gHideAPFrameCheck = true;
		if (AP_Bid_MoneyFrame) then
			AP_Bid_MoneyFrame:Hide();
			AP_Buy_MoneyFrame:Hide();
		end
	end
end

-----------------------------------------



-----------------------------------------

function Atr_OnNewAuctionUpdate()

	if (not gAtr_ClickAuctionSell) then
		gPrevSellItemLink = nil;
		return;
	end
--	zc.md ("gAtr_ClickAuctionSell:", gAtr_ClickAuctionSell);

	gAtr_ClickAuctionSell = false;

	local auctionItemName, auctionCount, auctionLink, exact, bloodforged = Atr_GetSellItemInfo();

	if (gPrevSellItemLink ~= auctionLink) then

		gPrevSellItemLink = auctionLink;

		if (auctionLink) then
			gJustPosted_ItemName = nil;
			Atr_AddToItemLinkCache (auctionItemName, auctionLink);
			Atr_ClearList();		-- better UE
			Atr_SetToShowCurrent();
		end

		MoneyInputFrame_SetCopper (Atr_StackPrice, 0);
		MoneyInputFrame_SetCopper (Atr_StartingPrice,  0);
		Atr_ResetDuration();

		if (gJustPosted_ItemName == nil) then

			local searchName = auctionItemName;
			if (string.find (auctionItemName, "RE:")) then
				searchName = string.gsub (auctionItemName, "RE:", "");
			end

			-- exact searches carry an IDstring + the link; Bloodforged/suffix-stripped
			-- names search by plain name so all variants match (fork behavior)

			local cacheHit;
			if (exact) then
				local IDstring = auctionLink and Auctionator.ItemLink:new({ item_link = auctionLink }):IdString() or ("***"..searchName);
				cacheHit = gSellPane:DoSearch (searchName, IDstring, auctionLink, 20);
			else
				cacheHit = gSellPane:DoSearch (searchName, nil, nil, 20);
			end

			gSellPane.totalItems	= Atr_GetNumItemInBags (auctionItemName, bloodforged);
			gSellPane.fullStackSize = auctionLink and (select (8, GetItemInfo (auctionLink))) or 0;

			-- rarity of the item actually being sold: same-named variants (Bloodforged)
			-- can be rare OR epic, and the recommendation must compare like with like

			gSellPane.sellItemQuality = select (4, GetAuctionSellItemInfo());

			-- the bag re-scan can miss (name-match/formatting quirks on custom items),
			-- which wrongly shows "max: 0" and greys out Create Auction even though the
			-- item is sitting in the sell slot. fall back to the count the game itself
			-- reports for the placed stack so a valid post is never blocked.

			if ((gSellPane.totalItems == nil or gSellPane.totalItems == 0) and auctionCount and auctionCount > 0) then
				gSellPane.totalItems = auctionCount;
			end

			local prefNumStacks, prefStackSize = Atr_GetSellStacking (auctionLink, auctionCount, gSellPane.totalItems);

			if (time() - gAutoSingleton < 5) then
				Atr_SetInitialStacking (1, 1);
			else
				Atr_SetInitialStacking (prefNumStacks, prefStackSize);
			end

			if (cacheHit) then

				-- a cached scan was condensed under the PREVIOUS item's rarity filter;
				-- re-condense so "My rarity only" reflects the item now being sold

				if (AUCTIONATOR_MATCH_RARITY == 1 and gSellPane.activeScan and not gSellPane.activeScan:IsNil()) then
					gSellPane.activeScan:CondenseAndSort();
				end

				Atr_OnSearchComplete ();
			end

			Atr_SetTextureButton ("Atr_SellControls_Tex", Atr_StackSize(), auctionLink);
			Atr_SellControls_TexName:SetText (auctionItemName);
		else
			Atr_SetTextureButton ("Atr_SellControls_Tex", 0, nil);
			Atr_SellControls_TexName:SetText ("");
		end

	elseif (Atr_StackSize() ~= auctionCount) then

		local prefNumStacks, prefStackSize = Atr_GetSellStacking (auctionLink, auctionCount, gSellPane.totalItems);

		Atr_SetInitialStacking (prefNumStacks, prefStackSize);

		Atr_SetTextureButton ("Atr_SellControls_Tex", Atr_StackSize(), auctionLink);

		Atr_FindBestCurrentAuction();
		Atr_ResetDuration();
	end

	gSellPane.UINeedsUpdate = true;

end

---------------------------------------------------------

function Atr_UpdateUI ()

	local needsUpdate = gCurrentPane.UINeedsUpdate;

	if (gCurrentPane.UINeedsUpdate) then

		gCurrentPane.UINeedsUpdate = false;

		Atr_RedisplayAuctions();

		if (gCurrentPane:IsScanNil()) then
			Atr_ListTabs:Hide();
		else
			Atr_ListTabs:Show();
		end

		Atr_SetMessage ("");
		local scn = gCurrentPane.activeScan;

		if (Atr_IsModeCreateAuction()) then

			Atr_UpdateRecommendation (false);
		else
			Atr_HideElems (recommendElements);

			if (scn:IsNil()) then
				Atr_ShowItemNameAndTexture (gCurrentPane.activeSearch.searchText);
			else
				Atr_ShowItemNameAndTexture (gCurrentPane.activeScan.itemName);
			end

			if (Atr_IsModeBuy()) then

				if (gCurrentPane.activeSearch.searchText == "") then
					Atr_SetMessage (ZT("Select an item from the list on the left\n or type a search term above to start a scan."));
				end
			end

		end


		if (Atr_IsTabSelected(BUY_TAB)) then
			Atr_Shop_UpdateUI();
		end

	end

	-- update the hlist if needed

	if (gHlistNeedsUpdate and Atr_IsModeActiveAuctions()) then
		gHlistNeedsUpdate = false;
		Atr_DisplayHlist();
	end

	if (Atr_IsTabSelected(SELL_TAB)) then
		Atr_UpdateUI_SellPane (needsUpdate);
	end

end

---------------------------------------------------------

function Atr_UpdateUI_SellPane (needsUpdate)

	local auctionItemName = GetAuctionSellItemInfo();

	if (needsUpdate) then

		if (gCurrentPane.activeSearch and gCurrentPane.activeSearch.processing_state ~= KM_NULL_STATE) then
			Atr_CreateAuctionButton:Disable();
			Atr_FullScanButton:Disable();
			Auctionator1Button:Disable();
			MoneyInputFrame_SetCopper (Atr_StartingPrice,  0);
			return;
		else
			Atr_FullScanButton:Enable();
			Auctionator1Button:Enable();


			if (Atr_Batch_Stacksize.oldStackSize ~= Atr_StackSize()) then
				Atr_Batch_Stacksize.oldStackSize = Atr_StackSize();
				local itemPrice = MoneyInputFrame_GetCopper(Atr_ItemPrice);
				MoneyInputFrame_SetCopper (Atr_StackPrice,  itemPrice * Atr_StackSize());
			end

			Atr_StartingPriceDiscountText:SetText (ZT("Starting Price Discount")..":  "..AUCTIONATOR_SAVEDVARS.STARTING_DISCOUNT.."%");

			if (Atr_Batch_NumAuctions:GetNumber() < 2) then
				Atr_Batch_Stacksize_Text:SetText (ZT("stack of"));
				Atr_CreateAuctionButton:SetText (ZT("Create Auction"));
			else
				Atr_Batch_Stacksize_Text:SetText (ZT("stacks of"));
				Atr_CreateAuctionButton:SetText (string.format (ZT("Create %d Auctions"), Atr_Batch_NumAuctions:GetNumber()));
			end

			if (Atr_StackSize() > 1) then
				Atr_StackPriceText:SetText (ZT("Buyout Price").." |cff55ddffx"..Atr_StackSize().."|r");
				Atr_ItemPriceText:SetText (ZT("Per Item"));
				Atr_ItemPriceText:Show();
				Atr_ItemPrice:Show();
			else
				Atr_StackPriceText:SetText (ZT("Buyout Price"));
				Atr_ItemPriceText:Hide();
				Atr_ItemPrice:Hide();
			end

			Atr_SetTextureButton ("Atr_SellControls_Tex", Atr_StackSize(), Atr_GetItemLink(auctionItemName));


			local maxAuctions = 0;
			if (Atr_StackSize() > 0) then
				maxAuctions = math.floor (gCurrentPane.totalItems / Atr_StackSize());
			end

			-- max stack size given how many stacks you are posting, never more than
			-- the full stack size or what you actually own (16 linen as 2 stacks -> 8)
			local maxStacksize = gCurrentPane.fullStackSize or 0;
			local numStacks    = Atr_Batch_NumAuctions:GetNumber();
			if (numStacks > 0 and gCurrentPane.totalItems) then
				maxStacksize = math.min (maxStacksize, math.floor (gCurrentPane.totalItems / numStacks));
			end

			Atr_Batch_MaxAuctions_Text:SetText (ZT("max")..": "..maxAuctions);
			Atr_Batch_MaxStacksize_Text:SetText (ZT("max")..": "..maxStacksize);

			Atr_SetDepositText();
		end

		if (gJustPosted_ItemName ~= nil) then

			Atr_Recommend_Text:SetText (string.format (ZT("Auction created for %s"), gJustPosted_ItemName));
			MoneyFrame_Update ("Atr_RecommendPerStack_Price", gJustPosted_BuyoutPrice);
			Atr_SetTextureButton ("Atr_RecommendItem_Tex", gJustPosted_StackSize, gJustPosted_ItemLink);

			gCurrentPane.currIndex = gCurrentPane.activeScan:FindInSortedData (gJustPosted_StackSize, gJustPosted_BuyoutPrice);

			if (Atr_IsSelectedTab_Current()) then
				Atr_HighlightEntry (gCurrentPane.currIndex);		-- highlight the newly created auction(s)
			else
				Atr_HighlightEntry (gCurrentPane.histIndex);
			end

		elseif (gCurrentPane:IsScanNil()) then
			Atr_SetMessage (ZT("Click an item in the bags panel on the right,\nor drag an item you want to sell to this area."));
		end
	end

	-- stuff we should do every time (not just when needsUpdate is true)

	local start		= MoneyInputFrame_GetCopper(Atr_StartingPrice);
	local buyout	= MoneyInputFrame_GetCopper(Atr_StackPrice);

	local pricesOK	= (start > 0 and (start <= buyout or buyout == 0) and (auctionItemName ~= nil));

	local numToSell = Atr_Batch_NumAuctions:GetNumber() * Atr_Batch_Stacksize:GetNumber();
	zc.EnableDisable (Atr_CreateAuctionButton,	pricesOK and (numToSell <= gCurrentPane.totalItems));

end

-----------------------------------------

function Atr_SetDepositText()
	local _, auctionCount = Atr_GetSellItemInfo();
	if (auctionCount > 0) then
		local duration = UIDropDownMenu_GetSelectedValue(Atr_Duration);
		local start = MoneyInputFrame_GetCopper(Atr_StartingPrice);
		local buyout = MoneyInputFrame_GetCopper(Atr_StackPrice);
		local deposit1 = CalculateAuctionDeposit(duration, 1, start, buyout);
		local numAuctionString = "";
		if (Atr_Batch_NumAuctions:GetNumber() > 1) then
			numAuctionString = "  |cffff55ff x"..Atr_Batch_NumAuctions:GetNumber();
		end

		Atr_Deposit_Text:SetText (ZT("Deposit")..":    "..zc.priceToMoneyString(deposit1 * Atr_StackSize(), true)..numAuctionString);
	else
		Atr_Deposit_Text:SetText ("");
	end
end


-----------------------------------------

function Atr_BuildActiveAuctions ()

	gActiveAuctions = {};

	local i = 1;
	while (true) do
		local name, _, count = GetAuctionItemInfo ("owner", i);
		if (name == nil) then
			break;
		end

		if (count > 0) then		-- count is 0 for sold items
			if (gActiveAuctions[name] == nil) then
				gActiveAuctions[name] = 1;
			else
				gActiveAuctions[name] = gActiveAuctions[name] + 1;
			end
		end

		i = i + 1;
	end
end

-----------------------------------------

function Atr_GetUCIcon (itemName)

	local icon = "|TInterface\\BUTTONS\\UI-PassiveHighlight:18:18:0:0|t "

	local undercutFound = false;

	local scan = Atr_FindScan (itemName);
	if (scan and scan.absoluteBest and scan.whenScanned ~= 0 and scan.yourBestPrice and scan.yourWorstPrice) then

		local absBestPrice = scan.absoluteBest.itemPrice;

		if (scan.yourBestPrice <= absBestPrice and scan.yourWorstPrice > absBestPrice) then
			icon = "|TInterface\\AddOns\\Auctionator\\Images\\CrossAndCheck:18:18:0:0|t "
			undercutFound = true;
		elseif (scan.yourBestPrice <= absBestPrice) then
			icon = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:18:18:0:0|t "
		else
			icon = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:18:18:0:0|t "
			undercutFound = true;
		end
	end

	if (gAtr_CheckingActive_State ~= ATR_CACT_NULL and undercutFound) then
		gAtr_CheckingActive_NumUndercuts = gAtr_CheckingActive_NumUndercuts + 1;
	end

	return icon;

end

-----------------------------------------

function Atr_DisplayHlist ()

	if (Atr_IsTabSelected (BUY_TAB)) then		-- done this way because OnScrollFrame always calls Atr_DisplayHlist
		Atr_DisplaySlist();
		return;
	end

	local doFull = (UIDropDownMenu_GetSelectedValue(Atr_DropDown1) == MODE_LIST_ALL);

	Atr_BuildGlobalHistoryList (doFull);

	local numrows = #gHistoryItemList;

	local dataOffset;					-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (Atr_Hlist_ScrollFrame, numrows, ITEM_HIST_NUM_LINES, 16);

	for line = 1,ITEM_HIST_NUM_LINES do

		gCurrentPane.hlistScrollOffset = FauxScrollFrame_GetOffset (Atr_Hlist_ScrollFrame);

		dataOffset = line + gCurrentPane.hlistScrollOffset;

		local lineEntry = _G["AuctionatorHEntry"..line];

		lineEntry:SetID(dataOffset);

		if (dataOffset <= numrows and gHistoryItemList[dataOffset]) then

			local lineEntry_text = _G["AuctionatorHEntry"..line.."_EntryText"];

			local iName = gHistoryItemList[dataOffset];

			local icon = "";

			if (not doFull) then
				icon = Atr_GetUCIcon (iName);
			end

			lineEntry_text:SetText	(icon..Atr_AbbrevItemName (iName));


			if (iName == gCurrentPane.activeSearch.searchText) then
				lineEntry:SetButtonState ("PUSHED", true);
			else
				lineEntry:SetButtonState ("NORMAL", false);
			end

			lineEntry:Show();
		else
			lineEntry:Hide();
		end
	end


end

-----------------------------------------

function Atr_ClearHlist ()
	for line = 1,ITEM_HIST_NUM_LINES do
		local lineEntry = _G["AuctionatorHEntry"..line];
		lineEntry:Hide();

		local lineEntry_text = _G["AuctionatorHEntry"..line.."_EntryText"];
		lineEntry_text:SetText		("");
		lineEntry_text:SetTextColor	(.7,.7,.7);
	end

end

-----------------------------------------

function Atr_HEntryOnClick(itemName)
	local itemLink;
	if (gCurrentPane == gShopPane) then
		Atr_SEntryOnClick();
		return;
	end

	if (not itemName) then
		local line = this;

		if (gHentryTryAgain) then
			line = gHentryTryAgain;
			gHentryTryAgain = nil;
		end


		local entryIndex = line:GetID();

		itemName = gHistoryItemList[entryIndex];
	end

	if (IsAltKeyDown() and Atr_IsModeActiveAuctions()) then
		Atr_Cancel_Undercuts_OnClick (itemName)
		return;
	end

	if (AUCTIONATOR_PRICING_HISTORY[itemName]) then
		local itemId, suffixId, uniqueId = strsplit(":", AUCTIONATOR_PRICING_HISTORY[itemName]["is"])

		local itemId	= tonumber(itemId);

		if (suffixId == nil) then	suffixId = 0;
		else		 				suffixId = tonumber(suffixId);
		end

		if (uniqueId == nil) then	uniqueId = 0;
		else		 				uniqueId = tonumber(suffixId);
		end

		local itemString = "item:"..itemId..":0:0:0:0:0:"..suffixId..":"..uniqueId;

		_, itemLink = GetItemInfo(itemString);

		if (itemLink == nil) then		-- pull it into the cache and go back to the idle loop to wait for it to appear
			AtrScanningTooltip:SetHyperlink(itemString);
			gHentryTryAgain = line;
			zc.md ("pulling "..itemName.." into the local cache");
			return;
		end
	end

	gCurrentPane.UINeedsUpdate = true;

	Atr_ClearAll();

	local dbInfo = gAtr_ScanDB[itemName];
	local cacheHit = gCurrentPane:DoSearch (itemName, (dbInfo and dbInfo.id) or ("***"..itemName), nil, 20);

	Atr_Process_Historydata ();
	Atr_FindBestHistoricalAuction ();

	Atr_DisplayHlist();	 -- for the highlight

	if (cacheHit) then
		Atr_OnSearchComplete();
	end

	PlaySound ("igMainMenuOptionCheckBoxOn");
end

-----------------------------------------

function Atr_HideBidOnly_OnShow ()

	Atr_HideBidOnly_Button:SetChecked (AUCTIONATOR_HIDE_BIDONLY == 1);
end

-----------------------------------------

function Atr_MatchRarity_OnShow ()

	Atr_MatchRarity_Button:SetChecked (AUCTIONATOR_MATCH_RARITY == 1);
end

-----------------------------------------

function Atr_MatchRarity_Onclick ()

	AUCTIONATOR_MATCH_RARITY = Atr_MatchRarity_Button:GetChecked() and 1 or 0;

	PlaySound("igMainMenuOptionCheckBoxOn");

	-- rebuild the displayed list from the raw scan data with the new filter

	if (gCurrentPane and gCurrentPane.activeScan and not gCurrentPane.activeScan:IsNil()) then
		gCurrentPane.activeScan:CondenseAndSort();

		gCurrentPane.currIndex = nil;
		Atr_FindBestCurrentAuction();
		gCurrentPane.UINeedsUpdate = true;
	end
end

-----------------------------------------

function Atr_HideBidOnly_Onclick ()

	AUCTIONATOR_HIDE_BIDONLY = Atr_HideBidOnly_Button:GetChecked() and 1 or 0;

	PlaySound("igMainMenuOptionCheckBoxOn");

	-- rebuild the displayed lists from the raw scan data with the new filter

	if (gCurrentPane == nil) then
		return;
	end

	if (gCurrentPane.activeSearch and gCurrentPane.activeSearch.sortedScans) then
		local n;
		for n = 1, #gCurrentPane.activeSearch.sortedScans do
			gCurrentPane.activeSearch.sortedScans[n]:CondenseAndSort();
		end
	end

	if (gCurrentPane.activeScan and not gCurrentPane.activeScan:IsNil()) then
		gCurrentPane.activeScan:CondenseAndSort();
	end

	gCurrentPane.currIndex = nil;

	if (gCurrentPane.activeScan and not gCurrentPane.activeScan:IsNil()) then
		Atr_FindBestCurrentAuction();
	end

	gCurrentPane.UINeedsUpdate = true;
end

-----------------------------------------

function Atr_ListTabOnClick (id)

	if (gCurrentPane.activeSearch.processing_state ~= KM_NULL_STATE) then		-- if we're scanning auctions don't respond
		return;
	end

	PlaySound("igMainMenuOptionCheckBoxOn");

	Atr_SetToShowTab (id);

	Atr_ClearHistory();

end

-----------------------------------------

function Atr_ShowOldPostings ()

	Atr_ShowHistory (true);
end

-----------------------------------------

function Atr_RedisplayAuctions ()

	if (Atr_ShowingSearchSummary()) then
		Atr_ShowSearchSummary();
	elseif (Atr_IsSelectedTab_Current()) then
		Atr_ShowCurrentAuctions();
	elseif (Atr_IsSelectedTab_History()) then
		Atr_ShowHistory();
	else
		Atr_ShowOldPostings();
	end
end

-----------------------------------------

function Atr_BuildHistItemText(data)

	local stacktext = "";
--	if (data.stackSize > 1) then
--		stacktext = " (stack of "..data.stackSize..")";
--	end

	local now		= time();
	local nowtime	= date ("*t");

	local when		= data.when;
	local whentime	= date ("*t", when);

	local numauctions = data.stackSize;

	local datestr = "";

	if (data.type == "hy") then
		return ZT("average of your auctions for").." "..whentime.year;
	elseif (data.type == "hm") then
		if (nowtime.year == whentime.year) then
			return ZT("average of your auctions for").." "..date("%B", when);
		else
			return ZT("average of your auctions for").." "..date("%B %Y", when);
		end
	elseif (data.type == "hd") then
		return ZT("average of your auctions for").." "..monthDay(whentime);
	else
		return ZT("your auction on").." "..monthDay(whentime)..date(" at %I:%M %p", when);
	end
end

-----------------------------------------

function monthDay (when)

	local t = time(when);

	local s = date("%b ", t);

	return s..when.day;

end

-----------------------------------------

function Atr_ShowLineTooltip (self)

	local itemLink = self.itemLink;

	if (itemLink) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -280);
		GameTooltip:SetHyperlink (itemLink, 1);
	end
end

-----------------------------------------

function Atr_HideLineTooltip (self)
	GameTooltip:Hide();
end


-----------------------------------------

function Atr_Onclick_Back ()

	gCurrentPane.activeScan = Atr_FindScan (nil);
	gCurrentPane.UINeedsUpdate = true;

end

-----------------------------------------

function Atr_Onclick_Col1 ()

	if (gCurrentPane.activeSearch) then
		gCurrentPane.activeSearch:ClickPriceCol();
		gCurrentPane.UINeedsUpdate = true;
	end

end

-----------------------------------------

function Atr_Onclick_Col3 ()

	if (gCurrentPane.activeSearch) then
		gCurrentPane.activeSearch:ClickNameCol();
		gCurrentPane.UINeedsUpdate = true;
	end

end

-----------------------------------------

function Atr_ShowSearchSummary()

	Atr_Col1_Heading:Hide();
	Atr_Col3_Heading:Hide();
	Atr_Col1_Heading_Button:Show();
	Atr_Col3_Heading_Button:Show();
	Atr_Col4_Heading:Show();

	gCurrentPane.activeSearch:UpdateArrows ();

	local numrows = gCurrentPane.activeSearch:NumScans();

	if (gCurrentPane.activeScan.hasStack) then
		Atr_Col4_Heading:SetText (ZT("Total Price"));
	else
		Atr_Col4_Heading:SetText ("");
	end

	local highIndex  = 0;
	local line		 = 0;															-- 1 through 12 of our window to scroll
	local dataOffset = FauxScrollFrame_GetOffset (AuctionatorScrollFrame);			-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (AuctionatorScrollFrame, numrows, 12, 16);

	while (line < 12) do

		dataOffset	= dataOffset + 1;
		line		= line + 1;

		local lineEntry = _G["AuctionatorEntry"..line];

		lineEntry:SetID(dataOffset);

		local scn;

		if (gCurrentPane.activeSearch and gCurrentPane.activeSearch:NumSortedScans() > 0) then
			scn = gCurrentPane.activeSearch.sortedScans[dataOffset];
		end

		if (dataOffset > numrows or not scn) then

			lineEntry:Hide();

		else
			local data = scn.absoluteBest;

			local lineEntry_item_tag = "AuctionatorEntry"..line.."_PerItem_Price";

			local lineEntry_item		= _G[lineEntry_item_tag];
			local lineEntry_itemtext	= _G["AuctionatorEntry"..line.."_PerItem_Text"];
			local lineEntry_text		= _G["AuctionatorEntry"..line.."_EntryText"];
			local lineEntry_stack		= _G["AuctionatorEntry"..line.."_StackPrice"];

			lineEntry_itemtext:SetText	("");
			lineEntry_text:SetText	("");
			lineEntry_stack:SetText	("");

			lineEntry_text:GetParent():SetPoint ("LEFT", 157, 0);

			Atr_SetMFcolor (lineEntry_item_tag);

			lineEntry:Show();

			lineEntry.itemLink = scn.itemLink;

			local r = scn.itemTextColor[1];
			local g = scn.itemTextColor[2];
			local b = scn.itemTextColor[3];

			lineEntry_text:SetTextColor (r, g, b);
			lineEntry_stack:SetTextColor (1, 1, 1);

			local icon = Atr_GetUCIcon (scn.itemName);

			lineEntry_text:SetText (icon.."  "..scn.itemName);
			lineEntry_stack:SetText (scn:GetNumAvailable().." "..ZT("available"));

			if (data == nil or data.buyoutPrice == 0) then
				lineEntry_item:Hide();
				lineEntry_itemtext:Show();
				lineEntry_itemtext:SetText (ZT("no buyout price"));
			else
				lineEntry_item:Show();
				lineEntry_itemtext:Hide();
				MoneyFrame_Update (lineEntry_item_tag, zc.round(data.buyoutPrice/data.stackSize) );
			end

			if (zc.StringSame (scn.itemName , gCurrentPane.SS_hilite_itemName)) then
				highIndex = dataOffset;
			end


		end
	end

	Atr_HighlightEntry (highIndex);		-- need this for when called from onVerticalScroll

end

-----------------------------------------

function Atr_ShowCurrentAuctions()

	Atr_Col1_Heading:Hide();
	Atr_Col3_Heading:Hide();
	Atr_Col4_Heading:Hide();
	Atr_Col1_Heading_Button:Hide();
	Atr_Col3_Heading_Button:Hide();


	local numrows = #gCurrentPane.activeScan.sortedData;

	if (numrows > 0) then
		Atr_Col1_Heading:Show();
		Atr_Col3_Heading:Show();
		Atr_Col4_Heading:Show();
	end

	Atr_Col1_Heading:SetText (ZT("Item Price"));
	Atr_Col3_Heading:SetText (ZT("Current Auctions"));

	if (gCurrentPane.activeScan.hasStack) then
		Atr_Col4_Heading:SetText (ZT("Stack Price"));
	else
		Atr_Col4_Heading:SetText ("");
	end

	local line		 = 0;															-- 1 through 12 of our window to scroll
	local dataOffset = FauxScrollFrame_GetOffset (AuctionatorScrollFrame);			-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (AuctionatorScrollFrame, numrows, 12, 16);

	while (line < 12) do

		dataOffset	= dataOffset + 1;
		line		= line + 1;

		local lineEntry = _G["AuctionatorEntry"..line];

		lineEntry:SetID(dataOffset);

		lineEntry.itemLink = nil;

		if (dataOffset > numrows or not gCurrentPane.activeScan.sortedData[dataOffset]) then

			lineEntry:Hide();

		else
			local data = gCurrentPane.activeScan.sortedData[dataOffset];

			local lineEntry_item_tag = "AuctionatorEntry"..line.."_PerItem_Price";

			local lineEntry_item		= _G[lineEntry_item_tag];
			local lineEntry_itemtext	= _G["AuctionatorEntry"..line.."_PerItem_Text"];
			local lineEntry_text		= _G["AuctionatorEntry"..line.."_EntryText"];
			local lineEntry_stack		= _G["AuctionatorEntry"..line.."_StackPrice"];

			lineEntry_itemtext:SetText	("");
			lineEntry_text:SetText	("");
			lineEntry_stack:SetText	("");

			lineEntry_text:GetParent():SetPoint ("LEFT", 172, 0);

			Atr_SetMFcolor (lineEntry_item_tag);

			local entrytext = "";

			if (data.type == "n") then

				lineEntry:Show();

				if (data.count == 1) then
					entrytext = string.format ("%i %s %i", data.count, ZT ("stack of"), data.stackSize);
				else
					entrytext = string.format ("%i %s %i", data.count, ZT ("stacks of"), data.stackSize);
				end

				-- dim rows whose stack size doesn't match yours (sell pane only);
				-- color by rarity so same-named variants (Bloodforged rare vs epic)
				-- are distinguishable at a glance

				local dim = 0.6;
				if ( data.stackSize == Atr_StackSize() or Atr_StackSize() == 0 or gCurrentPane ~= gSellPane) then
					dim = 1.0;
				end

				local qc = data.quality and data.quality ~= 1 and ITEM_QUALITY_COLORS[data.quality];
				if (qc) then
					lineEntry_text:SetTextColor (qc.r * dim, qc.g * dim, qc.b * dim);
				else
					lineEntry_text:SetTextColor (dim, dim, dim);
				end

				if (data.yours) then
					 entrytext = entrytext.." ("..ZT("yours")..")";
				elseif (data.altname) then
					 entrytext = entrytext.." ("..data.altname..")";
				end

				-- local ccc = zc.If (data.minpage ~= data.maxpage, "|cffff8888", "");
				-- entrytext = zc.msg_str (entrytext, "     ", ccc, data.minpage, " / ", data.maxpage, "         ", gCurrentPane.activeScan.searchWasExact);

				lineEntry_text:SetText (entrytext);

				if (data.buyoutPrice == 0) then
					lineEntry_item:Hide();
					lineEntry_itemtext:Show();
					lineEntry_itemtext:SetText (ZT("no buyout price"));
				else
					lineEntry_item:Show();
					lineEntry_itemtext:Hide();
					MoneyFrame_Update (lineEntry_item_tag, zc.round(data.buyoutPrice/data.stackSize) );

					if (data.stackSize > 1) then
						lineEntry_stack:SetText (zc.priceToString(data.buyoutPrice));
						lineEntry_stack:SetTextColor (0.6, 0.6, 0.6);
					end
				end

			else
				zc.msg_red ("Unknown datatype:");
				zc.msg_red (data.type);
			end
		end
	end

	Atr_HighlightEntry (gCurrentPane.currIndex);		-- need this for when called from onVerticalScroll
end

-----------------------------------------

function Atr_Build_PostingsList ()

	-- builds the "Other" sub-tab list: price hints (vendor, disenchant, external
	-- data etc.) merged with your posting history (ported from ver 3.2.6)

	if (gCurrentPane:IsScanNil()) then
		return;
	end

	local itemName = gCurrentPane.activeScan.itemName;

	if (gCondensedThisSession[itemName] == nil) then

		gCondensedThisSession[itemName] = true;

		Atr_Condense_History(itemName);
	end

	-- build the sorted history list

	gCurrentPane.sortedHist = {};

	-- add any external information

	local hints = Atr_BuildHints (itemName);

	local n;
	for n = 1, #hints do

		local entry = {};

		entry.when			= time();
		entry.whenText		= hints[n].text;
		entry.itemPrice		= hints[n].price;
		entry.yours			= true;		-- so doesn't undercut

		table.insert (gCurrentPane.sortedHist, entry)
	end

	-- now add all the posting history

	if (AUCTIONATOR_PRICING_HISTORY[itemName]) then
		local tag, hist;
		for tag, hist in pairs (AUCTIONATOR_PRICING_HISTORY[itemName]) do
			if (tag ~= "is") then
				local when, type, price = ParseHist (tag, hist);
				local entry = {};

				entry.itemPrice		= price;
				entry.type			= type;
				entry.when			= when;
				entry.yours			= true;
				entry.whenText		= Atr_BuildHistItemText (entry);

				table.insert (gCurrentPane.sortedHist, entry)
			end
		end
	end

	table.sort (gCurrentPane.sortedHist, Atr_SortHistoryData);

	if (#gCurrentPane.sortedHist > 0) then
		return gCurrentPane.sortedHist[1].itemPrice;
	end

end

-----------------------------------------

function Atr_ShowHistory (showPosts)

	-- History sub-tab shows the scan database's daily prices;
	-- when showPosts is true (the "Other" sub-tab) shows hints + your postings

	if (gCurrentPane.sortedHist == nil) then

		if (showPosts) then
			Atr_Build_PostingsList();
		else
			Atr_BuildSortedScanHistoryList(gCurrentPane.activeScan.itemName);
		end

		Atr_FindBestHistoricalAuction ();
	end

	Atr_Col1_Heading:Hide();
	Atr_Col3_Heading:Hide();
	Atr_Col4_Heading:Hide();

	if (showPosts) then
		Atr_Col3_Heading:SetText (ZT("History"));
	else
		Atr_Col3_Heading:SetText (ZT("Date"));
	end

	local numrows = gCurrentPane.sortedHist and #gCurrentPane.sortedHist or 0;

	if (numrows > 0) then
		Atr_Col1_Heading:Show();
		Atr_Col3_Heading:Show();
	end

	local line;							-- 1 through 12 of our window to scroll
	local dataOffset;					-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (AuctionatorScrollFrame, numrows, 12, 16);

	for line = 1,12 do

		dataOffset = line + FauxScrollFrame_GetOffset (AuctionatorScrollFrame);

		local lineEntry = _G["AuctionatorEntry"..line];

		lineEntry:SetID(dataOffset);

		if (dataOffset <= numrows and gCurrentPane.sortedHist[dataOffset]) then

			local data = gCurrentPane.sortedHist[dataOffset];

			local lineEntry_item_tag = "AuctionatorEntry"..line.."_PerItem_Price";

			local lineEntry_item		= _G[lineEntry_item_tag];
			local lineEntry_itemtext	= _G["AuctionatorEntry"..line.."_PerItem_Text"];
			local lineEntry_text		= _G["AuctionatorEntry"..line.."_EntryText"];
			local lineEntry_stack		= _G["AuctionatorEntry"..line.."_StackPrice"];

			lineEntry_item:Show();
			lineEntry_itemtext:Hide();
			lineEntry_stack:SetText	("");

			Atr_SetMFcolor (lineEntry_item_tag);

			MoneyFrame_Update (lineEntry_item_tag, zc.round(data.itemPrice) );

			lineEntry_text:SetText (data.whenText or Atr_BuildHistItemText (data));
			lineEntry_text:SetTextColor (0.8, 0.8, 1.0);

			lineEntry:Show();
		else
			lineEntry:Hide();
		end
	end

	if (Atr_IsTabSelected (SELL_TAB)) then
		Atr_HighlightEntry (gCurrentPane.histIndex);		-- need this for when called from onVerticalScroll
	else
		Atr_HighlightEntry (-1);
	end
end


-----------------------------------------

function Atr_FindBestCurrentAuction()

	local scan = gCurrentPane.activeScan;

	if (Atr_IsModeCreateAuction()) then

		-- prefer the cheapest auction of the SAME rarity as the item being sold
		-- (same-named Bloodforged variants can be rare or epic); fall back to
		-- the overall cheapest when no same-rarity auction exists

		gCurrentPane.currIndex = scan:FindCheapestOfQuality (gCurrentPane.sellItemQuality) or scan:FindCheapest ();

	elseif	(Atr_IsModeBuy()) then				gCurrentPane.currIndex = scan:FindCheapest ();
	else										gCurrentPane.currIndex = scan:FindMatchByYours ();
	end

end

-----------------------------------------

function Atr_FindBestHistoricalAuction()

	gCurrentPane.histIndex = nil;

	if (gCurrentPane.sortedHist and #gCurrentPane.sortedHist > 0) then
		gCurrentPane.histIndex = 1;
	end
end

-----------------------------------------

function Atr_HighlightEntry(entryIndex)

	local line;				-- 1 through 12 of our window to scroll

	for line = 1,12 do

		local lineEntry = _G["AuctionatorEntry"..line];

		if (lineEntry:GetID() == entryIndex) then
			lineEntry:SetButtonState ("PUSHED", true);
		else
			lineEntry:SetButtonState ("NORMAL", false);
		end
	end

	local doEnableCancel = false;
	local doEnableBuy = false;
	local data;

	if (Atr_ShowingCurrentAuctions() and entryIndex ~= nil and entryIndex > 0 and entryIndex <= #gCurrentPane.activeScan.sortedData) then
		data = gCurrentPane.activeScan.sortedData[entryIndex];
		if (data.yours) then
			doEnableCancel = true;
		end

		if (not data.yours and not data.altname and data.buyoutPrice > 0) then
			doEnableBuy = true;
		end
	end

	Atr_Buy1_Button:Disable();
	Atr_CancelSelectionButton:Disable();

	if (doEnableCancel) then
		Atr_CancelSelectionButton:Enable();

		if (data.count == 1) then
			Atr_CancelSelectionButton:SetText (CANCEL_AUCTION);
		else
			Atr_CancelSelectionButton:SetText (ZT("Cancel Auctions"));
		end
	end

	if (doEnableBuy) then
		Atr_Buy1_Button:Enable();
	end

end

-----------------------------------------

function Atr_EntryOnClick()

	local entryIndex = this:GetID();

	if     (Atr_ShowingSearchSummary()) 	then
	elseif (Atr_ShowingCurrentAuctions())	then		gCurrentPane.currIndex = entryIndex;
	else												gCurrentPane.histIndex = entryIndex;		-- History and Other sub-tabs share the sortedHist list
	end

	if (Atr_ShowingSearchSummary()) then
		local scn = gCurrentPane.activeSearch.sortedScans[entryIndex];

		FauxScrollFrame_SetOffset (AuctionatorScrollFrame, 0);
		gCurrentPane.activeScan = scn;
		gCurrentPane.currIndex = scn:FindMatchByYours ();
		gCurrentPane.SS_hilite_itemName = scn.itemName;
		gCurrentPane.UINeedsUpdate = true;
	else
		Atr_HighlightEntry (entryIndex);
		Atr_UpdateRecommendation(true);
	end

	PlaySound ("igMainMenuOptionCheckBoxOn");
end

-----------------------------------------

function AuctionatorMoneyFrame_OnLoad()

	this.small = 1;
	MoneyFrame_SetType(this, "AUCTION");
end


-----------------------------------------

function Atr_GetNumItemInBags (theItemName, bloodforged)
	bloodforged = bloodforged or false
	if theItemName:sub(1, 3) == "RE:" then
		return 1
	end

	if bloodforged then
		return 1
	end

	local numItems = 0;
	local b, bagID, slotID, numslots;

	for b = 1, #kBagIDs do
		bagID = kBagIDs[b];

		numslots = GetContainerNumSlots (bagID);
		for slotID = 1,numslots do
			local itemLink = GetContainerItemLink(bagID, slotID);
			if (itemLink) then
				local itemName				= GetItemInfo(itemLink);
				local texture, itemCount	= GetContainerItemInfo(bagID, slotID);

				if (itemName and zc.StringSame (itemName, theItemName)) then
					numItems = numItems + itemCount;
				end
			end
		end
	end

	return numItems;

end

-----------------------------------------
-- FINALIZED LAG-FREE STEP-LOCK CANCEL ENGINE
-----------------------------------------

-- Global tracking state variables for the batch cancellation queue
local gAtr_Cancel_ItemName     = nil;
local gAtr_Cancel_BuyoutPrice  = 0;
local gAtr_Cancel_StackSize    = 1;
local gAtr_Cancel_NumCancelled  = 0;
local gAtr_Cancel_TotalToCancel = 0;
local gAtr_Cancel_State         = 0; -- 0: Idle, 1: Active Processing

function Atr_CancelAuction(x)
	CancelAuction(x);
end

-----------------------------------------

function Atr_LogCancelAuction(numCancelled, itemLink, stackSize)
	local SSstring = "";
	if (stackSize and stackSize > 1) then
		SSstring = "|cff00ddddx"..stackSize;
	end

	if (numCancelled > 1) then
		zc.msg_yellow(numCancelled..ZT(" auctions cancelled for ")..itemLink..SSstring);
	elseif (numCancelled == 1) then
		zc.msg_yellow(ZT("Auction cancelled for ")..itemLink..SSstring);
	end
end

-----------------------------------------

function Atr_CancelSelection_OnClick()
	if (not Atr_ShowingCurrentAuctions or not Atr_ShowingCurrentAuctions()) then
		return;
	end

	local index = gCurrentPane and gCurrentPane.currIndex;
	if (not index or not gCurrentPane.activeScan or not gCurrentPane.activeScan.sortedData) then return end;

	local data = gCurrentPane.activeScan.sortedData[index];
	if (not data or not data.yours) then return end;

	-- Initialize our custom step-lock cancellation parameters
	gAtr_Cancel_ItemName     = gCurrentPane.activeScan.itemName;
	gAtr_Cancel_BuyoutPrice  = data.buyoutPrice;
	gAtr_Cancel_StackSize    = data.stackSize;
	gAtr_Cancel_NumCancelled  = 0;
	gAtr_Cancel_State         = 1;

	-- NO MORE OWNER CALLS: Read the count directly out of Auctionator's pre-calculated 
	-- memory object block ('data.count') to prevent channel conflicts and freezing!
	gAtr_Cancel_TotalToCancel = tonumber(data.count or 1);

	if (gAtr_Cancel_TotalToCancel == 0) then 
		gAtr_Cancel_State = 0;
		return; 
	end

	-- Ensure UI Frame text elements are safely verified before rendering
	if (Atr_Buy_Confirm_ItemName and Atr_Buy_Confirm_Numstacks and Atr_Buy_Confirm_Max_Text) then
		Atr_Buy_Confirm_ItemName:SetText(gAtr_Cancel_ItemName.." x"..gAtr_Cancel_StackSize);
		Atr_Buy_Confirm_Numstacks:SetNumber(1);
		Atr_Buy_Confirm_Max_Text:SetText(ZT("max")..": "..gAtr_Cancel_TotalToCancel);
		
		if (Atr_Buy_Continue_Text) then
			Atr_Buy_Continue_Text:SetText(string.format(ZT("%d of %d cancelled so far"), gAtr_Cancel_NumCancelled, gAtr_Cancel_TotalToCancel));
		end
		
		if (Atr_Buy_Part1 and Atr_Buy_Part2) then
			Atr_Buy_Part1:Hide();
			Atr_Buy_Part2:Show();
		end
		
		if (Atr_Buy_Confirm_OKBut) then
			Atr_Buy_Confirm_OKBut:SetText(ZT("Cancel Stack"))
			Atr_Buy_Confirm_OKBut:Enable();
			
			-- Override your confirmation button's click behavior during an active cancel session
			Atr_Buy_Confirm_OKBut:SetScript("OnClick", function()
				Atr_Execute_StepLock_Cancel();
			end)
		end
		
		if (Atr_Buy_Confirm_Frame) then
			Atr_Buy_Confirm_Frame:Show();
		end
	end
end

-----------------------------------------

function Atr_Execute_StepLock_Cancel()
	-- Safety validation check
	if (gAtr_Cancel_State == 0 or gAtr_Cancel_NumCancelled >= gAtr_Cancel_TotalToCancel) then
		Atr_Cancel_Batch_Close();
		return;
	end

	-- Lock the interface button instantly to prevent double-clicks
	if (Atr_Buy_Confirm_OKBut) then
		Atr_Buy_Confirm_OKBut:Disable();
	end

	local itemLink = gCurrentPane and gCurrentPane.activeScan and gCurrentPane.activeScan.itemLink or gAtr_Cancel_ItemName;
	local foundAndCancelled = false;
	local i = 1;

	-- Note: It is completely safe to call "owner" inside this function execution block 
	-- because broad scans are paused while the confirmation box wrapper stays active!
	while (true) do
		local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _ = GetAuctionItemInfo("owner", i);
		if (name == nil) then break end;

		if (zc.StringSame(name, gAtr_Cancel_ItemName) and buyoutPrice == gAtr_Cancel_BuyoutPrice and count == gAtr_Cancel_StackSize) then
			--print(string.format("|cffffaa00[Auctionator Debug] Targeted cancellation found dynamically at Live Row [%d]. Sending packet.|r", i))
			Atr_CancelAuction(i);
			
			-- Subtract from local scan panel display map manually per single action item step
			if (AuctionatorSubtractFromScan) then
				AuctionatorSubtractFromScan(name, count, buyoutPrice);
			end
			gJustPosted_ItemName = nil;

			gAtr_Cancel_NumCancelled = gAtr_Cancel_NumCancelled + 1;
			foundAndCancelled = true;
			
			Atr_LogCancelAuction(1, itemLink, gAtr_Cancel_StackSize);
			break; 
		end
		i = i + 1;
	end

	-- Process asynchronous pacing layout structures if an item was successfully targeted
	if (foundAndCancelled) then
		if (Atr_Buy_Continue_Text) then
			Atr_Buy_Continue_Text:SetText(string.format(ZT("%d of %d cancelled so far"), gAtr_Cancel_NumCancelled, gAtr_Cancel_TotalToCancel));
		end

		-- Check if the total requested cancellation batch has finished entirely
		if (gAtr_Cancel_NumCancelled >= gAtr_Cancel_TotalToCancel) then
			C_Timer.After(0.4, function()
				Atr_Cancel_Batch_Close();
			end)
			return;
		end

		-- HARD CACHE-SHATTER POISON MUTATION PACKET
		if (CanSendAuctionQuery()) then
			QueryAuctionItems("X_WIPE_X", "", "", nil, 0, 0, 0, nil, nil);
		end

		-- Rest 0.65 seconds to let server changes log completely, then re-enable the button
		C_Timer.After(0.65, function()
			if (gAtr_Cancel_State == 1 and gAtr_Cancel_NumCancelled < gAtr_Cancel_TotalToCancel) then
				-- Safely update the owner frame list snapshot in background cache
				if (CanSendAuctionQuery()) then
					QueryAuctionItems("", "", "", nil, 0, 0, 0, nil, nil);
				end

				-- Re-enable the button interface element for the next click action step
				if (Atr_Buy_Confirm_OKBut) then
					Atr_Buy_Confirm_OKBut:Enable();
				end
			else
				Atr_Cancel_Batch_Close();
			end
		end)
	else
		-- Fallback baseline if dynamic scanning returned zero matching traces entries
		Atr_Cancel_Batch_Close();
	end
end

-----------------------------------------

function Atr_Cancel_Batch_Close()
	gAtr_Cancel_State = 0;
	gAtr_Cancel_NumCancelled = 0;
	gAtr_Cancel_TotalToCancel = 0;
	
	if (Atr_Buy_Confirm_Frame) then
		Atr_Buy_Confirm_Frame:Hide();
	end
	
	-- Restore the buy button's original default handler script mapping logic
	if (Atr_Buy_Confirm_OKBut) then
		Atr_Buy_Confirm_OKBut:SetScript("OnClick", function()
			if (Atr_Buy_Confirm_OK) then Atr_Buy_Confirm_OK() end;
		end)
	end

	-- Run a final core interface refresh command step update to clean the scan lists panel map
	if (CanSendAuctionQuery() and gAtr_Cancel_ItemName) then
		QueryAuctionItems(zc.UTF8_Truncate(gAtr_Cancel_ItemName, 63), "", "", nil, 0, 0, 0, nil, nil);
	end
end

-----------------------------------------

function Atr_StackingPrefs_Init ()

	AUCTIONATOR_STACKING_PREFS = {};
end

-----------------------------------------

function Atr_Has_StackingPrefs (key)

	local lkey = key:lower();

	return (AUCTIONATOR_STACKING_PREFS[lkey] ~= nil);
end

-----------------------------------------

function Atr_Clear_StackingPrefs (key)

	local lkey = key:lower();

	AUCTIONATOR_STACKING_PREFS[lkey] = nil;
end

-----------------------------------------

function Atr_Get_StackingPrefs (key)

	local lkey = key:lower();

	if (Atr_Has_StackingPrefs(lkey)) then
		return AUCTIONATOR_STACKING_PREFS[lkey].numstacks, AUCTIONATOR_STACKING_PREFS[lkey].stacksize;
	end

	return nil, nil;

end

-----------------------------------------

function Atr_Set_StackingPrefs_numstacks (key, numstacks)

	local lkey = key:lower();

	if (not Atr_Has_StackingPrefs(lkey)) then
		AUCTIONATOR_STACKING_PREFS[lkey] = { stacksize = 0 };
	end

	AUCTIONATOR_STACKING_PREFS[lkey].numstacks = zc.Val (numstacks, 1);
end

-----------------------------------------

function Atr_Set_StackingPrefs_stacksize (key, stacksize)

	local lkey = key:lower();

	if (not Atr_Has_StackingPrefs(lkey)) then
		AUCTIONATOR_STACKING_PREFS[lkey] = { numstacks = 0};
	end

	AUCTIONATOR_STACKING_PREFS[lkey].stacksize = zc.Val (stacksize, 1);
end

-----------------------------------------

function Atr_GetStackingPrefs_ByItem (itemLink)

	if (itemLink) then

		local itemName = GetItemInfo (itemLink);
		local text, spinfo;

		for text, spinfo in pairs (AUCTIONATOR_STACKING_PREFS) do

			if (zc.StringContains (itemName, text)) then
				return spinfo.numstacks, spinfo.stacksize;
			end
		end

		if		(Atr_IsGlyph (itemLink))								then		return Atr_Special_SP (ATR_SK_GLYPHS, 0, 1);
		elseif	(Atr_IsCutGem (itemLink))								then		return Atr_Special_SP (ATR_SK_GEMS_CUT, 0, 1);
		elseif	(Atr_IsGem (itemLink))									then		return Atr_Special_SP (ATR_SK_GEMS_UNCUT, 1, 0);
		elseif	(Atr_IsItemEnhancement (itemLink))						then		return Atr_Special_SP (ATR_SK_ITEM_ENH, 0, 1);
		elseif	(Atr_IsPotion (itemLink) or Atr_IsElixir (itemLink))	then		return Atr_Special_SP (ATR_SK_POT_ELIX, 1, 0);
		elseif	(Atr_IsFlask (itemLink))								then		return Atr_Special_SP (ATR_SK_FLASKS, 1, 0);
		elseif	(Atr_IsHerb (itemLink))									then		return Atr_Special_SP (ATR_SK_HERBS, 1, 0);
		end
	end

	return nil, nil;
end

-----------------------------------------

function Atr_Special_SP (key, numstack, stacksize)

	if (Atr_Has_StackingPrefs (key)) then
		return Atr_Get_StackingPrefs(key);
	end

	return numstack, stacksize;
end

-----------------------------------------

function Atr_GetSellStacking (itemLink, numDragged, numTotal)

	local prefNumStacks, prefStackSize = Atr_GetStackingPrefs_ByItem (itemLink);

	if (prefNumStacks == nil) then
		return 1, numDragged;
	end

	if (prefNumStacks <= 0 and prefStackSize <= 0) then		-- shouldn't happen but just in case
		prefStackSize = 1;
	end

--zc.msg (prefNumStacks, prefStackSize);

	local numStacks = prefNumStacks;
	local stackSize = prefStackSize;
	local numToSell = numDragged;

	if (numStacks == -1) then		-- max number of stacks
		numToSell = numTotal;

	elseif (stackSize == 0) then		-- auto stacksize
		stackSize = math.floor (numDragged / numStacks);

	elseif (numStacks > 0) then
		numToSell = math.min (numStacks * stackSize, numTotal);
	end

	numStacks = math.floor (numToSell / stackSize);

--zc.msg_pink (numStacks, stackSize);

	if (numStacks == 0) then
		numStacks = 1;
		stackSize = numToSell;
--zc.msg_red (numStacks, stackSize);
	end

	return numStacks, stackSize;

end



-----------------------------------------

local gInitial_NumStacks;
local gInitial_StackSize;

-----------------------------------------

function Atr_SetInitialStacking (numStacks, stackSize)

	gInitial_NumStacks = numStacks;
	gInitial_StackSize = stackSize;

	Atr_Batch_NumAuctions:SetText (numStacks);
	Atr_SetStackSize (stackSize);
end

-----------------------------------------

function Atr_Memorize_Stacking_If ()

	local newNumStacks = Atr_Batch_NumAuctions:GetNumber();
	local newStackSize = Atr_StackSize();

	local numStacksChanged = (tonumber (gInitial_NumStacks) ~= newNumStacks);
	local stackSizeChanged = (tonumber (gInitial_StackSize) ~= newStackSize);

	if (stackSizeChanged) then

		local itemName = string.lower(gCurrentPane.activeScan.itemName);

		if (itemName) then

			-- see if user is trying to set it back to default

			if (newNumStacks == 1) then
				local _, _, auctionCount = GetAuctionSellItemInfo();
				if (auctionCount == newStackSize) then
					Atr_Clear_StackingPrefs (itemName);
					return;
				end
			end

			-- else remember the new stack size

			Atr_Set_StackingPrefs_stacksize (itemName, Atr_StackSize());
		end
	end
end




-----------------------------------------

function Atr_Duration_OnLoad(self)
	UIDropDownMenu_Initialize (self, Atr_Duration_Initialize);
	UIDropDownMenu_SetSelectedValue (Atr_Duration, 1);
end

-----------------------------------------

function Atr_Duration_OnShow(self)
	UIDropDownMenu_Initialize (self, Atr_Duration_Initialize);
end

-----------------------------------------

function Atr_Duration_Initialize()

	local info = UIDropDownMenu_CreateInfo();

	info.text = AUCTION_DURATION_ONE;
	info.value = 1;
	info.checked = nil;
	info.func = Atr_Duration_OnClick;
	UIDropDownMenu_AddButton(info);

	info.text = AUCTION_DURATION_TWO;
	info.value = 2;
	info.checked = nil;
	info.func = Atr_Duration_OnClick;
	UIDropDownMenu_AddButton(info);

	info.text = AUCTION_DURATION_THREE;
	info.value = 3;
	info.checked = nil;
	info.func = Atr_Duration_OnClick;
	UIDropDownMenu_AddButton(info);

end

-----------------------------------------

function Atr_Duration_OnClick(self)

	UIDropDownMenu_SetSelectedValue(Atr_Duration, self.value);
	Atr_SetDepositText();
end

-----------------------------------------

function Atr_DropDown1_OnLoad (self)
	UIDropDownMenu_Initialize(self, Atr_DropDown1_Initialize);
	UIDropDownMenu_SetSelectedValue(Atr_DropDown1, MODE_LIST_ACTIVE);
	Atr_DropDown1:Show();
end

-----------------------------------------

function Atr_DropDown1_Initialize()
	local info = UIDropDownMenu_CreateInfo();

	info.text = ZT("Active Items");
	info.value = MODE_LIST_ACTIVE;
	info.func = Atr_DropDown1_OnClick;
	info.owner = this:GetParent();
	info.checked = nil;
	UIDropDownMenu_AddButton(info);

	info.text = ZT("All Items");
	info.value = MODE_LIST_ALL;
	info.func = Atr_DropDown1_OnClick;
	info.owner = this:GetParent();
	info.checked = nil;
	UIDropDownMenu_AddButton(info);

end

-----------------------------------------

function Atr_DropDown1_OnClick(self)

	UIDropDownMenu_SetSelectedValue(self.owner, self.value);

	local mode = self.value;

	if (mode == MODE_LIST_ALL) then
		Atr_DisplayHlist();
	end

	if (mode == MODE_LIST_ACTIVE) then
		Atr_DisplayHlist();
	end

end



-----------------------------------------

function Atr_AddMenuPick (info, text, value, func)

	info.text			= text;
	info.value			= value;
	info.func			= func;
	info.checked		= nil;
	info.owner			= this:GetParent();
	UIDropDownMenu_AddButton(info);

end

-----------------------------------------

function Atr_Dropdown_AddPick (frame, text, value, func)

	local info = UIDropDownMenu_CreateInfo();

	info.arg1			= frame;
	info.text			= text;
	info.value			= value;
	info.checked		= nil;

	if (func) then
		info.func = func;
	else
		info.func = Atr_Dropdown_OnClick;
	end

	UIDropDownMenu_AddButton(info);
end

-----------------------------------------

function Atr_Dropdown_OnClick (info, frame, arg2, checked)

	UIDropDownMenu_SetSelectedValue (frame, info.value);

end

-----------------------------------------

function Atr_IsTabSelected(whichTab)

	if (not AuctionFrame or not AuctionFrame:IsShown()) then
		return false;
	end

	if (not whichTab) then
		return (Atr_IsTabSelected(SELL_TAB) or Atr_IsTabSelected(MORE_TAB) or Atr_IsTabSelected(BUY_TAB));
	end

	return (PanelTemplates_GetSelectedTab (AuctionFrame) == Atr_FindTabIndex(whichTab));
end

-----------------------------------------

function Atr_IsAuctionatorTab (tabIndex)

	if (tabIndex == Atr_FindTabIndex(SELL_TAB) or tabIndex == Atr_FindTabIndex(MORE_TAB) or tabIndex == Atr_FindTabIndex(BUY_TAB) ) then

		return true;

	end

	return false;
end

-----------------------------------------

function Atr_Confirm_Yes()

	if (Atr_Confirm_Proc_Yes) then
		Atr_Confirm_Proc_Yes();
		Atr_Confirm_Proc_Yes = nil;
	end

	Atr_Confirm_Frame:Hide();

end


-----------------------------------------

function Atr_Confirm_No()

	Atr_Confirm_Frame:Hide();

end


-----------------------------------------

function Atr_AddHistoricalPrice (itemName, price, stacksize, itemLink, testwhen)

	if (not AUCTIONATOR_PRICING_HISTORY[itemName] ) then
		AUCTIONATOR_PRICING_HISTORY[itemName] = {};
	end

	local itemId, suffixId, uniqueId = zc.ItemIDfromLink (itemLink);

	local is = itemId;

	if (suffixId ~= 0) then
		is = is..":"..suffixId;
		if (tonumber(suffixId) < 0) then
			is = is..":"..uniqueId;
		end
	end

	AUCTIONATOR_PRICING_HISTORY[itemName]["is"]  = is;

	local hist = tostring (zc.round (price))..":"..stacksize;

	local roundtime = floor (time() / 60) * 60;		-- so multiple auctions close together don't generate too many entries

	local tag = tostring(ToTightTime(roundtime));

	if (testwhen) then
		tag = tostring(ToTightTime(testwhen));
	end

	AUCTIONATOR_PRICING_HISTORY[itemName][tag] = hist;

	gCurrentPane.sortedHist = nil;

end

-----------------------------------------

function Atr_HasHistoricalData (itemName)

	if (AUCTIONATOR_PRICING_HISTORY[itemName] ) then
		return true;
	end

	return false;
end


-----------------------------------------

function Atr_BuildGlobalHistoryList(full)

	gHistoryItemList	= {};

	local n = 1;

	if (full) then
		for name,hist in pairs (AUCTIONATOR_PRICING_HISTORY) do
			gHistoryItemList[n] = name;
			n = n + 1;
		end
	else
		if (zc.tableIsEmpty (gActiveAuctions)) then
			Atr_BuildActiveAuctions();
		end

		local name;
		for name, count in pairs (gActiveAuctions) do
			if (name and count ~= 0) then
				gHistoryItemList[n] = name;
				n = n + 1;
			end
		end
	end

	table.sort (gHistoryItemList);
end



-----------------------------------------

function Atr_FindHListIndexByName (itemName)

	local x;

	for x = 1, #gHistoryItemList do
		if (itemName == gHistoryItemList[x]) then
			return x;
		end
	end

	return 0;

end

-----------------------------------------

local gAtr_CheckingActive_Index;
local gAtr_CheckingActive_NextItemName;
local gAtr_CheckingActive_AndCancel		= false;

-----------------------------------------

function Atr_CheckActive_OnClick (andCancel)

	if (gAtr_CheckingActive_State == ATR_CACT_NULL) then

		Atr_CheckActiveList (andCancel);
--[[
		if (andCancel == nil) then
			Atr_CheckActives_Frame:Show();
		else
			Atr_CheckActives_Frame:Hide();
			Atr_CheckActiveList (andCancel);
		end
]]--
	else		-- stop checking
		Atr_CheckingActive_Finish ();
		gCurrentPane.activeSearch:Abort();
		gCurrentPane:ClearSearch();
		Atr_SetMessage(ZT("Checking stopped"));
	end

end


-----------------------------------------

function Atr_CheckActiveList (andCancel)

	gAtr_CheckingActive_State			= ATR_CACT_READY;
	gAtr_CheckingActive_NextItemName	= gHistoryItemList[1];
	gAtr_CheckingActive_AndCancel		= andCancel;
	gAtr_CheckingActive_NumUndercuts	= 0;

	Atr_SetToShowCurrent();

	Atr_CheckingActiveIdle ();

end

-----------------------------------------

function Atr_CheckingActive_Finish()

	gAtr_CheckingActive_State = ATR_CACT_NULL;		-- done

	Atr_CheckActiveButton:SetText(ZT("Check for Undercuts"));

end



-----------------------------------------

function Atr_CheckingActiveIdle()

	if (gAtr_CheckingActive_State == ATR_CACT_READY) then

		if (gAtr_CheckingActive_NextItemName == nil) then

			Atr_CheckingActive_Finish ();

			if (gAtr_CheckingActive_NumUndercuts > 0) then
				Atr_CheckActives_Frame:Show();
			end

		else
			gAtr_CheckingActive_State = ATR_CACT_PROCESSING;

			Atr_CheckActiveButton:SetText(ZT("Stop Checking"));

			local itemName = gAtr_CheckingActive_NextItemName;

			local x = Atr_FindHListIndexByName (itemName);
			gAtr_CheckingActive_NextItemName = (x > 0 and #gHistoryItemList >= x+1) and gHistoryItemList[x+1] or nil;

			local dbInfo = gAtr_ScanDB[itemName];
		local cacheHit = gCurrentPane:DoSearch (itemName, (dbInfo and dbInfo.id) or ("***"..itemName), nil, 15);

			Atr_Hilight_Hentry (itemName);

			if (cacheHit) then
				Atr_CheckingActive_OnSearchComplete();
			end
		end
	end
end


-----------------------------------------

function Atr_CheckActive_IsBusy()

	return (gAtr_CheckingActive_State ~= ATR_CACT_NULL);

end

-----------------------------------------

function Atr_CheckingActive_OnSearchComplete()

	if (gAtr_CheckingActive_State == ATR_CACT_PROCESSING) then

		if (gAtr_CheckingActive_AndCancel) then
			zc.AddDeferredCall (0.1, "Atr_CheckingActive_CheckCancel");		-- need to defer so UI can update and show auctions about to be canceled
		else
			zc.AddDeferredCall (0.1, "Atr_CheckingActive_Next");			-- need to defer so UI can update
		end
	end
end

-----------------------------------------

function Atr_CheckingActive_CheckCancel()

	if (gAtr_CheckingActive_State == ATR_CACT_PROCESSING) then

		Atr_CancelUndercuts_CurrentScan(false);

		if (gAtr_CheckingActive_State ~= ATR_CACT_WAITING_ON_CANCEL_CONFIRM) then
			zc.AddDeferredCall (0.1, "Atr_CheckingActive_Next");		-- need to defer so UI can update
		end
	end

end

-----------------------------------------

function Atr_CheckingActive_Next ()

	if (gAtr_CheckingActive_State == ATR_CACT_PROCESSING) then
		gAtr_CheckingActive_State = ATR_CACT_READY;
	end
end


-----------------------------------------

function Atr_CancelUndercut_Confirm (yesCancel)
	gAtr_CheckingActive_State = ATR_CACT_PROCESSING;
	Atr_CancelAuction_Confirm_Frame:Hide();
	if (yesCancel) then
		Atr_CancelUndercuts_CurrentScan(true);
	end
	zc.AddDeferredCall (0.1, "Atr_CheckingActive_Next");
end

-----------------------------------------

function Atr_CancelUndercuts_CurrentScan(confirmed)

	local scan = gCurrentPane.activeScan;

	for x = #scan.sortedData,1,-1 do

		local data = scan.sortedData[x];

		if (data.yours and data.itemPrice > scan.absoluteBest.itemPrice) then

			if (not confirmed) then
				gAtr_CheckingActive_State = ATR_CACT_WAITING_ON_CANCEL_CONFIRM;
				Atr_CancelAuction_Confirm_Frame_text:SetText (string.format (ZT("Your auction has been undercut:\n%s%s"), "|cffffffff", scan.itemName));
				Atr_CancelAuction_Confirm_Frame:Show ();
				return;
			end

			Atr_CancelAuction_ByIndex (x);
		end
	end

end


-----------------------------------------

function Atr_Cancel_Undercuts_OnClick (nameToCancel)

	local i;
	local num = GetNumAuctionItems ("owner");

	local cancelled = {};

	for i = num, 1, -1 do
		local name, _, stackSize, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo ("owner", i);

		if (name == nil) then
			break;
		end

		if (nameToCancel == nil or zc.StringSame (name, nameToCancel)) then
			local scan = Atr_FindScan (name);
			if (scan and scan.absoluteBest and scan.whenScanned ~= 0 and scan.yourBestPrice and scan.yourWorstPrice) then

				local absBestPrice = scan.absoluteBest.itemPrice;

				local itemPrice = math.floor (buyoutPrice / stackSize);

				--	zc.md (i, name, "itemPrice: ", itemPrice, "absBestPrice: ", absBestPrice);

				if (itemPrice > absBestPrice) then

					Atr_CancelAuction (i);

					if (cancelled[name] == nil) then
						cancelled[name]				= {};
						cancelled[name].num			= 0;
						cancelled[name].link		= scan.itemLink;
						cancelled[name].stackSize	= stackSize;
					end

					cancelled[name].num = cancelled[name].num + 1;

					if (scan.yourBestPrice > absBestPrice) then
						gActiveAuctions[name] = nil;
					end

					AuctionatorSubtractFromScan (name, stackSize, buyoutPrice);
					gJustPosted_ItemName = nil;
				end
			end
		end
	end

	local nm, cancelInfo;
	for nm, cancelInfo in pairs (cancelled) do
		Atr_LogCancelAuction (cancelInfo.num, cancelInfo.link, cancelInfo.stackSize);
	end

	Atr_DisplayHlist();
	Atr_CheckActives_Frame:Hide();
end

-----------------------------------------

function Atr_Hilight_Hentry(itemName)

	for line = 1,ITEM_HIST_NUM_LINES do

		dataOffset = line + FauxScrollFrame_GetOffset (Atr_Hlist_ScrollFrame);

		local lineEntry = _G["AuctionatorHEntry"..line];

		if (dataOffset <= #gHistoryItemList and gHistoryItemList[dataOffset]) then

			if (gHistoryItemList[dataOffset] == itemName) then
				lineEntry:SetButtonState ("PUSHED", true);
			else
				lineEntry:SetButtonState ("NORMAL", false);
			end
		end
	end
end

-----------------------------------------

function Atr_Item_Autocomplete(self)

	local text = self:GetText();
	local textlen = strlen(text);
	local name;

	-- first search shopping lists

	local numLists = #AUCTIONATOR_SHOPPING_LISTS;
	local n;

	for n = 1,numLists do
		local slist = AUCTIONATOR_SHOPPING_LISTS[n];

		local numItems = #slist.items;

		if ( numItems > 0 ) then
			for i=1, numItems do
				name = slist.items[i];
				if ( name and text and (strfind(strupper(name), strupper(text), 1, 1) == 1) ) then
					self:SetText(name);
					if ( self:IsInIMECompositionMode() ) then
						self:HighlightText(textlen - strlen(arg1), -1);
					else
						self:HighlightText(textlen, -1);
					end
					return;
				end
			end
		end
	end


	-- next search history list

	numItems = #gHistoryItemList;

	if ( numItems > 0 ) then
		for i=1, numItems do
			name = gHistoryItemList[i];
			if ( name and text and (strfind(strupper(name), strupper(text), 1, 1) == 1) ) then
				self:SetText(name);
				if ( self:IsInIMECompositionMode() ) then
					self:HighlightText(textlen - strlen(arg1), -1);
				else
					self:HighlightText(textlen, -1);
				end
				return;
			end
		end
	end
end

-----------------------------------------

function Atr_GetCurrentPane ()			-- so other modules can use gCurrentPane
	return gCurrentPane;
end

-----------------------------------------

function Atr_SetUINeedsUpdate ()			-- so other modules can easily set
	gCurrentPane.UINeedsUpdate = true;
end


-----------------------------------------

function Atr_CalcUndercutPrice (price)

	if	(price > 5000000)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._5000000);	end;
	if	(price > 1000000)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._1000000);	end;
	if	(price >  200000)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._200000);	end;
	if	(price >   50000)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._50000);	end;
	if	(price >   10000)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._10000);	end;
	if	(price >    2000)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._2000);	end;
	if	(price >     500)	then return roundPriceDown (price, AUCTIONATOR_SAVEDVARS._500);		end;
	if	(price >       0)	then return math.floor (price - 1);	end;

	return 0;
end

-----------------------------------------

function Atr_CalcStartPrice (buyoutPrice)

	local discount = 1.00 - (AUCTIONATOR_SAVEDVARS.STARTING_DISCOUNT / 100);

	local newStartPrice = Atr_CalcUndercutPrice(math.floor(buyoutPrice * discount));

	if (AUCTIONATOR_SAVEDVARS.STARTING_DISCOUNT == 0) then		-- zero means zero
		newStartPrice = buyoutPrice;
	end

	return newStartPrice;

end

-----------------------------------------

function Atr_AbbrevItemName (itemName)

	return string.gsub (itemName, "Scroll of Enchant", "SoE");

end

-----------------------------------------

function Atr_IsMyToon (name)

	if (name and (AUCTIONATOR_TOONS[name] or AUCTIONATOR_TOONS[string.lower(name)])) then
		return true;
	end

	return false;
end

-----------------------------------------

function Atr_Error_Display (errmsg)
	if (errmsg) then
		Atr_Error_Text:SetText (errmsg);
		Atr_Error_Frame:Show ();
		return;
	end
end

-----------------------------------------

function Atr_PollWho(s)

	gSendZoneMsgs = true;
	gQuietWho = time();

	SetWhoToUI(1);

	zc.md (s);

	SendWho (s);
end

-----------------------------------------

function Atr_FriendsFrame_OnEvent(self, event, ...)

	if (event == "WHO_LIST_UPDATE" and gQuietWho > 0 and time() - gQuietWho < 10) then
		return;
	end

	if (gQuietWho > 0) then
		SetWhoToUI(0);
	end

	gQuietWho = 0;

	return auctionator_orig_FriendsFrame_OnEvent (self, event, ...);

end



-----------------------------------------
-- roundPriceDown - rounds a price down to the next lowest multiple of a.
--				  - if the result is not at least a/2 lower, rounds down by a/2.
--
--	examples:  	(128790, 500)  ->  128500
--				(128700, 500)  ->  128000
--				(128400, 500)  ->  128000
-----------------------------------------

function roundPriceDown (price, a)

	if (a == 0) then
		return price;
	end

	local newprice = math.floor((price-1) / a) * a;

	if ((price - newprice) < a/2) then
		newprice = newprice - (a/2);
	end

	if (newprice == price) then
		newprice = newprice - 1;
	end

	return newprice;

end

-----------------------------------------

function ToTightHour(t)

	return floor((t - gTimeTightZero)/3600);

end

-----------------------------------------

function FromTightHour(tt)

	return (tt*3600) + gTimeTightZero;

end


-----------------------------------------

function ToTightTime(t)

	return floor((t - gTimeTightZero)/60);

end

-----------------------------------------

function FromTightTime(tt)

	return (tt*60) + gTimeTightZero;

end


--[[

- right click item in bag
- reset to 12 hours when switching tabs
- off by one when cancelling multisell
- cosmetic issue with the background
- collapsed multiple cancel messages

]]--






-----------------------------------------
--------------- bag panel ---------------
--  clickable list of auctionable bag items, shown next to the AH frame on the
--  Sell tab; clicking an item loads it into the sell slot (same path as
--  right-clicking an item in your bags)
-----------------------------------------

local ATR_BAGPANEL_COLS = 4;
local ATR_BAGPANEL_ROWS = 9;

local gBagPanelDirty = true;
local gBagPanelItems = {};

-----------------------------------------

function Atr_BagItem_LoadToSellPane (bagID, slotID)

	if (not Atr_IsTabSelected(SELL_TAB)) then
		Atr_SelectPane (SELL_TAB);
	end

	if (IsControlKeyDown()) then
		gAutoSingleton = time();
	end

	PickupContainerItem (bagID, slotID);

	local infoType = GetCursorInfo();

	if (infoType == "item") then
		Atr_ClearAll();
		Atr_ClickAuctionSellItemButton ();
		ClearCursor();
	end

end

-----------------------------------------

-- returns: auctionable (bool), ready (bool)
--   ready=false means the item isn't cached yet so its binding lines aren't in
--   the tooltip - the caller should retry rather than trust the result

local function Atr_BagItem_IsAuctionable (bagID, slotID, link)

	-- if the item isn't in the client cache yet, SetBagItem won't have the
	-- binding lines and a Soulbound item would slip through - defer instead.
	-- (calling GetItemInfo also queues the item to be cached.)

	if (GetItemInfo (link) == nil) then
		return false, false;		-- not ready
	end

	if (Atr_BagScanTooltip == nil) then
		CreateFrame ("GameTooltip", "Atr_BagScanTooltip", nil, "GameTooltipTemplate");
		Atr_BagScanTooltip:SetOwner (WorldFrame, "ANCHOR_NONE");
	end

	Atr_BagScanTooltip:ClearLines();
	Atr_BagScanTooltip:SetBagItem (bagID, slotID);

	local numLines = Atr_BagScanTooltip:NumLines() or 0;

	-- scan every line after the name (line 1); a bound item is unsellable.
	-- matching "Bound" catches Soulbound / Account Bound / Realm Bound and any
	-- other custom "* Bound" strings, while the sellable "Binds when picked up /
	-- equipped" lines say "Binds", not "Bound", so they are correctly ignored.

	local i;
	for i = 2, numLines do
		local fs  = _G["Atr_BagScanTooltipTextLeft"..i];
		local txt = fs and fs:GetText();

		if (txt) then
			if (string.find (txt, "Bound", 1, true)
				or txt == ITEM_SOULBOUND
				or txt == ITEM_BIND_QUEST
				or txt == ITEM_CONJURED) then
				return false, true;
			end
		end
	end

	return true, true;
end

-----------------------------------------

local function Atr_BagPanel_BuildList()

	gBagPanelItems = {};

	local anyNotReady = false;

	local bagID;

	for bagID = 0, NUM_BAG_SLOTS do

		local numslots = GetContainerNumSlots (bagID);
		local slotID;

		for slotID = 1, numslots do

			local texture, count = GetContainerItemInfo (bagID, slotID);
			local link = GetContainerItemLink (bagID, slotID);

			if (link) then
				local auctionable, ready = Atr_BagItem_IsAuctionable (bagID, slotID, link);

				if (auctionable) then
					table.insert (gBagPanelItems, { bag=bagID, slot=slotID, texture=texture, count=count });
				elseif (not ready) then
					anyNotReady = true;		-- rebuild again shortly once the item caches
				end
			end
		end
	end

	if (anyNotReady) then
		gBagPanelDirty = true;
	end

end

-----------------------------------------

function Atr_BagPanel_Display()

	if (Atr_BagPanel == nil or not Atr_BagPanel:IsShown()) then
		return;
	end

	if (gBagPanelDirty) then
		gBagPanelDirty = false;
		Atr_BagPanel_BuildList();
	end

	local numItems = #gBagPanelItems;
	local numRows  = math.ceil (numItems / ATR_BAGPANEL_COLS);

	FauxScrollFrame_Update (Atr_BagPanel_ScrollFrame, numRows, ATR_BAGPANEL_ROWS, 37);

	local offsetRows = FauxScrollFrame_GetOffset (Atr_BagPanel_ScrollFrame);

	local i;
	for i = 1, ATR_BAGPANEL_ROWS * ATR_BAGPANEL_COLS do

		local b  = _G["Atr_BagPanelItem"..i];
		local it = gBagPanelItems[(offsetRows * ATR_BAGPANEL_COLS) + i];

		b.atrItem = it;

		if (it) then
			SetItemButtonTexture (b, it.texture);
			SetItemButtonCount (b, it.count);
			b:Show();
		else
			b:Hide();
		end
	end

end

-----------------------------------------

function Atr_CreateBagPanel()

	if (Atr_BagPanel) then
		return;
	end

	local f = CreateFrame ("Frame", "Atr_BagPanel", AuctionFrame);

	f:SetWidth (182);
	f:SetHeight (392);
	f:SetPoint ("TOPLEFT", AuctionFrame, "TOPRIGHT", -3, -14);

	f:SetBackdrop ({	bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
						edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
						tile = true, tileSize = 16, edgeSize = 16,
						insets = { left=4, right=4, top=4, bottom=4 } });
	f:SetBackdropColor (0, 0, 0, 0.85);

	f:Hide();

	local hdr = f:CreateFontString ("Atr_BagPanel_Header", "ARTWORK", "GameFontNormalSmall");
	hdr:SetPoint ("TOP", 0, -10);
	hdr:SetText (ZT("Click an item to sell it"));

	local sf = CreateFrame ("ScrollFrame", "Atr_BagPanel_ScrollFrame", f, "FauxScrollFrameTemplate");
	sf:SetPoint ("TOPLEFT", f, "TOPLEFT", 10, -26);
	sf:SetWidth (148);
	sf:SetHeight (ATR_BAGPANEL_ROWS * 37);
	sf:SetScript ("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll (self, offset, 37, Atr_BagPanel_Display);
	end);

	local i, r, c;
	local idx = 0;
	for r = 1, ATR_BAGPANEL_ROWS do
		for c = 1, ATR_BAGPANEL_COLS do

			idx = idx + 1;

			local b = CreateFrame ("Button", "Atr_BagPanelItem"..idx, f, "ItemButtonTemplate");

			b:SetPoint ("TOPLEFT", f, "TOPLEFT", 10 + ((c-1) * 37), -26 - ((r-1) * 37));

			b:SetScript ("OnClick", function(self)
				if (self.atrItem) then
					Atr_BagItem_LoadToSellPane (self.atrItem.bag, self.atrItem.slot);
				end
			end);

			b:SetScript ("OnEnter", function(self)
				if (self.atrItem) then
					GameTooltip:SetOwner (self, "ANCHOR_RIGHT");
					GameTooltip:SetBagItem (self.atrItem.bag, self.atrItem.slot);
					GameTooltip:Show();
				end
			end);

			b:SetScript ("OnLeave", function()
				GameTooltip:Hide();
			end);

			b:Hide();
		end
	end

	f:RegisterEvent ("BAG_UPDATE");
	f:RegisterEvent ("AUCTION_MULTISELL_UPDATE");

	f:SetScript ("OnEvent", function()
		gBagPanelDirty = true;
	end);

	f:SetScript ("OnShow", function()
		gBagPanelDirty = true;
		Atr_BagPanel_Display();
	end);

	f:SetScript ("OnUpdate", function(self, elapsed)
		if (gBagPanelDirty and zc.periodic (self, "bagp_lastUpdate", 0.25, elapsed)) then
			Atr_BagPanel_Display();
		end
	end);

end


-----------------------------------------
------------- button fixups -------------
--  UI skins (ElvUI etc.) and stock-Auctionator-aware code can re-anchor or
--  strip the buttons they know by name; enforce our geometry from Lua after
--  load and again whenever an Auctionator tab is clicked. Fonts are left
--  alone on purpose so ElvUI's font replacement applies normally.
-----------------------------------------

local function Atr_FixupButton (bname, w, h, point, relName, relPoint, x, y)

	local b = _G[bname];
	if (b == nil) then
		return;
	end

	b:SetWidth (w);
	b:SetHeight (h);

	local rel = relName and _G[relName] or b:GetParent();

	b:ClearAllPoints();
	b:SetPoint (point, rel, relPoint or point, x, y);

	-- a button with no normal texture and no skin backdrop renders as bare,
	-- unclickable-looking text; rebuild the standard panel-button look for it

	if (b:GetNormalTexture() == nil and b.backdrop == nil) then
		b:SetNormalTexture ("Interface/Buttons/UI-Panel-Button-Up");
		b:GetNormalTexture():SetTexCoord (0, 0.625, 0, 0.6875);
		b:SetPushedTexture ("Interface/Buttons/UI-Panel-Button-Down");
		b:GetPushedTexture():SetTexCoord (0, 0.625, 0, 0.6875);
		b:SetDisabledTexture ("Interface/Buttons/UI-Panel-Button-Disabled");
		b:GetDisabledTexture():SetTexCoord (0, 0.625, 0, 0.6875);
		b:SetHighlightTexture ("Interface/Buttons/UI-Panel-Button-Highlight");
		b:GetHighlightTexture():SetTexCoord (0, 0.625, 0, 0.6875);
		b:GetHighlightTexture():SetBlendMode ("ADD");
	end

end

-----------------------------------------

function Atr_FixupButtons()

	Atr_FixupButton ("Auctionator1Button",		74,  18, "TOPRIGHT", "AuctionFrame", "TOPRIGHT", -20, -42);
	Atr_FixupButton ("Atr_FullScanButton",		74,  18, "TOPLEFT", "Auctionator1Button", "BOTTOMLEFT", 0, -2);
	Atr_FixupButton ("Atr_CheckActiveButton",	165, 20, "TOPLEFT", nil, "TOPLEFT", -195, -413);
	Atr_FixupButton ("Atr_AddToSListButton",	97,  20, "TOPLEFT", nil, "TOPLEFT", -195, -329);
	Atr_FixupButton ("Atr_RemFromSListButton",	101, 20, "TOPLEFT", nil, "TOPLEFT", -100, -329);
	Atr_FixupButton ("Atr_SrchSListButton",		195, 20, "TOPLEFT", nil, "TOPLEFT", -195, -349);
	Atr_FixupButton ("Atr_MngSListsButton",		195, 20, "TOPLEFT", nil, "TOPLEFT", -195, -369);
	Atr_FixupButton ("Atr_DelSListButton",		97,  20, "TOPLEFT", nil, "TOPLEFT", -195, -389);
	Atr_FixupButton ("Atr_NewSListButton",		101, 20, "TOPLEFT", nil, "TOPLEFT", -100, -389);

end

-----------------------------------------

function Atr_UIDebug()

	local names = { "Auctionator1Button", "Atr_FullScanButton", "Atr_CheckActiveButton",
					"Atr_AddToSListButton", "Atr_RemFromSListButton", "Atr_SrchSListButton",
					"Atr_MngSListsButton", "Atr_DelSListButton", "Atr_NewSListButton" };

	local i;
	for i = 1, #names do
		local b = _G[names[i]];
		if (b == nil) then
			zc.msg_atr (names[i]..": MISSING");
		else
			local point, rel, relPoint, x, y = b:GetPoint(1);
			zc.msg_atr (string.format ("%s: %dx%d shown=%s tex=%s bd=%s at %s->%s (%d,%d)",
				names[i], b:GetWidth(), b:GetHeight(),
				tostring(b:IsShown()), tostring(b:GetNormalTexture() ~= nil), tostring(b.backdrop ~= nil),
				tostring(point), tostring(relPoint), x or 0, y or 0));
		end
	end

end


-----------------------------------------
--  /atr catdump - print the auction category tree the server actually exposes
--  (class > subclass > slot), so custom categories like "Weapon crafts" can be
--  verified. If a category the user expects is missing here, the server's
--  GetAuctionItemSubClasses / GetAuctionInvTypes API does not return it.
-----------------------------------------

function Atr_CategoryDump()

	local classes = { GetAuctionItemClasses() };

	zc.msg_atr ("Auction category tree ("..#classes.." categories):");

	local c;
	for c = 1, #classes do

		zc.msg_yellow (c..". "..tostring(classes[c]));

		local subs = { GetAuctionItemSubClasses(c) };

		local s;
		for s = 1, #subs do

			local invtxt = "";

			if (GetAuctionInvTypes) then
				local raw = { GetAuctionInvTypes(c, s) };
				local parts = {};
				local i = 1;
				while (i <= #raw) do
					local nm = raw[i+1];
					nm = (nm and _G[nm]) or nm or tostring(raw[i]);
					table.insert (parts, tostring(nm));
					i = i + 2;
				end
				if (#parts > 0) then
					invtxt = "  [slots: "..table.concat(parts, ", ").."]";
				end
			end

			zc.msg ("     "..c.."/"..s.." "..tostring(subs[s])..invtxt);
		end
	end

	zc.msg_atr ("(end of category tree)");
end
