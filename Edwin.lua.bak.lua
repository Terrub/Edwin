--[[

     ---- TODOs ----

    *   TODO#1 -- DONE
        Make money columns bigger, test with "ggggg ss cc"

    *   TODO#2 -- DONE
        Look into swapping around columns.
            icon - name - unitprice - amount - buyout
        may not be easiest, perhaps its easier with
            icon - amount - name - buyout - unitprice?

    *   TODO#3 -- Possibly DONE, still no true reproduction to make it happen
        Fix textures not always showing.. this is probably rather
        complex but I want it to work proper and consistent.
        Consider doing a full debug of the creation, initiation
        retirement and reinstatement of the listItem frames to
        identify any problems with wildgrowth in unrecognised
        frame attributes like frame level and strata and what not

    *   TODO#4 -- DONE
        Fix sorting items function with 0 buyout

    *   TODO#5
        Release all objects and frames back to the core object
        and frame pools respectively

    *   TODO#6 -- DONE
        Make greenies with suffixes search for all suffixes

    *   TODO#7 -- DONE
        Make selecting an item set the bid and buyout based on current count * unitprice * 0.95 instead of copying over the actual buyout
        ... OOPS =P
        Put a single item in the AH and click a listed item wich a count higher than 1 -> buyout is not unit price.

    *   TODO#8 -- DONE
        Make Edwin Hide and show when the AH panel is hidden or shown.

    *   TODO#9 -- DONE
        Make hiding and showing available in slashcommands (not using activation!)
        Remember DB updates and everything!

    *   TODO#10
        Make lock/unlock as well as Hide/Show buttons in interface?

    *   TODO#11 -- DONE
        Mark items with bids and buyout below vendor price!

    *   TODO#12 -- DONE
        Mark items with bids and buyout below vendor price!
--]]

----------------------------------------------------------------
-- "UP VALUES" FOR SPEED ---------------------------------------
----------------------------------------------------------------

local ceil = math.ceil
local floor = math.floor
local find = string.find
local format = string.format
local getTime = GetTime
local max = math.max
local min = math.min
local sub = string.sub
local tgetn = table.getn
local tinsert = table.insert
local tostring = tostring
local tremove = table.remove
local tsort = table.sort
local type = type

----------------------------------------------------------------
-- CONSTANTS THAT SHOULD BE GLOBAL PROBABLY --------------------
----------------------------------------------------------------

local TYPE_BOOLEAN = "boolean"
local TYPE_STRING = "string"
local TYPE_NUMBER = "number"
local TYPE_TABLE = "table"

local SCRIPTHANDLER_ON_EVENT = "OnEvent"
local SCRIPTHANDLER_ON_UPDATE = "OnUpdate"
local SCRIPTHANDLER_ON_DRAG_START = "OnDragStart"
local SCRIPTHANDLER_ON_DRAG_STOP = "OnDragStop"

local EVENT_PLAYER_LOGIN = "PLAYER_LOGIN"
local EVENT_PLAYER_LOGOUT = "PLAYER_LOGOUT"
local EVENT_ADDON_LOADED = "ADDON_LOADED"
local EVENT_NEW_AUCTION_UPDATE = "NEW_AUCTION_UPDATE"
local EVENT_AUCTION_ITEM_LIST_UPDATE = "AUCTION_ITEM_LIST_UPDATE"
local EVENT_AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_SHOW"
local EVENT_AUCTION_HOUSE_CLOSED = "AUCTION_HOUSE_CLOSED"

----------------------------------------------------------------
-- HELPER FUNCTIONS --------------------------------------------
----------------------------------------------------------------

--  These should be moved into the core at one point.

--------

local function isBoolean(value)

    return (type(value) == TYPE_BOOLEAN)

end

--------

local function isString(value)

    return (type(value) == TYPE_STRING)

end

--------

local function isNumber(value)

    return (type(value) == TYPE_NUMBER)

end

--------

local function isTable(value)

    return (type(value) == TYPE_TABLE)

end

--------

local function isFunction(value)

    return (type(value) == "function")

end

--------

local function throwError(error_message)

    if not isString(error_message) then

        throwError("throwError requires a non-empty string on argument position 1")

        return

    end

    error(error_message)

end

--------

local function merge(left, right)

    local t = {}

    if not isTable(left) or not isTable(right) then

        throwError("Usage: merge(left <table>, right <table>)")

    end

    -- copy left into temp table.
    for k, v in pairs(left) do

        t[k] = v

    end

    -- Add or overwrite right values.
    for k, v in pairs(right) do

        t[k] = v

    end

    return t

end

--------

local function toColourisedString(value)

    local result;

    if isString(value) then

        result = "|cffffffff" .. value .. "|r"

    elseif isNumber(value) then

        result = "|cffffff33" .. tostring(value) .. "|r"

    elseif isBoolean(value) then

        result = "|cff9999ff" .. tostring(value) .. "|r"

    end

    return result

end

--------

local function prt(proposed_message)

    local message = tostring(proposed_message)

    if not isString(message) then

        throwError("prt requires a non-empty string on argument position 1")

        return

    end

    DEFAULT_CHAT_FRAME:AddMessage(message)

end

--------

----------------------------------------------------------------
-- EDWIN ADDON ------------------------------------------------
----------------------------------------------------------------

Edwin = CreateFrame("FRAME", "Edwin", UIParent)

local base = Edwin

----------------------------------------------------------------
-- INTERNAL CONSTANTS ------------------------------------------
----------------------------------------------------------------

local PAGE_READY_FOR_SCANNING = "Page is ready for scanning"
local PAGE_IS_BEING_SCANNED = "Page is being scanned"
local PAGE_HAS_BEEN_SCANNED = "Page has been scanned"
local PAGE_SCAN_FAILED = "Page scan failed"

----------------------------------------------------------------
-- DATABASE KEYS -----------------------------------------------
----------------------------------------------------------------

-- IF ANY OF THE >>VALUES<< CHANGE YOU WILL RESET THE STORED
-- VARIABLES OF THE PLAYER. EFFECTIVELY DELETING THEIR CUSTOM-
-- ISATION SETTINGS!!!
--
-- Changing the constant itself may cause errors in some cases.
-- Or outright kill the addon alltogether.

-- #TODO:   Make these version specific, allowing full
--          backwards-compatability. Though doing so manually
--          is very error prone. Not sure how to do this auto-
--          matically. Yet.
--
--          Consider doing something like a property list.
--          When changing a property using the slash-cmds or
--          perhaps an in-game editor, we can change the version
--          and keep a record per version.

local IS_ADDON_ACTIVATED = "addon is active"
local IS_ADDON_LOCKED = "addon is locked"
local POSITION_POINT = "positioning point"
local POSITION_X = "X position"
local POSITION_Y = "Y position"
local DB_VERSION = "DB version"
local DB_ITEMS = "Stored item database"

local default_db = {
    [IS_ADDON_ACTIVATED] = false,
    [IS_ADDON_LOCKED] = true,
    [POSITION_POINT] = "CENTER",
    [POSITION_X] = 0,
    [POSITION_Y] = 0,
    [DB_VERSION] = 2,
    [DB_ITEMS] = {}
}

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local initialisation_event = EVENT_ADDON_LOADED

local threshold
local frames_per_second = 30
local t_current
local step_size = (1 / frames_per_second)
local render_jobs

local unit_name
local realm_name
local profile_id
local local_db

local event_handlers
local command_list

local default_width = 400
local default_height = 600

local listItem_height = 20
local listItem_margin_top = 1

local auctionFrameHeader
local auctionFrameListItems

local edwin_is_scanning = false
local current_page
local last_page
local waiting_period
local disconnection_prevention_buffer
local current_item_index
local auctions_this_page
local auctions_total
local amount_of_pages
local specific_item_name
local auctioning_item_name
local auctioning_item_count
local auctioning_item_vendor_price

local num_created_item_objects

-- Local tables we use for stuff
local scanned_pages
local retired_item_objects
local retired_list_items
local scan_results
local showing_results
local active_list_items
local known_suffixes

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local function report(label, message)

    local label = tostring(label)

    if not isString(label) then

        throwError("report requires a non-empty string at argument position 1")

        return

    end

    local message = tostring(message)

    if not isString(message) then

        throwError("report requires a non-empty string at argument position 2")

    end

    local str = "|cff22ff22Edwin|r - |cff999999" .. label .. ":|r " .. message

    DEFAULT_CHAT_FRAME:AddMessage(str)

end

--------

local function addEvent(event_name, eventHandler)

    if  (not event_name)
    or  (event_name == "")
    or  (not eventHandler)
    or  (not isFunction(eventHandler)) then

        throwError("Usage: addEvent(event_name <string>, eventHandler <function>)")

    end

    event_handlers[event_name] = eventHandler

    base:RegisterEvent(event_name)

end

--------

local function removeEvent(event_name)

    local eventHandler = event_handlers[event_name]

    if eventHandler then

        -- GC should pick this up when a new assignment happens
        event_handlers[event_name] = nil

    end

    base:UnregisterEvent(event_name)

end

--------
-- #TODO: This looks an awefull lot like a class... again.
local function addSlashCommand(name, command, command_description, db_property)

    -- prt("Adding a slash command");
    if  not isString(name)
    or  name == ""
    or  not isFunction(command)
    or  not command_description
    or  command_description == "" then

        throwError("Usage: addSlashCommand(name <string>, command <function>, command_description <string> [, db_property <string>])")

    end

    -- prt("Creating a slash command object into the command list");
    command_list[name] = {
        ["execute"] = command,
        ["description"] = command_description
    };

    if (db_property) then

        if (not isString(db_property) or db_property == "") then

            throwError("db_property must be a non-empty string.")

        end

        if (local_db[db_property] == nil) then

            throwError('The internal database property: "' .. db_property .. '" could not be found.')

        end
        -- prt("Add the database property to the command list");
        command_list[name]["value"] = db_property

    end

end

--------

local function finishInitialisation()

    -- we only need this once
    base:UnregisterEvent(EVENT_PLAYER_LOGIN)

end

--------

local function storeLocalDatabaseToSavedVariables()

    -- #OPTION: We could have local variables for lots of DB
    --          stuff that we can load into the local_db Object
    --          before we store it.
    --
    --          Should probably make a list of variables to keep
    --          track of which changed and should be updated.
    --          Something we can just loop through so load and
    --          unload never desync.

    -- Commit to local storage
    EdwinDB[profile_id] = local_db

end

--------

local function eventCoordinator()

    -- given:
    -- event <string> The event name that triggered.
    -- arg1, arg2, ..., arg9 <*> Given arguments specific to the event.

    local eventHandler = event_handlers[event]

    if eventHandler then

        eventHandler(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)

    end

end

--------

local function removeEvents()

    for event_name, eventHandler in pairs(event_handlers) do

        if event_name then

            removeEvent(event_name)

        end

    end

end

--------

local function reinstateRetiredItemObject()

    return tremove(retired_item_objects)

end

--------

local function retireItemObject(itemObject)

    tinsert(retired_item_objects, itemObject)

end

--------

local function newItemObject(name, texture, count, minimum_bid, buyout)

    local default_name = "itemObject"..num_created_item_objects
    local default_texture = "Interface/ICONS/INV_Misc_QuestionMark"
    local default_count = 1
    local default_minimum_bid = 0
    local default_buyout = 0

    local item = reinstateRetiredItemObject()

    if not item then

        item = {}

        num_created_item_objects = num_created_item_objects + 1

    end

    item["name"] = name or default_name
    item["texture"] = texture or default_texture
    item["count"] = count or default_count
    item["minimum_bid"] = minimum_bid or default_minimum_bid
    item["buyout"] = buyout or default_buyout
    item["unit_bid"] = floor(item["minimum_bid"] / count + 0.5)
    item["unit_price"] = floor(item["buyout"] / count + 0.5)

    return item

end

--------

local function addItemToDataStorage(index)

    -- local itemlink = GetAuctionItemLink("list", index)
    local name, texture, count, quality, _, level, minimum_bid, _,buyout_price = GetAuctionItemInfo("list", index)

    if not name then

        -- report("Item scan failed", "page "..current_page.." | row "..index)

        return

    end

    -- local lowest_bid, highest_bid
    -- local lowest_buyout, highest_buyout

    -- local last_scan_time = getTime()
    -- local cur_min_bid = minimum_bid
    -- local cur_max_bid = minimum_bid
    -- local cur_min_buyout = buyout_price
    -- local cur_max_buyout = buyout_price
    -- local times_scanned = 1
    -- local day_worth_in_seconds = 24*60*60

    -- local previously_scanned_item_data = local_db[DB_ITEMS][name]

    -- if previously_scanned_item_data then

    --     last_scan_time = previously_scanned_item_data["last_scan_time"] or last_scan_time
    --     cur_min_bid = previously_scanned_item_data["lowest_bid"] or cur_min_bid
    --     cur_max_bid = previously_scanned_item_data["highest_bid"] or cur_max_bid
    --     cur_min_buyout = previously_scanned_item_data["lowest_buyout"] or cur_min_buyout
    --     cur_max_buyout = previously_scanned_item_data["highest_buyout"] or cur_max_buyout
    --     times_scanned = previously_scanned_item_data["last_scan_time"] or times_scanned

    -- end

    -- lowest_bid = min(minimum_bid, cur_min_bid)
    -- highest_bid = max(minimum_bid, cur_max_bid)
    -- lowest_buyout = min(buyout_price, cur_min_buyout)
    -- highest_buyout = max(buyout_price, cur_max_buyout)

    -- if getTime() > day_worth_in_seconds + last_scan_time then

    --  times_scanned = times_scanned + 1;

    -- end

    if showing_results then

        local item = newItemObject(name, texture, count, minimum_bid, buyout_price)

        tinsert(scan_results, item)

    end

    -- prt("|cff22ff22scanned|r - "..name)
    -- log({
    --  ["name"] = name,
    --  ["texture"] = texture,
    --  ["itemlinke"] = itemlink,
    --  ["lowest_bid"] = lowest_bid,
    --  ["highest_bid"] = highest_bid,
    --  ["lowest_buyout"] = lowest_buyout,
    --  ["highest_buyout"] = highest_buyout,
    --  ["times_scanned"] = times_scanned,
    --  ["last_scan_time"] = last_scan_time
    -- })

    -- local_db[DB_ITEMS][name] = {
    --  ["name"] = name,
    --  ["texture"] = texture,
    --  ["itemlinke"] = itemlink,
    --  ["lowest_bid"] = lowest_bid,
    --  ["highest_bid"] = highest_bid,
    --  ["lowest_buyout"] = lowest_buyout,
    --  ["highest_buyout"] = highest_buyout,
    --  ["times_scanned"] = times_scanned,
    --  ["last_scan_time"] = last_scan_time
    -- }

end

--------

local function queryCurrentPage()

    QueryAuctionItems(specific_item_name, nil, nil, 0, 0, 0, current_page - 1)

    current_item_index = 1

end

--------

local function convertValueToGSC(value)

    local str = tostring(floor(value + 0.5))

    local gold = sub(str, 1, -5)
    local silver = sub(str, -4, -3)
    local copper = sub(str, -2, -1)

    return gold, silver, copper

end

--------

local function toColourisedCurrency(value)

    if not isNumber(value) then

        throwError("Expected: 'number' | Received: "..type(value))

    end

    local gold = ""
    local silver = ""
    local copper = ""

    local possible_gold, possible_silver, possible_copper = convertValueToGSC(value)

    if possible_gold ~= "" then

        gold = "|cffffff00" .. possible_gold .. "|r "

    end

    if possible_silver ~= "" then

        silver = "|cffccccdd" .. possible_silver .. "|r "

    end

    copper = "|cffffaa33" .. possible_copper .. "|r"

    return format("%s%s%s", gold, silver, copper)

end

--------

local function sortScanResults(item_one, item_two)

    if item_one["unit_price"] == 0 then

        return false

    end

    if item_two["unit_price"] == 0 then

        return true

    end

    return item_one["unit_price"] < item_two["unit_price"]

end

--------

local function retireListItem(listItem)

    listItem:Hide()
    listItem:SetParent(nil)
    listItem:ClearAllPoints()

    tinsert(retired_list_items, listItem)

end

--------

local function reinstateRetiredListItem(parent)

    local listItem = tremove(retired_list_items)

    if not listItem then

        return nil

    end

    listItem:Show()
    listItem:SetParent(parent)

    return listItem

end

--------

local function getNewListItem()

    local listItem = reinstateRetiredListItem( auctionFrameListItems )

    if not listItem then

        listItem = CreateFrame( "Frame", nil, auctionFrameListItems )

        listItem:SetWidth( auctionFrameListItems:GetWidth() )
        listItem:SetHeight( listItem_height )

        listItem:SetBackdrop( { ["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND" } )
        listItem:SetBackdropColor( 0, 0, 0, 1 )

        listItem:EnableMouse( true )

        listItem:SetScript( "OnEnter", function ()

            listItem:SetBackdropColor( 1, 1, 0, 0.2 )

        end )

        listItem:SetScript( "OnLeave", function ()

            listItem:SetBackdropColor( 0, 0, 0, 1 )

        end )

        listItem:SetScript( "OnMouseDown", function ()

            local undercut_buyout = ( listItem.itemObject.unit_price * auctioning_item_count ) * 0.95

            local gold, silver, copper = convertValueToGSC( undercut_buyout * 0.8 )

            StartPriceGold:SetText( gold )
            StartPriceSilver:SetText( silver )
            StartPriceCopper:SetText( copper )

            gold, silver, copper = convertValueToGSC( undercut_buyout )

            BuyoutPriceGold:SetText( gold )
            BuyoutPriceSilver:SetText( silver )
            BuyoutPriceCopper:SetText( copper )

            AuctionsShortAuctionButton:SetChecked( 0 )
            AuctionsMediumAuctionButton:SetChecked( 0 )
            AuctionsLongAuctionButton:SetChecked( 1 )
            AuctionFrameAuctions.duration = 1440

        end )

        local texture = listItem:CreateTexture( nil, "BACKGROUND" )
        local name = listItem:CreateFontString()
        local unitPrice = listItem:CreateFontString()
        local amount = listItem:CreateFontString()
        local buyout = listItem:CreateFontString()

        local texture_size = listItem:GetHeight() - 4
        local font_size = 10

        texture:SetTexture( "Interface/ICONS/INV_Misc_QuestionMark" )
        texture:SetWidth( texture_size )
        texture:SetHeight( texture_size )
        texture:SetPoint( "LEFT", listItem, "LEFT", 2, 0 )

        texture:SetDrawLayer( "ARTWORK" )

        amount:SetFont( "Fonts\\FRIZQT__.TTF", font_size )
        amount:SetPoint( "LEFT", texture, "RIGHT", 2, 0 )
        amount:SetWidth( 15 )
        amount:SetJustifyH( "RIGHT" )

        name:SetFont( "Fonts\\FRIZQT__.TTF", font_size )
        name:SetPoint( "LEFT", amount, "RIGHT", 5, 0 )
        name:SetPoint( "RIGHT", unitPrice, "LEFT", -5, 0 )
        name:SetJustifyH( "LEFT" )

        unitPrice:SetFont( "Fonts\\FRIZQT__.TTF", font_size )
        unitPrice:SetPoint( "RIGHT", buyout, "LEFT", -5, 0 )
        unitPrice:SetWidth( 65 )
        unitPrice:SetJustifyH( "RIGHT" )

        buyout:SetFont( "Fonts\\FRIZQT__.TTF", font_size )
        buyout:SetPoint( "RIGHT", listItem, "RIGHT", 5 )
        buyout:SetWidth( 65 )
        buyout:SetJustifyH( "RIGHT" )

        function listItem:SetItem( item )

            local buyout_price = item.buyout
            local vendor_price = 0

            -- local buyout_price = 133379595 -- Test for checking column spacing

            if auctioning_item_vendor_price then

                vendor_price = auctioning_item_vendor_price / auctioning_item_count

            end

            if item.unit_price <= vendor_price then

                name:SetText( "|cff666666" .. item.name .. "|r" )

            elseif item.unit_bid <= vendor_price then

                name:SetText( "|cffcc0000" .. item.name .. "|r" )

            else

                name:SetText( "|cffcccccc" .. item.name .. "|r" )

            end

            texture:SetTexture( item.texture )
            unitPrice:SetText( toColourisedCurrency( buyout_price / item.count ) )
            amount:SetText( toColourisedString( item.count ) )
            buyout:SetText( toColourisedCurrency( buyout_price ) )

            listItem[ "itemObject" ] = item

        end

    end

    return listItem

end

--------

local function updateAuctionFrameListItems()

    local listItem
    local previous_list_item

    local max_showing_list_items = auctionFrameListItems:GetHeight() / ( listItem_height + listItem_margin_top )
    local counter = 1
    local undercut_buyout
    local gold, silver, copper

    for item_index, item in ipairs( scan_results ) do

        listItem = active_list_items[ item_index ]

        if not listItem then

            listItem = getNewListItem()

            if not previous_list_item then

                listItem:SetPoint( "TOPLEFT", auctionFrameListItems, "TOPLEFT", 0, -1 )

            else

                listItem:SetPoint( "TOPLEFT", previous_list_item, "BOTTOMLEFT", 0, -1 )

            end

            tinsert( active_list_items, listItem )

        end

        listItem:SetItem( item )

        counter = counter + 1

        if counter > max_showing_list_items then

            break

        end

        previous_list_item = listItem

    end

    while tgetn( scan_results ) < tgetn( active_list_items ) do

        retireListItem( tremove( active_list_items ) )

    end

end

--------

local function finishUpCurrentScan()

    report( "finished scanning", "page " .. current_page .. " / " .. amount_of_pages )

    last_page = current_page
    current_page = last_page + 1

    if current_page > amount_of_pages then

        edwin_is_scanning = false

        if showing_results then

            tsort( scan_results, sortScanResults )

            tinsert( render_jobs, updateAuctionFrameListItems )

        end

    else

        scanned_pages[ current_page ] = PAGE_READY_FOR_SCANNING

    end

end

--------

local function queryNextItem()

    addItemToDataStorage(current_item_index)

    waiting_period = waiting_period + disconnection_prevention_buffer

    current_item_index = current_item_index + 1

    if current_item_index > auctions_this_page then

        scanned_pages[current_page] = PAGE_HAS_BEEN_SCANNED

    end

end

--------

local function doScanLogic()

    if scanned_pages[current_page] == PAGE_IS_BEING_SCANNED and getTime() > waiting_period then

        queryNextItem()

    -- http://vanilla-wow.wikia.com/wiki/API_CanSendAuctionQuery
    elseif scanned_pages[current_page] == PAGE_READY_FOR_SCANNING and CanSendAuctionQuery() then

        queryCurrentPage()

    elseif scanned_pages[current_page] == PAGE_HAS_BEEN_SCANNED then

        finishUpCurrentScan()

    end

end

--------

local function doRenderJobs()

    local func

    while tgetn(render_jobs) > 0 do

        func = tremove(render_jobs)

        if isFunction(func) then

            -- For now just call it
            func()

        else

            log("render jobs encountered a non-func")

        end

    end

end

--------

local function updateDisplay()

    t_current = getTime()

    if (t_current > threshold) then

        if edwin_is_scanning then

            doScanLogic()

        end

        if tgetn(render_jobs) > 0 then

            doRenderJobs()

        end

        -- Increase the threshold...
        threshold = threshold + step_size

    end

end

--------

local function printSlashCommandList()

    local result
    local description
    local current_value

    report("Listing", "Slash commands")

    for name, cmd_object in pairs(command_list) do

        description = cmd_object.description

        if not description then

            throwError('Attempt to print slash command with name: "' .. name .. '" without valid description')

        end

        result = SLASH_EDWIN1 .. " " .. name .. " " .. description

        -- If the slash command sets a value we should notify the user
        if cmd_object.value then

            result = result .. " (|cff666666Currently:|r " .. toColourisedString(local_db[cmd_object.value]) .. ")"

        end

        prt(result)

    end

end

--------

local function startMoving()

    base:StartMoving()

end

--------

local function stopMovingOrSizing()

    base:StopMovingOrSizing()

    local_db[POSITION_POINT], _, _, local_db[POSITION_X], local_db[POSITION_Y] = base:GetPoint()

end

--------

local function unlockAddon(silent)

    -- Make the left mouse button trigger drag events
    base:RegisterForDrag("LeftButton")

    -- Set the start and stop moving events on triggered events
    base:SetScript(SCRIPTHANDLER_ON_DRAG_START, startMoving)
    base:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, stopMovingOrSizing)

    -- Make the frame movable
    base:SetMovable(true)

    local_db[IS_ADDON_LOCKED] = false

    if not silent then

        report(IS_ADDON_LOCKED, toColourisedString(local_db[IS_ADDON_LOCKED]))

    end

end

--------

local function lockAddon()

    -- Stop the frame from being movable
    base:SetMovable(false)

    -- Remove all buttons from triggering drag events
    base:RegisterForDrag()

    -- Nil the 'OnSragStart' script event
    base:SetScript(SCRIPTHANDLER_ON_DRAG_START, nil)
    base:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, nil)

    local_db[IS_ADDON_LOCKED] = true

    report(IS_ADDON_LOCKED, toColourisedString(local_db[IS_ADDON_LOCKED]))

end

--------

local function showAddon()

    base:Show()

end

--------

local function hideAddon()

    base:Hide()

end

--------

local function toggleLockToScreen()

    -- Inversed logic to lock the addon if local_db[IS_ADDON_LOCKED] returns 'nil' for some reason.
    if not local_db[IS_ADDON_LOCKED] then

        lockAddon()

    else

        unlockAddon()

    end

end

--------

local function listedAuctionsUpdateHandler()

    if edwin_is_scanning and scanned_pages[current_page] == PAGE_READY_FOR_SCANNING then

        auctions_this_page, auctions_total = GetNumAuctionItems("list") -- http://vanilla-wow.wikia.com/wiki/API_GetNumAuctionItems

        amount_of_pages = math.ceil(auctions_total / NUM_AUCTION_ITEMS_PER_PAGE) -- NUM_AUCTION_ITEMS_PER_PAGE is actually a client Constant!

        scanned_pages[current_page] = PAGE_IS_BEING_SCANNED

        waiting_period = getTime()

    end

end

--------

local function resetScannedResults()

    scan_results = {}
    showing_results = true

end

--------

local function resetScanningProces()

    scanned_pages = {}
    current_page = 1

end

--------

local function startScanningProces()

    scanned_pages[current_page] = PAGE_READY_FOR_SCANNING
    edwin_is_scanning = true

end

--------

local function stopScanningProces()

    edwin_is_scanning = false;

end

--------

local function scanListedAuctions(proposed_item_name)

    specific_item_name = proposed_item_name or ""

    if specific_item_name and specific_item_name ~= "" then

        resetScannedResults()

    end

    resetScanningProces()
    startScanningProces()

end

--------

local function clearSuffix(name)

    -- Check if this is an uncommon item with a known suffix.
    local potential_suffix
    local suffix_start_position

    suffix_start_position, _, potential_suffix = find(name, "( of .+)$")

    if known_suffixes[potential_suffix] then

        name = sub (name, 1, suffix_start_position - 1)

    end

    return name

end

--------

local function newOwnAuctionUpdateHandler()

    local name

    name, _,
    auctioning_item_count, _, _,
    auctioning_item_vendor_price = GetAuctionSellItemInfo() -- http://vanilla-wow.wikia.com/wiki/API_GetAuctionSellItemInfo

    -- for now we just do nothing if we put back the item we just scanned.
    if name == auctioning_item_name then

        return

    end

    -- If a new item is gven to us, we can just start over for now.
    if name and name ~= "" then

        auctioning_item_name = name;

        name = clearSuffix(name)

        scanListedAuctions(name)

    end

end

--------

local function auctionHouseShowEventHandler()

    showAddon()

end

--------

local function auctionHouseClosedEventHandler()

    hideAddon()

end

--------

local function populateRequiredEvents()

    addEvent(EVENT_PLAYER_LOGIN, finishInitialisation)

    addEvent(EVENT_NEW_AUCTION_UPDATE, newOwnAuctionUpdateHandler)
    addEvent(EVENT_AUCTION_ITEM_LIST_UPDATE, listedAuctionsUpdateHandler)

    addEvent(EVENT_AUCTION_HOUSE_SHOW, auctionHouseShowEventHandler)
    addEvent(EVENT_AUCTION_HOUSE_CLOSED, auctionHouseClosedEventHandler)

end

--------

local function populateKnownSuffixes()

    -- This list is based on the information over at: http://vanilla-wow.wikia.com/wiki/Item_suffix

    known_suffixes = {

        -- Suffixes that increase a single attribute
        [" of Spirit"] = true, -- Increase Spirit when equipped.
        [" of Intellect"] = true, -- Increase Intellect when equipped.
        [" of Strength"] = true, -- Increase Strength when equipped.
        [" of Stamina"] = true, -- Increase Stamina when equipped.
        [" of Agility"] = true, -- Increase Agility when equipped.

        -- Wrath suffixes (spell damage)
        [" of Frozen Wrath"] = true, -- Increases damage done by Frost spells
        [" of Arcane Wrath"] = true, -- Increases damage done by Arcane spells.
        [" of Fiery Wrath"] = true, -- Increase damage done by Fire spells.
        [" of Nature's Wrath"] = true, -- Increase damage done by Nature spells.
        [" of Healing"] = true, -- Increase all spell power (previously only increased healing spell power.)
        [" of Shadow Wrath "] = true, -- Increases damage done by Shadow spells.

        -- Resistances
        [" of Fire Resistance"] = true, -- Increase resistance to Fire spells.
        [" of Nature Resistance"] = true, -- Increase resistance to Nature spells.
        [" of Arcane Resistance"] = true, -- Increase resistance to Arcane spells.
        [" of Frost Resistance"] = true, -- Increase resistance to Frost spells.
        [" of Shadow Resistance"] = true, -- Increase resistance to Shadow spells.

        -- Animal name suffixes
        [" of the Tiger"] = true, -- Increase Strength and Agility
        [" of the Bear"] = true, -- Increase Strength and Stamina
        [" of the Gorilla"] = true, -- Increase Strength and Intellect
        [" of the Boar"] = true, -- Increase Strength and Spirit
        [" of the Monkey"] = true, -- Increase Agility and Stamina
        [" of the Falcon"] = true, -- Increase Agility and Intellect
        [" of the Wolf"] = true, -- Increase Agility and Spirit
        [" of the Eagle"] = true, -- Increase Stamina and Intellect
        [" of the Whale"] = true, -- Increase Stamina and Spirit
        [" of the Owl"] = true, -- Increase Intellect and Spirit

        -- Abyssal Suffixes -- These only appear on Abyssal items, dropped from members of the Abyssal Council in Silithus.
        [" of Striking"] = true, -- Increases Strength, Agility, and Stamina.
        [" of Sorcery"] = true, -- Increases Stamina, Intellect, and spell damage.
        [" of Regeneration"] = true, -- Increases Stamina, spell healing, and mana regeneration.

        -- Health/Mana Regeneration
        [" of Concentration"] = true, -- Regenerates mana while equipped.
        -- REMOVED DUE TO NAMING CONFLICT. CONTENTS NOT RELEVANT.
        -- " of Regeneration", -- Regenerates health while equipped.

        -- " SUFFIXNAME", -- Explanation

    }


end

--------

local function createAuctionFrameHeader()

    auctionFrameHeader = CreateFrame("Frame", nil, base);

    auctionFrameHeader:SetWidth(base:GetWidth());
    auctionFrameHeader:SetHeight(50);

    auctionFrameHeader:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    auctionFrameHeader:SetBackdropColor(0.2, 0.2, 0.2, 1)
    auctionFrameHeader:SetPoint("TOP", base)

    local title = auctionFrameHeader:CreateFontString()
    title:SetPoint("LEFT", auctionFrameHeader, 20, 0)
    title:SetFont("Fonts\\FRIZQT__.TTF", 20)
    title:SetText("|cffffff33EDWIN|r")

end

--------

local function createAuctionFrameListItems()

    auctionFrameListItems = CreateFrame("Frame", nil, auctionFrameHeader);

    -- Pretty sure the harcoded 20 here stems from the square icon covering the entire height
    -- of a list item which is 20 px high by default!
    auctionFrameListItems:SetWidth(auctionFrameHeader:GetWidth() - 20);
    auctionFrameListItems:SetHeight(base:GetHeight() - auctionFrameHeader:GetHeight() - 1);

    auctionFrameListItems:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    auctionFrameListItems:SetBackdropColor(0.05, 0.05, 0.05, 1)
    auctionFrameListItems:SetPoint("TOPLEFT", auctionFrameHeader, "BOTTOMLEFT", 0, -1)

end

--------

local function constructAddon()

    base:Hide()

    base:SetWidth(default_width)
    base:SetHeight(default_height)

    base:SetBackdrop({["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"})
    base:SetBackdropColor(0, 0, 0, 1)
    base:SetPoint(
        local_db[POSITION_POINT],
        local_db[POSITION_X],
        local_db[POSITION_Y]
    )
    -- base:SetFrameStrata("DIALOG");

    base:EnableMouse(true)

    if not local_db[IS_ADDON_LOCKED] then

        unlockAddon(true)

    end

    ----------------------------------------------------------------
    -- INITIALISATION
    ----------------------------------------------------------------
    threshold = getTime() + step_size
    render_jobs = {}

    -- No more than 10 queries per second
    -- because the server might kick us off otherwise
    disconnection_prevention_buffer = 0.1

    active_list_items = {}
    retired_list_items = {}

    num_created_item_objects = 0
    retired_item_objects = {}

    scanned_pages = {}
    scan_results = {}

    ----------------------------------------------------------------
    -- POPULATION
    ----------------------------------------------------------------
    populateRequiredEvents()
    populateKnownSuffixes()

    ----------------------------------------------------------------
    -- CREATE CHILDREN
    ----------------------------------------------------------------
    createAuctionFrameHeader()
    createAuctionFrameListItems()

    base:SetScript(SCRIPTHANDLER_ON_UPDATE, updateDisplay)

end

--------

local function destructAddon()

    -- Stop frame updates
    base:SetScript(SCRIPTHANDLER_ON_UPDATE, nil)

    -- Remove all registered events
    removeEvents()

    -- TODO#4
    -- This is where I'd release all used objects and frames back to the core
    -- IF I HAD ONE!!!!!!!

    base:Hide()

end

--------

local function activateAddon()

    if local_db[IS_ADDON_ACTIVATED] then

        return

    end

    constructAddon()

    local_db[IS_ADDON_ACTIVATED] = true

    report(IS_ADDON_ACTIVATED, toColourisedString(local_db[IS_ADDON_ACTIVATED]))

end

--------

local function deactivateAddon()

    if not local_db[IS_ADDON_ACTIVATED] then

        return

    end

    destructAddon()

    local_db[IS_ADDON_ACTIVATED] = false

    -- This is here and not in the destructor because
    -- loadSavedVariables is not in the constructor either.
    storeLocalDatabaseToSavedVariables()

    report(IS_ADDON_ACTIVATED, toColourisedString(local_db[IS_ADDON_ACTIVATED]))

end

--------

local function toggleAddonActivity()

    if not local_db[IS_ADDON_ACTIVATED] then

        activateAddon()

    else

        deactivateAddon()

    end

end

--------

local function slashCmdHandler(message, chat_frame)

    local _,_,command_name, params = find(message, "^(%S+) *(.*)")

    command_name = tostring(command_name)

    local command = command_list[command_name]

    if (command) then

        if not isFunction(command.execute) then

            throwError("Attempt to execute slash command without execution function.")

        end

        command.execute(params)

    else

        printSlashCommandList()

    end

end

--------

local function loadProfileID()

    unit_name = UnitName("player")
    realm_name = GetRealmName()

    profile_id = unit_name .. "-" .. realm_name

end

--------

local function loadSavedVariables()

    -- First time install
    if not EdwinDB then

        EdwinDB = {}

    end

    -- this should produce an error if profile_id is not yet set, as is intended.
    local_db = EdwinDB[profile_id]

    -- This means we have a new char.
    if not local_db then

        local_db = default_db

    end

    -- In this case we have a player with an older version DB.
    if not local_db[DB_VERSION]
    or local_db[DB_VERSION] < default_db[DB_VERSION] then

        -- For now we just blindly attempt to merge.
        local_db = merge(default_db, local_db)

    end

end

--------

local function populateSlashCommandList()

    -- For now we just reset this thing.
    command_list = {}

    addSlashCommand(
        "lock",
        toggleLockToScreen,
        '<|cff9999fftoggle|r> |cff999999-- Toggle whether the addon is locked to the screen.|r',
        IS_ADDON_LOCKED
    )

    addSlashCommand(
        "activate",
        toggleAddonActivity,
        '<|cff9999fftoggle|r> |cff999999-- Toggle whether the AddOn itself is active.|r',
        IS_ADDON_ACTIVATED
    )

    addSlashCommand(
        "scan",
        scanListedAuctions,
        '<|cff9999ffaction|r> |cff999999-- Initiates a stable but slow full scan of all listed auctions.|r'
    )

end

--------

local function initialise()

    loadProfileID()
    loadSavedVariables()

    base:UnregisterEvent(initialisation_event)

    event_handlers = {}

    populateSlashCommandList()

    base:SetScript(SCRIPTHANDLER_ON_EVENT, eventCoordinator)

    addEvent(EVENT_PLAYER_LOGOUT, storeLocalDatabaseToSavedVariables)

    if local_db[IS_ADDON_ACTIVATED] then

        constructAddon()

    end

end

--------

-- local testSpeedResults

-- function logTestSpeedResults()

--     log(testSpeedResults)

-- end

--------

-- function testSpeed(x, log)

--     -- Lets create a table of x items with the name of the item in the key and perform a few simple table look ups

--     local test_start
--     local test_end
--     local rnd
--     local t
--     local max_rnd = x * 4
--     local result

--     testSpeedResults = {
--         ["test1"] = {},
--         ["test2"] = {}
--     }

--     -- test 1
--     -- setup
--     math.randomseed(1337)

--     t = {}

--     test_start = getTime() * 1000
--     for i = 1, x do

--         t["name"..i] = true

--     end
--     test_end = getTime() * 1000

--     prt(format("Setting up Test1 took: %dms", test_end - test_start))

--     -- running
--     test_start = getTime() * 1000
--     for i = 1, x / 2 do

--         rnd = math.random(1, max_rnd)

--         result = t["name"..rnd] or false

--         if log then
--             tinsert(testSpeedResults["test1"], result)
--         end

--     end
--     test_end = getTime() * 1000

--     prt(format("Test1 took: %dms", test_end - test_start))


--     -- Then try a similar thing with the same table of x items where the name of the itme is in the value
--     -- and we have to ipairs() through the whole list till we find one.

--     -- test 2
--     -- setup
--     math.randomseed(1337)

--     t = {}

--     test_start = getTime() * 1000
--     for i = 1, x do

--         tinsert(t, "name"..i)

--     end
--     test_end = getTime() * 1000

--     prt(format("Setting up Test2 took: %dms", test_end - test_start))

--     -- running
--     test_start = getTime() * 1000
--     for i = 1, x / 2 do

--         rnd = math.random(1, max_rnd)

--         result = false
--         for _, value in ipairs(t) do

--             if value == "name"..rnd then

--                 result = true
--                 break

--             end

--         end

--         if log then
--             tinsert(testSpeedResults["test2"], result)
--         end

--     end
--     test_end = getTime() * 1000

--     prt(format("Test2 took: %dms", test_end - test_start))

-- end

--------

-- Add slashcommand match entries into the global namespace for the client to pick up.
SLASH_EDWIN1 = "/edwin"

-- And add a handler to react on the above matches.
SlashCmdList["EDWIN"] = slashCmdHandler

base:SetScript(SCRIPTHANDLER_ON_EVENT, initialise)
base:RegisterEvent(initialisation_event)
