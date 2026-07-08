
local addonName, addonTable = ...;
local zc = addonTable.zc;

KM_NULL_STATE	= 0;
KM_PREQUERY		= 1;
KM_INQUERY		= 2;
KM_POSTQUERY	= 3;
KM_ANALYZING	= 4;
KM_SETTINGSORT	= 5;

local AUCTION_CLASS_WEAPON = 1;
local AUCTION_CLASS_ARMOR  = 2;

local gAllScans = {};

local BIGNUM = 999999999999;

local ATR_SORTBY_NAME_ASC = 0;
local ATR_SORTBY_NAME_DES = 1;
local ATR_SORTBY_PRICE_ASC = 2;
local ATR_SORTBY_PRICE_DES = 3;

-----------------------------------------

AtrScan = {};
AtrScan.__index = AtrScan;

-----------------------------------------

AtrSearch = {};
AtrSearch.__index = AtrSearch;

-----------------------------------------

function Atr_GetExactMatchText (searchText)

	local emtext = nil;

	if (zc.IsTextQuoted (searchText)) then
		emtext = string.sub (searchText, 2, searchText:len()-1);
	end

	return emtext;
end

-----------------------------------------

function Atr_IsShoppingListSearch (searchString)

	if (searchString == nil) then
		return false;
	end

	return zc.StringStartsWith (searchString, "{ ") and zc.StringEndsWith (searchString, " }");
end

-----------------------------------------

function Atr_GetShoppingListFromSearchText (searchString)

	if (Atr_IsShoppingListSearch (searchString)) then
		local len = string.len(searchString);

		local shoppingListName = string.sub (searchString, 3, len-2);

		return Atr_SList.FindByName (shoppingListName);
	end

	return nil;
end

-----------------------------------------

function Atr_GetShoppingListItem (search)

	if (search.shplist) then
		return search.shplist:GetNthItemName (search.shopListIndex);
	end

	return nil;
end

-----------------------------------------

-- searches for specific items should supply the IDstring and, if possible, the itemLink.
-- NOTE: unlike ver 3.2.6, scans stay keyed by item NAME (Bloodforged/suffix matching and
-- the Buy engine depend on name keys); the IDstring only flags exactness and seeds the link.

function Atr_NewSearch (itemName, IDstring, itemLink, rescanThreshold)

	local srch = {};
	setmetatable (srch, AtrSearch);
	srch:Init (itemName, IDstring, itemLink, rescanThreshold);

	return srch;
end

-----------------------------------------

function AtrSearch:Init (searchText, IDstring, itemLink, rescanThreshold)

	if (searchText == nil) then
		searchText = "";
	end

	self.origSearchText = searchText;

	self.exactMatchText	= nil;
	self.searchText		= searchText;

	if (IDstring == nil) then
		self.exactMatchText = Atr_GetExactMatchText (searchText);
		if (self.exactMatchText) then
			self.searchText = self.exactMatchText;
		end
	end

	self.IDstring			= IDstring;
	self.itemLink			= itemLink;
	self.exact				= (IDstring ~= nil or self.exactMatchText ~= nil);
	self.processing_state	= KM_NULL_STATE
	self.current_page		= -1
	self.items				= {};
	self.query				= Atr_NewQuery();
	self.sortedScans		= nil;
	self.sortHow			= ATR_SORTBY_PRICE_ASC;
	self.shopListIndex		= 1;
	self.shplist			= Atr_GetShoppingListFromSearchText (self.searchText);

	-- bad-data retry state (TSM pattern)

	self.retries			= 0;
	self.timeDelay			= 0;
	self.softRetryAt		= nil;

	if (self.exact) then

		local key = self.searchText;

		if (rescanThreshold and rescanThreshold > 0) then
			local scan = Atr_FindScan (key);
			if (scan and (time() - scan.whenScanned) <= rescanThreshold) then
				self.items[key] = scan;
			end
		end

		if (not self.items[key]) then
			self.items[key] = Atr_FindScanAndInit (key);
		end

		if (itemLink and self.items[key]) then
			self.items[key]:UpdateItemLink (itemLink);
		end

	end

end

-----------------------------------------

function Atr_FindScanAndInit (itemName)

	return Atr_FindScan (itemName, true);
end

-----------------------------------------

function Atr_FindScan (itemName, init)

	if (itemName == nil or itemName == "") then
		itemName = "nil";
	end

	local itemNameLC = string.lower (itemName);

	if (gAllScans[itemNameLC] == nil) then

		local scn = {};
		setmetatable (scn, AtrScan);
		scn:Init (itemName);

		gAllScans[itemNameLC] = scn;
	elseif (init) then
		gAllScans[itemNameLC]:Init (itemName);
	end

	return gAllScans[itemNameLC];
end

-----------------------------------------

function Atr_ClearScanCache ()

--	zc.msg_red ("Clearing Scan Cache");

	for a,v in pairs (gAllScans) do
		if (a ~= "nil") then
			gAllScans[a] = nil;
		end
	end

end

-----------------------------------------

function AtrScan:Init (itemName)
	self.itemName			= itemName;
	self.itemLink			= nil;
	self.scanData			= {};
	self.sortedData			= {};
	self.whenScanned		= 0;
	self.lowprices			= {BIGNUM, BIGNUM, BIGNUM};
	self.absoluteBest		= nil;
	self.itemClass			= 0;
	self.itemSubclass		= 0;
	self.yourBestPrice		= nil;
	self.yourWorstPrice		= nil;
	self.numYourSingletons	= 0;
	self.itemTextColor 		= { 1.0, 1.0, 1.0 };
	self.searchWasExact		= false;

	self:UpdateItemLink (Atr_GetItemLink (itemName));
end

-----------------------------------------

function AtrScan:UpdateItemLink (itemLink)

	self.itemLink = itemLink;

	if (itemLink) then

		Atr_AddToItemLinkCache (self.itemName, itemLink);

		local _, _, quality, _, _, sType, sSubType = GetItemInfo(itemLink);
		self.itemQuality	= quality;
		self.itemClass		= Atr_ItemType2AuctionClass (sType);
		self.itemSubclass	= Atr_SubType2AuctionSubclass (self.itemClass, sSubType);
		self.itemTextColor = ITEM_QUALITY_COLORS[quality]
	end

end


-----------------------------------------

function AtrSearch:NumScans()

	if (self.sortedScans) then
		return #self.sortedScans;
	end

	local count = 0;
	for name,scn in pairs (self.items) do
		count = count + 1;
	end

	return count;
end

-----------------------------------------

function AtrSearch:NumSortedScans()

	if (self.sortedScans) then
		return #self.sortedScans;
	end

	return 0;
end

-----------------------------------------

function AtrSearch:GetFirstScan()

	if (self.sortedScans) then
		return self.sortedScans[1];
	end

	for name,scn in pairs (self.items) do
		return scn;
	end

	return nil;

end


-----------------------------------------

function AtrSearch:Start ()

	if (self.searchText == "") then
		return;
	end

	if (Atr_IsCompoundSearch (self.searchText)) then

		local _, itemClass = Atr_ParseCompoundSearch (self.searchText);

		if (itemClass == 0) then
			Atr_Error_Display (ZT("The first part of this compound\n\nsearch is not a valid category."));
			return;
		end

		self.sortHow = ATR_SORTBY_PRICE_DES;

	end

	self.processing_state = KM_SETTINGSORT;

	SortAuctionClearSort ("list");

	BrowseName:SetText (self.searchText);		-- not necessary but nice when user switches to Browse tab

	self.current_page		= 0;
	self.processing_state	= KM_PREQUERY;

	self:Continue();

end

-----------------------------------------

function AtrSearch:Abort ()

	if (self.processing_state == KM_NULL_STATE) then
		return;
	end

	self.processing_state = KM_NULL_STATE;
	self:Init();
end

-----------------------------------------

function AtrSearch:CapturePageInfo ()

	self.query:CapturePageInfo(self.current_page)
end

-----------------------------------------

function AtrSearch:CheckForDuplicatePage ()

	local isDup = self.query:CheckForDuplicatePage(self.current_page);

	if (isDup) then
--		zc.msg_red ("DUPLICATE PAGE FOUND: ", "  current_page: ", self.current_page, "  numDupPages: ", self.query.numDupPages);

		self.current_page	= self.current_page - 1;   -- requery the page

		self.processing_state = KM_PREQUERY;
	end

	return isDup;
end

-----------------------------------------
--  bad-data detection with soft/hard retries (pattern borrowed from TSM's scan engine)
-----------------------------------------

local ATR_SCAN_BASE_DELAY	= 0.1;	-- soft retry: re-read the same page after this long; no re-query needed
local ATR_SCAN_RETRY_DELAY	= 2;	-- after this much soft-retrying, escalate to a hard retry (re-send the query)
local ATR_SCAN_MAX_RETRIES	= 4;	-- max hard retries before accepting the page as-is

-----------------------------------------

function AtrSearch:PageDataIsBad ()

	-- detects rows the server hasn't fully streamed to the client yet:
	-- nil names, or auctions with a buyout whose owner hasn't arrived yet
	-- (on 3.3.5 owner names often arrive a frame or two after AUCTION_ITEM_LIST_UPDATE)

	local q = self.query;

	if (q.curPageInfo == nil) then
		return false;
	end

	local x;

	for x = 1, q.curPageInfo.numOnPage do

		local ax = q.curPageInfo.auctionInfo[x];

		if (ax.name == nil) then
			return true;
		end

		if (ax.owner == nil and ax.buyoutPrice ~= nil and ax.buyoutPrice > 0) then
			return true;
		end
	end

	return false;
end

-----------------------------------------

function AtrSearch:OnListUpdate ()		-- called from Atr_OnAuctionUpdate when AUCTION_ITEM_LIST_UPDATE fires

	if (self.processing_state ~= KM_POSTQUERY) then
		return;
	end

	self:CapturePageInfo();
	self:ProcessCurrentPage();
end

-----------------------------------------

function AtrSearch:ProcessCurrentPage ()

	if (self.processing_state ~= KM_POSTQUERY) then		-- aborted while a soft retry was pending
		return;
	end

	if (self:PageDataIsBad() and self.retries < ATR_SCAN_MAX_RETRIES) then

		if (self.timeDelay >= ATR_SCAN_RETRY_DELAY) then

			-- hard retry: re-send the query for this page

			zc.md ("scan page incomplete after soft retries; re-sending page", self.current_page - 1);

			self.retries			= self.retries + 1;
			self.timeDelay			= 0;
			self.softRetryAt		= nil;
			self.current_page		= self.current_page - 1;
			self.processing_state	= KM_PREQUERY;
			self:Continue();
		else

			-- soft retry: re-read the same page shortly; the client usually
			-- back-fills owner names without needing another query

			self.timeDelay			= self.timeDelay + ATR_SCAN_BASE_DELAY;
			self.softRetryAt		= (Atr_ptime or 0) + ATR_SCAN_BASE_DELAY;
		end

		return;
	end

	self.retries		= 0;
	self.timeDelay		= 0;
	self.softRetryAt	= nil;

	if (self:CheckForDuplicatePage()) then		-- resets state to KM_PREQUERY so the page is requeried
		return;
	end

	local done = self:AnalyzeResultsPage();

	if (done) then
		self:Finish();
		Atr_OnSearchComplete ();
	end
end

-----------------------------------------

function AtrSearch:CheckSoftRetry ()	-- called every frame from Atr_OnUpdate while a soft retry is pending

	if (self.softRetryAt and Atr_ptime and Atr_ptime >= self.softRetryAt) then
		self.softRetryAt = nil;
		self:CapturePageInfo();			-- re-read the same page; no re-query needed
		self:ProcessCurrentPage();
	end
end

-----------------------------------------

function AtrSearch:CheckTimeout ()		-- called from Atr_Idle; detects a dropped AUCTION_ITEM_LIST_UPDATE

	if (self.processing_state == KM_POSTQUERY and self.query_sent_when and Atr_ptime and Atr_ptime - self.query_sent_when > 10) then

		if (self.retries < ATR_SCAN_MAX_RETRIES) then

			zc.md ("query timed out; re-sending page", self.current_page - 1);

			self.retries			= self.retries + 1;
			self.timeDelay			= 0;
			self.softRetryAt		= nil;
			self.current_page		= self.current_page - 1;
			self.processing_state	= KM_PREQUERY;
		else
			zc.msg_atr (ZT("Scan failed - the server did not respond"));
			self:Abort();
			Atr_SetMessage ("");
		end
	end
end




-----------------------------------------

function AtrSearch:AnalyzeResultsPage()

	self.processing_state = KM_ANALYZING;

	if (self.query.numDupPages > 10) then 	 -- hopefully this will never happen but need check to avoid looping
		return true;						 -- done
	end

	local q = self.query;

	if (self.current_page == 1 and q.totalAuctions > 5000) then -- give Blizz servers a break
		Atr_Error_Display (ZT("Too many results\n\nPlease narrow your search"));
		return true;  -- done
	end

	local msg;

	local slistItemName = Atr_GetShoppingListItem (self);
	if (slistItemName) then

		local pageText = "";
		if (self.current_page > 1) then
			pageText = string.format (ZT(": page %d"), self.current_page);
		end

		msg = string.format (ZT("Scanning auctions for %s%s"), slistItemName, pageText);
	elseif (q.totalAuctions >= 50) then
		msg = string.format (ZT("Scanning auctions: page %d"), self.current_page);
	end

	if (msg) then
		Atr_SetMessage (msg);
	end

	-- analyze (rows were captured once by CapturePageInfo; no repeated Blizz API calls)

	if (q.curPageInfo and q.curPageInfo.numOnPage > 0) then

		local x;

		for x = 1, q.curPageInfo.numOnPage do

			local ax = q.curPageInfo.auctionInfo[x];

			local name			= ax.name;
			local count			= ax.count;
			local buyoutPrice	= ax.buyoutPrice;
			local owner			= ax.owner;

			local acceptItem;
			if (self.exactMatchText) then						-- quoted search or quoted shopping-list entry
				acceptItem = zc.StringSame (name, self.exactMatchText);
			elseif (self.exact) then							-- IDstring-flagged exact search
				acceptItem = zc.StringSame (name, self.searchText);
			else
				acceptItem = true;
			end

			if (acceptItem) then

				if (self.items[name] == nil) then
					self.items[name] = Atr_FindScanAndInit (name);
				end

				local curpage = (tonumber(self.current_page)-1);

				local scn = self.items[name];

				scn:AddScanItem (name, count, buyoutPrice, owner, 1, curpage);

				if (scn.itemLink == nil or self.itemClass == nil) then
					scn:UpdateItemLink (ax.itemLink);
				end

				if (self.callback) then
					self.callback (x, q.curPageInfo.numOnPage, count, buyoutPrice, owner);
				end

			end
		end
	end

	local done = (q.curPageInfo == nil or q.curPageInfo.numOnPage < 50);

	if (done and self.shplist) then

		-- move on to the next item on the shopping list

		self.shopListIndex = self.shopListIndex + 1;

		local nextSearchItem = Atr_GetShoppingListItem (self);
		if (nextSearchItem) then
			self.current_page	= 0;
			self.exactMatchText	= nil;
			done = false;
		end
	end

	if (not done) then
		self.processing_state = KM_PREQUERY;
		self:Continue();		-- event-driven paging: send the next query right away
								-- (Continue self-gates on CanSendAuctionQuery; the 0.2s
								--  Atr_Idle pump remains as the fallback retry path)
	end

	return done;
end

-----------------------------------------

function AtrScan:AddScanItem (name, stackSize, buyoutPrice, owner, numAuctions, curpage)

	local sd = {};

	if (numAuctions == nil) then
		numAuctions = 1;
	end

	for i = 1, numAuctions do
		sd["stackSize"]		= stackSize;
		sd["buyoutPrice"]	= buyoutPrice;
		sd["owner"]			= owner;
		sd["pagenum"]		= curpage;
		sd["enchantID"]		= enchantID

		tinsert (self.scanData, sd);

		local itemPrice = math.floor (buyoutPrice / stackSize);

		Atr_AddToLowPrices (self.lowprices, itemPrice);
	end

end


-----------------------------------------

function AtrScan:AddSDXToScan (price, owner, volume)	-- helper function for AddExternalDataToScan

	local sd = {};

	if (price and price > 0) then
		sd["stackSize"]		= 1;
		sd["buyoutPrice"]	= price;
		sd["owner"]			= owner;

		if (volume) then
			sd["volume"] = volume;
		end

		tinsert (self.scanData, sd);
	end

end

-----------------------------------------

function AtrScan:AddExternalDataToScan ()

	if (self.itemLink == nil) then
		return;
	end

	-- Wowecon

	if (Wowecon and Wowecon.API) then

		local priceG, volG = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.GLOBAL_PRICE)
		local priceS, volS = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.SERVER_PRICE)

		self:AddSDXToScan (priceG, "__wowEconG", volG);
		self:AddSDXToScan (priceS, "__wowEconS", volS);

	end

	-- GoingPrice Wowhead

	local id = zc.ItemIDfromLink (self.itemLink);

	id = tonumber(id);

	if (GoingPrice_Wowhead_Data and GoingPrice_Wowhead_Data[id] and GoingPrice_Wowhead_SV._index) then
		local index = GoingPrice_Wowhead_SV._index["Buyout price"];

		if (index ~= nil) then
			local price = GoingPrice_Wowhead_Data[id][index];

			self:AddSDXToScan (price, "__wowHead");
		end
	end

	-- GoingPrice Allakhazam

	if (GoingPrice_Allakhazam_Data and GoingPrice_Allakhazam_Data[id] and GoingPrice_Allakhazam_SV._index) then
		local index = GoingPrice_Allakhazam_SV._index["Median"];

		if (index ~= nil) then
			local price = GoingPrice_Allakhazam_Data[id][index];

			self:AddSDXToScan (price, "__allakhazam");
		end
	end

	-- most recent historical price

	local price = Atr_Process_Historydata();
	if (price ~= nil) then
		self:AddSDXToScan (price, "__atrLast");
	end

end

-----------------------------------------

function AtrScan:SubtractScanItem (name, stackSize, buyoutPrice)

	local sd;
	local i;

	for i,sd in ipairs (self.scanData) do

		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice) then

			tremove (self.scanData, i);
			return;
		end
	end

end

-----------------------------------------

function Atr_IsCompoundSearch (searchString)

	return zc.StringContains (searchString, ">") or zc.StringContains (searchString, "/");
end

-----------------------------------------

function Atr_ParseCompoundSearch (searchString)

	local delim = "/";

	if (zc.StringContains (searchString, ">")) then
		delim = ">";
	end

	local tbl	= { strsplit (delim, searchString) };

	local queryString	= "";
	local itemClass		= 0;
	local itemSubclass	= 0;
	local minLevel		= nil;
	local maxLevel		= nil;
	local prevWasItemClass;
	local n;

	for n = 1,#tbl do
		local s = tbl[n];

		local handled = false;

		if (not handled and tonumber(s)) then
			if (minLevel == nil) then
				minLevel = tonumber(s);
			elseif (maxLevel == nil) then
				maxLevel = tonumber(s);
			end

			handled = true;
			prevWasItemClass = false;
		end

		if (not handled and prevWasItemClass and itemSubclass == 0) then
			itemSubclass = Atr_SubType2AuctionSubclass (itemClass, s);
			if (itemSubclass > 0) then
				handled = true;
				prevWasItemClass = false;
			end
		end

		if (not handled and itemClass == 0) then
			itemClass = Atr_ItemType2AuctionClass (s);
			if (itemClass > 0) then
				prevWasItemClass = true;
				handled = true;
			end
		end

		if (not handled) then
			queryString = s;
			handled = true;
		end
	end

	return queryString, itemClass, itemSubclass, minLevel, maxLevel;
end

-----------------------------------------

function AtrSearch:Continue()

	if (CanSendAuctionQuery()) then

		self.processing_state = KM_INQUERY;		-- (was the undefined KM_IN_QUERY; harmless but wrong)

		local queryString = self.searchText;

--	zc.md (queryString.."  page:"..self.current_page);

		local itemClass		= 0;
		local itemSubclass	= 0;
		local minLevel		= nil;
		local maxLevel		= nil;

		if (self.exact) then
			local scn = self:GetFirstScan();
			itemClass		= scn.itemClass;
			itemSubclass	= scn.itemSubclass;
		end

		if (Atr_IsCompoundSearch(queryString)) then

			queryString, itemClass, itemSubclass, minLevel, maxLevel = Atr_ParseCompoundSearch (queryString);

		elseif (self.shplist) then

			-- searching a shopping list: query for one item on the list at a time

			queryString = Atr_GetShoppingListItem (self);

			self.exactMatchText = queryString and Atr_GetExactMatchText (queryString) or nil;
			if (self.exactMatchText) then
				queryString = self.exactMatchText;
			end

			-- skip nested shopping lists or compound searches

			while (Atr_IsShoppingListSearch(queryString) or Atr_IsCompoundSearch(queryString)) do
				self.shopListIndex = self.shopListIndex + 1;
				queryString = Atr_GetShoppingListItem (self);
				if (queryString == nil) then
					break;
				end
			end

			if (queryString == nil) then
				queryString = "?????";
			end
		end

		queryString = zc.UTF8_Truncate (queryString,63);	-- attempting to reduce number of disconnects

		QueryAuctionItems (queryString, minLevel, maxLevel, nil, itemClass, itemSubclass, self.current_page, nil, nil);

		self.query_sent_when	= Atr_ptime;
		self.processing_state	= KM_POSTQUERY;
		self.current_page		= self.current_page + 1;
	end

end

-----------------------------------------

local gSortScansBy;

-----------------------------------------

local function Atr_SortScans (x, y)

	if (gSortScansBy == ATR_SORTBY_NAME_ASC) then		return string.lower (x.itemName) < string.lower (y.itemName);	end
	if (gSortScansBy == ATR_SORTBY_NAME_DES) then		return string.lower (x.itemName) > string.lower (y.itemName);	end

	local xprice = 0;
	local yprice = 0;

	if (x.absoluteBest) then	xprice = zc.round(x.absoluteBest.buyoutPrice/x.absoluteBest.stackSize);		end;
	if (y.absoluteBest) then	yprice = zc.round(y.absoluteBest.buyoutPrice/y.absoluteBest.stackSize);		end;

	if (gSortScansBy == ATR_SORTBY_PRICE_ASC) then		return xprice < yprice;		end
	if (gSortScansBy == ATR_SORTBY_PRICE_DES) then		return xprice > yprice;		end

end

-----------------------------------------

function AtrSearch:Finish()

	local finishTime = time();

	self.processing_state	= KM_NULL_STATE;
	self.current_page		= -1;
	self.query_sent_when	= nil;

	self.sortedScans = nil;

	-- add scans for items on the shopping list that weren't found so they still show in the summary

	if (self.shplist) then
		local n;
		for n = 1,self.shplist:GetNumItems() do
			local itemname = zc.TrimQuotes (self.shplist:GetNthItemName (n));

			if (itemname and itemname ~= "" and self.items[itemname] == nil and not Atr_IsShoppingListSearch(itemname) and not Atr_IsCompoundSearch(itemname)) then
				self.items[itemname] = Atr_FindScanAndInit (itemname);
			end
		end
	end

	local wasExactSearch = (self:NumScans() == 1);		-- search returned only 1 item

	local broadcastInfo = {};

	local x = 1;
	self.sortedScans = {};

	for name,scn in pairs (self.items) do
		self.sortedScans[x] = scn;
		x = x + 1;

		scn.whenScanned		= finishTime;
		scn.searchWasExact	= wasExactSearch;

		scn:CondenseAndSort();

		-- update the fullscan DB

		local newprice = Atr_CalcNewDBprice (scn.itemName, scn.lowprices);
		if (newprice > 0) then
			if (scn.itemQuality ~= nil and scn.itemQuality + 1 >= AUCTIONATOR_SCAN_MINLEVEL) then
				Atr_UpdateScanDBprice		(scn.itemName, newprice);
				Atr_UpdateScanDBclassInfo	(scn.itemName, scn.itemClass, scn.itemSubclass);
				Atr_UpdateScanDBitemID		(scn.itemName, scn.itemLink);

				table.insert (broadcastInfo, {i=scn.itemName, p=newprice});
			end
		end
	end

	Atr_Broadcast_DBupdated (#broadcastInfo, "partialscan", broadcastInfo);

	Atr_ClearBrowseListings();

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:ClickPriceCol()

	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		self.sortHow = ATR_SORTBY_PRICE_DES;
	else
		self.sortHow = ATR_SORTBY_PRICE_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);

end

-----------------------------------------

function AtrSearch:ClickNameCol()

	if (self.sortHow == ATR_SORTBY_NAME_ASC) then
		self.sortHow = ATR_SORTBY_NAME_DES;
	else
		self.sortHow = ATR_SORTBY_NAME_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:UpdateArrows()

	Atr_Col1_Heading_ButtonArrow:Hide();
	Atr_Col3_Heading_ButtonArrow:Hide();

	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_PRICE_DES) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	elseif (self.sortHow == ATR_SORTBY_NAME_ASC) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_NAME_DES) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	end
end

-----------------------------------------

function Atr_ClearBrowseListings()

	-- non-blocking (the old version busy-waited up to 5 seconds here);
	-- if the query throttle is active, retry in a second via the deferred-call queue

	if (not AuctionFrame or not AuctionFrame:IsShown()) then
		return;
	end

	if (gAtr_FullScanState and gAtr_FullScanState ~= ATR_FS_NULL) then
		return;		-- never fire a stray query while a full scan is walking the pages
	end

	if (CanSendAuctionQuery()) then
		QueryAuctionItems("xyzzy", 43, 43, 0, 7, 0);
	else
		zc.AddDeferredCall (1, "Atr_ClearBrowseListings", nil, nil, "clearBrowse");
	end

end

-----------------------------------------

function Atr_SortAuctionData (x, y)

	return x.itemPrice < y.itemPrice;

end

-----------------------------------------

function AtrScan:CondenseAndSort ()

	----- Condense the scan data into a table that has only a single entry per stacksize/price combo

	self.sortedData	= {};

	local conddata = {};

	for i,sd in ipairs (self.scanData) do

	  if (AUCTIONATOR_HIDE_BIDONLY ~= 1 or (sd.buyoutPrice and sd.buyoutPrice > 0)) then	-- optionally skip bid-only auctions

		local ownerCode = "x";
		local dataType  = "n";		-- normal

		if (sd.owner == UnitName("player")) then
			ownerCode = "y";
--		elseif (Atr_IsMyToon (sd.owner)) then
--			ownerCode = sd.owner;
		elseif (sd.owner == "__wowEconG") then
			dataType = "eg";
		elseif (sd.owner == "__wowEconS") then
			dataType = "es";
		elseif (sd.owner == "__wowHead") then
			dataType = "h";
		elseif (sd.owner == "__allakhazam") then
			dataType = "k";
		elseif (sd.owner == "__atrLast") then
			dataType = "a";
		end

		local key = "_"..sd.stackSize.."_"..sd.buyoutPrice.."_"..ownerCode..dataType;

		if (conddata[key]) then
			conddata[key].count		= conddata[key].count + 1;
			conddata[key].minpage 	= zc.Min (conddata[key].minpage, sd.pagenum);
			conddata[key].maxpage 	= zc.Max (conddata[key].maxpage, sd.pagenum);
		else
			local data = {};

			data.stackSize 		= sd.stackSize;
			data.buyoutPrice	= sd.buyoutPrice;
			data.itemPrice		= sd.buyoutPrice / sd.stackSize;
			data.minpage		= sd.pagenum;
			data.maxpage		= sd.pagenum;
			data.count			= 1;
			data.type			= dataType;
			data.yours			= (ownerCode == "y");

			if (ownerCode ~= "x" and ownerCode ~= "y") then
				data.altname = ownerCode;
			end

			if (sd.volume) then
				data.volume = sd.volume;
			end

			conddata[key] = data;
		end

	  end	-- AUCTIONATOR_HIDE_BIDONLY

	end

	----- create a table of these entries

	local n = 1;

	for _,v in pairs (conddata) do
		self.sortedData[n] = v;
		n = n + 1;
	end

	-- sort the table by itemPrice

	table.sort (self.sortedData, Atr_SortAuctionData);

	-- analyze and store some info about the data

	self:AnalyzeSortData ();

end

-----------------------------------------

function AtrScan:AnalyzeSortData ()

	self.absoluteBest			= nil;
	self.bestPrices				= {};		-- a table with one entry per stacksize that is the cheapest auction for that particular stacksize
	self.numMatches				= 0;
	self.numMatchesWithBuyout	= 0;
	self.hasStack				= false;
	self.yourBestPrice			= nil;
	self.yourWorstPrice			= nil;
	self.numYourSingletons		= 0;

	local j, sd;

	----- find the best price per stacksize and overall -----

	for j,sd in ipairs(self.sortedData) do

		if (sd.type == "n") then

			self.numMatches = self.numMatches + 1;

			if (sd.itemPrice > 0) then

				self.numMatchesWithBuyout = self.numMatchesWithBuyout + 1;

				if (self.bestPrices[sd.stackSize] == nil or self.bestPrices[sd.stackSize].itemPrice >= sd.itemPrice) then
					self.bestPrices[sd.stackSize] = sd;
				end

				if (self.absoluteBest == nil or self.absoluteBest.itemPrice > sd.itemPrice) then
					self.absoluteBest = sd;
				end

				if (sd.yours) then
					if (self.yourBestPrice == nil or self.yourBestPrice > sd.itemPrice) then
						self.yourBestPrice = sd.itemPrice;
					end

					if (self.yourWorstPrice == nil or self.yourWorstPrice < sd.itemPrice) then
						self.yourWorstPrice = sd.itemPrice;
					end

					if (sd.stackSize == 1) then
						self.numYourSingletons = self.numYourSingletons + sd.count;
					end
				end
			end

			if (sd.stackSize > 1) then
				self.hasStack = true;
			end
		end
	end
end

-----------------------------------------

function AtrScan:FindInSortedData (stackSize, buyoutPrice)
	local j = 1;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice and sd.yours) then
			return j;
		end
	end

	return 0;
end


-----------------------------------------

function AtrScan:FindMatchByStackSize (stackSize)

	local index = nil;

	local basedata = self.absoluteBest;

	if (self.bestPrices[stackSize]) then
		basedata = self.bestPrices[stackSize];
	end

	local numrows = #self.sortedData;

	local n;

	for n = 1,numrows do

		local data = self.sortedData[n];

		if (basedata and data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize and data.yours == basedata.yours) then
			index = n;
			break;
		end
	end

	return index;

end

-----------------------------------------

function AtrScan:FindMatchByYours ()

	local index = nil;

	local j;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.yours) then
			index = j;
			break;
		end
	end

	return index;

end

-----------------------------------------

function AtrScan:FindCheapest ()

	local index = nil;

	local j;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.itemPrice > 0) then
			index = j;
			break;
		end
	end

	return index;

end


-----------------------------------------

function AtrScan:GetNumAvailable ()

	local num = 0;

	local j, data;
	for j = 1,#self.sortedData do

		data = self.sortedData[j];
		num = num + (data.count * data.stackSize);
	end

	return num;
end

-----------------------------------------

function AtrScan:IsNil ()

	if (self.itemName == nil or self.itemName == "" or self.itemName == "nil") then
		return true;
	end

	return false;
end

-----------------------------------------

-- NOTE: the full scan lives in AuctionatorScanFull.lua now (ported from ver 3.2.6);
-- it defines the ATR_FS_* states, Atr_FullScanStart/Analyze/FrameIdle and the scan frame UI

-----------------------------------------

function Atr_GetDBsize()

	local n = 0;
	local a,v;

	for a,v in pairs (gAtr_ScanDB) do
		n = n + 1;
	end

	return n;
end

-----------------------------------------

function Atr_CalcNewDBprice (name, prices)

	if (prices[1] ~= BIGNUM) then
		return prices[1];
	end

	return 0;

end

-----------------------------------------

function Atr_AddToLowPrices (lowprices, itemPrice)

	if (itemPrice > 0) then
		if (itemPrice < lowprices[1]) then
			if (lowprices[1] < lowprices[2]) then
				lowprices[2] = lowprices[1];
			end
			lowprices[1] = itemPrice;
			return true;
		elseif (itemPrice < lowprices[2]) then
			lowprices[2] = itemPrice;
			return true;
		end
	end

	return false;
end




-----------------------------------------

function auctionator_AuctionFrameBrowse_Update ()

	return auctionator_orig_AuctionFrameBrowse_Update ();

end

-----------------------------------------
-------------- scan price DB ------------
--  (ported from Auctionator ver 6 / v3.2.6; entries are per-item tables:
--   mr = most recent low, H<day>/L<day> = daily high/low of the lows,
--   id = item IdString, cc/sc = class/subclass, po = purge-candidate mark)
-----------------------------------------

gScanHistDayZero = time({year=2010, month=11, day=15, hour=0});		-- never ever change

-----------------------------------------

function Atr_GetScanDay_Today()

	return (math.floor ((time() - gScanHistDayZero) / (86400)));

end

-----------------------------------------

function Atr_GetNumAuctionItems (which)

	local numBatchAuctions, totalAuctions = GetNumAuctionItems(which);

	local returnTotalAuctions = totalAuctions

	if (totalAuctions > 500000 or totalAuctions < 0) then
		totalAuctions = numBatchAuctions;
	end

	return numBatchAuctions, totalAuctions, returnTotalAuctions

end

-----------------------------------------

function Atr_UpdateScanDBitemID (itemName, itemLink)

	if (itemLink == nil) then
		return;
	end

	if (not gAtr_ScanDB[itemName]) then
		gAtr_ScanDB[itemName] = {};
	end

	local item_link = Auctionator.ItemLink:new({ item_link = itemLink })
	gAtr_ScanDB[itemName].id = item_link:IdString()
end

-----------------------------------------

function Atr_UpdateScanDBclassInfo (itemName, class, subclass)

	if (not gAtr_ScanDB[itemName]) then
		gAtr_ScanDB[itemName] = {};
	end

	gAtr_ScanDB[itemName].cc = class;
	gAtr_ScanDB[itemName].sc = subclass;

end

-----------------------------------------

function Atr_UpdateScanDBprice (itemName, currentLowPrice, db)

	if (currentLowPrice == nil) then
		zc.msg_badErr ("currentLowPrice in NIL!!!!!!", itemName)
		return
	end

	if (type(currentLowPrice) ~= "number") then
		zc.msg_badErr ("currentLowPrice in not a number !!!!!!", type(currentLowPrice), itemName)
		return
	end

	if (db == nil) then
		db = gAtr_ScanDB;
	end

	if (db and type (db) ~= "table") then
		zc.msg_badErr ("Scanning history database appears to be corrupt")
		zc.msg_badErr ("db:", db)
		return nil
	end

	if (not db[itemName]) then
		db[itemName] = {};
	end

	db[itemName].mr = currentLowPrice;

	local daysSinceZero = Atr_GetScanDay_Today();

	local lowlow  = db[itemName]["L"..daysSinceZero];
	local highlow = db[itemName]["H"..daysSinceZero];

	if (highlow == nil or currentLowPrice > highlow) then
		db[itemName]["H"..daysSinceZero] = currentLowPrice;
		highlow = currentLowPrice;
	end

	-- save memory by only saving lowlow when different from highlow

	local isLowerThanLow	= (lowlow ~= nil and currentLowPrice < lowlow);
	local isNewAndDifferent	= (lowlow == nil and currentLowPrice < highlow);

	if (isLowerThanLow or isNewAndDifferent) then
		db[itemName]["L"..daysSinceZero] = currentLowPrice;
	end

	if (db[itemName]["po"]) then	-- unmark this item so it isn't purged
		db[itemName]["po"] = nil;
	end
end

-----------------------------------------

function Atr_PurgeObsoleteItems ()

	-- one time removal of old items - called after a full scan

	local a = 0
	local b = 0
	local potentials = 0;
	local doPurge, mostRecentDay, key, price, name, itemInfo, char1, day

	local todayDay	= Atr_GetScanDay_Today()

	for name, itemInfo in pairs (gAtr_ScanDB) do

		doPurge = false;

		if (type(itemInfo) == "table") then

			mostRecentDay = -1

			for key, price in pairs (itemInfo) do
				char1 = string.sub (key, 1, 1)
				if (char1 == "H") then
					day = tonumber (string.sub(key, 2))
					mostRecentDay = math.max (day, mostRecentDay)
				end
			end

			if (itemInfo["po"]) then
				potentials = potentials + 1;
			end

			if (itemInfo["po"] and todayDay - mostRecentDay > 10) then
				doPurge = true;
			end
		end

		if (doPurge) then
			gAtr_ScanDB[name] = nil
			a = a + 1
		end

		b = b + 1
	end

end

-----------------------------------------

function Atr_PrunePostDB()

	-- remove old items from the posting history database

	if (AUCTIONATOR_PRICING_HISTORY == nil) then
		return;
	end

	local now = time();
	local x = 0;
	local total = 0;

	local tempDB = {};
	zc.CopyDeep (tempDB, AUCTIONATOR_PRICING_HISTORY);

	for itemName, info in pairs(tempDB) do

		local recentWhen = 0;
		local tag, hist;

		for tag, hist in pairs (info) do
			if (tag ~= "is") then
				local when, type, price = ParseHist (tag, hist);

				if (when > recentWhen) then
					recentWhen	= when;
				end
			end
		end

		if (now - recentWhen > 180 * 86400) then
			AUCTIONATOR_PRICING_HISTORY[itemName] = nil;
			x = x + 1;
		end

		total = total + 1;
	end

	collectgarbage  ("collect");

	if (x > 0) then
		zc.md (x, "of", total, "items pruned from post DB");
	end
end

-----------------------------------------

function Atr_MigtrateMaxHistAge()		-- 21 was too much

	if (AUCTIONATOR_DB_MAXHIST_AGE and AUCTIONATOR_DB_MAXHIST_AGE ~= 21 and AUCTIONATOR_DB_MAXHIST_AGE ~= -1) then
		AUCTIONATOR_DB_MAXHIST_DAYS = AUCTIONATOR_DB_MAXHIST_AGE;
	end

	AUCTIONATOR_DB_MAXHIST_AGE = -1;
end

-----------------------------------------

function Atr_PruneScanDB(verbose)

	local start = time();

	collectgarbage  ("collect");

	local startMem = Atr_GetAuctionatorMemString();

	local dbCopy = {};

	local todayDays = Atr_GetScanDay_Today();

	Atr_MigtrateMaxHistAge();

	local histCutoff	= todayDays - AUCTIONATOR_DB_MAXHIST_DAYS;
	local itemCutoff	= todayDays - AUCTIONATOR_DB_MAXITEM_AGE;

	local x = 0;
	local h = 0;
	local y = 0;
	local z = 0;

	local key, price, char1, day, doCopy;

	if (gAtr_ScanDB and type (gAtr_ScanDB) ~= "table") then
		zc.msg_badErr ("Scanning history database appears to be corrupt")
		zc.msg_badErr ("gAtr_ScanDB:", gAtr_ScanDB)
		return
	end

	for itemName, info in pairs (gAtr_ScanDB) do

		local mostRecentDay = -1;

		-- first pass over item

		for key, price in pairs (info) do
			char1 = string.sub (key, 1, 1);
			if (char1 == "H") then
				day = tonumber (string.sub(key, 2));
				mostRecentDay = math.max (day, mostRecentDay);
			end
		end

		-- decide if the item should be retained

		if (mostRecentDay == -1 or mostRecentDay >= itemCutoff) then

			dbCopy[itemName] = {};
			y = y + 1;

			for key, price in pairs (info) do			-- second pass over item
				doCopy = true;

				char1 = string.sub (key, 1, 1);
				if (char1 == "H" or char1 == "L") then
					day = tonumber (string.sub(key, 2));
					if (day < histCutoff and day ~= mostRecentDay) then
						doCopy = false;
						h = h + 1;
					end
				end

				if (doCopy) then
					dbCopy[itemName][key] = price;
					z = z + 1;
				end
			end
		else
			x = x + 1;
		end

	end

	zc.ClearTable (gAtr_ScanDB);
	zc.CopyDeep (gAtr_ScanDB, dbCopy);

	dbCopy = nil;

	collectgarbage  ("collect");

end

-----------------------------------------

function Atr_BuildSortedScanHistoryList (itemName)

	local currentPane = Atr_GetCurrentPane();

	local todayScanDay = Atr_GetScanDay_Today();

	-- build the sorted history list

	currentPane.sortedHist = {};

	if (gAtr_ScanDB[itemName]) then
		local n = 1;
		local key, highlowprice, char1, day, when;
		for key, highlowprice in pairs (gAtr_ScanDB[itemName]) do

			char1 = string.sub (key, 1, 1);

			if (char1 == "H") then

				day = tonumber (string.sub(key, 2));

				when = gScanHistDayZero + (day *86400);

				local lowlowprice = gAtr_ScanDB[itemName]["L"..day];
				if (lowlowprice == nil) then
					lowlowprice = highlowprice;
				end

				highlowprice = tonumber (highlowprice)
				lowlowprice  = tonumber (lowlowprice)

				currentPane.sortedHist[n]				= {};
				currentPane.sortedHist[n].itemPrice		= zc.round ((highlowprice + lowlowprice) / 2);
				currentPane.sortedHist[n].when			= when;
				currentPane.sortedHist[n].yours			= true;
				currentPane.sortedHist[n].type			= "n";

				if (day == todayScanDay) then
					currentPane.sortedHist[n].whenText = ZT("Today");
				elseif (day == todayScanDay - 1) then
					currentPane.sortedHist[n].whenText = ZT("Yesterday");
				else
					currentPane.sortedHist[n].whenText = date("%A, %B %d", when);
				end

				n = n + 1;
			end
		end
	end

	table.sort (currentPane.sortedHist, Atr_SortHistoryData);

	if (#currentPane.sortedHist > 0) then
		return currentPane.sortedHist[1].itemPrice;
	end

end







