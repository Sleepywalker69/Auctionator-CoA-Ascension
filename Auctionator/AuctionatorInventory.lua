local addonName, addonTable = ...
local zc = addonTable.zc

local ROW_COUNT        = 8
local ROW_HEIGHT       = 25
local MARKET_ROW_COUNT = 8
local MARKET_ROW_HEIGHT = 23

local inventoryFrame
local inventoryScroll
local inventoryRows = {}
local marketScroll
local marketRows = {}
local inventoryItems = {}
local selectedItems = {}
local inventoryDirty = true
local nextInventoryRefresh = 0

local queue = {
	state = "IDLE",
	groups = {},
	index = 0,
	postedQuantity = 0,
	listedValue = 0,
	itemInSellSlot = false,
}

local BuildInventoryList
local RefreshInventoryDisplay
local UpdateControls
local PrepareCurrentQueueItem
local ProcessAuctionPage
local RefreshMarketDisplay
local SetQueueStatus
local CurrentGroup

-----------------------------------------

local function PriceText(price)
	if type(price) ~= "number" then
		return "No data"
	end
	if price <= 0 then return "0c" end

	local text = zc.priceToString(price)
	if text == "" then return "0c" end
	return text
end

-----------------------------------------

local function CompactPriceText(price)
	if type(price) ~= "number" then return "No data" end
	price = math.max(0, math.floor(price))
	local gold = math.floor(price / 10000)
	local silver = math.floor((price % 10000) / 100)
	local copper = price % 100

	if gold > 0 then
		if gold < 100 and silver > 0 then return string.format("%dg %ds", gold, silver) end
		return tostring(gold).."g"
	elseif silver > 0 then
		if copper > 0 then return string.format("%ds %dc", silver, copper) end
		return tostring(silver).."s"
	end
	return tostring(copper).."c"
end

-----------------------------------------

local function PositiveInteger(value, fallback)
	value = math.floor(tonumber(value) or 0)
	if value < 1 then return fallback end
	return value
end

-----------------------------------------

local function SetEditNumber(editBox, value, showZero)
	if not editBox then return end
	value = math.floor(tonumber(value) or 0)
	if value == 0 and not showZero then
		editBox:SetText("")
	else
		editBox:SetText(tostring(value))
	end
end

-----------------------------------------

local function GetUnitPriceCopper()
	if not inventoryFrame or not inventoryFrame.priceGold then return 0 end
	local gold = math.max(0, math.floor(tonumber(inventoryFrame.priceGold:GetText()) or 0))
	local silver = math.max(0, math.floor(tonumber(inventoryFrame.priceSilver:GetText()) or 0))
	local copper = math.max(0, math.floor(tonumber(inventoryFrame.priceCopper:GetText()) or 0))
	return (gold * 10000) + (silver * 100) + copper
end

-----------------------------------------

local function SetUnitPriceCopper(price)
	if not inventoryFrame or not inventoryFrame.priceGold then return end
	price = math.max(0, math.floor(tonumber(price) or 0))
	SetEditNumber(inventoryFrame.priceGold, math.floor(price / 10000), false)
	SetEditNumber(inventoryFrame.priceSilver, math.floor((price % 10000) / 100), true)
	SetEditNumber(inventoryFrame.priceCopper, price % 100, true)
end

-----------------------------------------

local function NormalizeMoneyInputs()
	SetUnitPriceCopper(GetUnitPriceCopper())
	UpdateControls()
end

-----------------------------------------

local function InventoryItemKey(name, variantKey, link)
	return (name or "?").."||"..(variantKey or link or "?")
end

-----------------------------------------

local function GetStoredPrice(item)
	local info = type(gAtr_ScanDB) == "table" and gAtr_ScanDB[item.name] or nil

	if type(info) == "table" then
		if type(info.vmr) == "table" and type(info.vmr[item.variantKey]) == "number" then
			return info.vmr[item.variantKey], "exact variant"
		end

		local qkey = tostring(item.quality or -1)
		if type(info.qmr) == "table" and type(info.qmr[qkey]) == "number" then
			return info.qmr[qkey], "same rarity"
		end

		if type(info.mr) == "number" then
			return info.mr, "item-name scan"
		end
	end

	if Atr_GetMostRecentSale then
		local historical = Atr_GetMostRecentSale(item.name)
		if type(historical) == "number" and historical > 0 then
			return historical, "posting history"
		end
	end

	return nil, "no market data"
end

-----------------------------------------

local function ReadBagItem(bag, slot)
	local texture, count, locked = GetContainerItemInfo(bag, slot)
	local link = GetContainerItemLink(bag, slot)

	if not link then return nil, false end

	local auctionable, ready = Atr_BagItem_IsAuctionable(bag, slot, link)
	if not ready then return nil, false end
	if not auctionable then return nil, true end

	local name, cachedLink, quality, itemLevel, _, _, _, maxStack, _, itemTexture = GetItemInfo(link)
	if not name then return nil, false end

	link = cachedLink or link
	quality = quality or 0
	itemLevel = itemLevel or 0
	count = count or 1

	local variantKey = Atr_GetItemVariantKey(link, quality, itemLevel)
	local key = InventoryItemKey(name, variantKey, link)

	return {
		key = key,
		name = name,
		link = link,
		quality = quality,
		itemLevel = itemLevel,
		maxStack = maxStack or 1,
		variantKey = variantKey,
		texture = texture or itemTexture,
		count = count,
		locked = locked,
		bag = bag,
		slot = slot,
	}, true
end

-----------------------------------------

BuildInventoryList = function()
	local grouped = {}
	local anyNotReady = false
	local bag, slot

	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local bagItem, ready = ReadBagItem(bag, slot)

			if bagItem then
				local item = grouped[bagItem.key]
				if not item then
					item = bagItem
					item.quantity = 0
					item.slots = {}
					grouped[item.key] = item
				end

				item.quantity = item.quantity + bagItem.count
				item.slots[#item.slots + 1] = {
					bag = bag,
					slot = slot,
					count = bagItem.count,
				}
			elseif not ready then
				anyNotReady = true
			end
		end
	end

	inventoryItems = {}
	local key, item
	for key,item in pairs(grouped) do
		item.unitPrice, item.priceSource = GetStoredPrice(item)
		item.totalValue = item.unitPrice and (item.unitPrice * item.quantity) or nil
		inventoryItems[#inventoryItems + 1] = item
	end

	table.sort(inventoryItems, function(a, b)
		local av = a.totalValue or -1
		local bv = b.totalValue or -1
		if av ~= bv then return av > bv end
		if a.quality ~= b.quality then return a.quality > b.quality end
		return string.lower(a.name) < string.lower(b.name)
	end)

	local retained = {}
	for _,item in ipairs(inventoryItems) do
		if selectedItems[item.key] then retained[item.key] = true end
	end
	selectedItems = retained

	inventoryDirty = anyNotReady
end

-----------------------------------------

local function SelectionSummary()
	local variants = 0
	local quantity = 0
	local value = 0
	local missingPrices = 0

	for _,item in ipairs(inventoryItems) do
		if selectedItems[item.key] then
			variants = variants + 1
			quantity = quantity + item.quantity
			if item.totalValue then
				value = value + item.totalValue
			else
				missingPrices = missingPrices + 1
			end
		end
	end

	return variants, quantity, value, missingPrices
end

-----------------------------------------

local function SetSelection(item, selected)
	if not item then return end
	if queue.state ~= "IDLE" and queue.state ~= "COMPLETE" then
		RefreshInventoryDisplay()
		return
	end

	selectedItems[item.key] = selected and true or nil
	RefreshInventoryDisplay()
end

-----------------------------------------

local function ShowItemTooltip(row)
	local item = row.inventoryItem
	if not item then return end

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if item.bag ~= nil and item.slot ~= nil and GetContainerItemLink(item.bag, item.slot) then
		GameTooltip:SetBagItem(item.bag, item.slot)
	else
		GameTooltip:SetHyperlink(item.link)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Estimated unit value: "..PriceText(item.unitPrice), 0.75, 0.85, 1)
	GameTooltip:AddLine("Source: "..item.priceSource, 0.65, 0.65, 0.65)
	GameTooltip:Show()
end

-----------------------------------------

local function ShowMarketTooltip(row)
	local auction = row.marketAuction
	if not auction then return end

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if auction.link then GameTooltip:SetHyperlink(auction.link) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Per item: "..PriceText(auction.unitPrice), 0.75, 0.85, 1)
	GameTooltip:AddLine(string.format("Stack: %d   Buyout: %s", auction.stackSize, PriceText(auction.buyoutPrice)), 0.75, 0.85, 1)
	GameTooltip:AddLine(string.format("%d matching auction%s from %s", auction.auctionCount, auction.auctionCount == 1 and "" or "s", auction.yours and "you" or (auction.owner or "unknown seller")), 0.65, 0.65, 0.65)
	if auction.suspicious then
		GameTooltip:AddLine("Possible low-price outlier; Auctionator did not use it for the recommendation.", 1, 0.35, 0.25, true)
		GameTooltip:AddLine("Click to use it anyway.", 0.3, 1, 0.3)
	else
		GameTooltip:AddLine("Click to use this per-item price.", 0.3, 1, 0.3)
	end
	GameTooltip:Show()
end

-----------------------------------------

local function UseMarketPrice(row)
	local auction = row.marketAuction
	if not auction or (queue.state ~= "READY" and queue.state ~= "PAUSED") then return end

	local group = CurrentGroup()
	SetUnitPriceCopper(auction.unitPrice)
	if group then group.unitPrice = auction.unitPrice end
	SetQueueStatus(string.format("Manual price selected: %s each from the matching-auctions list.", PriceText(auction.unitPrice)))
	UpdateControls()
end

-----------------------------------------

RefreshMarketDisplay = function()
	if not inventoryFrame or not marketScroll then return end

	local rows = queue.marketRows or {}
	FauxScrollFrame_Update(marketScroll, #rows, MARKET_ROW_COUNT, MARKET_ROW_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(marketScroll)
	local index

	for index = 1, MARKET_ROW_COUNT do
		local row = marketRows[index]
		local auction = rows[offset + index]
		row.marketAuction = auction

		if auction then
			row.each:SetText(CompactPriceText(auction.unitPrice))
			row.stack:SetText(tostring(auction.stackSize))
			row.count:SetText(tostring(auction.auctionCount))
			row.seller:SetText(auction.yours and "You" or (auction.owner or "Unknown"))

			if auction.suspicious then
				row.each:SetTextColor(1, 0.3, 0.2)
				row.stack:SetTextColor(1, 0.3, 0.2)
				row.count:SetTextColor(1, 0.3, 0.2)
				row.seller:SetTextColor(1, 0.3, 0.2)
			elseif auction.yours then
				row.each:SetTextColor(0.3, 1, 0.3)
				row.stack:SetTextColor(0.3, 1, 0.3)
				row.count:SetTextColor(0.3, 1, 0.3)
				row.seller:SetTextColor(0.3, 1, 0.3)
			else
				row.each:SetTextColor(1, 1, 1)
				row.stack:SetTextColor(1, 1, 1)
				row.count:SetTextColor(1, 1, 1)
				row.seller:SetTextColor(1, 1, 1)
			end
			row:Show()
		else
			row:Hide()
		end
	end

	local group = CurrentGroup()
	if group and queue.state ~= "IDLE" and queue.state ~= "COMPLETE" then
		local levelText = group.itemLevel and group.itemLevel > 0 and (" (iLvl "..group.itemLevel..")") or ""
		inventoryFrame.marketTitle:SetText("Matching auctions: "..group.name..levelText)
	elseif queue.state == "COMPLETE" then
		inventoryFrame.marketTitle:SetText("Matching live auctions")
	else
		inventoryFrame.marketTitle:SetText("Matching live auctions")
	end

	if #rows == 0 then
		if queue.state == "WAIT_SEND" or queue.state == "WAIT_RESULT" or queue.state == "REPROCESS_PAGE" then
			inventoryFrame.marketHint:SetText("Scanning every page for the exact rarity and item variant...")
		elseif group and queue.state == "READY" then
			inventoryFrame.marketHint:SetText("No matching buyout auctions found. Enter your own price below.")
		else
			inventoryFrame.marketHint:SetText("Start a queue to load competing auctions for the current item.")
		end
	else
		inventoryFrame.marketHint:SetText("Click a row to copy its per-item price. Red rows are suspicious outliers; green rows are yours.")
	end
end

-----------------------------------------

RefreshInventoryDisplay = function()
	if not inventoryFrame then return end

	if inventoryDirty then BuildInventoryList() end

	FauxScrollFrame_Update(inventoryScroll, #inventoryItems, ROW_COUNT, ROW_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(inventoryScroll)
	local selectionLocked = queue.state ~= "IDLE" and queue.state ~= "COMPLETE"
	local rowIndex

	for rowIndex = 1, ROW_COUNT do
		local row = inventoryRows[rowIndex]
		local item = inventoryItems[offset + rowIndex]
		row.inventoryItem = item

		if item then
			row.check:SetChecked(selectedItems[item.key] and true or false)
			if selectionLocked then row.check:Disable() else row.check:Enable() end
			row.icon:SetTexture(item.texture)
			row.name:SetText(item.name)

			local color = ITEM_QUALITY_COLORS[item.quality]
			if color then
				row.name:SetTextColor(color.r, color.g, color.b)
			else
				row.name:SetTextColor(1, 1, 1)
			end

			row.level:SetText(item.itemLevel > 0 and tostring(item.itemLevel) or "-")
			row.quantity:SetText(tostring(item.quantity))
			row.unitPrice:SetText(CompactPriceText(item.unitPrice))
			row.totalValue:SetText(CompactPriceText(item.totalValue))
			row:Show()
		else
			row:Hide()
		end
	end

	local variants, quantity, value, missing = SelectionSummary()
	local summary = string.format("Selected: %d variants / %d items   Estimated value: %s", variants, quantity, PriceText(value))
	if missing > 0 then summary = summary..string.format("   (%d without price data)", missing) end
	inventoryFrame.selectionSummary:SetText(summary)

	RefreshMarketDisplay()
	UpdateControls()
end

-----------------------------------------

SetQueueStatus = function(text, isError)
	if not inventoryFrame then return end
	inventoryFrame.queueStatus:SetText(text or "")
	if isError then
		inventoryFrame.queueStatus:SetTextColor(1, 0.35, 0.25)
	else
		inventoryFrame.queueStatus:SetTextColor(1, 0.82, 0)
	end
end

-----------------------------------------

CurrentGroup = function()
	return queue.groups[queue.index]
end

-----------------------------------------

local function FindBagSlot(group, requiredCount)
	if not group then return nil end
	requiredCount = math.max(1, math.floor(tonumber(requiredCount) or 1))

	local bestBag, bestSlot, bestCount, bestLink
	local bag, slot
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local bagItem = ReadBagItem(bag, slot)
			if bagItem and bagItem.key == group.key and not bagItem.locked and bagItem.count >= requiredCount then
				-- Prefer the smallest stack which can satisfy the request.  This leaves
				-- larger physical stacks available for later queue entries.
				if not bestCount or bagItem.count < bestCount then
					bestBag, bestSlot, bestCount, bestLink = bag, slot, bagItem.count, bagItem.link
				end
			end
		end
	end

	return bestBag, bestSlot, bestCount, bestLink
end

-----------------------------------------

local function BagQuantity(group)
	if not group then return 0 end
	local total = 0
	local bag, slot

	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local bagItem = ReadBagItem(bag, slot)
			if bagItem and bagItem.key == group.key then
				total = total + bagItem.count
			end
		end

	end

	return total
end

-----------------------------------------

local function LargestBagStack(group)
	if not group then return 0 end
	local largest = 0
	local bag, slot

	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local bagItem = ReadBagItem(bag, slot)
			if bagItem and bagItem.key == group.key and not bagItem.locked then
				largest = math.max(largest, bagItem.count or 0)
			end
		end
	end

	return largest
end

-----------------------------------------

local function GroupIsComplete(group)
	return not group or group.remaining <= 0 or group.queueComplete or
		(group.planInitialized and (group.auctionsRemaining or 0) <= 0)
end

-----------------------------------------

local function SetPlanInputs(group)
	if not inventoryFrame or not inventoryFrame.stackSize then return end
	if not group then
		SetEditNumber(inventoryFrame.stackSize, 0, false)
		SetEditNumber(inventoryFrame.numAuctions, 0, false)
		return
	end
	SetEditNumber(inventoryFrame.stackSize, group.stackSize or 1, true)
	SetEditNumber(inventoryFrame.numAuctions, group.auctionsRemaining or 1, true)
end

-----------------------------------------

local function InitializeGroupPlan(group)
	if not group or group.planInitialized then return end

	local total = math.min(group.remaining or 0, BagQuantity(group))
	local largest = LargestBagStack(group)
	local maxStack = math.max(1, math.min(group.maxStack or largest or 1, largest, total))
	local numStacks, stackSize

	if Atr_GetSellStacking and group.link then
		numStacks, stackSize = Atr_GetSellStacking(group.link, largest, total)
	end

	stackSize = PositiveInteger(stackSize, maxStack)
	stackSize = math.max(1, math.min(stackSize, maxStack))
	local maxAuctions = math.max(1, math.floor(total / stackSize))
	numStacks = PositiveInteger(numStacks, 1)
	numStacks = math.max(1, math.min(numStacks, maxAuctions))

	group.stackSize = stackSize
	group.auctionsRemaining = numStacks
	group.planInitialized = true
end

-----------------------------------------

local function ReadPostingPlan(group)
	if not group or not inventoryFrame then return nil end

	local stackSize = PositiveInteger(inventoryFrame.stackSize:GetText())
	local numAuctions = PositiveInteger(inventoryFrame.numAuctions:GetText())
	if not stackSize then return nil, "Enter a stack size of at least 1." end
	if not numAuctions then return nil, "Enter at least 1 auction to post." end

	local available = math.min(group.remaining or 0, BagQuantity(group))
	local itemMax = math.max(1, group.maxStack or 1)
	if stackSize > itemMax then
		return nil, string.format("%s can only be posted in stacks of %d or fewer.", group.name, itemMax)
	end
	if stackSize > LargestBagStack(group) then
		return nil, string.format("No unlocked bag stack contains %d of %s. Use Stack Max or rearrange the stack in your bags.", stackSize, group.name)
	end
	if stackSize * numAuctions > available then
		return nil, string.format("Only %d are available. At stack size %d, the maximum is %d auctions.", available, stackSize, math.floor(available / stackSize))
	end

	return stackSize, numAuctions
end

-----------------------------------------

local function PostSucceededByEvidence()
	local group = CurrentGroup()
	return queue.itemInSellSlot and queue.ownedUpdateSeen and not GetAuctionSellItemInfo() and
		group and queue.currentPostCount and queue.quantityBefore and
		BagQuantity(group) <= queue.quantityBefore - queue.currentPostCount
end

-----------------------------------------

local function FinishQueue()
	queue.state = "COMPLETE"
	queue.itemInSellSlot = false
	SetQueueStatus(string.format("Queue complete: listed %d items for %s total buyout.", queue.postedQuantity, PriceText(queue.listedValue)))
	SetUnitPriceCopper(0)
	SetPlanInputs(nil)
	inventoryDirty = true
	RefreshMarketDisplay()
	RefreshInventoryDisplay()
end

-----------------------------------------

local function PauseQueue(message)
	queue.state = "PAUSED"
	queue.lastError = message or "The posting queue was paused."
	SetQueueStatus(queue.lastError.." Nothing was counted; retry or skip this item.", true)
	if inventoryFrame and not inventoryFrame:IsShown() and zc and zc.msg_yellow then
		zc.msg_yellow("Auctionator Inventory queue paused: "..queue.lastError.." Return to the Inventory tab to retry or stop it.")
	end
	UpdateControls()
end

-----------------------------------------

local function QueryNameForGroup(group)
	local queryName = group.name
	if AUCTIONATOR_ROMOVE_BLOOFORGED == 1 then
		queryName = string.gsub(queryName, "^Bloodforged%s+", "")
	end
	return zc.UTF8_Truncate(queryName, 63)
end

-----------------------------------------

local function SendQueueQuery()
	local group = CurrentGroup()
	if not group or queue.state ~= "WAIT_SEND" then return end

	if gAtr_FullScanState and ATR_FS_NULL and gAtr_FullScanState ~= ATR_FS_NULL then
		PauseQueue("Wait for the full scan to finish before running the post queue.")
		return
	end

	if not CanSendAuctionQuery() then return end

	QueryAuctionItems(QueryNameForGroup(group), nil, nil, nil, nil, nil, queue.scanPage, nil, group.quality, false)
	queue.state = "WAIT_RESULT"
	queue.querySentAt = GetTime()
	SetQueueStatus(string.format("Queue %d/%d: scanning %s (page %d)...", queue.index, #queue.groups, group.name, queue.scanPage + 1))
	UpdateControls()
end

-----------------------------------------

local function MergeMarketAuction(auction)
	if not auction or not auction.unitPrice then return end
	queue.marketMap = queue.marketMap or {}

	local ownerKey = auction.owner or "?"
	local key = tostring(auction.unitPrice).."|"..tostring(auction.stackSize).."|"..ownerKey
	local existing = queue.marketMap[key]
	if existing then
		existing.auctionCount = existing.auctionCount + auction.auctionCount
		existing.buyoutPrice = math.min(existing.buyoutPrice, auction.buyoutPrice)
	else
		queue.marketMap[key] = auction
	end
end

-----------------------------------------

local function BuildSortedMarketRows()
	queue.marketRows = {}
	local _, auction
	for _,auction in pairs(queue.marketMap or {}) do
		queue.marketRows[#queue.marketRows + 1] = auction
	end

	table.sort(queue.marketRows, function(a, b)
		if a.unitPrice ~= b.unitPrice then return a.unitPrice < b.unitPrice end
		if a.stackSize ~= b.stackSize then return a.stackSize < b.stackSize end
		if a.yours ~= b.yours then return a.yours end
		return (a.owner or "") < (b.owner or "")
	end)
end

-----------------------------------------

local function GetSafeCompetitorPrice()
	local priceCounts = {}
	local prices = {}
	local _, auction

	for _,auction in ipairs(queue.marketRows or {}) do
		if not auction.yours then
			if not priceCounts[auction.unitPrice] then
				priceCounts[auction.unitPrice] = 0
				prices[#prices + 1] = auction.unitPrice
			end
			priceCounts[auction.unitPrice] = priceCounts[auction.unitPrice] + auction.auctionCount
		end
	end

	table.sort(prices)
	local lowest = prices[1]
	local nextPrice = prices[2]
	local ignoredOutlier = false

	-- A single typo-priced auction should be visible without automatically
	-- dragging every queued post down with it.  Only skip a very strong outlier:
	-- at most two auction rows priced below one quarter of the next tier.
	if lowest and nextPrice and priceCounts[lowest] <= 2 and lowest * 4 < nextPrice then
		ignoredOutlier = true
		for _,auction in ipairs(queue.marketRows) do
			if not auction.yours and auction.unitPrice == lowest then auction.suspicious = true end
		end
		return nextPrice, ignoredOutlier, lowest
	end

	return lowest, ignoredOutlier
end

-----------------------------------------

local function FinishMarketScan()
	local group = CurrentGroup()
	if not group then return end

	BuildSortedMarketRows()
	local competitorPrice, ignoredOutlier, outlierPrice = GetSafeCompetitorPrice()
	local proposedPrice
	local source

	if queue.bestOwnPrice and queue.bestOwnPrice > 0 and
		(not competitorPrice or queue.bestOwnPrice <= competitorPrice) then
		proposedPrice = queue.bestOwnPrice
		source = "your lowest matching auction"
		Atr_UpdateScanDBVariantPrice(group.name, group.quality, group.variantKey, queue.bestOwnPrice)
	elseif competitorPrice and competitorPrice > 0 then
		proposedPrice = math.max(1, Atr_CalcUndercutPrice(competitorPrice))
		if ignoredOutlier then
			source = "next price tier; ignored isolated "..PriceText(outlierPrice).." outlier"
		else
			source = "lowest matching live auction"
		end
		Atr_UpdateScanDBVariantPrice(group.name, group.quality, group.variantKey, competitorPrice)
	else
		proposedPrice, source = GetStoredPrice(group)
	end

	group.unitPrice = proposedPrice
	group.recommendedPrice = proposedPrice
	group.marketScanned = true
	queue.state = "READY"
	queue.currentPostCount = group.stackSize or 1

	SetUnitPriceCopper(proposedPrice or 0)
	SetPlanInputs(group)

	if proposedPrice and proposedPrice > 0 then
		SetQueueStatus(string.format("Queue %d/%d ready: %d auction%s of %s x%d at %s each (%s).", queue.index, #queue.groups, group.auctionsRemaining, group.auctionsRemaining == 1 and "" or "s", group.name, group.stackSize, PriceText(proposedPrice), source))
	else
		SetQueueStatus(string.format("Queue %d/%d: no price for %s. Enter a per-item buyout, then post or skip it.", queue.index, #queue.groups, group.name), true)
	end

	RefreshMarketDisplay()
	UpdateControls()
end

-----------------------------------------

ProcessAuctionPage = function()
	if queue.state ~= "WAIT_RESULT" and queue.state ~= "REPROCESS_PAGE" then return end

	local group = CurrentGroup()
	if not group then return end

	local numOnPage, totalAuctions = Atr_GetNumAuctionItems("list")
	local incomplete = false
	local pageBestCompetitorPrice
	local pageBestOwnPrice
	local pageBestUnknownPrice
	local pageMarketMap = {}
	local index

	for index = 1, numOnPage do
		local name, _, count, quality, _, level, _, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", index)
		local link = GetAuctionItemLink("list", index)
		if owner == "" then owner = nil end

		if name == nil then
			incomplete = true
		elseif count and count > 0 and buyoutPrice and buyoutPrice > 0 then
			if not link then
				incomplete = true
			else
				local _, _, cachedQuality, cachedLevel = GetItemInfo(link)
				quality = cachedQuality or quality
				level = cachedLevel or level
				local variantKey = Atr_GetItemVariantKey(link, quality, level)

				if variantKey == group.variantKey then
					local unitPrice = math.floor(buyoutPrice / count)
					if unitPrice > 0 then
						local marketOwner = owner
						local marketKey = tostring(unitPrice).."|"..tostring(count).."|"..(marketOwner or "?")
						local marketAuction = pageMarketMap[marketKey]
						if marketAuction then
							marketAuction.auctionCount = marketAuction.auctionCount + 1
							marketAuction.buyoutPrice = math.min(marketAuction.buyoutPrice, buyoutPrice)
						else
							pageMarketMap[marketKey] = {
								unitPrice = unitPrice,
								buyoutPrice = buyoutPrice,
								stackSize = count,
								auctionCount = 1,
								owner = marketOwner,
								yours = marketOwner == UnitName("player"),
								link = link,
							}
						end

						if owner == nil then
							-- Owner names often stream in after the rest of an auction row.
							-- Do not permanently classify a temporarily unknown auction as
							-- somebody else's and undercut our own listing.
							incomplete = true
							pageBestUnknownPrice = math.min(pageBestUnknownPrice or unitPrice, unitPrice)
						elseif owner == UnitName("player") then
							pageBestOwnPrice = math.min(pageBestOwnPrice or unitPrice, unitPrice)
						else
							pageBestCompetitorPrice = math.min(pageBestCompetitorPrice or unitPrice, unitPrice)
						end
					end
				end
			end
		end
	end

	queue.pageReads = (queue.pageReads or 0) + 1
	if incomplete and queue.pageReads < 6 then
		queue.state = "REPROCESS_PAGE"
		queue.reprocessAt = GetTime() + 0.12
		return
	end

	-- If the server never supplied an owner after all soft reads, price the row
	-- conservatively as a competitor. Page-local values are only committed now,
	-- so an early incomplete read cannot contaminate the final result.
	if pageBestUnknownPrice then
		pageBestCompetitorPrice = math.min(pageBestCompetitorPrice or pageBestUnknownPrice, pageBestUnknownPrice)
	end
	if pageBestCompetitorPrice then
		queue.bestCompetitorPrice = math.min(queue.bestCompetitorPrice or pageBestCompetitorPrice, pageBestCompetitorPrice)
	end
	if pageBestOwnPrice then
		queue.bestOwnPrice = math.min(queue.bestOwnPrice or pageBestOwnPrice, pageBestOwnPrice)
	end
	local _, marketAuction
	for _,marketAuction in pairs(pageMarketMap) do MergeMarketAuction(marketAuction) end

	queue.queryRetries = 0
	queue.pageReads = 0
	local totalPages = math.max(1, math.ceil((totalAuctions or numOnPage) / 50))
	if numOnPage > 0 and queue.scanPage + 1 < totalPages then
		queue.scanPage = queue.scanPage + 1
		queue.state = "WAIT_SEND"
		SendQueueQuery()
	else
		FinishMarketScan()
	end
	RefreshMarketDisplay()
end

-----------------------------------------

PrepareCurrentQueueItem = function(reusePrice)
	while queue.index <= #queue.groups and GroupIsComplete(queue.groups[queue.index]) do
		queue.index = queue.index + 1
	end

	if queue.index > #queue.groups then
		FinishQueue()
		return
	end

	local group = CurrentGroup()
	InitializeGroupPlan(group)
	SetPlanInputs(group)

	local bag, slot, slotCount, link = FindBagSlot(group, group.stackSize)
	if not bag then
		if BagQuantity(group) > 0 then
			PauseQueue(string.format("No unlocked bag stack can supply %s x%d. Lower Stack size or rearrange the item in your bags.", group.name, group.stackSize))
		else
			PauseQueue("Selected item is no longer available in your bags: "..group.name..".")
		end
		return
	end

	queue.currentBag = bag
	queue.currentSlot = slot
	queue.currentLink = link
	queue.currentPostCount = math.min(group.stackSize, slotCount, group.remaining)
	queue.quantityBefore = BagQuantity(group)
	queue.lastError = nil
	queue.ownedUpdateSeen = false
	queue.postSentAt = nil

	if reusePrice and group.unitPrice and group.unitPrice > 0 then
		queue.state = "READY"
		SetUnitPriceCopper(group.unitPrice)
		SetPlanInputs(group)
		SetQueueStatus(string.format("Queue %d/%d ready: %d auction%s remaining, %s x%d at %s each.", queue.index, #queue.groups, group.auctionsRemaining, group.auctionsRemaining == 1 and "" or "s", group.name, group.stackSize, PriceText(group.unitPrice)))
		RefreshMarketDisplay()
		UpdateControls()
		return
	end

	queue.bestCompetitorPrice = nil
	queue.bestOwnPrice = nil
	queue.marketMap = {}
	queue.marketRows = {}
	queue.scanPage = 0
	queue.queryRetries = 0
	queue.pageReads = 0
	queue.state = "WAIT_SEND"
	SetUnitPriceCopper(0)
	RefreshMarketDisplay()
	SendQueueQuery()
	UpdateControls()
end

-----------------------------------------

local function MarkPostSuccessful(stopAfterSuccess)
	if queue.state ~= "WAIT_CONFIRM" then return end

	local group = CurrentGroup()
	if not group then return end

	group.remaining = math.max(0, group.remaining - queue.currentPostCount)
	group.auctionsRemaining = math.max(0, (group.auctionsRemaining or 1) - 1)
	group.unitPrice = queue.currentUnitPrice
	queue.postedQuantity = queue.postedQuantity + queue.currentPostCount
	queue.listedValue = queue.listedValue + queue.currentBuyout
	queue.itemInSellSlot = false

	if Atr_LogMsg then
		Atr_LogMsg(queue.currentLink, queue.currentPostCount, queue.currentBuyout, 1)
	end
	if Atr_AddHistoricalPrice then
		Atr_AddHistoricalPrice(group.name, queue.currentUnitPrice, queue.currentPostCount, queue.currentLink)
	end

	if group.remaining <= 0 or group.auctionsRemaining <= 0 or group.remaining < (group.stackSize or 1) then
		group.queueComplete = true
		selectedItems[group.key] = nil
	end

	if stopAfterSuccess then
		queue.state = "IDLE"
		queue.groups = {}
		queue.index = 0
		SetUnitPriceCopper(0)
		SetPlanInputs(nil)
		inventoryDirty = true
		SetQueueStatus(string.format("Confirmed: listed %s x%d. Queue stopped; remaining selections were kept.", group.name, queue.currentPostCount))
		RefreshInventoryDisplay()
		return
	end

	queue.state = "ADVANCING"
	queue.advanceAt = GetTime() + 0.6
	inventoryDirty = true
	SetPlanInputs(group)
	if GroupIsComplete(group) then
		SetQueueStatus(string.format("Confirmed: listed %s x%d. Moving to the next selected item...", group.name, queue.currentPostCount))
	else
		SetQueueStatus(string.format("Confirmed: listed %s x%d. %d auction%s remain in this plan.", group.name, queue.currentPostCount, group.auctionsRemaining, group.auctionsRemaining == 1 and "" or "s"))
	end
	UpdateControls()
end

-----------------------------------------

local function ClearLoadedAuctionItem()
	if not GetAuctionSellItemInfo() then return true end

	ClearCursor()
	ClickAuctionSellItemButton()
	ClearCursor()
	return GetAuctionSellItemInfo() == nil
end

-----------------------------------------

local function ReturnAuctionItemToBags()
	if not queue.itemInSellSlot then return end
	if not GetAuctionSellItemInfo() then
		queue.itemInSellSlot = false
		return
	end

	ClearCursor()
	ClickAuctionSellItemButton()
	if GetCursorInfo() == "item" then
		if queue.currentBag ~= nil and queue.currentSlot ~= nil and not GetContainerItemLink(queue.currentBag, queue.currentSlot) then
			PickupContainerItem(queue.currentBag, queue.currentSlot)
		elseif PutItemInBackpack then
			PutItemInBackpack()
		end
	end
	ClearCursor()
	queue.itemInSellSlot = GetAuctionSellItemInfo() ~= nil
end

-----------------------------------------

local function PostCurrentStack()
	if queue.state ~= "READY" then return end

	local group = CurrentGroup()
	local unitPrice = GetUnitPriceCopper()
	if not group or not unitPrice or unitPrice <= 0 then
		SetQueueStatus("Enter a per-item buyout price before posting this stack.", true)
		return
	end

	local stackSize, numAuctionsOrError = ReadPostingPlan(group)
	if not stackSize then
		SetQueueStatus(numAuctionsOrError, true)
		return
	end
	local numAuctions = numAuctionsOrError
	group.stackSize = stackSize
	group.auctionsRemaining = numAuctions
	group.queueComplete = false
	SetPlanInputs(group)

	local bag, slot, slotCount, link = FindBagSlot(group, stackSize)
	if not bag then
		PauseQueue(string.format("No unlocked bag stack can supply %s x%d.", group.name, stackSize))
		return
	end

	local postCount = stackSize
	local buyoutPrice = unitPrice * postCount
	local startPrice = math.max(1, Atr_CalcStartPrice(buyoutPrice))
	local duration = queue.duration or (Atr_Duration and UIDropDownMenu_GetSelectedValue(Atr_Duration)) or 1
	local quantityBefore = BagQuantity(group)

	-- A Sell-tab item can remain loaded when the player moves to Inventory.
	-- Return it before loading the queue item so it cannot be swapped onto the
	-- cursor and accidentally discarded by the subsequent cursor cleanup.
	if not ClearLoadedAuctionItem() then
		SetQueueStatus("Clear the item already loaded in the auction sell slot, then click Post Next again.", true)
		return
	end

	ClearCursor()
	PickupContainerItem(bag, slot)
	if GetCursorInfo() ~= "item" then
		ClearCursor()
		PauseQueue("Auctionator could not pick up the current bag item.")
		return
	end

	ClickAuctionSellItemButton()
	ClearCursor()
	if not GetAuctionSellItemInfo() then
		PauseQueue("Auctionator could not load the current item into the auction sell slot.")
		return
	end

	if AuctionFrameAuctions and not AuctionFrameAuctions.duration then
		AuctionFrameAuctions.duration = duration
	end

	if Atr_ClearJustPostedItem then Atr_ClearJustPostedItem() end

	queue.currentBag = bag
	queue.currentSlot = slot
	queue.currentLink = link
	queue.currentPostCount = postCount
	queue.currentUnitPrice = unitPrice
	queue.currentBuyout = buyoutPrice
	queue.quantityBefore = quantityBefore
	queue.postSentAt = GetTime()
	queue.ownedUpdateSeen = false
	queue.itemInSellSlot = true
	queue.state = "WAIT_CONFIRM"

	local ok, err = pcall(StartAuction, startPrice, buyoutPrice, duration, postCount, 1)
	if not ok then
		PauseQueue("Posting failed before the server accepted it: "..tostring(err))
		return
	end

	SetQueueStatus(string.format("Posting auction 1 of %d: %s x%d for %s; waiting for server confirmation...", numAuctions, group.name, postCount, PriceText(buyoutPrice)))
	UpdateControls()
end

-----------------------------------------

local function RetryQueueItem()
	if queue.state ~= "PAUSED" then return end

	if PostSucceededByEvidence() then
		queue.state = "WAIT_CONFIRM"
		MarkPostSuccessful()
		return
	end

	local group = CurrentGroup()
	if group then
		local editedPrice = GetUnitPriceCopper()
		if editedPrice > 0 then group.unitPrice = editedPrice end
		group.stackSize = PositiveInteger(inventoryFrame.stackSize:GetText(), group.stackSize or 1)
		group.auctionsRemaining = PositiveInteger(inventoryFrame.numAuctions:GetText(), group.auctionsRemaining or 1)
		group.queueComplete = false
	end
	local reusePrice = group and group.marketScanned and group.unitPrice and group.unitPrice > 0
	ReturnAuctionItemToBags()
	PrepareCurrentQueueItem(reusePrice)
end

-----------------------------------------

local function SkipQueueItem()
	if queue.state == "IDLE" or queue.state == "COMPLETE" or queue.state == "WAIT_CONFIRM" then return end
	if queue.state == "PAUSED" and PostSucceededByEvidence() then
		local confirmedGroup = CurrentGroup()
		queue.state = "WAIT_CONFIRM"
		MarkPostSuccessful()
		if queue.state == "ADVANCING" and confirmedGroup then
			confirmedGroup.queueComplete = true
			selectedItems[confirmedGroup.key] = nil
		end
		return
	end
	if queue.state == "PAUSED" then ReturnAuctionItemToBags() end

	local group = CurrentGroup()
	if group then
		group.queueComplete = true
		selectedItems[group.key] = nil
	end

	queue.index = queue.index + 1
	inventoryDirty = true
	PrepareCurrentQueueItem(false)
end

-----------------------------------------

local function StopQueue(message, returnItem)
	if queue.state == "PAUSED" and PostSucceededByEvidence() then
		queue.state = "WAIT_CONFIRM"
		MarkPostSuccessful(true)
		return
	end

	if returnItem then ReturnAuctionItemToBags() end
	queue.state = "IDLE"
	queue.groups = {}
	queue.index = 0
	queue.currentBag = nil
	queue.currentSlot = nil
	queue.currentLink = nil
	queue.itemInSellSlot = false
	queue.marketMap = {}
	queue.marketRows = {}
	SetUnitPriceCopper(0)
	SetPlanInputs(nil)
	inventoryDirty = true
	SetQueueStatus(message or "Queue stopped. Your remaining selections were kept.")
	RefreshMarketDisplay()
	RefreshInventoryDisplay()
end

-----------------------------------------

local function StartQueue()
	if queue.state ~= "IDLE" and queue.state ~= "COMPLETE" then return end
	if not ClearLoadedAuctionItem() then
		SetQueueStatus("Clear the item already loaded in the auction sell slot, then start the queue again.", true)
		return
	end

	inventoryDirty = true
	BuildInventoryList()

	local groups = {}
	for _,item in ipairs(inventoryItems) do
		if selectedItems[item.key] then
			groups[#groups + 1] = {
				key = item.key,
				name = item.name,
				link = item.link,
				quality = item.quality,
				itemLevel = item.itemLevel,
				maxStack = item.maxStack,
				variantKey = item.variantKey,
				remaining = item.quantity,
				unitPrice = item.unitPrice,
			}
		end
	end

	if #groups == 0 then
		SetQueueStatus("Select at least one inventory item first.", true)
		return
	end

	queue.groups = groups
	queue.index = 1
	queue.postedQuantity = 0
	queue.listedValue = 0
	queue.duration = queue.duration or (Atr_Duration and UIDropDownMenu_GetSelectedValue(Atr_Duration)) or 1
	queue.itemInSellSlot = false
	queue.marketMap = {}
	queue.marketRows = {}
	queue.state = "STARTING"
	PrepareCurrentQueueItem(false)
	RefreshInventoryDisplay()
end

-----------------------------------------

local function UseRecommendedPrice()
	local group = CurrentGroup()
	if (queue.state ~= "READY" and queue.state ~= "PAUSED") or not group or not group.recommendedPrice then return end
	group.unitPrice = group.recommendedPrice
	SetUnitPriceCopper(group.recommendedPrice)
	SetQueueStatus("Restored the recommended per-item buyout: "..PriceText(group.recommendedPrice).." each.")
	UpdateControls()
end

-----------------------------------------

local function SetMaximumStackSize()
	local group = CurrentGroup()
	if (queue.state ~= "READY" and queue.state ~= "PAUSED") or not group then return end
	local available = math.min(group.remaining or 0, BagQuantity(group))
	local maximum = math.min(group.maxStack or 1, LargestBagStack(group), available)
	SetEditNumber(inventoryFrame.stackSize, math.max(1, maximum), true)
	UpdateControls()
end

-----------------------------------------

local function SetMaximumAuctionCount()
	local group = CurrentGroup()
	if (queue.state ~= "READY" and queue.state ~= "PAUSED") or not group then return end
	local stackSize = PositiveInteger(inventoryFrame.stackSize:GetText(), 1)
	local available = math.min(group.remaining or 0, BagQuantity(group))
	SetEditNumber(inventoryFrame.numAuctions, math.max(1, math.floor(available / stackSize)), true)
	UpdateControls()
end

-----------------------------------------

local function CycleDuration()
	if queue.state == "WAIT_CONFIRM" then return end
	queue.duration = (tonumber(queue.duration) or 1) + 1
	if queue.duration > 3 then queue.duration = 1 end
	local hours = queue.duration == 1 and 12 or (queue.duration == 2 and 24 or 48)
	inventoryFrame.durationButton:SetText("Duration: "..hours.."h")
end

-----------------------------------------

UpdateControls = function()
	if not inventoryFrame then return end

	local variants = SelectionSummary()
	local idle = queue.state == "IDLE" or queue.state == "COMPLETE"

	if idle and variants > 0 then inventoryFrame.startButton:Enable() else inventoryFrame.startButton:Disable() end
	if idle then
		inventoryFrame.refreshButton:Enable()
		inventoryFrame.selectAllButton:Enable()
		inventoryFrame.clearButton:Enable()
	else
		inventoryFrame.refreshButton:Disable()
		inventoryFrame.selectAllButton:Disable()
		inventoryFrame.clearButton:Disable()
	end

	local editable = queue.state == "READY" or queue.state == "PAUSED"
	local editBoxes = {
		inventoryFrame.priceGold, inventoryFrame.priceSilver, inventoryFrame.priceCopper,
		inventoryFrame.stackSize, inventoryFrame.numAuctions,
	}
	local _, editBox
	for _,editBox in ipairs(editBoxes) do
		if editable then
			editBox:Enable()
			editBox:SetTextColor(1, 1, 1)
		else
			editBox:Disable()
			editBox:SetTextColor(0.55, 0.55, 0.55)
		end
	end

	if editable and CurrentGroup() and CurrentGroup().recommendedPrice then inventoryFrame.recommendedButton:Enable() else inventoryFrame.recommendedButton:Disable() end
	if editable then
		inventoryFrame.stackMaxButton:Enable()
		inventoryFrame.auctionsMaxButton:Enable()
	else
		inventoryFrame.stackMaxButton:Disable()
		inventoryFrame.auctionsMaxButton:Disable()
	end

	inventoryFrame.postButton:SetText(queue.state == "PAUSED" and "Retry" or "Post Next")
	if queue.state == "READY" then
		local price = GetUnitPriceCopper()
		local stackSize = PositiveInteger(inventoryFrame.stackSize:GetText())
		local numAuctions = PositiveInteger(inventoryFrame.numAuctions:GetText())
		if price and price > 0 and stackSize and numAuctions then inventoryFrame.postButton:Enable() else inventoryFrame.postButton:Disable() end
	elseif queue.state == "PAUSED" then
		inventoryFrame.postButton:Enable()
	else
		inventoryFrame.postButton:Disable()
	end

	-- Skipping while a server query is outstanding can make its late response
	-- look like the next item's result, so Skip is only available at a stable
	-- decision point. Stop is safe because IDLE ignores any late response.
	if queue.state == "READY" or queue.state == "PAUSED" then
		inventoryFrame.skipButton:Enable()
	else
		inventoryFrame.skipButton:Disable()
	end

	if not idle and queue.state ~= "WAIT_CONFIRM" then
		inventoryFrame.stopButton:Enable()
	else
		inventoryFrame.stopButton:Disable()
	end

	if queue.state == "WAIT_CONFIRM" then inventoryFrame.durationButton:Disable() else inventoryFrame.durationButton:Enable() end
	local group = CurrentGroup()
	if group and group.planInitialized then
		local shownAuctions = editable and PositiveInteger(inventoryFrame.numAuctions:GetText(), group.auctionsRemaining or 0) or (group.auctionsRemaining or 0)
		local shownStack = editable and PositiveInteger(inventoryFrame.stackSize:GetText(), group.stackSize or 1) or (group.stackSize or 1)
		local shownUnitPrice = GetUnitPriceCopper()
		local perAuctionBuyout = shownUnitPrice * shownStack
		local totalBuyout = perAuctionBuyout * shownAuctions
		if shownUnitPrice > 0 then
			local totalText = zc.priceToMoneyString and zc.priceToMoneyString(totalBuyout) or PriceText(totalBuyout)
			local auctionText = zc.priceToMoneyString and zc.priceToMoneyString(perAuctionBuyout) or PriceText(perAuctionBuyout)
			inventoryFrame.buyoutTotal:SetText(string.format("Buyout total: %s   Per auction: %s", totalText, auctionText))
		else
			inventoryFrame.buyoutTotal:SetText("Buyout total: enter a per-item price")
		end
		inventoryFrame.planSummary:SetText(string.format("Plan: %d auction%s x %d = %d items. One post per click.", shownAuctions, shownAuctions == 1 and "" or "s", shownStack, shownAuctions * shownStack))
	else
		inventoryFrame.buyoutTotal:SetText("Buyout total: -")
		inventoryFrame.planSummary:SetText("Posts are submitted one at a time and counted only after server confirmation.")
	end
end

-----------------------------------------

local function CreateButton(name, parent, text, width, x, y, callback)
	local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	button:SetWidth(width)
	button:SetHeight(22)
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	button:SetText(text)
	button:SetScript("OnClick", callback)
	return button
end

-----------------------------------------

local function CreateNumericEditBox(name, parent, width, x, y, maxLetters, commitCallback)
	local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	editBox:SetWidth(width)
	editBox:SetHeight(20)
	editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	editBox:SetAutoFocus(false)
	if editBox.SetNumeric then editBox:SetNumeric(true) end
	editBox:SetMaxLetters(maxLetters or 6)
	editBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if commitCallback then commitCallback(self) end
	end)
	editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	editBox:SetScript("OnEditFocusLost", function(self)
		if commitCallback then commitCallback(self) end
	end)
	editBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then UpdateControls() end
	end)
	return editBox
end

-----------------------------------------

local function CreateTextLabel(parent, text, x, y, width, justify, fontObject)
	local label = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	if width then label:SetWidth(width) end
	label:SetJustifyH(justify or "LEFT")
	label:SetText(text)
	return label
end

-----------------------------------------

local function CreateInventoryRow(index)
	local row = CreateFrame("Button", "Atr_Inventory_Row"..index, inventoryFrame)
	row:SetWidth(378)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 2, -55 - ((index - 1) * ROW_HEIGHT))
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.check = CreateFrame("CheckButton", "$parentCheck", row, "UICheckButtonTemplate")
	row.check:SetWidth(20)
	row.check:SetHeight(20)
	row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.check:SetScript("OnClick", function(self) SetSelection(row.inventoryItem, self:GetChecked()) end)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(22)
	row.icon:SetHeight(22)
	row.icon:SetPoint("LEFT", row, "LEFT", 24, 0)

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.name:SetWidth(150)
	row.name:SetHeight(ROW_HEIGHT)
	row.name:SetPoint("LEFT", row, "LEFT", 47, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.level = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.level:SetWidth(32)
	row.level:SetHeight(ROW_HEIGHT)
	row.level:SetPoint("LEFT", row, "LEFT", 198, 0)
	row.level:SetJustifyH("CENTER")
	row.level:SetWordWrap(false)

	row.quantity = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.quantity:SetWidth(32)
	row.quantity:SetHeight(ROW_HEIGHT)
	row.quantity:SetPoint("LEFT", row, "LEFT", 232, 0)
	row.quantity:SetJustifyH("RIGHT")
	row.quantity:SetWordWrap(false)

	row.unitPrice = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.unitPrice:SetWidth(55)
	row.unitPrice:SetHeight(ROW_HEIGHT)
	row.unitPrice:SetPoint("LEFT", row, "LEFT", 266, 0)
	row.unitPrice:SetJustifyH("RIGHT")
	row.unitPrice:SetWordWrap(false)

	row.totalValue = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.totalValue:SetWidth(55)
	row.totalValue:SetHeight(ROW_HEIGHT)
	row.totalValue:SetPoint("LEFT", row, "LEFT", 323, 0)
	row.totalValue:SetJustifyH("RIGHT")
	row.totalValue:SetWordWrap(false)

	row:SetScript("OnClick", function(self) SetSelection(self.inventoryItem, not selectedItems[self.inventoryItem.key]) end)
	row:SetScript("OnEnter", ShowItemTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)

	inventoryRows[index] = row
end

-----------------------------------------

local function CreateMarketRow(index)
	local row = CreateFrame("Button", "Atr_Inventory_MarketRow"..index, inventoryFrame)
	row:SetWidth(323)
	row:SetHeight(MARKET_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 405, -70 - ((index - 1) * MARKET_ROW_HEIGHT))
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.each = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.each:SetWidth(76)
	row.each:SetHeight(MARKET_ROW_HEIGHT)
	row.each:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.each:SetJustifyH("RIGHT")
	row.each:SetWordWrap(false)

	row.stack = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.stack:SetWidth(42)
	row.stack:SetHeight(MARKET_ROW_HEIGHT)
	row.stack:SetPoint("LEFT", row, "LEFT", 82, 0)
	row.stack:SetJustifyH("RIGHT")
	row.stack:SetWordWrap(false)

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.count:SetWidth(34)
	row.count:SetHeight(MARKET_ROW_HEIGHT)
	row.count:SetPoint("LEFT", row, "LEFT", 128, 0)
	row.count:SetJustifyH("RIGHT")
	row.count:SetWordWrap(false)

	row.seller = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.seller:SetWidth(150)
	row.seller:SetHeight(MARKET_ROW_HEIGHT)
	row.seller:SetPoint("LEFT", row, "LEFT", 168, 0)
	row.seller:SetJustifyH("LEFT")
	row.seller:SetWordWrap(false)

	row:SetScript("OnClick", UseMarketPrice)
	row:SetScript("OnEnter", ShowMarketTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	marketRows[index] = row
end

-----------------------------------------

function Atr_Inventory_Init(parent)
	if inventoryFrame then return end

	inventoryFrame = CreateFrame("Frame", "Atr_InventoryFrame", parent)
	inventoryFrame:SetWidth(744)
	inventoryFrame:SetHeight(374)
	inventoryFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 17, -53)
	if Atr_Main_Panel then inventoryFrame:SetFrameLevel(Atr_Main_Panel:GetFrameLevel() + 4) end
	inventoryFrame:Hide()

	local intro = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 2, 2)
	intro:SetWidth(335)
	intro:SetHeight(28)
	intro:SetJustifyH("LEFT")
	intro:SetJustifyV("TOP")
	intro:SetText("Auctionable inventory sorted by estimated value. Select items, then review their exact live auctions before posting.")

	inventoryFrame.refreshButton = CreateButton("Atr_Inventory_Refresh", inventoryFrame, "Refresh", 68, 340, -10, function()
		inventoryDirty = true
		RefreshInventoryDisplay()
	end)
	inventoryFrame.selectAllButton = CreateButton("Atr_Inventory_SelectAll", inventoryFrame, "Select All", 72, 412, -10, function()
		for _,item in ipairs(inventoryItems) do selectedItems[item.key] = true end
		RefreshInventoryDisplay()
	end)
	inventoryFrame.clearButton = CreateButton("Atr_Inventory_Clear", inventoryFrame, "Clear", 62, 488, -10, function()
		selectedItems = {}
		RefreshInventoryDisplay()
	end)

	local headings = {
		{"Item", 47, 150, "LEFT"},
		{"iLvl", 198, 32, "CENTER"},
		{"Qty", 232, 32, "RIGHT"},
		{"Each", 266, 55, "RIGHT"},
		{"Total", 323, 55, "RIGHT"},
	}
	for _,heading in ipairs(headings) do
		local text = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		text:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", heading[2], -41)
		text:SetWidth(heading[3])
		text:SetJustifyH(heading[4])
		text:SetText(heading[1])
	end

	inventoryScroll = CreateFrame("ScrollFrame", "Atr_Inventory_ScrollFrame", inventoryFrame, "FauxScrollFrameTemplate")
	inventoryScroll:SetWidth(380)
	inventoryScroll:SetHeight(ROW_COUNT * ROW_HEIGHT)
	inventoryScroll:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 0, -55)
	inventoryScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RefreshInventoryDisplay)
	end)

	local index
	for index = 1, ROW_COUNT do CreateInventoryRow(index) end

	local divider = inventoryFrame:CreateTexture(nil, "BACKGROUND")
	divider:SetTexture(0.45, 0.45, 0.45, 0.55)
	divider:SetWidth(1)
	divider:SetHeight(226)
	divider:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 394, -38)

	inventoryFrame.marketTitle = CreateTextLabel(inventoryFrame, "Matching live auctions", 405, -37, 327, "LEFT", "GameFontNormalSmall")
	inventoryFrame.marketTitle:SetWordWrap(false)
	local marketHeadings = {
		{"Each", 405, 76, "RIGHT"},
		{"Stack", 487, 42, "RIGHT"},
		{"#", 533, 34, "RIGHT"},
		{"Seller", 573, 150, "LEFT"},
	}
	for _,heading in ipairs(marketHeadings) do
		CreateTextLabel(inventoryFrame, heading[1], heading[2], -55, heading[3], heading[4], "GameFontNormalSmall")
	end

	marketScroll = CreateFrame("ScrollFrame", "Atr_Inventory_MarketScrollFrame", inventoryFrame, "FauxScrollFrameTemplate")
	marketScroll:SetWidth(326)
	marketScroll:SetHeight(MARKET_ROW_COUNT * MARKET_ROW_HEIGHT)
	marketScroll:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 405, -70)
	marketScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, MARKET_ROW_HEIGHT, RefreshMarketDisplay)
	end)
	for index = 1, MARKET_ROW_COUNT do CreateMarketRow(index) end

	inventoryFrame.selectionSummary = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	inventoryFrame.selectionSummary:SetWidth(388)
	inventoryFrame.selectionSummary:SetHeight(28)
	inventoryFrame.selectionSummary:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 2, -259)
	inventoryFrame.selectionSummary:SetJustifyH("LEFT")
	inventoryFrame.selectionSummary:SetJustifyV("TOP")

	inventoryFrame.marketHint = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	inventoryFrame.marketHint:SetWidth(331)
	inventoryFrame.marketHint:SetHeight(28)
	inventoryFrame.marketHint:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 405, -259)
	inventoryFrame.marketHint:SetJustifyH("LEFT")
	inventoryFrame.marketHint:SetJustifyV("TOP")

	inventoryFrame.queueStatus = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	inventoryFrame.queueStatus:SetWidth(738)
	inventoryFrame.queueStatus:SetHeight(30)
	inventoryFrame.queueStatus:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 2, -284)
	inventoryFrame.queueStatus:SetJustifyH("LEFT")
	inventoryFrame.queueStatus:SetJustifyV("TOP")
	inventoryFrame.queueStatus:SetText("Select items, then start the assisted posting queue.")

	CreateTextLabel(inventoryFrame, "Buyout per item:", 2, -319, 84, "LEFT")
	inventoryFrame.priceGold = CreateNumericEditBox("Atr_Inventory_PriceGold", inventoryFrame, 38, 88, -313, 9, NormalizeMoneyInputs)
	local goldIcon = inventoryFrame:CreateTexture(nil, "ARTWORK")
	goldIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	goldIcon:SetWidth(12)
	goldIcon:SetHeight(12)
	goldIcon:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 128, -317)

	inventoryFrame.priceSilver = CreateNumericEditBox("Atr_Inventory_PriceSilver", inventoryFrame, 31, 144, -313, 2, NormalizeMoneyInputs)
	local silverIcon = inventoryFrame:CreateTexture(nil, "ARTWORK")
	silverIcon:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")
	silverIcon:SetWidth(12)
	silverIcon:SetHeight(12)
	silverIcon:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 177, -317)

	inventoryFrame.priceCopper = CreateNumericEditBox("Atr_Inventory_PriceCopper", inventoryFrame, 31, 193, -313, 2, NormalizeMoneyInputs)
	local copperIcon = inventoryFrame:CreateTexture(nil, "ARTWORK")
	copperIcon:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")
	copperIcon:SetWidth(12)
	copperIcon:SetHeight(12)
	copperIcon:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 226, -317)

	inventoryFrame.recommendedButton = CreateButton("Atr_Inventory_UseRecommended", inventoryFrame, "Use Rec.", 64, 242, -314, UseRecommendedPrice)

	CreateTextLabel(inventoryFrame, "Stack:", 310, -319, 42, "LEFT")
	inventoryFrame.stackSize = CreateNumericEditBox("Atr_Inventory_StackSize", inventoryFrame, 36, 354, -313, 4, function(self)
		local group = CurrentGroup()
		SetEditNumber(self, PositiveInteger(self:GetText(), group and group.stackSize or 1), true)
		UpdateControls()
	end)
	inventoryFrame.stackMaxButton = CreateButton("Atr_Inventory_StackMax", inventoryFrame, "Max", 42, 394, -314, SetMaximumStackSize)

	CreateTextLabel(inventoryFrame, "Auctions:", 448, -319, 52, "LEFT")
	inventoryFrame.numAuctions = CreateNumericEditBox("Atr_Inventory_NumAuctions", inventoryFrame, 36, 502, -313, 4, function(self)
		local group = CurrentGroup()
		SetEditNumber(self, PositiveInteger(self:GetText(), group and group.auctionsRemaining or 1), true)
		UpdateControls()
	end)
	inventoryFrame.auctionsMaxButton = CreateButton("Atr_Inventory_AuctionsMax", inventoryFrame, "Max", 42, 542, -314, SetMaximumAuctionCount)

	queue.duration = (Atr_Duration and UIDropDownMenu_GetSelectedValue(Atr_Duration)) or 1
	local durationHours = queue.duration == 1 and 12 or (queue.duration == 2 and 24 or 48)
	inventoryFrame.durationButton = CreateButton("Atr_Inventory_Duration", inventoryFrame, "Duration: "..durationHours.."h", 120, 590, -314, CycleDuration)

	inventoryFrame.startButton = CreateButton("Atr_Inventory_StartQueue", inventoryFrame, "Start Queue", 90, 0, -347, StartQueue)
	inventoryFrame.postButton = CreateButton("Atr_Inventory_PostStack", inventoryFrame, "Post Next", 90, 94, -347, function()
		if queue.state == "PAUSED" then RetryQueueItem() else PostCurrentStack() end
	end)
	inventoryFrame.skipButton = CreateButton("Atr_Inventory_Skip", inventoryFrame, "Skip Item", 78, 188, -347, SkipQueueItem)
	inventoryFrame.stopButton = CreateButton("Atr_Inventory_Stop", inventoryFrame, "Stop", 52, 270, -347, function() StopQueue(nil, true) end)

	inventoryFrame.buyoutTotal = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	inventoryFrame.buyoutTotal:SetWidth(407)
	inventoryFrame.buyoutTotal:SetHeight(14)
	inventoryFrame.buyoutTotal:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 330, -337)
	inventoryFrame.buyoutTotal:SetJustifyH("LEFT")
	inventoryFrame.buyoutTotal:SetJustifyV("MIDDLE")
	inventoryFrame.buyoutTotal:SetTextColor(1, 0.82, 0)
	inventoryFrame.buyoutTotal:SetWordWrap(false)

	inventoryFrame.planSummary = inventoryFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	inventoryFrame.planSummary:SetWidth(407)
	inventoryFrame.planSummary:SetHeight(18)
	inventoryFrame.planSummary:SetPoint("TOPLEFT", inventoryFrame, "TOPLEFT", 330, -352)
	inventoryFrame.planSummary:SetJustifyH("LEFT")
	inventoryFrame.planSummary:SetJustifyV("MIDDLE")
	inventoryFrame.planSummary:SetWordWrap(false)

	inventoryFrame:SetScript("OnShow", function()
		inventoryDirty = true
		RefreshInventoryDisplay()
	end)

	UpdateControls()
end

-----------------------------------------

function Atr_Inventory_Show()
	if not inventoryFrame then return end

	if AuctionatorScrollFrame then AuctionatorScrollFrame:Hide() end
	if Atr_HeadingsBar then Atr_HeadingsBar:Hide() end
	if Atr_HideBidOnly_Button then Atr_HideBidOnly_Button:Hide() end
	if Atr_CancelSelectionButton then Atr_CancelSelectionButton:Hide() end
	if Atr_Buy1_Button then Atr_Buy1_Button:Hide() end
	if Atr_ListTabs then Atr_ListTabs:Hide() end
	if AuctionatorMessageFrame then AuctionatorMessageFrame:Hide() end
	if AuctionatorMessage2Frame then AuctionatorMessage2Frame:Hide() end

	local index
	for index = 1, 15 do
		local entry = _G["AuctionatorEntry"..index]
		if entry then entry:Hide() end
	end

	inventoryFrame:Show()
end

-----------------------------------------

function Atr_Inventory_Hide(keepQueue)
	if not inventoryFrame then return end

	local wasShown = inventoryFrame:IsShown()
	if wasShown and not keepQueue and queue.state ~= "IDLE" and queue.state ~= "COMPLETE" then
		if queue.state == "WAIT_CONFIRM" then
			SetQueueStatus("Wait for the current post to be confirmed before leaving the Inventory tab.", true)
			if zc and zc.msg_yellow then
				zc.msg_yellow("Auctionator: wait for the current Inventory post to be confirmed before changing tabs.")
			end
			return false
		else
			StopQueue("Queue stopped because you left the Inventory tab.", queue.state == "PAUSED")
		end
	end

	inventoryFrame:Hide()

	-- Restore the shared list canvas before the destination Auctionator tab lays
	-- out its own controls.  The destination tab will hide anything it does not use.
	if AuctionatorScrollFrame then AuctionatorScrollFrame:Show() end
	if Atr_HeadingsBar then Atr_HeadingsBar:Show() end
	if Atr_HideBidOnly_Button then Atr_HideBidOnly_Button:Show() end
	if Atr_CancelSelectionButton then Atr_CancelSelectionButton:Show() end
	return true
end

-----------------------------------------

function Atr_Inventory_OnAuctionHouseClosed()
	if inventoryFrame and queue.state ~= "IDLE" and queue.state ~= "COMPLETE" then
		StopQueue("Queue stopped because the auction house was closed.")
	end
end

-----------------------------------------

function Atr_Inventory_IsPosting()
	return queue.state ~= "IDLE" and queue.state ~= "COMPLETE"
end

-----------------------------------------

function Atr_Inventory_IsBusy()
	return queue.state ~= "IDLE" and queue.state ~= "COMPLETE"
end

-----------------------------------------

function Atr_Inventory_MarkDirty()
	inventoryDirty = true
	if inventoryFrame and inventoryFrame:IsShown() and not Atr_Inventory_IsBusy() then
		RefreshInventoryDisplay()
	end
end

-----------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
eventFrame:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
eventFrame:RegisterEvent("AUCTION_MULTISELL_UPDATE")
eventFrame:RegisterEvent("AUCTION_MULTISELL_FAILURE")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	local firstArg, secondArg = ...
	firstArg = firstArg or arg1
	secondArg = secondArg or arg2

	if event == "BAG_UPDATE" then
		inventoryDirty = true
		if inventoryFrame and inventoryFrame:IsShown() and (queue.state == "IDLE" or queue.state == "COMPLETE") then
			RefreshInventoryDisplay()
		end
	elseif event == "AUCTION_ITEM_LIST_UPDATE" then
		if queue.state == "WAIT_RESULT" then ProcessAuctionPage() end
	elseif event == "CHAT_MSG_SYSTEM" then
		if queue.state == "WAIT_CONFIRM" and firstArg == ERR_AUCTION_STARTED then MarkPostSuccessful() end
	elseif event == "AUCTION_MULTISELL_UPDATE" then
		if queue.state == "WAIT_CONFIRM" and tonumber(firstArg) and tonumber(secondArg) and tonumber(firstArg) >= tonumber(secondArg) then
			MarkPostSuccessful()
		end
	elseif event == "AUCTION_OWNED_LIST_UPDATE" then
		if queue.state == "WAIT_CONFIRM" then queue.ownedUpdateSeen = true end
	elseif event == "AUCTION_MULTISELL_FAILURE" then
		if queue.state == "WAIT_CONFIRM" then PauseQueue("The server rejected the auction operation.") end
	elseif event == "UI_ERROR_MESSAGE" then
		if queue.state == "WAIT_CONFIRM" then
			local message = type(secondArg) == "string" and secondArg or firstArg
			PauseQueue(tostring(message or "Internal auction error"))
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		Atr_Inventory_OnAuctionHouseClosed()
	end
end)

eventFrame:SetScript("OnUpdate", function(self, elapsed)
	if queue.state == "WAIT_SEND" then
		SendQueueQuery()
	elseif queue.state == "REPROCESS_PAGE" and queue.reprocessAt and GetTime() >= queue.reprocessAt then
		ProcessAuctionPage()
	elseif queue.state == "WAIT_RESULT" and queue.querySentAt and GetTime() - queue.querySentAt > 10 then
		queue.queryRetries = (queue.queryRetries or 0) + 1
		if queue.queryRetries <= 2 then
			queue.state = "WAIT_SEND"
			SendQueueQuery()
		else
			PauseQueue("The auction search timed out.")
		end
	elseif queue.state == "WAIT_CONFIRM" and queue.postSentAt and GetTime() - queue.postSentAt > 10 then
		if PostSucceededByEvidence() then
			MarkPostSuccessful()
		else
			PauseQueue("No posting confirmation arrived from the server.")
		end
	elseif queue.state == "ADVANCING" and queue.advanceAt and GetTime() >= queue.advanceAt then
		local group = CurrentGroup()
		local sameGroup = group and not GroupIsComplete(group)
		if group and not sameGroup then queue.index = queue.index + 1 end
		PrepareCurrentQueueItem(sameGroup)
	end

	if inventoryFrame and inventoryFrame:IsShown() and inventoryDirty and queue.state ~= "WAIT_CONFIRM" and GetTime() >= nextInventoryRefresh then
		nextInventoryRefresh = GetTime() + 0.25
		RefreshInventoryDisplay()
	end

	if inventoryFrame and inventoryFrame:IsShown() and (queue.state == "READY" or queue.state == "PAUSED") then
		UpdateControls()
	end
end)
