local addonName, addonTable = ...; 
local zc = addonTable.zc;

local ATR_BUY_NULL						= 0;
local ATR_BUY_QUERY_SENT				= 1;
local ATR_BUY_JUST_BOUGHT				= 2;
local ATR_BUY_PROCESSING_QUERY_RESULTS	= 3;
local ATR_BUY_WAITING_FOR_AH_CAN_SEND	= 4;

local Atr_BuyState = ATR_BUY_NULL;

-----------------------------------------

local gAtr_Buy_BuyoutPrice  = 0;
local gAtr_Buy_ItemName     = "";
local gAtr_Buy_StackSize    = 1;
local gAtr_Buy_NumBought    = 0;  
local gAtr_Buy_NumUserWants = -1; 
local gAtr_Buy_MaxCanBuy    = 0;
local gAtr_Buy_CurPage      = 0;
local gAtr_Buy_Waiting_Start = 0;
local gAtr_Buy_Query        = nil;
local gAtr_Buy_Pass         = 1;

local gAtr_Buy_Last_Query_Time = 0;

-----------------------------------------
--  chain buy: keep the buy dialog open and hop straight to the next auction,
--  with a running purchase summary (purchases, actual item quantity, gold spent)
-----------------------------------------

local gAtr_Chain_TotalSpent   = 0;
local gAtr_Chain_QtyBought    = 0;		-- actual items (sum of stack sizes), not auction rows
local gAtr_Chain_NumPurchases = 0;
local gAtr_Chain_Continuing   = false;

local gAtr_Buy_Pending        = nil;	-- last PlaceAuctionBid awaiting confirmation, for rollback

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

	PlaySound("igMainMenuOptionCheckBoxOn");

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
	local asstr = "ATR_BUY_NULL"
	if (Atr_BuyState == ATR_BUY_NULL)										then asstr = "ATR_BUY_NULL"; end;
	if (Atr_BuyState == ATR_BUY_QUERY_SENT)								then asstr = "ATR_BUY_QUERY_SENT"; end;
	if (Atr_BuyState == ATR_BUY_PROCESSING_QUERY_RESULTS)					then asstr = "ATR_BUY_PROCESSING_QUERY_RESULTS"; end;
	if (Atr_BuyState == ATR_BUY_JUST_BOUGHT)								then asstr = "ATR_BUY_JUST_BOUGHT"; end;
	if (Atr_BuyState == ATR_BUY_WAITING_FOR_AH_CAN_SEND)					then asstr = "ATR_BUY_WAITING_FOR_AH_CAN_SEND"; end;

	if (Atr_BuyState ~= ATR_BUY_NULL) then
		if (yellow) then
			zc.msg (asstr, "curpage: ", gAtr_Buy_CurPage, "   gAtr_Buy_NumBought: ", gAtr_Buy_NumBought);
		else
			zc.msg_pink (asstr, "curpage: ", gAtr_Buy_CurPage, "   gAtr_Buy_NumBought: ", gAtr_Buy_NumBought);
		end
	end
end

-----------------------------------------

function Atr_ClearBuyState()
	Atr_BuyState = ATR_BUY_NULL;
end

-----------------------------------------

function Atr_Buy1_Onclick ()
	if (not Atr_ShowingCurrentAuctions or not Atr_ShowingCurrentAuctions()) then
		return;
	end

	-- a manual Buy click starts a fresh chain-buy session; an automatic
	-- chain continuation keeps accumulating into the current one

	if (not gAtr_Chain_Continuing) then
		Atr_ChainBuy_Reset();
	end
	gAtr_Chain_Continuing = false;

	gAtr_Buy_Query			= Atr_NewQuery();
	gAtr_Buy_NumUserWants	= -1;
	gAtr_Buy_NumBought		= 0;
	gAtr_Buy_Last_Query_Time = 0;
	
	local currentPane = Atr_GetCurrentPane and Atr_GetCurrentPane();
	if (not currentPane or not currentPane.activeScan) then return end;
	
	local scan = currentPane.activeScan;
	local data = scan.sortedData[currentPane.currIndex];
	if (not data) then return end;

	gAtr_Buy_BuyoutPrice	= data.buyoutPrice;
	gAtr_Buy_ItemName		= scan.itemName;
	gAtr_Buy_StackSize		= data.stackSize;
	gAtr_Buy_MaxCanBuy		= data.count;
	gAtr_Buy_Pass			= 1;
	
	Atr_Buy_Confirm_ItemName:SetText (gAtr_Buy_ItemName.." x"..gAtr_Buy_StackSize);
	Atr_Buy_Confirm_Numstacks:SetNumber (1);
	Atr_Buy_Confirm_Max_Text:SetText (ZT("max")..": "..gAtr_Buy_MaxCanBuy);
	
	Atr_Buy_Part1:Show();
	Atr_Buy_Part2:Hide();
	
	Atr_Buy_Confirm_OKBut:SetText (ZT("Buy"))
	Atr_Buy_Confirm_OKBut:Disable();
	Atr_Buy_UpdateChainText();
	Atr_Buy_Confirm_Frame:Show();

	Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
	gAtr_Buy_Waiting_Start = GetTime();
	gAtr_Buy_CurPage = (scan.searchWasExact and data.minpage ~= nil) and data.minpage or 0;

	C_Timer.After(0.15, function()
		if (Atr_BuyState == ATR_BUY_WAITING_FOR_AH_CAN_SEND) then
			Atr_Buy_SendQuery();
		end
	end)
end

-----------------------------------------

function Atr_Buy_QueueQuery (page)
	if (Atr_BuyState == ATR_BUY_NULL) then
		return;
	end

	if (gAtr_Buy_NumUserWants and gAtr_Buy_NumBought and gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
		return;
	end

	gAtr_Buy_CurPage = page or 0;
	Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
	gAtr_Buy_Waiting_Start = GetTime();
	
	Atr_Buy_SendQuery();
end

-----------------------------------------

function Atr_Buy_SendQuery ()
	if (CanSendAuctionQuery()) then
		if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought > 0) then
			if (GetTime() - gAtr_Buy_Last_Query_Time < 0.4) then
				return;
			end
		end

		Atr_BuyState = ATR_BUY_QUERY_SENT;
		gAtr_Buy_Last_Query_Time = GetTime();

		local queryString = zc.UTF8_Truncate (gAtr_Buy_ItemName, 63);
		QueryAuctionItems (queryString, "", "", nil, 0, 0, gAtr_Buy_CurPage, nil, nil);
	end
end

-----------------------------------------
local prevBuyState;
-----------------------------------------

function Atr_Buy_Idle ()
	if (Atr_BuyState ~= prevBuyState) then
		prevBuyState = Atr_BuyState;
	end
	
	if (Atr_BuyState == ATR_BUY_NULL) then
		return;
	end

	if (not gAtr_Buy_NumUserWants or not gAtr_Buy_NumBought) then
		return;
	end
	
	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
		return;
	end

	if (Atr_BuyState == ATR_BUY_WAITING_FOR_AH_CAN_SEND) then
		if (gAtr_Buy_BuyoutPrice and GetMoney() < gAtr_Buy_BuyoutPrice) then
			Atr_Buy_Cancel (ZT("You do not have enough gold\n\nto make any more purchases."));
		elseif (gAtr_Buy_Waiting_Start and (GetTime() - gAtr_Buy_Waiting_Start > 10)) then
			Atr_Buy_Cancel (ZT("Auction House timed out"));
		else	
			Atr_Buy_SendQuery();
		end
		
	elseif (Atr_BuyState == ATR_BUY_JUST_BOUGHT) then
		-- Suspend calculations completely while the forced-wipe sequence processes
		Atr_BuyState = ATR_BUY_PROCESSING_QUERY_RESULTS; 
		
		-- 1. HARD CACHE SHATTER: Fire a query for an impossible item name.
		-- This completely poisons and breaks the client's cached array for "Linen Cloth"
		if (CanSendAuctionQuery()) then
			QueryAuctionItems("X_WIPE_X", "", "", nil, 0, 0, 0, nil, nil);
		end
		
		-- 2. DYNAMIC RETRY TIMEOUT: Give the cache break 0.4 seconds to clear out of client memory,
		-- then execute a fresh structural lookup for your true item name straight from the database.
		C_Timer.After(0.4, function()
			if (gAtr_Buy_NumUserWants and gAtr_Buy_NumBought and gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
				Atr_Buy_Cancel();
			else
				gAtr_Buy_Query = Atr_NewQuery();
				Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
				Atr_Buy_QueueQuery(gAtr_Buy_CurPage or 0);
			end
		end)
	end
end

-----------------------------------------
-- PART 2 & PART 3: MUTATED RUNTIMES
-----------------------------------------

function Atr_Buy_OnAuctionUpdate()
	if (Atr_BuyState == ATR_BUY_NULL) then
		return false;
	end

	-- Lock event processing completely during the hard cache shatter delay window
	if (Atr_BuyState == ATR_BUY_PROCESSING_QUERY_RESULTS) then
		return true;
	end

	-- MUTATION GUARD: If the server returns data from our "X_WIPE_X" cache poison trick,
	-- discard it immediately and wait for the real item query payload to register.
	local firstRowName = GetAuctionItemInfo("list", 1);
	if (Atr_BuyState == ATR_BUY_QUERY_SENT and firstRowName == nil) then
		return true;
	end

	if (Atr_BuyState == ATR_BUY_QUERY_SENT) then
		Atr_Buy_CheckForMatches();
	end
	return (Atr_BuyState ~= ATR_BUY_NULL);
end

-----------------------------------------

function Atr_Buy_CheckForMatches()
	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
		Atr_Buy_Cancel();
		return;
	end

	Atr_BuyState = ATR_BUY_PROCESSING_QUERY_RESULTS;

	local numMatches = Atr_Buy_CountMatches();
	
	if (numMatches > 0) then	
		if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought >= gAtr_Buy_NumUserWants) then
			Atr_Buy_Cancel();
			return;
		end

		-- Re-enable the hardware click interface only once a true mutated snapshot is downloaded
		Atr_Buy_Confirm_OKBut:Enable();

		if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumUserWants > 0) then		
			Atr_Buy_Continue_Text:SetText(string.format(ZT("%d of %d bought so far"), gAtr_Buy_NumBought, gAtr_Buy_NumUserWants));
			Atr_Buy_Part1:Hide();
			Atr_Buy_Part2:Show();
			Atr_Buy_Confirm_OKBut:SetText(ZT("Continue"))
		end
	else
		Atr_Buy_NextPage_Or_Cancel();
	end
end

-----------------------------------------

function Atr_Buy_BuyMatches()
	return Atr_Buy_CountMatches(true);
end

-----------------------------------------

function Atr_Buy_CountMatches(andBuy)
	local numMatches		= 0;
	local numBoughtThisPage	= 0;
	local i = 1; 

	while (true) do
		local name, _, count, _, _, _, _, _, buyoutPrice, _ = GetAuctionItemInfo("list", i);

		if (name == nil) then
			break;
		end

		if (zc.StringSame(name, gAtr_Buy_ItemName) and buyoutPrice == gAtr_Buy_BuyoutPrice and count == gAtr_Buy_StackSize) then
			numMatches = numMatches + 1;

			if (andBuy) then
				--print(string.format("|cff00ff00[Auctionator Debug] Targeted item found dynamically at Live Row [%d]. Sending execution click!|r", i))

				-- remember this bid so the totals can be rolled back if the server
				-- rejects it ("Item not found" when someone sniped the auction)

				gAtr_Buy_Pending = { price = gAtr_Buy_BuyoutPrice, qty = count, t = GetTime(), moneyBefore = GetMoney() };

				PlaceAuctionBid("list", i, gAtr_Buy_BuyoutPrice);

				numBoughtThisPage  = numBoughtThisPage + 1;
				gAtr_Buy_NumBought = gAtr_Buy_NumBought + 1;

				-- chain-buy purchase summary: track real item quantity, not just rows

				gAtr_Chain_TotalSpent   = gAtr_Chain_TotalSpent + gAtr_Buy_BuyoutPrice;
				gAtr_Chain_QtyBought    = gAtr_Chain_QtyBought + count;
				gAtr_Chain_NumPurchases = gAtr_Chain_NumPurchases + 1;
				Atr_Buy_UpdateChainText();

				return numMatches, numBoughtThisPage;
			end
		end
		i = i + 1;
	end
	return numMatches, numBoughtThisPage;
end

-----------------------------------------

function Atr_Buy_Confirm_Update()
	local num = Atr_Buy_Confirm_Numstacks:GetNumber();

	if (num == 1) then
		Atr_Buy_Confirm_Text2:SetText(ZT("stack for"));
	else
		Atr_Buy_Confirm_Text2:SetText(ZT("stacks for"));
	end

	MoneyFrame_Update("Atr_Buy_Confirm_TotalPrice", gAtr_Buy_BuyoutPrice * num);
end

-----------------------------------------

function Atr_Buy_SetMax()

	Atr_Buy_Confirm_Numstacks:SetNumber (gAtr_Buy_MaxCanBuy or 1);
	Atr_Buy_Confirm_Update();
end

-----------------------------------------

function Atr_Buy_NextPage_Or_Cancel(queueIf)
	if (Atr_Buy_IsComplete()) then
		Atr_Buy_Cancel();
	elseif (queueIf == nil or queueIf == true) then
		if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumBought < gAtr_Buy_NumUserWants) then
			Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
			Atr_Buy_QueueQuery(gAtr_Buy_CurPage);
		else
			if (Atr_Buy_IsFirstPassComplete()) then
				gAtr_Buy_Pass = 2;
				Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
				Atr_Buy_QueueQuery(0);
			else
				Atr_BuyState = ATR_BUY_WAITING_FOR_AH_CAN_SEND;
				Atr_Buy_QueueQuery(gAtr_Buy_CurPage + 1);
			end
		end
	end
end

-----------------------------------------

function Atr_Buy_IsComplete()
	if (gAtr_Buy_NumUserWants ~= -1 and gAtr_Buy_NumUserWants <= gAtr_Buy_NumBought) then
		return true;
	end

	if (gAtr_Buy_Query and gAtr_Buy_Query:IsLastPage(gAtr_Buy_CurPage) and gAtr_Buy_Pass == 2) then
		return true;
	end

	return false;
end

-----------------------------------------

function Atr_Buy_IsFirstPassComplete()
	if (gAtr_Buy_Query and gAtr_Buy_Query:IsLastPage(gAtr_Buy_CurPage) and gAtr_Buy_Pass == 1) then
		return true;
	end

	return false;
end

-----------------------------------------

function Atr_Buy_Confirm_OK()
	if (gAtr_Buy_NumUserWants == -1) then
		local numToBuy = Atr_Buy_Confirm_Numstacks:GetNumber();

		if (numToBuy > gAtr_Buy_MaxCanBuy) then
			Atr_Error_Text:SetText(string.format(ZT("You can buy at most %d auctions"), gAtr_Buy_MaxCanBuy));
			Atr_Error_Frame:Show();
			return;
		end
		
		gAtr_Buy_NumUserWants = numToBuy;
	end

	Atr_Buy_Confirm_OKBut:Disable();
	
	local _, numJustBought = Atr_Buy_BuyMatches();

	if (numJustBought > 0) then
		Atr_BuyState = ATR_BUY_JUST_BOUGHT;
		gAtr_Buy_Waiting_Start = GetTime();
		Atr_Buy_Confirm_OKBut:Disable();
	else
		Atr_Buy_NextPage_Or_Cancel();
	end
end

-----------------------------------------

function Atr_Buy_Wait_For_Bought_To_Clear()
end

-----------------------------------------

function Atr_Buy_Cancel(msg, userCancelled)

	local boughtCount = gAtr_Buy_NumBought or 0;

	Atr_BuyState = ATR_BUY_NULL;
	gAtr_Buy_NumUserWants = -1;
	gAtr_Buy_NumBought = 0;

	Atr_Buy_Confirm_Frame:Hide();

	-- remove the purchased auctions from the displayed scan and re-render, so a
	-- stale (already-bought) row can never be clicked and bought again.
	-- (the old requery-based cleanup left Atr_BuyState non-NULL with nothing to
	--  consume the response, wedging the state machine AND keeping the stale rows)

	if (boughtCount > 0) then

		local currentPane = Atr_GetCurrentPane and Atr_GetCurrentPane();
		local scan = currentPane and currentPane.activeScan;

		if (scan and not scan:IsNil()) then

			local n;
			for n = 1, boughtCount do
				scan:SubtractScanItem (gAtr_Buy_ItemName, gAtr_Buy_StackSize, gAtr_Buy_BuyoutPrice);
			end

			scan:CondenseAndSort();

			currentPane.currIndex = nil;
			Atr_FindBestCurrentAuction();
			currentPane.UINeedsUpdate = true;
		end
	end

	-- chain buy: after a successful purchase, hop straight to the next auction
	-- (never on a user cancel or an error abort)

	if (msg == nil and not userCancelled and boughtCount > 0 and Atr_IsChainBuyEnabled()) then

		local currentPane = Atr_GetCurrentPane and Atr_GetCurrentPane();
		local scan = currentPane and currentPane.activeScan;

		if (currentPane and scan and not scan:IsNil() and currentPane.currIndex and scan.sortedData[currentPane.currIndex]) then
			gAtr_Chain_Continuing = true;
			Atr_Buy1_Onclick();
			return;
		end

		zc.msg_atr (string.format (ZT("Chain buy finished: %d purchases, %d items"), gAtr_Chain_NumPurchases, gAtr_Chain_QtyBought).." - "..Atr_MoneyText (gAtr_Chain_TotalSpent));
	end

	if (msg) then
		Atr_Error_Display(msg);
	end
end

-----------------------------------------
--  purchase confirmation / rollback watcher
--
--  purchases are counted optimistically when PlaceAuctionBid is sent. if the
--  server rejects the bid (the auction was already bought - "Item not found" -
--  or funds ran short), the spent/quantity totals and the bought counter are
--  rolled back so the summary never claims gold that was not actually spent.
--  a PLAYER_MONEY drop matching the bid price confirms the purchase instead.
-----------------------------------------

local gAtr_BuyWatch = CreateFrame ("Frame");

gAtr_BuyWatch:RegisterEvent ("UI_ERROR_MESSAGE");
gAtr_BuyWatch:RegisterEvent ("PLAYER_MONEY");

gAtr_BuyWatch:SetScript ("OnEvent", function (self, event, arg1)

	if (gAtr_Buy_Pending == nil) then
		return;
	end

	if (GetTime() - gAtr_Buy_Pending.t > 5) then	-- too old to attribute either way
		gAtr_Buy_Pending = nil;
		return;
	end

	if (event == "PLAYER_MONEY") then

		if (GetMoney() <= (gAtr_Buy_Pending.moneyBefore - gAtr_Buy_Pending.price)) then
			gAtr_Buy_Pending = nil;		-- the gold actually left: purchase confirmed
		end

	elseif (event == "UI_ERROR_MESSAGE") then

		if (arg1 == ERR_ITEM_NOT_FOUND or arg1 == ERR_NOT_ENOUGH_MONEY) then

			gAtr_Chain_TotalSpent   = math.max (0, gAtr_Chain_TotalSpent - gAtr_Buy_Pending.price);
			gAtr_Chain_QtyBought    = math.max (0, gAtr_Chain_QtyBought - gAtr_Buy_Pending.qty);
			gAtr_Chain_NumPurchases = math.max (0, gAtr_Chain_NumPurchases - 1);

			if (gAtr_Buy_NumBought > 0) then
				gAtr_Buy_NumBought = gAtr_Buy_NumBought - 1;	-- keeps "N of M" and the row-removal count honest
			end

			gAtr_Buy_Pending = nil;

			Atr_Buy_UpdateChainText();

			zc.msg_atr (ZT("Purchase failed - the auction was already gone. Totals corrected."));
		end
	end

end);