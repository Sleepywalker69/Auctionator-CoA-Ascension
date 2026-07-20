
local addonName, addonTable = ...
local ZT = addonTable.ztt.ZT;
local zc = addonTable.zc
local zz = zc.md
local _

-----------------------------------------

ATR_FS_NULL					= 0
ATR_FS_STARTED				= 1
ATR_FS_SLOW_QUERY_SENT		= 2
ATR_FS_SLOW_QUERY_NEEDED	= 3
ATR_FS_ANALYZING			= 4
ATR_FS_UPDATING_DB			= 5
ATR_FS_CLEANING_UP			= 6

local BIGNUM = 999999999999;

gDefaultFullScanChunkSize = 50;

gAtr_FullScanState		= ATR_FS_NULL

local gFullScanPosition
local gCanQueryAll

local gFSNumNullItemNames
local gFSNumNullItemLinks
local gFSNumNullOwners

local gFullScanStart

local gSlowScanPage
local gSlowScanTotalPages

local gNumScanned
local gNumAdded
local gNumUpdated

local gDoSlowScan = false;
local gDeniedCounter
local gSlowQuerySentWhen

local gScanDetails = {}

local gLowPrices = {};
local gQualities = {};
local gQualityLowPrices = {};
local gVariantLowPrices = {};
local gTSMScanBridgeActive = false;

local badItemCount = 0

local gGetAllTotalAuctions
local gGetAllNumBatchAuctions
local gGetAllSuccess

-----------------------------------------

function Atr_FullScanStart()
	if (Atr_Inventory_IsBusy and Atr_Inventory_IsBusy()) then
		Atr_FullScanStatus:SetText("Stop the Inventory posting queue before starting a full scan.");
		zc.msg_yellow("Auctionator: stop the Inventory posting queue before starting a full scan.");
		return;
	end

	-- the DEFAULT scan is page-by-page (TSM style): it works on every server and
	-- needs no getAll cooldown. Ctrl+click requests the single-shot getAll scan
	-- instead, when the server allows one.

	local doGetAll = (IsControlKeyDown() and gCanQueryAll);

	Atr_FullScanStatus:SetText (ZT("Waiting for auction data").."...");
	Atr_FullScanStartButton:Disable();
	Atr_FullScanDone:Disable();

	gFullScanPosition	= nil

	gFullScanStart = time()

	gFSNumNullItemNames = 0
	gFSNumNullItemLinks = 0
	gFSNumNullOwners = 0

	SortAuctionClearSort ("list")

	gNumAdded   = 0
	gNumUpdated = 0
	gNumScanned = 0
	gLowPrices = {}
	gQualities = {}
	gQualityLowPrices = {}
	gVariantLowPrices = {}
	gTSMScanBridgeActive = Atr_TSMScanBridge_Begin()

	gGetAllSuccess = true

	gDeniedCounter = 0;

	if (doGetAll) then
		gDoSlowScan = false;
		gAtr_FullScanState = ATR_FS_STARTED;
		QueryAuctionItems ("", nil, nil, 0, 0, 0, 0, 0, 0, true);
	else
		-- no CanSendAuctionQuery gate here: SLOW_QUERY_NEEDED waits in the idle
		-- loop and sends each page as soon as the query throttle allows it

		gDoSlowScan = true;
		gAtr_FullScanState = ATR_FS_SLOW_QUERY_NEEDED;
		gSlowScanPage = 0
		gSlowScanTotalPages = nil
	end

end

-----------------------------------------

function Atr_FullScan_SendSlowQuery()

	if (gAtr_FullScanState ~= ATR_FS_SLOW_QUERY_NEEDED) then
		return;
	end

	if (CanSendAuctionQuery()) then
		gDeniedCounter = 0;

		-- NOTE: filters must be nil, not 0 - on 3.3.5 a qualityIndex of 0 means
		-- "Poor quality only" and the scan would only ever see the grey auctions

		QueryAuctionItems ("", nil, nil, nil, nil, nil, gSlowScanPage, nil, nil);
		gSlowQuerySentWhen = time();
		gAtr_FullScanState = ATR_FS_SLOW_QUERY_SENT;
	else
		gDeniedCounter = gDeniedCounter + 1;
	end

end

-----------------------------------------

function Atr_FullScan_OnAHClosed()

	-- abort cleanly; a wedged non-NULL state would otherwise keep
	-- Atr_FullScanFrameIdle claiming every OnUpdate tick after the AH closes

	if (gAtr_FullScanState ~= ATR_FS_NULL) then
		Atr_TSMScanBridge_Abort()
		gTSMScanBridgeActive = false
		gAtr_FullScanState = ATR_FS_NULL;
		Atr_FullScanStatus:SetText ("");
		Atr_FullScanStartButton:Enable();
		Atr_FullScanDone:Enable();
		zc.msg_anm (ZT("Full scan interrupted - the auction house was closed."));
	end

end

-----------------------------------------

function Atr_FullScanFrameIdle()

	---- ui stuff ----
	
	
	if (gAtr_FullScanState == ATR_FS_NULL) then

		if (Atr_FullScanFrame:IsShown()) then

			local _;
			_, gCanQueryAll = CanSendAuctionQuery();

			if (IsControlKeyDown()) then
				Atr_FullScanStartButton:SetText ("Fast Scan (getAll)")
				if (gCanQueryAll) then
					Atr_FullScanStartButton:Enable();
				else
					Atr_FullScanStartButton:Disable();
				end
			else
				Atr_FullScanStartButton:SetText ("Start Scanning")
				Atr_FullScanStartButton:Enable();
			end
		end

		return false;
	end

	-- getAll requests can be silently ignored by the server even when CanSendAuctionQuery
	-- claims getAll is available, so never wait on the response forever (TSM pattern)

	if (gAtr_FullScanState == ATR_FS_STARTED and gFullScanStart and time() - gFullScanStart > 30) then
		zc.msg_anm ("|cffff3333Warning:|r server did not respond to the getAll request.");
		zc.msg_anm ("Use the default page-by-page scan instead (click without holding Ctrl).");
		gAtr_FullScanState = ATR_FS_NULL;
		Atr_TSMScanBridge_Abort()
		gTSMScanBridgeActive = false
		Atr_FullScanStatus:SetText ("");
		Atr_FullScanStartButton:Enable();
		Atr_FullScanDone:Enable();
		return true;
	end

	-- processing stuff --

	if (gAtr_FullScanState == ATR_FS_ANALYZING and not gDoSlowScan) then
		Atr_FullScanAnalyze()
	end

	local statusText;

	if (gAtr_FullScanState == ATR_FS_SLOW_QUERY_NEEDED) then
		Atr_FullScan_SendSlowQuery();
	end

	-- a dropped AUCTION_ITEM_LIST_UPDATE would otherwise wedge the scan forever;
	-- re-send the page if the server hasn't answered in 10 seconds (TSM hard-retry)

	if (gAtr_FullScanState == ATR_FS_SLOW_QUERY_SENT and gSlowQuerySentWhen and time() - gSlowQuerySentWhen > 10) then
		zz ("slow-scan page timed out; re-sending page", gSlowScanPage);
		gAtr_FullScanState = ATR_FS_SLOW_QUERY_NEEDED;
		Atr_FullScan_SendSlowQuery();
	end

	if (gAtr_FullScanState == ATR_FS_SLOW_QUERY_NEEDED or gAtr_FullScanState == ATR_FS_SLOW_QUERY_SENT) then
		if (gSlowScanTotalPages) then
			statusText = string.format ("Page %s of %s", gSlowScanPage+1, gSlowScanTotalPages)
		end
	end
		
	if (gAtr_FullScanState == ATR_FS_STARTED)		then	statusText = "Waiting for auction data"		end
	if (gAtr_FullScanState == ATR_FS_UPDATING_DB)	then	statusText = "Updating database"			end
	if (gAtr_FullScanState == ATR_FS_CLEANING_UP)	then	statusText = "Scan complete"				end
	if (gAtr_FullScanState == ATR_FS_ANALYZING ) 	then	statusText = "Analyzing data ["..gFullScanPosition.." out of "..gGetAllTotalAuctions.."]";				end





	if (gAtr_FullScanState == ATR_FS_CLEANING_UP) then

		if (Atr_GetNumAuctionItems("list") < 100) then
			PlaySound("AuctionWindowClose");
			Atr_PurgeObsoleteItems ();
			gAtr_FullScanState = ATR_FS_NULL;
		end
	end
	
	local btext = Atr_FullScanStatus:GetText ();
	if (btext and statusText) then
		Atr_FullScanStatus:SetText (string.format (statusText.." (%s)", Atr_FullScan_GetDurString()));
	end
	
	
	return true;
end


-----------------------------------------

function Atr_FullScanBeginAnalyzePhase()

	gAtr_FullScanState = ATR_FS_ANALYZING;

	local numBatchAuctions, totalAuctions, returnedTotalAuction = Atr_GetNumAuctionItems("list");

	gGetAllTotalAuctions	= returnedTotalAuction
	gGetAllNumBatchAuctions	= numBatchAuctions

	if (totalAuctions ~= returnedTotalAuction) then
		gGetAllSuccess			= false
	end

	gFullScanPosition = 1


	if (not gDoSlowScan) then
		gLowPrices = {}
		gQualities = {}
		gQualityLowPrices = {}
		gVariantLowPrices = {}

		zz ("FULL SCAN:"..numBatchAuctions.." out of  "..totalAuctions)
		zz ("AUCTIONATOR_FS_CHUNK: ", AUCTIONATOR_FS_CHUNK)
	end
	
end

-----------------------------------------

function Atr_FullScanAnalyze()

	if (gFullScanPosition == nil) then
		zc.msg_anm ("|cffff3333Warning:|r Atr_FullScanAnalyze: gFullScanPosition is nil!");
	end

	local firstScanPosition = gFullScanPosition;
	local numBatchAuctions  = gGetAllNumBatchAuctions;
	
	if (gDoSlowScan) then
		local numBatchAuctions, totalAuctions = Atr_GetNumAuctionItems("list");

		firstScanPosition = 1
		gSlowScanTotalPages = math.floor (totalAuctions / 50) + 1
		
		if (numBatchAuctions == 0) then		-- slow scan done
			Atr_FullScanUpdateDB();
			return;
		end
	end
	
	local dataIsGood = true
	local tsmRecords = gTSMScanBridgeActive and {} or nil

	-- 3.3.5 GetAuctionItemInfo layout (12 values; no levelColHeader / *FullName / saleStatus)
	local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner, itemLink

	if (numBatchAuctions > 0) then


		local chunk_size = gDefaultFullScanChunkSize;
		if (AUCTIONATOR_FS_CHUNK ~= nil) then
			chunk_size = AUCTIONATOR_FS_CHUNK
		end


		local x;

		for x = firstScanPosition, numBatchAuctions do

			name, texture, count, quality, canUse, level, minBid,
					minIncrement, buyoutPrice, bidAmount, highBidder, owner   = GetAuctionItemInfo("list", x);

			gNumScanned = gNumScanned + 1
			
			if (name == nil) then
				gFSNumNullItemNames = gFSNumNullItemNames + 1;
			end
			
			if (owner == nil) then
				gFSNumNullOwners = gFSNumNullOwners + 1;
			end
			
			if (name == nil or name == "") then
				badItemCount = badItemCount + 1
				dataIsGood = false
				zz ("bad item scanned.  name: ", name, " count: ", count, "badItemCount: ", badItemCount);
			else
				if (quality ~= nil) then
					gQualities[name] = math.max(gQualities[name] or quality, quality);
				end

				if (buyoutPrice ~= nil and count and count > 0) then

					local itemPrice = math.floor (buyoutPrice / count);

					if (itemPrice > 0) then
						if (not gLowPrices[name]) then
							gLowPrices[name] = BIGNUM;
						end
						
						gLowPrices[name] = math.min (gLowPrices[name], itemPrice);

						itemLink = GetAuctionItemLink("list", x);
						if (itemLink and tsmRecords) then
							tsmRecords[#tsmRecords + 1] = {itemLink, itemPrice, count};
						elseif (not itemLink) then
							gFSNumNullItemLinks = gFSNumNullItemLinks + 1;
						end
						local linkQuality = quality;
						local linkLevel = level;
						if (itemLink) then
							local _, _, cachedQuality, cachedLevel = GetItemInfo(itemLink);
							linkQuality = cachedQuality or linkQuality;
							linkLevel = cachedLevel or linkLevel;
						end
						if (linkQuality ~= nil) then
							gQualities[name] = math.max(gQualities[name] or linkQuality, linkQuality);
						end

						local qkey = tostring(linkQuality or -1);
						if (not gQualityLowPrices[name]) then gQualityLowPrices[name] = {}; end
						gQualityLowPrices[name][qkey] = math.min(gQualityLowPrices[name][qkey] or itemPrice, itemPrice);

						local variantKey = Atr_GetItemVariantKey(itemLink, linkQuality, linkLevel);
						if (variantKey) then
							if (not gVariantLowPrices[name]) then gVariantLowPrices[name] = {}; end
							gVariantLowPrices[name][variantKey] = math.min(gVariantLowPrices[name][variantKey] or itemPrice, itemPrice);
						end
					end
				end
			end
			
			if (not gDoSlowScan and (x % chunk_size) == 0 and x < numBatchAuctions) then			-- analyze fast scan data in chunks so as not to cause client to timeout?
				if (tsmRecords) then Atr_TSMScanBridge_AddRecords(tsmRecords); end
				gFullScanPosition = x + 1;
				return;
			end
		end
	end

	-- Slow pages with incomplete rows are retried, so only commit a complete
	-- page.  A getAll payload cannot be retried per-page; retain every valid row.
	if (tsmRecords and (not gDoSlowScan or dataIsGood)) then
		Atr_TSMScanBridge_AddRecords(tsmRecords);
	end

	
	if (gDoSlowScan) then
		if (dataIsGood) then
			gSlowScanPage = gSlowScanPage + 1

			if (gSlowScanTotalPages and gSlowScanPage >= gSlowScanTotalPages) then	-- that was the last page
				Atr_FullScanUpdateDB();
				return;
			end
		else
			zz ("*** bad scan data.  requerying page: ", gSlowScanPage);
		end
		gAtr_FullScanState = ATR_FS_SLOW_QUERY_NEEDED;
		Atr_FullScan_SendSlowQuery();		-- chain the next page in the same frame when the throttle allows (TSM pattern)
	else
		Atr_FullScanUpdateDB()		-- if we get to here on a fast scan, we're done
	end;

end

-----------------------------------------

function Atr_FullScanUpdateDB()

	gAtr_FullScanState = ATR_FS_UPDATING_DB
	
	zz ("Updating DB")

	local numEachQual = {0, 0, 0, 0, 0, 0, 0, 0, 0};
	local totalItems = 0;
	local numRemoved = { 0, 0, 0, 0, 0, 0, 0, 0 };

	for name,newprice in pairs (gLowPrices) do
		
		if (newprice < BIGNUM) then
		
			local qx = (gQualities[name] or 0) + 1;
			
			if (qx == nil or numEachQual[qx] == nil) then
				zz ("ERROR: numEachQual[qx] == nil,  qx: ", qx, " name: ", name, " totalItems: ", totalItems);
			end
			
			numEachQual[qx]	= numEachQual[qx] + 1;
			totalItems		= totalItems + 1;
			
			if (type(AUCTIONATOR_SCAN_MINLEVEL) ~= "number") then
				AUCTIONATOR_SCAN_MINLEVEL = 1;
			end
			
			if ((qx < AUCTIONATOR_SCAN_MINLEVEL) and gAtr_ScanDB[name]) then
				numRemoved[qx] = numRemoved[qx] + 1;
				gAtr_ScanDB[name] = nil;
			end
			
			if (qx >= AUCTIONATOR_SCAN_MINLEVEL) then

				if (gAtr_ScanDB[name] == nil) then
					gNumAdded = gNumAdded + 1;
				else
					gNumUpdated = gNumUpdated + 1;
				end

				Atr_UpdateScanDBprice (name, newprice);

				local dbInfo = gAtr_ScanDB[name];
				if (type(dbInfo) == "table") then
					dbInfo.qmr = gQualityLowPrices[name] or {};
					dbInfo.vmr = gVariantLowPrices[name] or {};
					dbInfo.vwhen = time();
				end
			end
		end
	end

	zz ("Cleaning up")

	gScanDetails.numBatchAuctions		= gNumScanned;
	gScanDetails.totalItems				= totalItems;
	gScanDetails.numEachQual			= numEachQual;
	gScanDetails.numRemoved				= numRemoved;
	gScanDetails.gNumAdded				= gNumAdded;
	gScanDetails.gNumUpdated			= gNumUpdated;

	gAtr_FullScanState = ATR_FS_CLEANING_UP;

	Atr_FullScanMoreDetails();

	Atr_FullScanDone:Enable();
	Atr_FullScanStatus:SetText ("");
	
	Atr_FSR_scanned_count:SetText	(gNumScanned);
	Atr_FSR_added_count:SetText		(gNumAdded);
	Atr_FSR_updated_count:SetText	(gNumUpdated);
	Atr_FSR_ignored_count:SetText	(totalItems - (gNumAdded + gNumUpdated));
	
	Atr_FullScanHTML:Hide();
	Atr_FullScanResults:Show();
	
	Atr_FullScanResults:SetBackdropColor (0.3, 0.3, 0.4);
	
	AUCTIONATOR_LAST_SCAN_TIME = time();
	
	Atr_UpdateFullScanFrame ();

	Atr_Broadcast_DBupdated (totalItems, "fullscan");
	Atr_TSMScanBridge_Finish();
	gTSMScanBridgeActive = false
	if (Atr_Inventory_MarkDirty) then Atr_Inventory_MarkDirty(); end

	Atr_ClearBrowseListings();
	
	gLowPrices = {};
	gQualities = {};
	gQualityLowPrices = {};
	gVariantLowPrices = {};

	collectgarbage ("collect");
	
end

-----------------------------------------

function Atr_ShowFullScanFrame()

	Atr_FullScanHTML:Show();
	Atr_FullScanResults:Hide();

	Atr_FullScanFrame:Show();
	Atr_FullScanFrame:SetBackdropColor(0,0,0,100);
	
	Atr_UpdateFullScanFrame();
	Atr_FullScanStatus:SetText ("");

	local expText = "<html><body>"
					.."<p>"
					..ZT("SCAN_EXPLANATION")
					.."</p>"
					.."</body></html>"
					;



	Atr_FullScanHTML:SetText (expText);
	Atr_FullScanHTML:SetSpacing (3);
end

-----------------------------------------

function Atr_UpdateFullScanFrame()

	Atr_FullScanDBsize:SetText (Atr_GetDBsize());
	
	if (AUCTIONATOR_LAST_SCAN_TIME) then
		Atr_FullScanDBwhen:SetText (date ("%A, %B %d at %I:%M %p", AUCTIONATOR_LAST_SCAN_TIME));
	else
		Atr_FullScanDBwhen:SetText (ZT("Never"));
	end

	local canQuery

	canQuery, gCanQueryAll = CanSendAuctionQuery();

	-- the default page-by-page scan is always available; the "next" line only
	-- describes when the Ctrl+click getAll fast scan becomes available again

	Atr_FullScanStatus:SetText ("");
	Atr_FullScanStartButton:Enable();

	if (gCanQueryAll) then
		Atr_FullScanNext:SetText(ZT("Now"));
	else
		if (AUCTIONATOR_LAST_SCAN_TIME) then
			local when = 15*60 - (time() - AUCTIONATOR_LAST_SCAN_TIME);

			when = math.floor (when/60);

			if (when == 0) then
				Atr_FullScanNext:SetText (ZT("in less than a minute"));
			elseif (when == 1) then
				Atr_FullScanNext:SetText (ZT("in about one minute"));
			elseif (when > 0) then
				Atr_FullScanNext:SetText (string.format (ZT("in about %d minutes"), when));
			else
				Atr_FullScanNext:SetText (ZT("unknown"));
			end
		else
			Atr_FullScanNext:SetText (ZT("unknown"));
		end
	end
end

-----------------------------------------

function Atr_FullScan_GetDurString()

	local fullScanDur = time()- gFullScanStart;

	local minutes = math.floor (fullScanDur/60);
	local seconds = fullScanDur - (minutes * 60);

	return string.format ("%d:%02d", minutes, seconds);
end



-----------------------------------------

function GetIgnoredString (qx)

	if (qx < AUCTIONATOR_SCAN_MINLEVEL) then
		return " |cffeeeeee(ignored)|r"
	end
	
	return ""

end
-----------------------------------------

function Atr_FullScanMoreDetails ()

	zc.msg (" ");
	zc.msg_anm (ZT("Auctions scanned")..": |cffffffff", gScanDetails.numBatchAuctions, " |r("..gScanDetails.totalItems, "items) ", "time: ", Atr_FullScan_GetDurString());
	zc.msg_anm ("|cffa335ee   "..ZT("Epic items")..": |r",		gScanDetails.numEachQual[5]..GetIgnoredString(5));
	zc.msg_anm ("|cff0070dd   "..ZT("Rare items")..": |r",		gScanDetails.numEachQual[4]..GetIgnoredString(4));
	zc.msg_anm ("|cff1eff00   "..ZT("Uncommon items")..": |r",	gScanDetails.numEachQual[3]..GetIgnoredString(3));
	zc.msg_anm ("|cffffffff   "..ZT("Common items")..": |r",	gScanDetails.numEachQual[2]..GetIgnoredString(2));
	zc.msg_anm ("|cff9d9d9d   "..ZT("Poor items")..": |r",		gScanDetails.numEachQual[1]..GetIgnoredString(1));
	
	if (gScanDetails.numRemoved[4] > 0) then		zc.msg_anm (ZT("Rare items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[4]);		end
	if (gScanDetails.numRemoved[3] > 0) then		zc.msg_anm (ZT("Uncommon items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[3]);		end
	if (gScanDetails.numRemoved[2] > 0) then		zc.msg_anm (ZT("Common items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[2]);		end
	if (gScanDetails.numRemoved[1] > 0) then		zc.msg_anm (ZT("Poor items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[1]);		end
	
	zc.msg_anm (ZT("Items added to database")..": |cffffffff", gScanDetails.gNumAdded);
	zc.msg_anm (ZT("Items updated in database")..": |cffffffff", gScanDetails.gNumUpdated);

	if (gFSNumNullItemNames > 0) then
		zc.msg_anm (string.format ("|cffff3333%d auctions returned empty results (out of %d)|r", gFSNumNullItemNames, gScanDetails.numBatchAuctions));
	end
		
	if (gFSNumNullItemLinks > 0) then
		zc.msg_anm (string.format ("|cffff3333%d auctions returned null itemLinks (out of %d)|r", gFSNumNullItemLinks, gScanDetails.numBatchAuctions));
	end

	if (not gGetAllSuccess) then
		zc.msg (" ");
		zc.msg_anm ("|cffff3333Warning:|r Blizzard server failed to return all items: ", gGetAllTotalAuctions, gGetAllNumBatchAuctions);
		zc.msg_anm ("You might want to try slow scanning.");
	end
		
	zc.msg (" ");
end

