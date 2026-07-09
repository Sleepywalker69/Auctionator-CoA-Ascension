
local addonName, addonTable = ...; 
local zc = addonTable.zc;

-----------------------------------------

Atr_SList = {};
Atr_SList.__index = Atr_SList;

ATR_MAXNUM_ITEMS_ON_SHOPPING_LIST = 50;

local SLITEMS_NUM_LINES = 15;

gCurrentSList = nil;			-- global: the shopping-lists options panel needs it too
gTempShoppingList = nil;		-- unsaved list created by searching for a list someone linked/shared

-----------------------------------------

function Atr_ShoppingListsInit ()

	local num = #AUCTIONATOR_SHOPPING_LISTS;
	local x;
	
	for x = 1,num do
		setmetatable (AUCTIONATOR_SHOPPING_LISTS[x], Atr_SList);
	end
	
end

-----------------------------------------

function Atr_SList.create (name, isRecents, isTemporary)

	if (name == nil) then
		return;
	end

	local slist = {};
	setmetatable (slist,Atr_SList);

	slist.name		= name;
	slist.items		= {};

	if (isRecents) then
		slist.isRecents = 1;
	end

	if (isTemporary) then
		gTempShoppingList = slist;
		return slist;
	end

	table.insert (AUCTIONATOR_SHOPPING_LISTS, slist);

	table.sort (AUCTIONATOR_SHOPPING_LISTS, Atr_SortSlists);
	Atr_DropDownSL_Initialize ();

	return slist;
end


-----------------------------------------

function Atr_SortSlists (x, y)

	if (x.isRecents) then return true; end;
	if (y.isRecents) then return false; end;

	return (string.lower(x.name) < string.lower(y.name));

end

-----------------------------------------

function Atr_SList:AddItem (itemName)

	if (itemName == "" or itemName == nil) then
		return;
	end

	if (self.isRecents) then
		table.insert (self.items, 1, itemName);
		
		while (#self.items > 50) do		-- max 50 items on recents list
			table.remove (self.items);
		end
	else
		table.insert (self.items, itemName);
		self.isSorted = false;
	end

	
end

-----------------------------------------

function Atr_SList:RemoveItem (itemName)

	local num = #self.items;
	local n;
	
	for n = 1,num do
		if (zc.StringSame (self.items[n], itemName)) then
			table.remove (self.items, n);
			return;
		end
	end

end

-----------------------------------------

function Atr_DisplaySlist ()
	if (gCurrentSList) then
		gCurrentSList:DisplayX ();
	end
end



-----------------------------------------

function sortSlist (x, y)

	return (string.lower(x) < string.lower(y));

end

-----------------------------------------

function Atr_SList:DisplayX ()

	gCurrentSList = self;

	local currentPane = Atr_GetCurrentPane();

	if (not (self.isRecents or self.isSorted)) then
		self.isSorted = true;
		table.sort (self.items, sortSlist);
	end


	local numrows = #self.items;
	local dataOffset;					-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (Atr_Hlist_ScrollFrame, numrows, SLITEMS_NUM_LINES, 16);

	for line = 1,SLITEMS_NUM_LINES do

		currentPane.hlistScrollOffset = FauxScrollFrame_GetOffset (Atr_Hlist_ScrollFrame);
		
		dataOffset = line + currentPane.hlistScrollOffset;

		local lineEntry = _G["AuctionatorHEntry"..line];

		lineEntry:SetID(dataOffset);

		local slItem = self.items[dataOffset];
		
		if (dataOffset <= numrows and slItem) then

			local lineEntry_text = _G["AuctionatorHEntry"..line.."_EntryText"];

			lineEntry_text:SetText		(Atr_AbbrevItemName (slItem));
			lineEntry_text:SetTextColor	(.6,.6,.6);

			if (currentPane.activeSearch.origSearchText ~= "" and zc.StringSame (slItem , currentPane.activeSearch.origSearchText)) then
				lineEntry:SetButtonState ("PUSHED", true);
			elseif (currentPane.activeSearch.searchText == "" and zc.StringSame (slItem , Atr_Search_Box:GetText())) then
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

function Atr_SList:FindItemIndex (itemName)

	local num = #self.items;
	local n;
	
	for n = 1,num do
		if (zc.StringSame (itemName, self.items[n])) then
			return n;
		end
	end
	
	return 0;

end

-----------------------------------------

function Atr_SList:IsItemOnList (itemName)

	return (self:FindItemIndex(itemName) > 0);
	
end

-----------------------------------------

function Atr_Search_Onclick ()

	local currentPane = Atr_GetCurrentPane();

	local searchText = Atr_Search_Box:GetText();

	Atr_Search_Button:Disable();
	Atr_Adv_Search_Button:Disable();
	Atr_Exact_Search_Button:Disable();
	Atr_Buy1_Button:Disable();
	Atr_AddToSListButton:Disable();
	Atr_RemFromSListButton:Disable();

	Atr_ClearAll();

	currentPane:DoSearch (searchText);

	Atr_ClearHistory();
end

-----------------------------------------

function Atr_AddToRecents (searchText)

	local recentsList = AUCTIONATOR_SHOPPING_LISTS[1];

	if (recentsList and getmetatable(recentsList) == Atr_SList) then

		local isRecentsShown = (gCurrentSList == recentsList);

		local n = recentsList:FindItemIndex(searchText);

		if (n > 14 or (not isRecentsShown and n > 0)) then
			table.remove (recentsList.items, n);
		end

		n = recentsList:FindItemIndex(searchText);

		if (n == 0) then
			recentsList:AddItem (searchText);
		end

		if (isRecentsShown) then
			FauxScrollFrame_SetOffset (Atr_Hlist_ScrollFrame, 0);
			Atr_Hlist_ScrollFrame:SetVerticalScroll(0);
		end

	end

end

-----------------------------------------

function Atr_SetSearchText (searchText)

	Atr_Search_Box:SetText (searchText);
	Atr_Search_Box:ClearFocus();

end

-----------------------------------------

function Atr_Shop_OnFinishScan ()

	local currentPane = Atr_GetCurrentPane();

	local searchText = currentPane.activeSearch.origSearchText;

	Atr_SetSearchText (searchText);

	local shplist = Atr_GetShoppingListFromSearchText (searchText);

	-- don't add temp lists or advanced-category searches to recents (an advanced
	-- label is display-only and can't be meaningfully re-run by name)

	if ((shplist == nil or shplist ~= gTempShoppingList) and not currentPane.activeSearch.advFilter) then
		Atr_AddToRecents (searchText);
	end

	if (#currentPane.activeScan.sortedData > 0) then
		currentPane.currIndex = 1;
	end

	currentPane.UINeedsUpdate = true;

	Atr_Search_Button:Enable();
	Atr_Adv_Search_Button:Enable();
	Atr_Exact_Search_Button:Enable();
end


-----------------------------------------

function Atr_DropDownSL_OnLoad (self)
	UIDropDownMenu_Initialize (self, Atr_DropDownSL_Initialize);
	UIDropDownMenu_SetSelectedValue (Atr_DropDownSL, 1);
	Atr_DropDownSL:Show();
end

-----------------------------------------

function Atr_DropDownSL_Initialize()

	local info = UIDropDownMenu_CreateInfo();

	local num = #AUCTIONATOR_SHOPPING_LISTS;
	local x;
	
	for x = 1,num do
	
		local slist = AUCTIONATOR_SHOPPING_LISTS[x];
		
		info.text = slist.name;
		info.value = x;
		info.func = Atr_DropDownSL_OnClick;
		info.checked = nil;
		info.owner = this:GetParent();

		UIDropDownMenu_AddButton(info);

	end

end

-----------------------------------------

function Atr_DropDownSL_OnClick(self)
	
	UIDropDownMenu_SetSelectedValue (self.owner, self.value);
	
	gCurrentSList = AUCTIONATOR_SHOPPING_LISTS[self.value];
	
	Atr_SetUINeedsUpdate();

end

-----------------------------------------

function Atr_SEntryOnClick ()

	local line			= this;
	local entryIndex	= line:GetID();

	local itemName = gCurrentSList.items[entryIndex];
	
	Atr_Search_Box:SetText (itemName);

	if (IsAltKeyDown()) then
		Atr_GetCurrentPane():ClearSearch();
		Atr_RemFromSListOnClick();
	else
		Atr_Search_Onclick ();
	end
	
	Atr_Shop_UpdateUI();

--	gCurrentSList:DisplayX();		-- for the highlight
end



-----------------------------------------

local function FinishCreateNewSList(text)

	local slist = Atr_SList.create(text);

	local num = #AUCTIONATOR_SHOPPING_LISTS;
	local n;
	
	for n = 1,num do
		if (AUCTIONATOR_SHOPPING_LISTS[n] == slist) then
			UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, n);
			UIDropDownMenu_SetText (Atr_DropDownSL, text);	-- needed to fix bug in UIDropDownMenu
			slist:DisplayX();
			Atr_SetUINeedsUpdate();
			break;
		end
	end
	

end

-----------------------------------------

StaticPopupDialogs["ATR_NEW_SHOPPING_LIST"] = {
	text = "",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnAccept = function(self)
		local text = self.editBox:GetText();
		FinishCreateNewSList (text);
	end,
	EditBoxOnEnterPressed = function(self)
		local text = self:GetParent().editBox:GetText();
		FinishCreateNewSList (text);
		self:GetParent():Hide();
	end,
	OnShow = function(self)
		self.editBox:SetText("");
		self.editBox:SetFocus();
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1
};

-----------------------------------------

StaticPopupDialogs["ATR_DEL_SHOPPING_LIST"] = {
	text = "",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self)
		local x;
		for x = 1,#AUCTIONATOR_SHOPPING_LISTS do
			if (AUCTIONATOR_SHOPPING_LISTS[x] == gCurrentSList) then
				table.remove (AUCTIONATOR_SHOPPING_LISTS, x);
				gCurrentSList = AUCTIONATOR_SHOPPING_LISTS[1];
				UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, 1);
				UIDropDownMenu_SetText (Atr_DropDownSL, gCurrentSList.name);	-- needed to fix bug in UIDropDownMenu
				Atr_SetUINeedsUpdate();
				return;
			end
		end
	end,
	OnShow = function(self)
		local s = string.format (ZT("Really delete the shopping list %s ?"), ": \n\n"..gCurrentSList.name);
		
		self.text:SetText("\n"..s.."\n\n");
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1
};

-----------------------------------------

function Atr_NewSlist_OnClick ()

	StaticPopupDialogs["ATR_NEW_SHOPPING_LIST"].text = ZT("Name for your new shopping list");

	StaticPopup_Show("ATR_NEW_SHOPPING_LIST");
	
end

-----------------------------------------

function Atr_DelSList_OnClick ()

	StaticPopup_Show("ATR_DEL_SHOPPING_LIST");
	
end



-----------------------------------------

function Atr_AddToSListOnClick ()

	local currentPane = Atr_GetCurrentPane();

	if (gCurrentSList) then
		if (#gCurrentSList.items >= 50) then
			Atr_Error_Text:SetText (string.format (ZT("You may have no more than\n\n%d items on a shopping list."), 50));
			Atr_Error_Frame.withMask = 1;
			Atr_Error_Frame:Show ();
		else		
			gCurrentSList:AddItem (Atr_Search_Box:GetText());
			Atr_SetUINeedsUpdate();
		end
	end

end

-----------------------------------------

function Atr_RemFromSListOnClick ()

	local currentPane = Atr_GetCurrentPane();

	if (gCurrentSList) then
		gCurrentSList:RemoveItem (Atr_Search_Box:GetText());
		Atr_SetUINeedsUpdate();

	end

end


-----------------------------------------

function Atr_Shop_UpdateUI ()

	local currentPane = Atr_GetCurrentPane();

	Atr_AddToSListButton:Disable();
	Atr_RemFromSListButton:Disable();
	Atr_DelSListButton:Disable();
	Atr_SrchSListButton:Disable();
	Atr_MngSListsButton:Enable();

	if (gCurrentSList == nil) then
		Atr_ShpList_SetToRecents();
	end

	if (gCurrentSList and getmetatable (gCurrentSList) ~= Atr_SList) then
		Atr_ShpList_Validate();
	end

	if (gCurrentSList and getmetatable (gCurrentSList) == Atr_SList) then
		gCurrentSList:DisplayX ();

		local iName = Atr_Search_Box:GetText();

		if (gCurrentSList:IsItemOnList (iName)) then
			Atr_RemFromSListButton:Enable();
		elseif (iName ~= "" and iName ~= nil and gCurrentSList ~= AUCTIONATOR_SHOPPING_LISTS[1]) then		-- hack
			Atr_AddToSListButton:Enable();
		end

		if (gCurrentSList ~= AUCTIONATOR_SHOPPING_LISTS[1]) then
			Atr_DelSListButton:Enable();
			Atr_SrchSListButton:Enable();
		end

	end

	Atr_SaveThisList_Button:Hide();
	Atr_Back_Button:Hide();

	if (currentPane.activeSearch:NumScans() > 1 and not currentPane:IsScanNil()) then
		Atr_Back_Button:Show();
	elseif (gTempShoppingList) then
		local listWithSameName = Atr_SList.FindByName (gTempShoppingList.name, { skipTempList=true } );

		if (gTempShoppingList == currentPane.activeSearch.shplist and #gTempShoppingList.items > 1 and listWithSameName == nil) then
			Atr_SaveThisList_Button:Show();
		end
	end

end


-----------------------------------------

function Atr_Adv_Search_Onclick ()

	local searchText = Atr_Search_Box:GetText();

	Atr_Adv_Search_Dialog:Show();

	-- pre-fill the plain-text field only; leave the category dropdowns at their
	-- current selection (re-deriving categories from typed text by name is exactly
	-- the fragile round-trip we moved away from)

	if (not Atr_IsCompoundSearch (searchText) and not Atr_IsShoppingListSearch (searchText)) then
		Atr_AS_Searchtext:SetText (searchText);
	end

end

-----------------------------------------

function Atr_ASDD_Class_OnLoad (self)

	UIDropDownMenu_Initialize(self, Atr_ASDD_Class_Initialize);
	UIDropDownMenu_SetSelectedValue(Atr_ASDD_Class, 0);
	Atr_ASDD_Class:Show();
end

-----------------------------------------

function Atr_ASDD_Class_Initialize (self)

	local itemClasses = Atr_GetAuctionClasses();
	local n;

	Atr_Dropdown_AddPick (self, ZT("(any)"), 0, Atr_ASDD_Class_OnClick);

	if (#itemClasses > 0) then
		local text;
		for n, text in pairs(itemClasses) do
			Atr_Dropdown_AddPick (self, text, n, Atr_ASDD_Class_OnClick);
		end
	end

end

-----------------------------------------

function Atr_ASDD_Class_OnClick (info, frame, arg2, checked)

	UIDropDownMenu_SetSelectedValue(frame, info.value);

	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Subclass, 0);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Invtype, 0);

	Atr_ASDD_UpdateSubclassMenu();
	Atr_ASDD_UpdateInvtypeMenu();

end

-----------------------------------------

function Atr_ASDD_UpdateSubclassMenu ()

	Atr_ASDD_Subclass:Hide();
	Atr_ASDD_Subclass_Initialize (Atr_ASDD_Subclass);
	Atr_ASDD_Subclass:Show();

end

-----------------------------------------


function Atr_ASDD_Subclass_OnLoad (self)

	UIDropDownMenu_Initialize (self, Atr_ASDD_Subclass_Initialize);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Subclass, 0);
	Atr_ASDD_Subclass:Show();

end


-----------------------------------------

function Atr_ASDD_Subclass_Initialize (self)

	local itemClass = UIDropDownMenu_GetSelectedValue (Atr_ASDD_Class);

	Atr_Dropdown_AddPick (Atr_ASDD_Subclass, ZT("(any)"), 0, Atr_ASDD_Subclass_OnClick);

	if (itemClass and itemClass > 0) then

		local itemSubclasses = Atr_GetAuctionSubclasses(itemClass);
		local n;

		if (#itemSubclasses > 0) then
			local text;
			for n, text in pairs(itemSubclasses) do

				Atr_Dropdown_AddPick (Atr_ASDD_Subclass, text, n, Atr_ASDD_Subclass_OnClick);
			end
		end
	end

end

-----------------------------------------

function Atr_ASDD_Subclass_OnClick (info, frame, arg2, checked)

	UIDropDownMenu_SetSelectedValue (frame, info.value);

	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Invtype, 0);

	Atr_ASDD_UpdateInvtypeMenu();

end

-----------------------------------------
--  sub-sub-category (equipment slot); the list comes straight from the server
--  via GetAuctionInvTypes, so whatever slots this core exposes show up here
-----------------------------------------

function Atr_GetAuctionInvtypeList (itemClass, itemSubclass)

	local out = {};

	if (GetAuctionInvTypes == nil or itemClass == nil or itemClass <= 0 or itemSubclass == nil or itemSubclass <= 0) then
		return out;
	end

	-- 3.3.5 returns alternating pairs: token1, displayFlag1, token2, displayFlag2, ...
	-- where the token is a global-string name ("INVTYPE_HEAD" -> "Head").
	-- Iterate with select(): flags can be nil, which would punch holes in a
	-- table capture and scramble the pairs.
	-- The query's invTypeIndex is the pair ordinal (1 for the first slot, etc.),
	-- counted across ALL pairs including hidden ones, matching Blizzard's browse UI.

	local numRets = select ('#', GetAuctionInvTypes (itemClass, itemSubclass));

	local i;
	for i = 1, numRets, 2 do

		local token, canDisplay = select (i, GetAuctionInvTypes (itemClass, itemSubclass));

		if (token and canDisplay) then

			local displayName = _G[token] or token;

			table.insert (out, { value = math.ceil(i/2), name = displayName });
		end
	end

	return out;
end

-----------------------------------------

function Atr_SkinDropdown (frame)

	-- ElvUI skins the ORIGINAL Auctionator dropdowns by name; our new frames are
	-- unknown to it, so hand them to its skinner explicitly (no-op without ElvUI)

	if (frame == nil or frame.atrSkinned or ElvUI == nil) then
		return;
	end

	frame.atrSkinned = true;

	local ok, E = pcall (function() return (unpack(ElvUI)); end);

	if (ok and E and E.GetModule) then
		local ok2, S = pcall (function() return E:GetModule ("Skins", true); end);

		if (ok2 and S and S.HandleDropDownBox) then
			pcall (function() S:HandleDropDownBox (frame); end);
		end
	end

end

-----------------------------------------

function Atr_ASDD_Invtype_OnLoad (self)

	UIDropDownMenu_Initialize (self, Atr_ASDD_Invtype_Initialize);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Invtype, 0);
	Atr_SkinDropdown (Atr_ASDD_Invtype);
	Atr_ASDD_Invtype:Show();

end

-----------------------------------------

function Atr_ASDD_UpdateInvtypeMenu ()

	Atr_ASDD_Invtype:Hide();
	Atr_ASDD_Invtype_Initialize (Atr_ASDD_Invtype);
	Atr_ASDD_Invtype:Show();

end

-----------------------------------------

function Atr_ASDD_Invtype_Initialize (self)

	local itemClass    = UIDropDownMenu_GetSelectedValue (Atr_ASDD_Class);
	local itemSubclass = UIDropDownMenu_GetSelectedValue (Atr_ASDD_Subclass);

	Atr_Dropdown_AddPick (Atr_ASDD_Invtype, ZT("(any)"), 0, Atr_Dropdown_OnClick);

	local invlist = Atr_GetAuctionInvtypeList (itemClass, itemSubclass);

	local n;
	for n = 1, #invlist do
		Atr_Dropdown_AddPick (Atr_ASDD_Invtype, invlist[n].name, invlist[n].value, Atr_Dropdown_OnClick);
	end

end

-----------------------------------------
--  rarity / quality filter (0 = Poor .. 7 = Heirloom); -1 = any
-----------------------------------------

function Atr_ASDD_Quality_OnLoad (self)

	UIDropDownMenu_Initialize (self, Atr_ASDD_Quality_Initialize);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Quality, -1);
	Atr_SkinDropdown (Atr_ASDD_Quality);
	Atr_ASDD_Quality:Show();

end

-----------------------------------------

function Atr_ASDD_Quality_Initialize (self)

	Atr_Dropdown_AddPick (Atr_ASDD_Quality, ZT("(any)"), -1, Atr_Dropdown_OnClick);

	local q;
	for q = 0, 7 do
		local name = _G["ITEM_QUALITY"..q.."_DESC"];
		if (name) then
			local c = ITEM_QUALITY_COLORS[q];
			if (c and c.hex) then
				name = c.hex..name.."|r";
			end
			Atr_Dropdown_AddPick (Atr_ASDD_Quality, name, q, Atr_Dropdown_OnClick);
		end
	end

end

-----------------------------------------

function Atr_Adv_Search_Reset()

	Atr_AS_Searchtext:SetText ("");

	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Class, 0);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Subclass, 0);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Invtype, 0);
	UIDropDownMenu_SetSelectedValue (Atr_ASDD_Quality, -1);

	Atr_ASDD_UpdateSubclassMenu();
	Atr_ASDD_UpdateInvtypeMenu();

	Atr_AS_Minlevel:SetText ("");
	Atr_AS_Maxlevel:SetText ("");
end

-----------------------------------------

function Atr_Adv_Search_Do()

	local itemClass		= UIDropDownMenu_GetSelectedValue (Atr_ASDD_Class)    or 0;
	local itemSubclass	= UIDropDownMenu_GetSelectedValue (Atr_ASDD_Subclass) or 0;
	local invType		= UIDropDownMenu_GetSelectedValue (Atr_ASDD_Invtype)  or 0;
	local quality		= UIDropDownMenu_GetSelectedValue (Atr_ASDD_Quality);
	if (quality == nil) then quality = -1; end

	local minLevel		= Atr_AS_Minlevel:GetNumber ();
	local maxLevel		= Atr_AS_Maxlevel:GetNumber ();
	local text			= Atr_AS_Searchtext:GetText();

	if (maxLevel > 0 and minLevel == 0) then
		minLevel = 1;
	end

	-- structured filter (numeric indices) drives the query directly - no text re-parse

	gAtr_PendingAdvFilter =
	{
		class		= itemClass,
		subclass	= itemSubclass,
		invtype		= invType,
		quality		= quality,
		minLevel	= minLevel,
		maxLevel	= maxLevel,
		text		= text,
	};

	-- build a readable label for the search box / recents (display only)

	local itemClassList = Atr_GetAuctionClasses();

	local parts = {};

	if (itemClass > 0 and itemClassList[itemClass]) then
		table.insert (parts, itemClassList[itemClass]);

		if (itemSubclass > 0) then
			local subList = Atr_GetAuctionSubclasses (itemClass);
			if (subList[itemSubclass]) then
				table.insert (parts, subList[itemSubclass]);
			end

			if (invType > 0) then
				local invList = Atr_GetAuctionInvtypeList (itemClass, itemSubclass);
				local k;
				for k = 1, #invList do
					if (invList[k].value == invType) then
						table.insert (parts, invList[k].name);
						break;
					end
				end
			end
		end
	end

	if (quality and quality >= 0) then
		local qn = _G["ITEM_QUALITY"..quality.."_DESC"];
		if (qn) then table.insert (parts, qn); end
	end

	if (minLevel > 0 or maxLevel > 0) then
		table.insert (parts, "lvl "..(minLevel > 0 and minLevel or "1").."-"..(maxLevel > 0 and maxLevel or ""));
	end

	if (text ~= "") then
		table.insert (parts, "\""..text.."\"");
	end

	-- separator must NOT contain "/" or ">" or it would be re-parsed as a
	-- compound search if the label is ever typed/clicked from recents

	local label = table.concat (parts, " - ");
	if (label == "") then
		label = ZT("(all auctions)");
	end

	Atr_Search_Box:SetText (label);

	-- do the search directly with the structured filter still pending

	local currentPane = Atr_GetCurrentPane();

	Atr_Search_Button:Disable();
	Atr_Adv_Search_Button:Disable();
	Atr_Exact_Search_Button:Disable();
	Atr_Buy1_Button:Disable();
	Atr_AddToSListButton:Disable();
	Atr_RemFromSListButton:Disable();

	Atr_ClearAll();

	currentPane:DoSearch (label);

	Atr_ClearHistory();

	Atr_Adv_Search_Dialog:Hide();

end




-----------------------------------------
--  ported from ver 3.2.6: exact-match checkbox, shopping-list search,
--  temp lists and the Manage Shopping Lists panel hooks
-----------------------------------------

function Atr_SList.FindByName (name, options)

	local checkTempList = (options == nil or not options.skipTempList)

	if (checkTempList and gTempShoppingList and zc.StringSame (gTempShoppingList.name, name)) then
		return gTempShoppingList;
	end

	local num = #AUCTIONATOR_SHOPPING_LISTS;
	local x;

	for x = 1,num do
		if (zc.StringSame (AUCTIONATOR_SHOPPING_LISTS[x].name, name)) then
			return AUCTIONATOR_SHOPPING_LISTS[x];
		end
	end
end

-----------------------------------------

function Atr_SList:Clear ()

	self.items = {};

end

-----------------------------------------

function Atr_SList:GetNumItems ()

	return #self.items;
end

-----------------------------------------

function Atr_SList:GetNthItemName (n)

	if (n <= #self.items) then
		return self.items[n];
	end

	return nil;
end

-----------------------------------------

local function IsExactChecked ()
	return Atr_Exact_Search_Button:GetChecked();
end

-----------------------------------------

function Atr_Exact_Search_Onclick ()

	local searchText		= Atr_Search_Box:GetText();
	local isQuoted			= zc.IsTextQuoted (searchText);
	local isExactChecked	= IsExactChecked();

	if (isExactChecked and not isQuoted) then
		Atr_Search_Box:SetText ("\""..searchText.."\"");
	end

	if ((not isExactChecked) and isQuoted) then
		Atr_Search_Box:SetText (zc.TrimQuotes (searchText));
	end

end

-----------------------------------------

function Atr_SetExactChecked (b)

	return Atr_Exact_Search_Button:SetChecked(b);
end

-----------------------------------------

function Atr_Shop_Idle ()

	local searchText	= Atr_Search_Box:GetText();
	local isQuoted		= zc.IsTextQuoted (searchText);

	Atr_SetExactChecked (isQuoted);
end

-----------------------------------------

function Atr_MngSLists_OnClick ()

	InterfaceOptionsFrame_OpenToCategory (ZT("Shopping Lists"));

	local slist;

	local currentPane = Atr_GetCurrentPane();

	if (gCurrentSList) then
		if (not gCurrentSList.isRecents) then
			slist = gCurrentSList;
		elseif (currentPane and currentPane.activeSearch) then
			local searchText = strtrim (currentPane.activeSearch.searchText, "{}");
			slist = Atr_SList.FindByName (strtrim (searchText));
		end
	end

	if (slist and Atr_ShpListsEntry_Select) then
		local n;
		for n=2,#AUCTIONATOR_SHOPPING_LISTS do
			if (AUCTIONATOR_SHOPPING_LISTS[n] == slist) then
				Atr_ShpListsEntry_Select(n);
				Atr_ShpListsEntry_ScrollToShow(n);
				return;
			end
		end
	end
end

-----------------------------------------

function Atr_SrchSList_OnClick ()

	if (gCurrentSList) then
		local searchText = "{ "..gCurrentSList.name.." }";

		Atr_SetSearchText (searchText);
		Atr_Search_Onclick();
	end
end

-----------------------------------------

function Atr_ShpList_Validate ()

	if (gCurrentSList and getmetatable (gCurrentSList) ~= Atr_SList) then
		zc.msg_badErr ("gCurrentSList bad metatable; type gCurrentSList: ", type (gCurrentSList));
	end

	local x, slist;
	for x = 1,#AUCTIONATOR_SHOPPING_LISTS do

		slist = AUCTIONATOR_SHOPPING_LISTS[x];

		if (slist == nil) then
			zc.md ("slist["..x.."] is nil");
		elseif (getmetatable (slist) ~= Atr_SList) then
			zc.msg_badErr ("slist["..x.."] bad metatable; type: ", type (slist));
		end

	end
end

-----------------------------------------

function Atr_ShpList_SetToRecents()

	gCurrentSList = AUCTIONATOR_SHOPPING_LISTS[1];

	UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, 1);
	if (gCurrentSList) then
		UIDropDownMenu_SetText (Atr_DropDownSL, gCurrentSList.name);	-- needed to fix bug in UIDropDownMenu
	end

end

-----------------------------------------

function Atr_Onclick_SaveTempList()

	if (gTempShoppingList) then
		table.insert (AUCTIONATOR_SHOPPING_LISTS, gTempShoppingList);
		table.sort (AUCTIONATOR_SHOPPING_LISTS, Atr_SortSlists);
		Atr_ShpList_SetToRecents();
		Atr_AddToRecents("{ "..gTempShoppingList.name.." }");		-- nice visual confirmation
		gTempShoppingList = nil;
		Atr_SetUINeedsUpdate();
	end
end

-----------------------------------------

function Atr_RenameSList(index, newname)

	if (newname == nil or newname == "") then
		return;
	end

	AUCTIONATOR_SHOPPING_LISTS[index].name = newname;

	-- in case it's the currently selected one

	local curIndex = UIDropDownMenu_GetSelectedValue(Atr_DropDownSL);
	if (curIndex and curIndex > 0 and AUCTIONATOR_SHOPPING_LISTS[curIndex]) then
		UIDropDownMenu_SetText (Atr_DropDownSL, AUCTIONATOR_SHOPPING_LISTS[curIndex].name);	-- needed to fix bug in UIDropDownMenu
	end

end
