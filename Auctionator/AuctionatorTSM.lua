local addonName, addonTable = ...
local zc = addonTable and addonTable.zc

-- Auctionator and TSM_AuctionDB keep separate saved-variable databases.  The
-- Ascension TSM build exposes a scan importer, so a completed Auctionator full
-- scan can also be processed by TSM's own market-value code.  This bridge is
-- entirely optional and remains dormant when TSM_AuctionDB is not loaded.

local gTSMScanImporter = nil
local gTSMScanAuctions = nil
local gTSMScanAuctionCount = 0
local gTSMScanItemCount = 0

local function Atr_TSMScanBridge_Reset()
	gTSMScanImporter = nil
	gTSMScanAuctions = nil
	gTSMScanAuctionCount = 0
	gTSMScanItemCount = 0
end

local function Atr_TSMScanBridge_GetImporter()
	if (not LibStub) then
		return nil
	end

	local aceAddon = LibStub("AceAddon-3.0", true)
	if (not aceAddon or type(aceAddon.GetAddon) ~= "function") then
		return nil
	end

	local auctionDB = aceAddon:GetAddon("TSM_AuctionDB", true)
	if (not auctionDB or type(auctionDB.GetModule) ~= "function") then
		return nil
	end

	local scanModule = auctionDB:GetModule("Scan", true)
	if (scanModule and type(scanModule.ProcessImportedData) == "function") then
		return scanModule
	end

	return nil
end

function Atr_TSMScanBridge_Begin()
	Atr_TSMScanBridge_Reset()

	local importer = Atr_TSMScanBridge_GetImporter()
	if (not importer) then
		return false
	end

	gTSMScanImporter = importer
	gTSMScanAuctions = {}
	return true
end

-- Records are staged one Auctionator page/chunk at a time.  A record contains
-- the item link, per-item buyout and stack quantity.  TSM v2 deliberately keys
-- AuctionDB by base item ID, so Ascension variants sharing an ID are merged here
-- exactly as they would be by TSM's own scanner.

function Atr_TSMScanBridge_AddRecords(records)
	if (not gTSMScanImporter or type(gTSMScanAuctions) ~= "table" or type(records) ~= "table") then
		return
	end

	local _, record
	for _, record in ipairs(records) do
		local itemLink = record[1]
		local itemPrice = record[2]
		local count = record[3]
		local itemID = type(itemLink) == "string" and tonumber(string.match(itemLink, "item:(%d+)")) or nil

		if (itemID and itemID > 0 and type(itemPrice) == "number" and itemPrice > 0 and type(count) == "number" and count > 0) then
			local auctions = gTSMScanAuctions[itemID]
			if (not auctions) then
				auctions = {}
				gTSMScanAuctions[itemID] = auctions
				gTSMScanItemCount = gTSMScanItemCount + 1
			end

			auctions[#auctions + 1] = {itemPrice, count}
			gTSMScanAuctionCount = gTSMScanAuctionCount + 1
		end
	end
end

function Atr_TSMScanBridge_Abort()
	Atr_TSMScanBridge_Reset()
end

function Atr_TSMScanBridge_Finish()
	local importer = gTSMScanImporter
	local auctions = gTSMScanAuctions
	local auctionCount = gTSMScanAuctionCount
	local itemCount = gTSMScanItemCount

	Atr_TSMScanBridge_Reset()

	if (not importer or type(auctions) ~= "table" or itemCount == 0) then
		return false
	end

	-- Let TSM calculate DBMarket, DBMinBuyout, quantity and scan age using its
	-- native algorithms, and let it encode/persist the result itself.
	local ok, errorMessage = pcall(importer.ProcessImportedData, importer, auctions)
	if (not ok) then
		if (zc and zc.msg_badErr) then
			zc.msg_badErr("TSM AuctionDB sync failed:", tostring(errorMessage))
		end
		return false
	end

	if (zc and zc.msg_anm) then
		zc.msg_anm(string.format("TSM AuctionDB update started: %d auction rows across %d items.", auctionCount, itemCount))
	end

	return true
end
