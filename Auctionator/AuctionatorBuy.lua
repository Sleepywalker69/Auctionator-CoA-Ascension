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
				
				PlaceAuctionBid("list", i, gAtr_Buy_BuyoutPrice);

				numBoughtThisPage  = numBoughtThisPage + 1;
				gAtr_Buy_NumBought = gAtr_Buy_NumBought + 1;

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

function Atr_Buy_Cancel(msg)

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

	if (msg) then
		Atr_Error_Display(msg);
	end
end