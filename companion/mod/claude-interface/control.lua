-- Claude Interface - In-game chat with Claude AI (multi-agent)
-- Communication: write_file -> bridge daemon -> Claude CLI -> RCON -> remote interface

local GUI_FRAME = "claude_interface_frame"
local MAX_MESSAGES = 100
local INPUT_FILE = "claude-chat/input.jsonl"

-- ============================================================
-- Storage
-- ============================================================

local function init_storage()
    storage.messages = storage.messages or {}
    storage.msg_counter = storage.msg_counter or 0
    storage.agents = storage.agents or {"default"}
    storage.agent_labels = storage.agent_labels or {}
    storage.active_agent = storage.active_agent or {}
    storage._rcon_queue = storage._rcon_queue or {}
    storage.spectator_mode = storage.spectator_mode or false
    -- Agent character entities and walk targets (for deterministic on_tick processing)
    storage.characters = storage.characters or {}
    storage.walk_state = storage.walk_state or {}
    storage.walk_targets = storage.walk_targets or {}
    storage.entity_queue = storage.entity_queue or {}
    -- Map markers for agent characters (chart tag references)
    storage.agent_tags = storage.agent_tags or {}
    -- In-game chat captured for the bridge. Registered in the MOD (not the
    -- level script) so every peer has an identical handler set and clients can
    -- join — runtime-injected level-script handlers break MP ("not multiplayer safe").
    storage.chat_messages = storage.chat_messages or {}
end

-- Ensure per-agent message tables exist for a player
local function ensure_agent_messages(player_index)
    if not storage.messages[player_index] then
        storage.messages[player_index] = {}
    end
    for _, agent_name in ipairs(storage.agents) do
        if not storage.messages[player_index][agent_name] then
            storage.messages[player_index][agent_name] = {}
        end
    end
end

-- Get the active agent for a player (defaults to first registered)
local function get_active_agent(player_index)
    local agent = storage.active_agent[player_index]
    if agent then
        -- Verify agent still exists
        for _, a in ipairs(storage.agents) do
            if a == agent then return agent end
        end
    end
    return storage.agents[1] or "default"
end

-- ============================================================
-- Shortcut Bar State
-- ============================================================

local function update_shortcut_state(player)
    local is_open = player.gui.screen[GUI_FRAME] ~= nil
    player.set_shortcut_toggled("claude-interface-toggle", is_open)
end

-- ============================================================
-- GUI Construction
-- ============================================================

local function get_agent_display_name(player)
    return settings.get_player_settings(player)["claude-interface-agent-label"].value or "Claude"
end

local function add_message_label(chat_flow, role, text, player)
    local caption
    if role == "user" then
        caption = "[color=1,0.85,0.4]You:[/color] " .. text
    elseif role == "claude" then
        local name = player and get_agent_display_name(player) or "Claude"
        caption = "[color=0.6,0.8,1]" .. name .. ":[/color] " .. text
    else
        caption = "[color=0.6,0.6,0.6]" .. text .. "[/color]"
    end

    local label = chat_flow.add{
        type = "label",
        caption = caption
    }
    label.style.single_line = false
    label.style.horizontally_stretchable = true
    return label
end

local function restore_chat(player, chat_flow, agent_name)
    ensure_agent_messages(player.index)
    local msgs = storage.messages[player.index][agent_name]
    if not msgs then return end
    for _, msg in ipairs(msgs) do
        add_message_label(chat_flow, msg.role, msg.text, player)
    end
end

-- Get the chat_flow for a specific agent tab
local function get_agent_chat_flow(frame, agent_name)
    if not frame or not frame.valid then return nil end
    local tabbed = frame["ci_agent_tabs"]
    if not tabbed then return nil end
    local scroll = tabbed["ci_scroll_" .. agent_name]
    if not scroll then return nil end
    return scroll["ci_chat_" .. agent_name]
end

-- Get the scroll-pane for a specific agent tab
local function get_agent_scroll(frame, agent_name)
    if not frame or not frame.valid then return nil end
    local tabbed = frame["ci_agent_tabs"]
    if not tabbed then return nil end
    return tabbed["ci_scroll_" .. agent_name]
end

-- Find the tab index for a given agent name
local function find_tab_index(tabbed, agent_name)
    for i, tab_and_content in ipairs(tabbed.tabs) do
        if tab_and_content.tab.name == "ci_tab_" .. agent_name then
            return i
        end
    end
    return nil
end

-- Get display label for a tab (short name or agent_name)
local function get_agent_label(agent_name)
    return storage.agent_labels[agent_name] or agent_name
end

-- Create a single agent tab + scroll-pane + chat_flow inside a tabbed-pane
local function create_agent_tab(tabbed, player, agent_name)
    local tab = tabbed.add{
        type = "tab",
        name = "ci_tab_" .. agent_name,
        caption = get_agent_label(agent_name),
    }

    local scroll = tabbed.add{
        type = "scroll-pane",
        name = "ci_scroll_" .. agent_name,
        direction = "vertical",
    }
    scroll.style.vertically_stretchable = true
    scroll.style.horizontally_stretchable = true

    local chat_flow = scroll.add{
        type = "flow",
        name = "ci_chat_" .. agent_name,
        direction = "vertical",
    }
    chat_flow.style.vertical_spacing = 6
    chat_flow.style.horizontally_stretchable = true

    tabbed.add_tab(tab, scroll)

    -- Restore history for this agent
    restore_chat(player, chat_flow, agent_name)
    scroll.scroll_to_bottom()

    return tab, scroll
end

local function create_gui(player)
    if player.gui.screen[GUI_FRAME] then return end

    ensure_agent_messages(player.index)

    -- Main frame
    local frame = player.gui.screen.add{
        type = "frame",
        name = GUI_FRAME,
        direction = "vertical"
    }
    frame.auto_center = true
    frame.style.width = 700
    frame.style.height = 650

    -- Titlebar: drag + close
    local titlebar = frame.add{
        type = "flow",
        name = "ci_titlebar",
        direction = "horizontal"
    }
    titlebar.drag_target = frame
    titlebar.style.vertical_align = "center"

    local title_text = settings.get_player_settings(player)["claude-interface-title"].value or "Claude AI"
    titlebar.add{
        type = "label",
        name = "ci_title",
        caption = title_text,
        style = "frame_title"
    }

    local spacer = titlebar.add{
        type = "empty-widget",
        name = "ci_spacer",
        style = "draggable_space"
    }
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame

    titlebar.add{
        type = "sprite-button",
        name = "ci_close",
        sprite = "utility/close",
        style = "close_button",
        tooltip = "Close [Ctrl+Shift+C]"
    }

    -- Tabbed pane for agents
    local tabbed = frame.add{
        type = "tabbed-pane",
        name = "ci_agent_tabs",
    }
    tabbed.style.vertically_stretchable = true
    tabbed.style.horizontally_stretchable = true

    -- Create a tab per registered agent
    local active_agent = get_active_agent(player.index)
    local active_idx = 1
    for i, agent_name in ipairs(storage.agents) do
        create_agent_tab(tabbed, player, agent_name)
        if agent_name == active_agent then
            active_idx = i
        end
    end

    -- Select the active tab
    tabbed.selected_tab_index = active_idx
    storage.active_agent[player.index] = storage.agents[active_idx]

    -- Status indicator
    frame.add{
        type = "label",
        name = "ci_status",
        caption = "[color=0.4,0.8,0.4]Ready[/color]"
    }

    -- Input area: textfield + send button
    local input_flow = frame.add{
        type = "flow",
        name = "ci_input_flow",
        direction = "horizontal"
    }
    input_flow.style.vertical_align = "center"
    input_flow.style.horizontally_stretchable = true

    local input = input_flow.add{
        type = "textfield",
        name = "ci_input",
        tooltip = "Type a message and press Enter"
    }
    input.style.horizontally_stretchable = true
    input.style.minimal_width = 0
    input.style.maximal_width = 0

    input_flow.add{
        type = "sprite-button",
        name = "ci_send",
        sprite = "utility/enter",
        style = "tool_button",
        tooltip = "Send"
    }

    -- Focus input and register for Escape-close
    input.focus()
    player.opened = frame
end

local function destroy_gui(player)
    local frame = player.gui.screen[GUI_FRAME]
    if frame and frame.valid then
        frame.destroy()
    end
end

local function toggle_gui(player)
    if player.gui.screen[GUI_FRAME] then
        destroy_gui(player)
    else
        create_gui(player)
    end
    update_shortcut_state(player)
end

-- ============================================================
-- Chat Logic
-- ============================================================

local function save_message(player_index, agent_name, role, text)
    ensure_agent_messages(player_index)
    local msgs = storage.messages[player_index][agent_name]
    table.insert(msgs, {
        role = role,
        text = text,
        tick = game.tick,
    })
    while #msgs > MAX_MESSAGES do
        table.remove(msgs, 1)
    end
end

local function add_chat_message(player, agent_name, role, text)
    save_message(player.index, agent_name, role, text)

    local frame = player.gui.screen[GUI_FRAME]
    if not frame or not frame.valid then return end

    local chat_flow = get_agent_chat_flow(frame, agent_name)
    if not chat_flow then return end
    add_message_label(chat_flow, role, text, player)

    while #chat_flow.children > MAX_MESSAGES do
        chat_flow.children[1].destroy()
    end

    local scroll = get_agent_scroll(frame, agent_name)
    if scroll then scroll.scroll_to_bottom() end

    -- Badge for non-active tabs
    local active = get_active_agent(player.index)
    if agent_name ~= active and role ~= "user" then
        local tabbed = frame["ci_agent_tabs"]
        if tabbed then
            local tab_idx = find_tab_index(tabbed, agent_name)
            if tab_idx then
                local tab_obj = tabbed.tabs[tab_idx].tab
                local current = tab_obj.badge_text
                local count = 0
                if current and current ~= "" then
                    count = tonumber(current) or 0
                end
                tab_obj.badge_text = tostring(count + 1)
            end
        end
    end
end

local function set_status(player, status_text)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame or not frame.valid then return end
    frame["ci_status"].caption = status_text
end

local function send_to_bridge(player, message)
    storage.msg_counter = storage.msg_counter + 1
    local target = get_active_agent(player.index)
    local payload = {
        id = storage.msg_counter,
        player_index = player.index,
        player_name = player.name,
        message = message,
        target_agent = target,
        tick = game.tick,
    }
    helpers.write_file(INPUT_FILE, helpers.table_to_json(payload) .. "\n", true, 0)
end

local function handle_send(player)
    local frame = player.gui.screen[GUI_FRAME]
    if not frame or not frame.valid then return end

    local input = frame["ci_input_flow"]["ci_input"]
    local text = input.text
    if text == "" or text == nil then return end

    input.text = ""
    input.focus()

    local agent_name = get_active_agent(player.index)
    add_chat_message(player, agent_name, "user", text)
    set_status(player, "[color=1,0.8,0.2]Thinking...[/color]")
    send_to_bridge(player, text)
end

-- ============================================================
-- Agent Management
-- ============================================================

local function agent_exists(name)
    for _, a in ipairs(storage.agents) do
        if a == name then return true end
    end
    return false
end

local function register_agent(agent_name, label)
    if label then
        storage.agent_labels[agent_name] = label
    end
    if agent_exists(agent_name) then return end
    table.insert(storage.agents, agent_name)

    -- Create message tables for all players
    for _, player in pairs(game.players) do
        ensure_agent_messages(player.index)
    end

    -- Add tab to all open GUIs
    for _, player in pairs(game.players) do
        local frame = player.gui.screen[GUI_FRAME]
        if frame and frame.valid then
            local tabbed = frame["ci_agent_tabs"]
            if tabbed then
                create_agent_tab(tabbed, player, agent_name)
            end
        end
    end
end

local function unregister_agent(agent_name)
    -- Allow removing "default" only if other agents exist
    if agent_name == "default" and #storage.agents <= 1 then return end
    local idx = nil
    for i, a in ipairs(storage.agents) do
        if a == agent_name then idx = i; break end
    end
    if not idx then return end

    table.remove(storage.agents, idx)

    -- Remove tab from all open GUIs
    for _, player in pairs(game.players) do
        local frame = player.gui.screen[GUI_FRAME]
        if frame and frame.valid then
            local tabbed = frame["ci_agent_tabs"]
            if tabbed then
                local tab_idx = find_tab_index(tabbed, agent_name)
                if tab_idx then
                    tabbed.remove_tab(tabbed.tabs[tab_idx].tab)
                    -- Clean up the scroll pane element
                    local scroll = tabbed["ci_scroll_" .. agent_name]
                    if scroll then scroll.destroy() end
                    local tab_el = tabbed["ci_tab_" .. agent_name]
                    if tab_el then tab_el.destroy() end
                end
            end
        end

        -- Reset active agent if it was the removed one
        if storage.active_agent[player.index] == agent_name then
            storage.active_agent[player.index] = storage.agents[1] or "default"
        end
    end
end

-- ============================================================
-- Queue Processing (on_tick)
-- ============================================================

-- Apply walk states to agent characters each tick.
-- Processed in on_tick for deterministic multiplayer behavior.
local function process_walk_states()
    if not storage.walk_state then return end
    local to_remove = {}
    for agent_id, ws in pairs(storage.walk_state) do
        local c = storage.characters[agent_id]
        if c and c.valid then
            c.walking_state = ws
        end
        -- Clean up stopped entries (applied once, then removed)
        if not ws.walking then
            table.insert(to_remove, agent_id)
        end
    end
    for _, agent_id in ipairs(to_remove) do
        storage.walk_state[agent_id] = nil
    end
end

-- Step queued walk targets for agent characters each tick.
-- Processed in on_tick for deterministic multiplayer behavior.
local function process_walk_targets()
    if not storage.walk_targets then return end
    for agent_id, tgt in pairs(storage.walk_targets) do
        local c = storage.characters[agent_id]
        if not (c and c.valid) then
            storage.walk_targets[agent_id] = nil
            if storage.walk_state then storage.walk_state[agent_id] = nil end
            goto continue
        end
        if tgt.expires_tick and game.tick >= tgt.expires_tick then
            storage.walk_targets[agent_id] = nil
            c.walking_state = {walking = false}
            goto continue
        end

        local dx = tgt.x - c.position.x
        local dy = tgt.y - c.position.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local sp = c.character_running_speed or 0.15

        if dist <= sp then
            c.teleport({tgt.x, tgt.y})
            storage.walk_targets[agent_id] = nil
            c.walking_state = {walking = false}
        else
            local last_x = tgt.last_x or c.position.x
            local last_y = tgt.last_y or c.position.y
            local nx = c.position.x + (dx / dist) * sp
            local ny = c.position.y + (dy / dist) * sp
            if not c.teleport({nx, ny}) then
                if not c.teleport({nx, c.position.y}) then
                    c.teleport({c.position.x, ny})
                end
            end

            -- Teleport is the ONLY mover. Never set walking_state.walking = true:
            -- the engine then physically walks the orphan character cardinally on
            -- top of the teleport, and on expiry/stuck clears it keeps walking for
            -- hundreds of tiles (the "positional discontinuity" runaway).
            c.walking_state = {walking = false}

            local moved = math.sqrt((c.position.x - last_x) * (c.position.x - last_x) + (c.position.y - last_y) * (c.position.y - last_y))
            if moved < 0.001 then
                tgt.stuck_ticks = (tgt.stuck_ticks or 0) + 1
            else
                tgt.stuck_ticks = 0
            end
            tgt.last_x = c.position.x
            tgt.last_y = c.position.y
            if tgt.stuck_ticks >= 120 then
                storage.walk_targets[agent_id] = nil
                c.walking_state = {walking = false}
            end
        end

        ::continue::
    end
end

-- Apply queued entity operations each tick (rotation, etc.).
-- Processed in on_tick for deterministic multiplayer behavior.
local function process_entity_queue()
    if not storage.entity_queue or #storage.entity_queue == 0 then return end
    local queue = storage.entity_queue
    storage.entity_queue = {}
    for _, item in ipairs(queue) do
        if item.action == "rotate" then
            local surface = game.surfaces[item.surface_name]
            if surface then
                for _, e in pairs(surface.find_entities_filtered{area = {{-500, -500}, {500, 500}}}) do
                    if e.unit_number == item.unit_number then
                        if e.supports_direction then
                            e.direction = item.direction
                        end
                        break
                    end
                end
            end
        end
    end
end

-- Update map markers for agent characters (every 60 ticks = 1 second)
local function update_agent_markers()
    if not storage.characters then return end
    if not storage.agent_tags then storage.agent_tags = {} end
    for agent_id, c in pairs(storage.characters) do
        if c and c.valid then
            local tag = storage.agent_tags[agent_id]
            if tag and tag.valid then
                -- Update position if moved
                local tp = tag.position
                local cp = c.position
                if tp.x ~= cp.x or tp.y ~= cp.y then
                    tag.position = cp
                end
            else
                -- Create new chart tag
                local label = storage.agent_labels[agent_id] or agent_id
                local new_tag = c.force.add_chart_tag(c.surface, {
                    position = c.position,
                    text = label,
                })
                if new_tag then
                    storage.agent_tags[agent_id] = new_tag
                end
            end
        else
            -- Character gone — remove tag
            local tag = storage.agent_tags[agent_id]
            if tag and tag.valid then tag.destroy() end
            storage.agent_tags[agent_id] = nil
        end
    end
end

-- Process queued RCON commands deterministically in on_tick.
-- This prevents desync in multiplayer: RCON pushes to queue,
-- on_tick processes it identically on server and all clients.
local function process_rcon_queue()
    if not storage._rcon_queue or #storage._rcon_queue == 0 then return end
    local queue = storage._rcon_queue
    storage._rcon_queue = {}
    for _, item in ipairs(queue) do
        -- Skip GUI updates for injected/synthetic messages (player_index=0)
        local pi = item.pi or 0
        if item.type == "response" then
            if pi > 0 then
                local player = game.get_player(pi)
                if player then
                    add_chat_message(player, item.agent, "claude", item.text)
                    set_status(player, "[color=0.4,0.8,0.4]Ready[/color]")
                end
            end
        elseif item.type == "tool" then
            -- Tool calls only shown in status bar, not in chat log
            if pi > 0 then
                local player = game.get_player(pi)
                if player then
                    set_status(player, "[color=0.6,0.7,1]Using " .. item.tool .. "...[/color]")
                end
            end
        elseif item.type == "status" then
            if pi > 0 then
                local player = game.get_player(pi)
                if player then
                    set_status(player, item.text)
                end
            end
        elseif item.type == "register" then
            register_agent(item.agent, item.label)
        elseif item.type == "unregister" then
            unregister_agent(item.agent)
        elseif item.type == "clear" then
            if pi < 1 then goto continue end
            local player = game.get_player(pi)
            if player then
                if item.agent then
                    if storage.messages[item.pi] then
                        storage.messages[item.pi][item.agent] = {}
                    end
                    local frame = player.gui.screen[GUI_FRAME]
                    if frame and frame.valid then
                        local chat_flow = get_agent_chat_flow(frame, item.agent)
                        if chat_flow then chat_flow.clear() end
                    end
                else
                    storage.messages[item.pi] = {}
                    ensure_agent_messages(item.pi)
                    local frame = player.gui.screen[GUI_FRAME]
                    if frame and frame.valid then
                        for _, a in ipairs(storage.agents) do
                            local chat_flow = get_agent_chat_flow(frame, a)
                            if chat_flow then chat_flow.clear() end
                        end
                    end
                end
            end
        elseif item.type == "spectator" then
            storage.spectator_mode = item.enabled
            if item.enabled then
                for _, player in pairs(game.players) do
                    if player.connected and player.controller_type ~= defines.controllers.spectator then
                        player.set_controller{type = defines.controllers.spectator}
                    end
                end
            end
        end
        ::continue::
    end
end

-- ============================================================
-- Remote Interface (called by bridge via RCON)
-- All state-modifying operations push to _rcon_queue for
-- deterministic processing in on_tick (prevents MP desync).
-- ============================================================

local function pos_table(pos)
    if not pos then return nil end
    return {x = pos.x, y = pos.y}
end

local function fluid_table(fluid)
    if not fluid then return nil end
    if type(fluid) == "string" then
        return {name = fluid}
    end
    return {
        name = fluid.name,
        amount = fluid.amount,
        temperature = fluid.temperature,
    }
end

local function fluid_filter_name(filter)
    if not filter then return nil end
    if type(filter) == "string" then return filter end
    if type(filter) == "table" then
        if type(filter.name) == "string" then return filter.name end
        if type(filter.name) == "table" and filter.name.name then return filter.name.name end
    end
    return tostring(filter)
end

local function inventory_contents(inv)
    local result = {}
    if not inv then return result end
    for _, item in pairs(inv.get_contents()) do
        table.insert(result, {name = item.name, count = item.count})
    end
    return result
end

local function status_name(status_value)
    if status_value == nil then return nil end
    for name, value in pairs(defines.entity_status) do
        if value == status_value then return name end
    end
    return tostring(status_value)
end

local function safe_entity_status(entity)
    local ok, value = pcall(function() return entity.status end)
    if ok then return status_name(value) end
    return nil
end

local function append_steam_issue(result, issue_type, severity, entity, message, action)
    table.insert(result.issues, {
        type = issue_type,
        severity = severity,
        entity = entity and {
            unit_number = entity.unit_number,
            name = entity.name,
            position = pos_table(entity.position),
        } or nil,
        message = message,
        action = action,
    })
    if action then table.insert(result.suggested_actions, action) end
end

local function fluidbox_neighbours(entity, index)
    local neighbours = {}
    local ok, records = pcall(function()
        return entity.get_fluid_box_neighbours(index)
    end)
    if ok and type(records) == "table" then
        for _, record in pairs(records) do
            if record.entity then
                table.insert(neighbours, {
                    name = record.entity.name,
                    unit_number = record.entity.unit_number,
                    position = pos_table(record.entity.position),
                    fluidbox_index = record.index,
                })
            end
        end
    end
    return neighbours
end

local function fluidbox_pipe_connections(entity, index)
    local connections = {}
    local ok, records = pcall(function()
        return entity.get_fluid_box_pipe_connections(index)
    end)
    if ok and type(records) == "table" then
        for _, connection in pairs(records) do
            local target = connection.target
            table.insert(connections, {
                flow_direction = tostring(connection.flow_direction),
                connection_type = tostring(connection.connection_type),
                position = pos_table(connection.position),
                target_position = pos_table(connection.target_position),
                target = target and {
                    name = target.name,
                    unit_number = target.unit_number,
                    position = pos_table(target.position),
                } or nil,
                target_fluidbox_index = connection.target_fluidbox_index,
                target_pipe_connection_index = connection.target_pipe_connection_index,
            })
        end
    end
    return connections
end

local function describe_fluidboxes(entity, result)
    local boxes = {}
    for index = 1, 12 do
        local info = {
            index = index,
            neighbours = {},
            pipe_connections = {},
        }
        local has_box = false

        local ok_capacity, capacity = pcall(function()
            return entity.get_fluid_capacity(index)
        end)
        if ok_capacity and capacity ~= nil then
            info.capacity = capacity
            has_box = true
        end

        local ok_filter, filter = pcall(function()
            return entity.get_fluid_filter(index)
        end)
        if ok_filter and filter ~= nil then
            info.filter = fluid_filter_name(filter)
            has_box = true
        end

        local ok_fluid, fluid = pcall(function()
            return entity.get_fluid(index)
        end)
        if ok_fluid and fluid ~= nil then
            info.fluid = fluid_table(fluid)
            has_box = true
        end

        local ok_has_segment, has_segment = pcall(function()
            return entity.has_fluid_segment(index)
        end)
        if ok_has_segment and has_segment then
            info.has_segment = true
            has_box = true

            local ok_segment_id, segment_id = pcall(function()
                return entity.get_fluid_segment_id(index)
            end)
            if ok_segment_id and segment_id ~= nil then
                info.segment_id = segment_id
            end

            local ok_segment_fluid, segment_fluid = pcall(function()
                return entity.get_fluid_segment_fluid(index)
            end)
            if ok_segment_fluid and segment_fluid ~= nil then
                info.segment_fluid = fluid_table(segment_fluid)
            end

            local ok_segment_capacity, segment_capacity = pcall(function()
                return entity.get_fluid_segment_capacity(index)
            end)
            if ok_segment_capacity and segment_capacity ~= nil then
                info.segment_capacity = segment_capacity
            end

            local ok_extent, extent = pcall(function()
                return entity.get_fluid_segment_extent_bounding_box(index)
            end)
            if ok_extent and extent then
                info.segment_extent = {
                    left_top = pos_table(extent.left_top),
                    right_bottom = pos_table(extent.right_bottom),
                }
            end

            if info.segment_id then
                local key = tostring(info.segment_id)
                if not result.fluid_segments[key] then
                    result.fluid_segments[key] = {
                        id = info.segment_id,
                        fluid = info.segment_fluid,
                        capacity = info.segment_capacity,
                        members = {},
                    }
                end
                table.insert(result.fluid_segments[key].members, {
                    unit_number = entity.unit_number,
                    name = entity.name,
                    position = pos_table(entity.position),
                    fluidbox_index = index,
                })
                result.fluid_segments[key].member_count = #result.fluid_segments[key].members
            end
        end

        local neighbours = fluidbox_neighbours(entity, index)
        if #neighbours > 0 then
            info.neighbours = neighbours
            has_box = true
        end

        local pipe_connections = fluidbox_pipe_connections(entity, index)
        if #pipe_connections > 0 then
            info.pipe_connections = pipe_connections
            has_box = true
        end

        if has_box then table.insert(boxes, info) end
    end
    return boxes
end

local function diagnose_steam_power_impl(x, y, radius)
    local surface = game.surfaces[1]
    local r = radius or 50
    local area = {{x - r, y - r}, {x + r, y + r}}
    local result = {
        area = {
            center = {x = x, y = y},
            radius = r,
        },
        summary = {
            offshore_pumps = 0,
            boilers = 0,
            steam_engines = 0,
            pipes = 0,
            electric_poles = 0,
        },
        entities = {},
        fluid_segments = {},
        issues = {},
        suggested_actions = {},
    }

    local poles = surface.find_entities_filtered{type = "electric-pole", area = area, force = "player"}
    result.summary.electric_poles = #poles

    local steam_entities = surface.find_entities_filtered{
        area = area,
        force = "player",
        name = {"offshore-pump", "boiler", "steam-engine", "pipe", "pipe-to-ground"},
    }

    for _, entity in pairs(steam_entities) do
        if entity.name == "offshore-pump" then result.summary.offshore_pumps = result.summary.offshore_pumps + 1 end
        if entity.name == "boiler" then result.summary.boilers = result.summary.boilers + 1 end
        if entity.name == "steam-engine" then result.summary.steam_engines = result.summary.steam_engines + 1 end
        if entity.name == "pipe" or entity.name == "pipe-to-ground" then result.summary.pipes = result.summary.pipes + 1 end

        local item = {
            unit_number = entity.unit_number,
            name = entity.name,
            type = entity.type,
            position = pos_table(entity.position),
            direction = entity.direction,
            status = safe_entity_status(entity),
            fluid_contents = {},
            fluidboxes = {},
        }

        local ok_contents, contents = pcall(function()
            return entity.get_fluid_contents()
        end)
        if ok_contents and type(contents) == "table" then
            for name, amount in pairs(contents) do
                table.insert(item.fluid_contents, {name = name, amount = amount})
            end
        end

        if entity.burner then
            local fuel_inv = entity.get_fuel_inventory()
            item.fuel = {
                total = fuel_inv and fuel_inv.get_item_count() or 0,
                inventory = inventory_contents(fuel_inv),
            }
        end

        local ok_connected, connected = pcall(function()
            return entity.is_connected_to_electric_network()
        end)
        if ok_connected then item.connected_to_electric_network = connected end

        item.fluidboxes = describe_fluidboxes(entity, result)
        table.insert(result.entities, item)

        if entity.name == "boiler" then
            if item.fuel and item.fuel.total == 0 then
                append_steam_issue(result, "boiler_no_fuel", "critical", entity, "Boiler has no fuel.", "Insert coal or another fuel into boiler unit " .. tostring(entity.unit_number) .. ".")
            end
            if item.status == "no_input_fluid" then
                append_steam_issue(result, "boiler_no_water", "critical", entity, "Boiler is missing water input.", "Connect offshore pump water output to boiler unit " .. tostring(entity.unit_number) .. " water input.")
            elseif item.status == "full_output" then
                append_steam_issue(result, "boiler_steam_output_blocked", "critical", entity, "Boiler has steam but cannot drain it.", "Connect boiler unit " .. tostring(entity.unit_number) .. " steam output to a steam engine input, or move the blocking engine/pipe.")
            end
        elseif entity.name == "steam-engine" then
            if item.status == "no_input_fluid" then
                append_steam_issue(result, "steam_engine_no_steam", "critical", entity, "Steam engine is missing steam input.", "Connect a boiler steam output to steam engine unit " .. tostring(entity.unit_number) .. ".")
            end
            local nearby_poles = surface.find_entities_filtered{type = "electric-pole", position = entity.position, radius = 8, force = "player", limit = 1}
            if #nearby_poles == 0 then
                append_steam_issue(result, "steam_engine_not_on_grid", "warning", entity, "Steam engine has no electric pole close enough to receive generated power.", "Place an electric pole within wire reach of steam engine unit " .. tostring(entity.unit_number) .. ".")
            end
        elseif entity.name == "offshore-pump" then
            if item.status == "no_power" then
                append_steam_issue(result, "offshore_pump_no_power", "critical", entity, "Offshore pump reports no power.", "Move/rebuild pump at a valid shoreline or inspect modded pump requirements.")
            elseif item.status == "no_input_fluid" then
                append_steam_issue(result, "offshore_pump_not_on_water", "critical", entity, "Offshore pump is not receiving water.", "Rebuild offshore pump on a valid shoreline tile.")
            end
        end
    end

    if result.summary.offshore_pumps == 0 then
        table.insert(result.suggested_actions, "No offshore pump in area; locate shoreline before building steam power.")
    end
    if result.summary.boilers == 0 then
        table.insert(result.suggested_actions, "No boiler in area; build one between pump water output and steam engine input.")
    end
    if result.summary.steam_engines == 0 then
        table.insert(result.suggested_actions, "No steam engine in area; build one on boiler steam output.")
    end

    return result
end

remote.add_interface("claude_interface", {
    receive_response = function(player_index, agent_name, text)
        table.insert(storage._rcon_queue, {
            type = "response", pi = player_index,
            agent = agent_name or "default", text = text,
        })
    end,

    tool_status = function(player_index, agent_name, tool_name)
        table.insert(storage._rcon_queue, {
            type = "tool", pi = player_index,
            agent = agent_name or "default", tool = tool_name,
        })
    end,

    set_status = function(player_index, status_text)
        table.insert(storage._rcon_queue, {
            type = "status", pi = player_index, text = status_text,
        })
    end,

    clear_chat = function(player_index, agent_name)
        table.insert(storage._rcon_queue, {
            type = "clear", pi = player_index, agent = agent_name,
        })
    end,

    register_agent = function(agent_name, label)
        table.insert(storage._rcon_queue, {
            type = "register", agent = agent_name, label = label,
        })
    end,

    unregister_agent = function(agent_name)
        table.insert(storage._rcon_queue, {
            type = "unregister", agent = agent_name,
        })
    end,

    -- Register an agent character entity for on_tick walk processing
    register_character = function(agent_id, entity)
        if not storage.characters then storage.characters = {} end
        storage.characters[agent_id] = entity
    end,

    -- Set walking direction for an agent (processed in on_tick)
    set_walk = function(agent_id, direction)
        if not storage.walk_state then storage.walk_state = {} end
        storage.walk_state[agent_id] = {walking = true, direction = direction}
    end,

    -- Stop walking for an agent (processed in on_tick)
    stop_walk = function(agent_id)
        if not storage.walk_state then storage.walk_state = {} end
        storage.walk_state[agent_id] = {walking = false}
    end,

    -- Set target position for deterministic agent step-walking (processed in on_tick)
    set_walk_target = function(agent_id, x, y)
        if not storage.walk_targets then storage.walk_targets = {} end
        -- Drop any durable directional walk_state so it can't co-drive the
        -- character alongside the teleport stepper (audit F1/F2).
        if storage.walk_state then storage.walk_state[agent_id] = nil end
        storage.walk_targets[agent_id] = {x = x, y = y, stuck_ticks = 0, expires_tick = game.tick + 7200}
    end,

    -- Clear target position AND any leftover walk state for an agent. Must reset
    -- walking_state too, or a stale {walking=true} keeps the orphan character
    -- engine-walking with no target (audit F2 trapdoor).
    clear_walk_target = function(agent_id)
        if storage.walk_targets then storage.walk_targets[agent_id] = nil end
        if storage.walk_state then storage.walk_state[agent_id] = nil end
        local c = storage.characters and storage.characters[agent_id]
        if c and c.valid then c.walking_state = {walking = false} end
    end,

    -- Report whether an agent has an active deterministic walk target
    has_walk_target = function(agent_id)
        return storage.walk_targets ~= nil and storage.walk_targets[agent_id] ~= nil
    end,

    -- Return and clear captured chat messages as a JSON string (bridge polls this)
    get_chat_messages = function()
        local msgs = storage.chat_messages or {}
        storage.chat_messages = {}
        return helpers.table_to_json(msgs)
    end,

    -- Get character entity (safe from any context, uses synced mod storage)
    get_character = function(agent_id)
        if not storage.characters then return nil end
        local c = storage.characters[agent_id]
        if c and c.valid then return c end
        return nil
    end,

    -- List all agent characters as JSON string
    list_characters = function()
        if not storage.characters then return "[]" end
        local result = {}
        for agent_id, c in pairs(storage.characters) do
            if c and c.valid then
                table.insert(result, {
                    agent_id = agent_id,
                    unit_number = c.unit_number,
                    position = { x = c.position.x, y = c.position.y },
                    health = c.health
                })
            end
        end
        return helpers.table_to_json(result)
    end,

    -- Diagnose steam-power fluid and electric connectivity near a position.
    diagnose_steam_power = function(x, y, radius)
        local ok, result_or_error = pcall(function()
            return diagnose_steam_power_impl(x, y, radius)
        end)
        if not ok then
            return helpers.table_to_json({
                error = tostring(result_or_error),
                action_needed = "fix_diagnose_steam_power",
            })
        end
        return helpers.table_to_json(result_or_error)
    end,

    -- Get character position (read-only, safe from any context)
    get_character_pos = function(agent_id)
        if not storage.characters then return nil end
        local c = storage.characters[agent_id]
        if c and c.valid then
            return c.position.x .. "," .. c.position.y
        end
        return nil
    end,

    -- Queue spectator mode change (processed in on_tick for MP determinism)
    set_spectator_mode = function(enabled)
        table.insert(storage._rcon_queue, {
            type = "spectator", enabled = enabled,
        })
    end,

    -- Queue entity rotation (processed in on_tick for MP determinism)
    queue_rotate = function(unit_number, direction, surface_name)
        if not storage.entity_queue then storage.entity_queue = {} end
        table.insert(storage.entity_queue, {
            action = "rotate",
            unit_number = unit_number,
            direction = direction,
            surface_name = surface_name,
        })
    end,

    -- Inject a message into the bridge input as if from a player.
    -- Used by supervisor sessions to send tasks to agents.
    inject_message = function(from_name, target_agent, message)
        helpers.write_file(INPUT_FILE, helpers.table_to_json({
            player_index = 0,
            player_name = from_name or "Supervisor",
            target_agent = target_agent or "all",
            message = message,
        }) .. "\n", true, 0)
    end,

    ping = function()
        rcon.print("pong")
    end,
})

-- ============================================================
-- Event Handlers
-- ============================================================

script.on_init(init_storage)

-- Process RCON queue and walk states every tick
script.on_event(defines.events.on_tick, function(event)
    process_rcon_queue()
    process_walk_states()
    process_walk_targets()
    process_entity_queue()
    -- Update map markers every 60 ticks (~1 second)
    if event.tick % 60 == 0 then
        update_agent_markers()
    end
end)

script.on_configuration_changed(function(data)
    -- Migrate old flat messages to per-agent structure
    if storage.messages then
        for player_index, msgs in pairs(storage.messages) do
            -- Detect old format: flat array of {role, text, tick}
            if msgs[1] and msgs[1].role then
                storage.messages[player_index] = {default = msgs}
            end
        end
    end

    init_storage()

    -- Rebuild GUI for existing players after mod update
    for _, player in pairs(game.players) do
        local frame = player.gui.screen[GUI_FRAME]
        if frame and frame.valid then
            frame.destroy()
            create_gui(player)
        end
        update_shortcut_state(player)
    end
end)

-- Settings changed — rebuild GUI to pick up new title/label
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "claude-interface-title" or event.setting == "claude-interface-agent-label" then
        local player = game.get_player(event.player_index)
        if player then
            local frame = player.gui.screen[GUI_FRAME]
            if frame and frame.valid then
                frame.destroy()
                create_gui(player)
            end
        end
    end
end)

-- Auto-spectator: when spectator_mode is enabled, new players join as spectators
script.on_event(defines.events.on_player_joined_game, function(event)
    if storage.spectator_mode then
        local player = game.get_player(event.player_index)
        if player and player.controller_type ~= defines.controllers.spectator then
            player.set_controller{type = defines.controllers.spectator}
        end
    end
end)

-- Capture in-game chat for the bridge (registered in the mod -> MP-safe)
script.on_event(defines.events.on_console_chat, function(event)
    if not event.message then return end
    storage.chat_messages = storage.chat_messages or {}
    local player_name = "console"
    if event.player_index then
        local p = game.get_player(event.player_index)
        if p then player_name = p.name end
    end
    table.insert(storage.chat_messages, {
        player = player_name,
        message = event.message,
        tick = event.tick,
    })
    while #storage.chat_messages > MAX_MESSAGES do
        table.remove(storage.chat_messages, 1)
    end
end)

-- Hotkey toggle
script.on_event("claude-interface-toggle", function(event)
    local player = game.get_player(event.player_index)
    if player then toggle_gui(player) end
end)

-- Shortcut bar toggle
script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name ~= "claude-interface-toggle" then return end
    local player = game.get_player(event.player_index)
    if player then toggle_gui(player) end
end)

-- Tab switching
script.on_event(defines.events.on_gui_selected_tab_changed, function(event)
    if not event.element or not event.element.valid then return end
    if event.element.name ~= "ci_agent_tabs" then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local tabbed = event.element
    local idx = tabbed.selected_tab_index
    if not idx or not tabbed.tabs[idx] then return end

    local tab_obj = tabbed.tabs[idx].tab
    local tab_name = tab_obj.name  -- "ci_tab_<agent_name>"
    local agent_name = tab_name:sub(8)  -- strip "ci_tab_"

    storage.active_agent[player.index] = agent_name

    -- Clear badge on newly selected tab
    tab_obj.badge_text = ""
end)

-- Click handler
script.on_event(defines.events.on_gui_click, function(event)
    if not event.element or not event.element.valid then return end
    local name = event.element.name

    if name == "ci_send" then
        handle_send(game.get_player(event.player_index))
    elseif name == "ci_close" then
        local player = game.get_player(event.player_index)
        destroy_gui(player)
        update_shortcut_state(player)
    end
end)

-- Enter key submits
script.on_event(defines.events.on_gui_confirmed, function(event)
    if not event.element or not event.element.valid then return end
    if event.element.name == "ci_input" then
        handle_send(game.get_player(event.player_index))
    end
end)

-- Escape closes
script.on_event(defines.events.on_gui_closed, function(event)
    if event.element and event.element.valid and event.element.name == GUI_FRAME then
        local player = game.get_player(event.player_index)
        destroy_gui(player)
        update_shortcut_state(player)
    end
end)
