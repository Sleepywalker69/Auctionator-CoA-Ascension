# Auctionator (3.3.5 fork) — Scanning & Selling Overhaul

A heavily upgraded fork of **Auctionator v2.9.9** for WotLK 3.3.5 clients, backporting the auction database and selling UI from Auctionator v3.2.6 (WoD 6.2) and rebuilding the scanning engine around the reliability patterns used by **TradeSkillMaster v2.8**.

Requires the companion data addons `Auctionator_Price_Database` and `Auctionator_Pricing_History` (they own the saved data so it survives reinstalls of the main addon).

---

## Full scan (Full Scan… button)

The full scan was rebuilt from scratch:

- **Page-by-page scanning is the default** (TSM style). It works on every server, needs no getAll cooldown, and walks the entire auction house 50 results at a time with a live `Page N of M` counter.
- **Zero dead time per page.** The scan loop is fully event-driven: the query throttle is polled every frame, pages are processed synchronously inside `AUCTION_ITEM_LIST_UPDATE`, and the next page query is chained in the same frame. The old version pumped its loop from a 0.2s idle timer at both ends of the cycle, which is why it was so much slower than TSM.
- **Self-healing:** pages that arrive with incomplete data are re-requested; a dropped server response triggers a hard retry after 10 seconds; closing the auction house aborts the scan cleanly.
- **Fixed a 3.3.5 filter bug** inherited from the WoD code: the page query passed `0` for its filter arguments, which WoD treats as "no filter" but 3.3.5 interprets as *"Poor quality only"* — the scan only ever saw grey items. Filters are now `nil`, matching the (working) item-search path and TSM.
- **Ctrl+click = getAll fast scan** where the server permits one. Results are analyzed in configurable chunks per frame (`/atr fsc N`, default 50) so a 50k-auction payload never freezes or disconnects the client, and a 30-second no-response timeout protects against servers that advertise getAll but silently ignore it.
- Both scan types feed the same database, record daily price history, and clear stale items via purge marks.

## Item search / browse scanning

The per-item scan engine (Sell tab current-auctions scan, Buy tab searches, undercut checking) adopted TSM's reliability model:

- **Event-driven paging** — the next page is requested the instant the current one is processed, instead of waiting for the old 0.2s idle tick.
- **Bad-data detection with soft/hard retries** — on 3.3.5 the owner names of a results page often arrive a frame or two after the page itself. The scanner detects incomplete rows and re-reads the page (0.1s soft retries), escalating to a full re-query after 2 seconds, up to 4 attempts — so "(yours)" tags and undercut detection are reliable.
- **Duplicate-page detection** via full row snapshots, handling the server occasionally re-sending the same page.
- **Stuck-query timeout** — a lost `AUCTION_ITEM_LIST_UPDATE` no longer hangs the scan; the page is re-queried after 10 seconds and the search aborts with a message after repeated failures.
- Removed a **client freeze of up to 5 seconds** (a busy-wait loop in the old browse-clearing code, now deferred and non-blocking).
- Each results page is read from the API once and cached, rather than per-row repeated API calls.

## Price database

Upgraded from a single scalar price per item to a rich per-item record, migrated automatically on first login (`__dbversion` 4; your existing prices are preserved as the starting point):

- `mr` — most recent lowest buyout
- `H<day>` / `L<day>` — daily high/low of the observed lows (the History sub-tab's data)
- `id` — item ID string, `cc`/`sc` — class/subclass
- `po` — purge mark: items no longer seen in full scans are cleaned out automatically; long-unseen items and old history are pruned on login (`AUCTIONATOR_DB_MAXITEM_AGE`, `AUCTIONATOR_DB_MAXHIST_DAYS`)

## Sell tab

- **Clickable bag panel** — a "Click an item to sell it" panel attached to the right of the AH frame lists every auctionable item in your bags (soulbound / quest / conjured items filtered out via tooltip scan). Clicking an item loads it into the sell slot and starts the price scan; drag & drop and right-clicking bag items still work. The panel live-updates as your bags change.
- **Results sub-tabs reworked:** *Current* (live auctions) / *History* (the scan database's daily prices for the item) / *Other* (price hints — vendor, disenchant, external data — merged with your own posting history).
- **"Hide bid-only" checkbox** above the results list (available on every page): filters out auctions with no buyout price so undercut pricing isn't buried in bid-only spam. Toggling rebuilds the current list instantly — no rescan needed — and the setting is remembered across sessions. While active, price recommendations are also based purely on buyout auctions.
- Smarter fallbacks: with no current auctions, the recommendation is based on scan history, then hints.
- **Clickable bag panel** with reliable soulbound filtering: items are only listed once cached, and any `* Bound` line (Soulbound, Account Bound, custom **Realm Bound**, etc.) excludes them — while the sellable "Binds when picked up/equipped" state is correctly kept. Uncached slots are retried automatically instead of leaking a bound item into the list.
- Fork features preserved: Bloodforged/suffix name stripping, stacking preferences, multi-stack posting.

## Buy tab

- **Exact Match checkbox** — syncs both ways with quoted search text (`"Copper Ore"`).
- **Advanced search dialog** — now a full category browser:
  - **Category → Subcategory → Slot** three-level drill-down. The Slot (sub-sub-category) level is populated live from the server's `GetAuctionInvTypes`, so equipment slots like Head, Shoulder, Chest, Trinket, Held-in-Off-Hand appear per subcategory.
  - **Rarity filter** (Any / Poor … Heirloom, colored) passed as the query's quality index.
  - Level range and free-text name filter as before.
  - **Fixed the category round-trip bug:** the dialog previously rebuilt your selection into a `"Armor/Miscellaneous"` text string and re-parsed it *by name*, so any subcategory whose name didn't string-match (or collided with a top-level category like *Miscellaneous*) silently fell back to a useless name search. The selection now drives the query with numeric class/subclass/slot/quality indices directly — no lossy text round-trip — and whatever category tree the server exposes is browsable. (Use `/atr catdump` to print that tree.)
- **Shopping list upgrades:** *Search for All Items* scans a whole list in one pass (`{ list name }` searches); a full **Manage Shopping Lists** options panel with rename, inline editing, delete, and plain-text **import/export**; unsaved shared lists can be saved with one click. Compact two-per-row list buttons.
- **Buying quality-of-life:**
  - **Max button** on the buy-confirm dialog sets the quantity to every matching auction in one click.
  - **Bought auctions disappear from the results list immediately.** Previously a purchased auction stayed in the list as a stale row; clicking Buy on it wedged the buy engine and blocked further list updates until reload. Purchases now subtract from the local scan data and the list re-renders — no follow-up server query needed.
  - **Clear (✕) buttons** on the Buy tab search bar and the Advanced dialog's text field.

## UI & compatibility

- **ElvUI coexistence:** button geometry is enforced from Lua (`Atr_FixupButtons`) after load and on every tab switch, so UI skins that re-anchor frames they recognize can no longer scramble the layout. Fonts are deliberately left to the skin.
- Options and Full Scan buttons anchored at the frame's far right on every page.
- XML ported from the WoD codebase was converted to 3.3.5-safe long forms (no attribute shorthand, no `function=` script handlers, no chained virtual button templates — the 3.3.5 client mishandles them).

## Commands

| Command | Effect |
|---|---|
| `/atr fsc N` | Full-scan analysis chunk size (rows per frame, default 50) |
| `/atr catdump` | Print the server's auction category tree (class › subclass › slot) |
| `/atr uidebug` | Print button geometry/state for skin-conflict diagnosis |
| `/atr clear fullscandb` | Wipe the scan price database |
| `/atr clear posthistory` | Wipe your posting history |
| `/atr mem` | Addon memory usage |

## Credits

Based on **Auctionator** by Zirco (and the Borjamacare v3.2.6 WoD branch). Scanning reliability patterns modeled on **TradeSkillMaster v2** by Sapu94 et al. Fork maintained for WotLK 3.3.5 private servers.
