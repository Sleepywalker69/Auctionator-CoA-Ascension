local addonName, addonTable = ...;
local zc = addonTable.zc;

-- The Auction House only permits one protected purchase per hardware click.
-- Keep the confirmation window open between clicks, but make everything around
-- that required click event-driven: reuse valid rows already on the current page,
-- and only query again after those rows have been consumed.

local ATR_BUY_NULL                         = 0;
local ATR_BUY_QUERY_SENT                   = 1;
local ATR_BUY_PAGE_READY                   = 2;
local ATR_BUY_WAITING_FOR_RESULT           = 3;
local ATR_BUY_WAITING_FOR_AH_CAN_SEND      = 4;

local Atr_BuyState = ATR_BUY_NULL;

-----------------------------------------

local gAtr_Buy_BuyoutPrice   = 0;
local gAtr_Buy_ItemName      = "";
local gAtr_Buy_StackSize     = 1;
local gAtr_Buy_Quality       = nil;
local gAtr_Buy_Link          = nil;
local gAtr_Buy_NumBought     = 0;
local gAtr_Buy_NumSkipped    = 0;
local gAtr_Buy_NumUserWants  = -1;
local gAtr_Buy_MaxCanBuy     = 0;
local gAtr_Buy_CurPage       = 0;
local gAtr_Buy_StartPage     = 0;
local gAtr_Buy_Waiting_Start = 0;
local gAtr_Buy_QuerySentAt   = 0;
local gAtr_Buy_QueryRetries  = 0;
local gAtr_Buy_PageReadStart = 0;
local gAtr_Buy_Query         = nil;
local gAtr_Buy_Pass          = 1;
local gAtr_Buy_MatchList     = {};
local gAtr_Buy_Pending       = nil;
local gAtr_Buy_Session       = 0;

-----------------------------------------
-- Chain-buy totals are only updated after the server confirms a purchase.
-----------------------------------------

local gAtr_Chain_TotalSpent   = 0;
local gAtr_Chain_QtyBought    = 0;
local gAtr_Chain_NumPurchases = 0;
local gAtr_Chain_Continuing   = false;

-----------------------------------------

local function Atr_MoneyText (copper)

	if (GetCoinTextureString) then
		return GetCoinTextureString (copper);
	end

	local g = math.floor (copper / 10000);
	local s = math.floor ((copper % 10000) / 100);
	local c = copper % 100;

	return g.."g "..s.."s "..c.."c";
end

-----------------------------------------

function Atr_IsChainBuyEnabled ()

	return (AUCTIONATOR_CHAIN_BUY == 1);
end

-----------------------------------------

function Atr_ChainBuy_Reset ()

	gAtr_Chain_TotalSpent   = 0;
	gAtr_Chain_QtyBought    = 0;
	gAtr_Chain_NumPurchases = 0;
end

-----------------------------------------

function Atr_ChainBuy_OnShow ()

	Atr_Chain_Buy_Button:SetChecked (AUCTIONATOR_CHAIN_BUY == 1);
end

-----------------------------------------

function Atr_ChainBuy_Toggle ()

	AUCTIONATOR_CHAIN_BUY = Atr_Chain_Buy_Button:GetChecked() and 1 or 0;

	PlaySound ("igMainMenuOptionCheckBoxOn");

	Atr_ChainBuy_Reset();
	Atr_Buy_UpdateChainText();
end

-----------------------------------------

function Atr_Buy_UpdateChainText ()

	if (Atr_IsChainBuyEnabled()) then
		Atr_Buy_Chain_Text:SetText (string.format (ZT("Bought %d (%d items) for"), gAtr_Chain_NumPurchases, gAtr_Chain_QtyBought)..": "..Atr_MoneyText (gAtr_Chain_TotalSpent));
		Atr_Buy_Chain_Text:Show();
	else
		Atr_Buy_Chain_Text:Hide();
	end
end

-----------------------------------------

function Atr_Buy_Debug1 (yellow)

	local asstr = "ATR_BUY_NULL";

	if (Atr_BuyState == ATR_BUY_QUERY_SENT)              then asstr = "ATR_BUY_QUERY_SENT"; end
	if (Atr_BuyState == ATR_BUY_PAGE_READY)              then asstr = "ATR_BUY_PAGE_READY"; end
	if (Atr_BuyState == ATR_BUY_WAITING_FOR_RESULT)      then asstr = "ATR_BUY_WAITING_FOR_RESULT"; end
	if (Atr_BuyState == ATR_BUY_WAITING_FOR_AH_CAN_SEND) then asstr = "ATR_BUY_WAITING_FOR_AH_CAN_SEND"; end

	if (Atr_BuyState ~= ATR_BUY_NULL) then
		if (yellow) then
			zc.msg (asstr, "curpage: ", gAtr_Buy_CurPage, "   bought: ", gAtr_Buy_NumBought);
		else
			zc.msg_pink (asstr, "curpage: ", gAtr_Buy_CurPage, "   bought: ", gAtr_Buy_NumBought);
		end
	end
end

-----------------------------------------

local function Atr_Buy_ClearRuntime ()

	gAtr_Buy_Session       = gAtr_Buy_Session + 1;
	gAtr_Buy_Pending       = nil;
	gAtr_Buy_MatchList     = {};
	gAtr_Buy_PageReadStart = 0;
	gAtr_Buy_QuerySentAt   = 0;
	gAtr_Buy_QueryRetries  = 0;
	Atr_BuyState           = ATR_BUY_NULL;
end

-----------------------------------------

function Atr_ClearBuyState ()

	Atr_Buy_ClearRuntime();
end

-----------------------------------------
-- Exact live-row validation. This intentionally includes rarity and item link:
-- same-named Bloodforged items can have different rarity and item level.
-----------------------------------------

local function Atr_Buy_RowMatches (index)

	local name, _, count, quality, _, _, _, _, buyoutPrice, _, _, owner = GetAuctionItemInfo ("list", index);

	if (name == nil) then
		return false, true;
	end

	if (not zc.StringSame (name, gAtr_Buy_ItemName) or count ~= gAtr_Buy_StackSize or buyoutPrice ~= gAtr_Buy_BuyoutPrice) then
		return false, false;
	end

	if (owner ~= nil and owner == UnitName ("player")) then
		return false, false;
	end

	if (gAtr_Buy_Quality ~= nil and quality ~= nil and quality ~= gAtr_Buy_Quality) then
		return false, false;
	end

	local link = GetAuctionItemLink ("list", index);

	if (gAtr_Buy_Link ~= nil) then
		if (link == nil) then
			return false, true;
		end

		if (link ~= gAtr_Buy_Link) then
			return false, false;
		end
	elseif (gAtr_Buy_Quality ~= nil and quality == nil) then
		return false, true;
	end

	return true, false;
end

-----------------------------------------

local function Atr_Buy_BuildMatchList ()

	gAtr_Buy_MatchList = {};

	local numOnPage = Atr_GetNumAuctionItems ("list");
	local incomplete = false;
	local index;

	for index = 1, numOnPage do
		local matches, rowIncomplete = Atr_Buy_RowMatches (index);

		if (matches) then
			tinsert (gAtr_Buy_MatchList, index);
		elseif (rowIncomplete) then
			incomplete = true;
		end
	end

	return #gAtr_Buy_MatchList, incomplete;
end

-----------------------------------------
-- Remove confirmed purchases (or definitively stale auctions) immediately from
-- Auctionator's displayed snapshot. Delaying this until the dialog closed was
-- what allowed already-bought rows to be selected again.
-----------------------------------------

local function Atr_Buy_ScanRowMatches (sd)

	if (sd.stackSize ~= gAtr_Buy_StackSize or sd.buyoutPrice ~= gAtr_Buy_BuyoutPrice) then
		return false;
	end

	if (sd.owner ~= nil and sd.owner == UnitName ("player")) then
		return false;
	end

	if (type (sd.owner) == "string" and string.sub (sd.owner, 1, 2) == "__") then
		return false;
	end

	if (gAtr_Buy_Quality ~= nil and sd.quality ~= gAtr_Buy_Quality) then
		return false;
	end

	if (gAtr_Buy_Link ~= nil and sd.link ~= gAtr_Buy_Link) then
		return false;
	end

	return true;
end

-----------------------------------------

local function Atr_Buy_SortedRowMatches (sd)

	if (sd == nil or sd.stackSize ~= gAtr_Buy_StackSize or sd.buyoutPrice ~= gAtr_Buy_BuyoutPrice) then
		return false;
	end

	if (gAtr_Buy_Quality ~= nil and sd.quality ~= gAtr_Buy_Quality) then
		return false;
	end

	if (gAtr_Buy_Link ~= nil and sd.link ~= gAtr_Buy_Link) then
		return false;
	end

	return (not sd.yours and not sd.altname);
end

-----------------------------------------

local function Atr_Buy_RemoveFromDisplayedScan (howMany)

	local currentPane = Atr_GetCurrentPane and Atr_GetCurrentPane();
	local scan = currentPane and currentPane.activeScan;

	if (howMany == nil or howMany < 1 or scan == nil or scan:IsNil() or not zc.StringSame (scan.itemName, gAtr_Buy_ItemName)) then
		return 0;
	end

	local removed = 0;
	local count;

	for count = 1, howMany do
		local index;
		local found = nil;

		for index = #scan.scanData, 1, -1 do
			if (Atr_Buy_ScanRowMatches (scan.scanData[index])) then
				found = index;
				break;
			end
		end

		if (found == nil) then
			break;
		end

		tremove (scan.scanData, found);
		removed = removed + 1;
	end

	if (removed > 0) then
		scan:CondenseAndSort();

		local selected = nil;
		local index;

		for index = 1, #scan.sortedData do
			if (Atr_Buy_SortedRowMatches (scan.sortedData[index])) then
				selected = index;
				break;
			end
		end

		currentPane.currIndex = selected;

		if (currentPane.currIndex == nil) then
			Atr_FindBestCurrentAuction();
		end

		currentPane.UINeedsUpdate = true;
	end

	return removed;
end

-----------------------------------------

local function Atr_Buy_UpdateProgress ()

	local progress = string.format (ZT("%d of %d bought so far"), gAtr_Buy_NumBought, gAtr_Buy_NumUserWants);

	if (gAtr_Buy_NumSkipped > 0) then
		progress = progress.."  |cffffaa00("..gAtr_Buy_NumSkipped.." unavailable)|r";
	end

	Atr_Buy_Continue_Text:SetText (progress);
	Atr_Buy_Part1:Hide();
	Atr_Buy_Part2:Show();
	Atr_Buy_Confirm_OKBut:SetText (ZT("Buy Next"));
	Atr_Buy_Confirm_CancelBut:SetText (ZT("Done"));
end

-----------------------------------------

local function Atr_Buy_ShowReady ()

	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
		return;
	end

	Atr_BuyState = ATR_BUY_PAGE_READY;

	if (gAtr_Buy_NumUserWants == -1) then
		Atr_Buy_Part1:Show();
		Atr_Buy_Part2:Hide();
		Atr_Buy_Confirm_OKBut:SetText (ZT("Buy"));
		Atr_Buy_Confirm_CancelBut:SetText (ZT("Cancel"));
	else
		Atr_Buy_UpdateProgress();
	end

	Atr_Buy_Confirm_OKBut:Enable();
	Atr_Buy_Confirm_CancelBut:Enable();
end

-----------------------------------------

function Atr_Buy1_Onclick ()

	if (not Atr_ShowingCurrentAuctions or not Atr_ShowingCurrentAuctions()) then
		return;
	end

	if (not gAtr_Chain_Continuing) then
		Atr_ChainBuy_Reset();
	end

	gAtr_Chain_Continuing = false;

	local currentPane = Atr_GetCurrentPane and Atr_GetCurrentPane();
	local scan = currentPane and currentPane.activeScan;
	local data = scan and currentPane.currIndex and scan.sortedData[currentPane.currIndex];

	if (data == nil or data.yours or data.altname or data.buyoutPrice == nil or data.buyoutPrice <= 0) then
		return;
	end

	Atr_Buy_ClearRuntime();

	gAtr_Buy_Query          = Atr_NewQuery();
	gAtr_Buy_NumUserWants  = -1;
	gAtr_Buy_NumBought     = 0;
	gAtr_Buy_NumSkipped    = 0;
	gAtr_Buy_BuyoutPrice   = data.buyoutPrice;
	gAtr_Buy_ItemName      = scan.itemName;
	gAtr_Buy_StackSize     = data.stackSize;
	gAtr_Buy_Quality       = data.quality;
	gAtr_Buy_Link          = data.link;
	gAtr_Buy_MaxCanBuy     = data.count;
	gAtr_Buy_Pass          = 1;

	gAtr_Buy_StartPage = (scan.searchWasExact and data.minpage ~= nil) and tonumber (data.minpage) or 0;

	if (gAtr_Buy_StartPage == nil or gAtr_Buy_StartPage < 0) then
		gAtr_Buy_StartPage = 0;
	end

	gAtr_Buy_CurPage = gAtr_Buy_StartPage;

	Atr_Buy_Confirm_ItemName:SetText (gAtr_Buy_ItemName.." x"..gAtr_Buy_StackSize);
	Atr_Buy_Confirm_Numstacks:SetNumber (1);
	Atr_Buy_Confirm_Max_Text:SetText (ZT("max")..": "..gAtr_Buy_MaxCanBuy);
	Atr_Buy_Part1:Show();
	Atr_Buy_Part2:Hide();
	Atr_Buy_Confirm_OKBut:SetText (ZT("Searching..."));
	Atr_Buy_Confirm_OKBut:Disable();
	Atr_Buy_Confirm_CancelBut:SetText (ZT("Cancel"));
	Atr_Buy_Confirm_CancelBut:Enable();
	Atr_Buy_UpdateChainText();
	Atr_Buy_Confirm_Frame:Show();

	Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
	Atr_Buy_QueueQuery (gAtr_Buy_StartPage);
end

-----------------------------------------

function Atr_Buy_QueueQuery (page, isRetry)

	if (Atr_BuyState == ATR_BUY_NULL) then
		return;
	end

	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
		return;
	end

	gAtr_Buy_CurPage       = math.max (0, tonumber (page) or 0);
	gAtr_Buy_Waiting_Start = GetTime();
	gAtr_Buy_PageReadStart = 0;
	gAtr_Buy_MatchList     = {};
	Atr_BuyState           = ATR_BUY_WAITING_FOR_AH_CAN_SEND;

	if (not isRetry) then
		gAtr_Buy_QueryRetries = 0;
	end

	Atr_Buy_Confirm_OKBut:SetText (ZT("Searching..."));
	Atr_Buy_Confirm_OKBut:Disable();

	Atr_Buy_SendQuery();
end

-----------------------------------------

function Atr_Buy_SendQuery ()

	if (Atr_BuyState ~= ATR_BUY_WAITING_FOR_AH_CAN_SEND or not CanSendAuctionQuery()) then
		return;
	end

	Atr_BuyState         = ATR_BUY_QUERY_SENT;
	gAtr_Buy_QuerySentAt = GetTime();

	local queryString = zc.UTF8_Truncate (gAtr_Buy_ItemName, 63);
	QueryAuctionItems (queryString, "", "", nil, 0, 0, gAtr_Buy_CurPage, nil, nil);
end

-----------------------------------------

local function Atr_Buy_SearchIsExhausted ()

	if (gAtr_Buy_Query == nil) then
		return true;
	end

	if (gAtr_Buy_Pass == 1) then
		return (gAtr_Buy_StartPage == 0 and gAtr_Buy_Query:IsLastPage (gAtr_Buy_CurPage));
	end

	return (gAtr_Buy_CurPage >= (gAtr_Buy_StartPage - 1) or gAtr_Buy_Query:IsLastPage (gAtr_Buy_CurPage));
end

-----------------------------------------

local function Atr_Buy_PruneRemainingStaleRows ()

	local remaining = math.max (0, gAtr_Buy_MaxCanBuy - gAtr_Buy_NumBought - gAtr_Buy_NumSkipped);

	if (remaining > 0) then
		local removed = Atr_Buy_RemoveFromDisplayedScan (remaining);
		gAtr_Buy_NumSkipped = gAtr_Buy_NumSkipped + removed;
	end
end

-----------------------------------------

function Atr_Buy_NextPage_Or_Cancel (queueIf)

	if (queueIf == false) then
		return;
	end

	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
		return;
	end

	if (Atr_Buy_SearchIsExhausted()) then
		Atr_Buy_PruneRemainingStaleRows();

		if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought < gAtr_Buy_NumUserWants) then
			zc.msg_atr (string.format (ZT("Bought %d of %d; the remaining auctions were no longer available."), gAtr_Buy_NumBought, gAtr_Buy_NumUserWants));
		end

		Atr_Buy_Cancel();
		return;
	end

	if (gAtr_Buy_Pass == 1 and gAtr_Buy_Query:IsLastPage (gAtr_Buy_CurPage)) then
		gAtr_Buy_Pass = 2;
		Atr_Buy_QueueQuery (0);
	else
		Atr_Buy_QueueQuery (gAtr_Buy_CurPage + 1);
	end
end

-----------------------------------------

local Atr_Buy_ProcessQueryResults;

Atr_Buy_ProcessQueryResults = function ()

	if (Atr_BuyState ~= ATR_BUY_QUERY_SENT) then
		return;
	end

	if (gAtr_Buy_PageReadStart == 0) then
		gAtr_Buy_PageReadStart = GetTime();
	end

	local numMatches, incomplete = Atr_Buy_BuildMatchList();

	-- Auction rows and links may stream in a frame after AUCTION_ITEM_LIST_UPDATE.
	-- Re-read locally for a short window; do not issue another server query.

	if (incomplete and (GetTime() - gAtr_Buy_PageReadStart) < 0.4) then
		local session = gAtr_Buy_Session;

		C_Timer.After (0.05, function ()
			if (session == gAtr_Buy_Session and Atr_BuyState == ATR_BUY_QUERY_SENT) then
				Atr_Buy_ProcessQueryResults();
			end
		end);

		return;
	end

	if (gAtr_Buy_Query) then
		gAtr_Buy_Query:CapturePageInfo (gAtr_Buy_CurPage);
	end

	if (numMatches > 0) then
		Atr_Buy_ShowReady();
	else
		Atr_Buy_NextPage_Or_Cancel();
	end
end

-----------------------------------------

function Atr_Buy_CheckForMatches ()

	Atr_Buy_ProcessQueryResults();
end

-----------------------------------------

local function Atr_Buy_MessageIsBidPlaced (message)

	if (type (message) ~= "string" or type (ERR_AUCTION_BID_PLACED) ~= "string") then
		return false;
	end

	if (message == ERR_AUCTION_BID_PLACED) then
		return true;
	end

	local marker = string.find (ERR_AUCTION_BID_PLACED, "%s", 1, true);

	if (marker == nil) then
		return false;
	end

	local prefix = string.sub (ERR_AUCTION_BID_PLACED, 1, marker - 1);
	local suffix = string.sub (ERR_AUCTION_BID_PLACED, marker + 2);
	local prefixOK = (prefix == "" or string.sub (message, 1, string.len (prefix)) == prefix);
	local suffixOK = (suffix == "" or string.sub (message, -string.len (suffix)) == suffix);

	return (prefixOK and suffixOK);
end

-----------------------------------------

local function Atr_Buy_ContinueAfterResult ()

	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
	elseif ((gAtr_Buy_NumBought + gAtr_Buy_NumSkipped) >= gAtr_Buy_MaxCanBuy) then
		if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought < gAtr_Buy_NumUserWants) then
			zc.msg_atr (string.format (ZT("Bought %d of %d; the remaining auctions were no longer available."), gAtr_Buy_NumBought, gAtr_Buy_NumUserWants));
		end

		Atr_Buy_Cancel();
	elseif (#gAtr_Buy_MatchList > 0) then
		Atr_Buy_ShowReady();
	else
		-- Re-query this page once after consuming its cached rows. Auctions from
		-- the following page may have shifted into it after the purchase.
		Atr_Buy_QueueQuery (gAtr_Buy_CurPage);
	end
end

-----------------------------------------

local function Atr_Buy_ResolvePendingSuccess ()

	local pending = gAtr_Buy_Pending;

	if (pending == nil) then
		return;
	end

	gAtr_Buy_Pending = nil;
	gAtr_Buy_NumBought = gAtr_Buy_NumBought + 1;

	gAtr_Chain_TotalSpent   = gAtr_Chain_TotalSpent + pending.price;
	gAtr_Chain_QtyBought    = gAtr_Chain_QtyBought + pending.qty;
	gAtr_Chain_NumPurchases = gAtr_Chain_NumPurchases + 1;

	Atr_Buy_RemoveFromDisplayedScan (1);
	Atr_Buy_UpdateChainText();
	Atr_Buy_ContinueAfterResult();
end

-----------------------------------------

local function Atr_Buy_ResolvePendingFailure (message, stopBuying)

	if (gAtr_Buy_Pending == nil) then
		return;
	end

	gAtr_Buy_Pending = nil;

	if (stopBuying) then
		Atr_Buy_Cancel (message);
		return;
	end

	gAtr_Buy_NumSkipped = gAtr_Buy_NumSkipped + 1;
	Atr_Buy_RemoveFromDisplayedScan (1);

	if (message) then
		zc.msg_atr (message);
	end

	Atr_Buy_ContinueAfterResult();
end

-----------------------------------------

local function Atr_Buy_TryResolvePending ()

	local pending = gAtr_Buy_Pending;

	if (pending == nil) then
		return;
	end

	local elapsed = GetTime() - pending.t;
	local moneySpent = (GetMoney() <= (pending.moneyBefore - pending.price));
	local confirmed = (pending.acknowledged or moneySpent);

	-- Normal path: both server acknowledgement and list mutation arrive almost
	-- immediately. The short fallback covers private-server clients which omit
	-- one of those events without reintroducing a fixed delay for everyone.

	if (confirmed and (pending.listUpdated or elapsed >= 0.25)) then
		Atr_Buy_ResolvePendingSuccess();
	elseif (elapsed >= 3) then
		Atr_Buy_ResolvePendingFailure (ZT("The Auction House did not confirm that purchase; it was skipped."), false);
	end
end

-----------------------------------------

function Atr_Buy_OnAuctionUpdate ()

	if (Atr_BuyState == ATR_BUY_NULL) then
		return false;
	end

	if (Atr_BuyState == ATR_BUY_WAITING_FOR_RESULT) then
		if (gAtr_Buy_Pending) then
			gAtr_Buy_Pending.listUpdated = true;
		end

		Atr_Buy_TryResolvePending();
	elseif (Atr_BuyState == ATR_BUY_QUERY_SENT) then
		Atr_Buy_ProcessQueryResults();
	end

	return (Atr_BuyState ~= ATR_BUY_NULL);
end

-----------------------------------------

function Atr_Buy_Idle ()

	if (Atr_BuyState == ATR_BUY_NULL) then
		return;
	end

	if (Atr_BuyState == ATR_BUY_WAITING_FOR_RESULT) then
		Atr_Buy_TryResolvePending();
		return;
	end

	if (Atr_BuyState == ATR_BUY_WAITING_FOR_AH_CAN_SEND) then
		if (gAtr_Buy_BuyoutPrice and GetMoney() < gAtr_Buy_BuyoutPrice) then
			Atr_Buy_Cancel (ZT("You do not have enough gold\n\nto make any more purchases."));
		elseif (GetTime() - gAtr_Buy_Waiting_Start > 10) then
			Atr_Buy_Cancel (ZT("Auction House timed out"));
		else
			Atr_Buy_SendQuery();
		end
	elseif (Atr_BuyState == ATR_BUY_QUERY_SENT and GetTime() - gAtr_Buy_QuerySentAt > 3) then
		if (gAtr_Buy_QueryRetries < 2) then
			gAtr_Buy_QueryRetries = gAtr_Buy_QueryRetries + 1;
			Atr_Buy_QueueQuery (gAtr_Buy_CurPage, true);
		else
			Atr_Buy_Cancel (ZT("Auction House timed out"));
		end
	end
end

-----------------------------------------

function Atr_Buy_BuyNextOnPage ()

	while (#gAtr_Buy_MatchList > 0) do
		-- Always buy the highest matching row. When Blizzard removes that row,
		-- every remaining (lower) match index stays valid, exactly as in TSM.

		local index = tremove (gAtr_Buy_MatchList);
		local matches = Atr_Buy_RowMatches (index);

		if (matches) then
			gAtr_Buy_Pending = {
				price        = gAtr_Buy_BuyoutPrice,
				qty          = gAtr_Buy_StackSize,
				t            = GetTime(),
				moneyBefore  = GetMoney(),
				rowIndex     = index,
				listUpdated  = false,
				acknowledged = false,
			};

			Atr_BuyState = ATR_BUY_WAITING_FOR_RESULT;
			PlaceAuctionBid ("list", index, gAtr_Buy_BuyoutPrice);
			return 1;
		end
	end

	return 0;
end

-----------------------------------------

function Atr_Buy_CountMatches (andBuy)

	local numMatches = #gAtr_Buy_MatchList;

	if (andBuy) then
		return numMatches, Atr_Buy_BuyNextOnPage();
	end

	return numMatches, 0;
end

-----------------------------------------

function Atr_Buy_BuyMatches ()

	return Atr_Buy_CountMatches (true);
end

-----------------------------------------

function Atr_Buy_Confirm_Update ()

	local num = Atr_Buy_Confirm_Numstacks:GetNumber();

	if (num == 1) then
		Atr_Buy_Confirm_Text2:SetText (ZT("stack for"));
	else
		Atr_Buy_Confirm_Text2:SetText (ZT("stacks for"));
	end

	MoneyFrame_Update ("Atr_Buy_Confirm_TotalPrice", gAtr_Buy_BuyoutPrice * num);
end

-----------------------------------------

function Atr_Buy_SetMax ()

	Atr_Buy_Confirm_Numstacks:SetNumber (gAtr_Buy_MaxCanBuy or 1);
	Atr_Buy_Confirm_Update();
end

-----------------------------------------

function Atr_Buy_IsComplete ()

	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		return true;
	end

	return Atr_Buy_SearchIsExhausted();
end

-----------------------------------------

function Atr_Buy_IsFirstPassComplete ()

	return (gAtr_Buy_Query ~= nil and gAtr_Buy_Pass == 1 and gAtr_Buy_Query:IsLastPage (gAtr_Buy_CurPage));
end

-----------------------------------------

function Atr_Buy_Confirm_OK ()

	if (Atr_BuyState ~= ATR_BUY_PAGE_READY or gAtr_Buy_Pending ~= nil) then
		return;
	end

	if (gAtr_Buy_NumUserWants == -1) then
		local numToBuy = Atr_Buy_Confirm_Numstacks:GetNumber();

		if (numToBuy == nil or numToBuy < 1) then
			Atr_Error_Text:SetText (ZT("Enter how many auctions you want to buy"));
			Atr_Error_Frame:Show();
			return;
		end

		if (numToBuy > gAtr_Buy_MaxCanBuy) then
			Atr_Error_Text:SetText (string.format (ZT("You can buy at most %d auctions"), gAtr_Buy_MaxCanBuy));
			Atr_Error_Frame:Show();
			return;
		end

		gAtr_Buy_NumUserWants = numToBuy;
		Atr_Buy_UpdateProgress();
	end

	Atr_Buy_Confirm_OKBut:SetText (ZT("Buying..."));
	Atr_Buy_Confirm_OKBut:Disable();
	Atr_Buy_Confirm_CancelBut:Disable();

	if (Atr_Buy_BuyNextOnPage() == 0) then
		Atr_Buy_QueueQuery (gAtr_Buy_CurPage);
	end
end

-----------------------------------------

function Atr_Buy_Wait_For_Bought_To_Clear ()
	-- Kept for compatibility with old Auctionator integrations. Purchase progress
	-- is now driven by AH acknowledgement events instead of a polling delay.
end

-----------------------------------------

function Atr_Buy_Cancel (msg, userCancelled)

	local boughtCount = gAtr_Buy_NumBought or 0;
	local skippedCount = gAtr_Buy_NumSkipped or 0;

	Atr_Buy_ClearRuntime();
	gAtr_Buy_NumUserWants = -1;
	gAtr_Buy_NumBought = 0;
	gAtr_Buy_NumSkipped = 0;

	Atr_Buy_Confirm_OKBut:Disable();
	Atr_Buy_Confirm_CancelBut:Enable();
	Atr_Buy_Confirm_Frame:Hide();

	if (msg == nil and not userCancelled and (boughtCount > 0 or skippedCount > 0) and Atr_IsChainBuyEnabled()) then
		local currentPane = Atr_GetCurrentPane and Atr_GetCurrentPane();
		local scan = currentPane and currentPane.activeScan;

		if (currentPane and scan and not scan:IsNil()) then
			currentPane.currIndex = nil;
			Atr_FindBestCurrentAuction();
			currentPane.UINeedsUpdate = true;
		end

		if (currentPane and scan and not scan:IsNil() and currentPane.currIndex and scan.sortedData[currentPane.currIndex]) then
			gAtr_Chain_Continuing = true;
			Atr_Buy1_Onclick();
			return;
		end

		zc.msg_atr (string.format (ZT("Chain buy finished: %d purchases, %d items"), gAtr_Chain_NumPurchases, gAtr_Chain_QtyBought).." - "..Atr_MoneyText (gAtr_Chain_TotalSpent));
	end

	if (msg) then
		Atr_Error_Display (msg);
	end
end

-----------------------------------------
-- Purchase acknowledgement and failure handling. TSM watches the same server
-- events: CHAT_MSG_SYSTEM confirms the bid, AUCTION_ITEM_LIST_UPDATE confirms
-- the list mutation, and UI_ERROR_MESSAGE identifies stale auctions.
-----------------------------------------

local gAtr_BuyWatch = CreateFrame ("Frame");

gAtr_BuyWatch:RegisterEvent ("UI_ERROR_MESSAGE");
gAtr_BuyWatch:RegisterEvent ("CHAT_MSG_SYSTEM");
gAtr_BuyWatch:RegisterEvent ("PLAYER_MONEY");

gAtr_BuyWatch:SetScript ("OnEvent", function (self, event, arg1, arg2)

	if (gAtr_Buy_Pending == nil or Atr_BuyState ~= ATR_BUY_WAITING_FOR_RESULT) then
		return;
	end

	if (event == "PLAYER_MONEY") then
		Atr_Buy_TryResolvePending();
		return;
	end

	local message = (type (arg2) == "string" and arg2) or arg1;

	if (event == "CHAT_MSG_SYSTEM") then
		if (Atr_Buy_MessageIsBidPlaced (message)) then
			gAtr_Buy_Pending.acknowledged = true;
			Atr_Buy_TryResolvePending();
		end
		return;
	end

	if (event == "UI_ERROR_MESSAGE") then
		if (message == ERR_ITEM_NOT_FOUND or (ERR_AUCTION_HIGHER_BID and message == ERR_AUCTION_HIGHER_BID)) then
			Atr_Buy_ResolvePendingFailure (ZT("Auction was no longer available; skipped it."), false);
		elseif (message == ERR_NOT_ENOUGH_MONEY) then
			Atr_Buy_ResolvePendingFailure (ZT("You do not have enough gold\n\nto make any more purchases."), true);
		elseif ((ERR_AUCTION_DATABASE_ERROR and message == ERR_AUCTION_DATABASE_ERROR)
			or (type (message) == "string" and string.find (string.lower (message), "internal auction error", 1, true))) then
			Atr_Buy_ResolvePendingFailure (ZT("The Auction House rejected that auction; skipped it."), false);
		end
	end
end);
