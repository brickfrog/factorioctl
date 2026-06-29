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
    storage.blueprints = storage.blueprints or {}
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

local function find_entity_by_unit_number(unit_number)
    storage.factorioctl_entities = storage.factorioctl_entities or {}
    local registered = storage.factorioctl_entities[unit_number]
    if registered and registered.valid then return registered end
    storage.factorioctl_entities[unit_number] = nil

    for _, surface in pairs(game.surfaces) do
        local entities = surface.find_entities_filtered{area = {{-500, -500}, {500, 500}}}
        for _, entity in pairs(entities) do
            if entity.unit_number == unit_number then
                storage.factorioctl_entities[unit_number] = entity
                return entity
            end
        end
    end
    return nil
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

local function raw_entity_status(entity)
    local ok, value = pcall(function() return entity.status end)
    if ok then return value end
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

local POWER_CONSUMER_TYPES = {
    "assembling-machine",
    "furnace",
    "lab",
    "mining-drill",
    "inserter",
    "beacon",
    "radar",
}

local POWER_ISSUE_CONSUMER_TYPES = {
    "assembling-machine",
    "furnace",
    "lab",
    "mining-drill",
    "inserter",
    "beacon",
    "radar",
    "lamp",
    "roboport",
}

local POLE_SUPPLY_AREAS = {
    ["small-electric-pole"] = 2.5,
    ["medium-electric-pole"] = 3.5,
    ["big-electric-pole"] = 2.0,
    ["substation"] = 9.0,
}

local function area_around(x, y, radius)
    local r = radius or 50
    return r, {{x - r, y - r}, {x + r, y + r}}
end

local function entity_uses_electricity(entity)
    local proto = prototypes.entity[entity.name]
    if not proto then return false end
    local ok, uses_electric = pcall(function()
        return proto.electric_energy_source_prototype ~= nil
    end)
    return ok and uses_electric
end

local function entity_position_record(entity)
    return {
        name = entity.name,
        x = entity.position.x,
        y = entity.position.y,
        unit_number = entity.unit_number,
    }
end

local function build_power_coverage(surface, area, x, y, radius, display_ids)
    local poles = surface.find_entities_filtered{
        type = "electric-pole",
        area = area,
        force = "player",
    }
    local coverage = {}
    local network_map = {}
    local next_display_id = 1
    local networks = {}
    local pole_records = {}

    for _, pole in pairs(poles) do
        local network_id = pole.electric_network_id
        if display_ids and network_id and not network_map[network_id] then
            network_map[network_id] = next_display_id
            networks[tostring(next_display_id)] = network_id
            next_display_id = next_display_id + 1
            if next_display_id > 9 then next_display_id = 9 end
        end

        local supply_dist = POLE_SUPPLY_AREAS[pole.name] or 2.5
        local coverage_id = display_ids and (network_map[network_id] or 0) or network_id
        if display_ids then
            table.insert(pole_records, {
                name = pole.name,
                x = pole.position.x,
                y = pole.position.y,
                network_id = network_id,
                display_id = coverage_id,
                supply_area = supply_dist,
            })
        end

        local px, py = math.floor(pole.position.x), math.floor(pole.position.y)
        local sd = math.ceil(supply_dist)
        for dx = -sd, sd do
            for dy = -sd, sd do
                if dx * dx + dy * dy <= supply_dist * supply_dist then
                    local tx, ty = px + dx, py + dy
                    if not display_ids or (tx >= x - radius and tx <= x + radius and ty >= y - radius and ty <= y + radius) then
                        coverage[tx .. "," .. ty] = coverage_id
                    end
                end
            end
        end
    end

    return coverage, poles, pole_records, networks
end

local function get_power_status_impl(x, y, radius)
    local surface = game.surfaces[1]
    local r, area = area_around(x, y, radius)
    local poles = surface.find_entities_filtered{
        type = "electric-pole",
        area = area,
        force = "player",
    }

    if #poles == 0 then
        return {error = "No electric poles found in area"}
    end

    local pole = poles[1]
    local network_id = pole.electric_network_id
    local result = {
        network_id = network_id,
        pole_count = #poles,
        generators = {},
        consumers = {
            working = 0,
            low_power = 0,
            no_power = 0,
            total = 0,
        },
        production_kw = 0,
        consumption_kw = 0,
        satisfaction = "unknown",
    }

    local generator_counts = {}
    local total_production = 0
    local generators = surface.find_entities_filtered{
        area = area,
        type = {"generator", "solar-panel", "accumulator"},
        force = "player",
    }

    for _, gen in pairs(generators) do
        local connected_pole = surface.find_entities_filtered{
            type = "electric-pole",
            position = gen.position,
            radius = 10,
            force = "player",
            limit = 1,
        }[1]
        if connected_pole and connected_pole.electric_network_id == network_id then
            generator_counts[gen.name] = (generator_counts[gen.name] or 0) + 1
            if gen.type == "generator" then
                total_production = total_production + (gen.energy_generated_last_tick or 0) * 60 / 1000
            elseif gen.type == "solar-panel" then
                total_production = total_production + 60 * surface.daytime
            end
        end
    end

    for name, count in pairs(generator_counts) do
        table.insert(result.generators, {name = name, count = count})
    end

    local total_consumption = 0
    local consumers_by_status = {working = {}, low_power = {}, no_power = {}}
    for _, entity_type in pairs(POWER_CONSUMER_TYPES) do
        local entities = surface.find_entities_filtered{
            area = area,
            type = entity_type,
            force = "player",
        }
        for _, ent in pairs(entities) do
            if entity_uses_electricity(ent) then
                result.consumers.total = result.consumers.total + 1
                local status = raw_entity_status(ent)
                if status == defines.entity_status.no_power then
                    result.consumers.no_power = result.consumers.no_power + 1
                    table.insert(consumers_by_status.no_power, entity_position_record(ent))
                elseif status == defines.entity_status.low_power then
                    result.consumers.low_power = result.consumers.low_power + 1
                    table.insert(consumers_by_status.low_power, entity_position_record(ent))
                elseif status == defines.entity_status.working then
                    result.consumers.working = result.consumers.working + 1
                end

                local proto = prototypes.entity[ent.name]
                pcall(function()
                    local usage = proto.energy_usage or 0
                    if status == defines.entity_status.working then
                        total_consumption = total_consumption + usage * 60 / 1000
                    end
                end)
            end
        end
    end

    result.production_kw = math.floor(total_production)
    result.consumption_kw = math.floor(total_consumption)
    if result.consumers.no_power > 0 then
        result.satisfaction = "critical"
    elseif result.consumers.low_power > 0 then
        result.satisfaction = "low"
    elseif result.consumers.working > 0 then
        result.satisfaction = "ok"
    else
        result.satisfaction = "idle"
    end

    if #consumers_by_status.no_power > 0 then
        result.no_power_entities = {}
        for i = 1, math.min(5, #consumers_by_status.no_power) do
            table.insert(result.no_power_entities, consumers_by_status.no_power[i])
        end
    end
    if #consumers_by_status.low_power > 0 then
        result.low_power_entities = {}
        for i = 1, math.min(5, #consumers_by_status.low_power) do
            table.insert(result.low_power_entities, consumers_by_status.low_power[i])
        end
    end

    local stats = pole.electric_network_statistics
    if stats then
        local input_flow = {}
        local output_flow = {}
        for name, _ in pairs(stats.input_counts) do
            local flow = stats.get_flow_count{
                name = name,
                input = true,
                precision_index = defines.flow_precision_index.five_seconds,
            }
            if flow > 0 then table.insert(input_flow, {name = name, flow = flow}) end
        end
        for name, _ in pairs(stats.output_counts) do
            local flow = stats.get_flow_count{
                name = name,
                input = false,
                precision_index = defines.flow_precision_index.five_seconds,
            }
            if flow > 0 then table.insert(output_flow, {name = name, flow = flow}) end
        end
        if #input_flow > 0 then result.input_flow = input_flow end
        if #output_flow > 0 then result.output_flow = output_flow end
    end

    return result
end

local function get_power_networks_impl(x, y, radius)
    local surface = game.surfaces[1]
    local _, area = area_around(x, y, radius)
    local poles = surface.find_entities_filtered{
        type = "electric-pole",
        area = area,
        force = "player",
    }
    local networks = {}
    for _, pole in pairs(poles) do
        local network_id = pole.electric_network_id
        if network_id then
            if not networks[network_id] then
                networks[network_id] = {
                    network_id = network_id,
                    pole_count = 0,
                    poles = {},
                }
            end
            networks[network_id].pole_count = networks[network_id].pole_count + 1
            if #networks[network_id].poles < 3 then
                table.insert(networks[network_id].poles, {
                    name = pole.name,
                    position = pos_table(pole.position),
                })
            end
        end
    end

    local result = {}
    for _, data in pairs(networks) do
        table.insert(result, data)
    end
    return result
end

local function find_power_issues_impl(x, y, radius)
    local surface = game.surfaces[1]
    local r, area = area_around(x, y, radius)
    local coverage, poles = build_power_coverage(surface, area, x, y, r, false)
    local result = {
        unpowered_entities = {},
        low_power_entities = {},
        suggested_actions = {},
    }

    for _, entity_type in pairs(POWER_ISSUE_CONSUMER_TYPES) do
        local entities = surface.find_entities_filtered{
            area = area,
            type = entity_type,
            force = "player",
        }
        for _, ent in pairs(entities) do
            if entity_uses_electricity(ent) then
                local status = raw_entity_status(ent)
                local ex, ey = math.floor(ent.position.x), math.floor(ent.position.y)
                local key = ex .. "," .. ey
                if status == defines.entity_status.no_power then
                    table.insert(result.unpowered_entities, {
                        unit_number = ent.unit_number,
                        name = ent.name,
                        x = ent.position.x,
                        y = ent.position.y,
                        in_coverage = coverage[key] ~= nil,
                    })
                    if not coverage[key] then
                        table.insert(result.suggested_actions, "Place pole near (" .. ex .. ", " .. ey .. ") to power " .. ent.name)
                    else
                        table.insert(result.suggested_actions, ent.name .. " at (" .. ex .. ", " .. ey .. ") is in coverage but has no power - check generator capacity")
                    end
                elseif status == defines.entity_status.low_power then
                    table.insert(result.low_power_entities, {
                        unit_number = ent.unit_number,
                        name = ent.name,
                        x = ent.position.x,
                        y = ent.position.y,
                    })
                    table.insert(result.suggested_actions, ent.name .. " at (" .. ex .. ", " .. ey .. ") has low power - add more generators")
                end
            end
        end
    end

    result.summary = {
        unpowered_count = #result.unpowered_entities,
        low_power_count = #result.low_power_entities,
        pole_count = #poles,
    }
    local original_action_count = #result.suggested_actions
    if original_action_count > 10 then
        local limited = {}
        for i = 1, 10 do
            limited[i] = result.suggested_actions[i]
        end
        result.suggested_actions = limited
        result.summary.more_issues = original_action_count - 10
    end
    return result
end

local function get_power_coverage_impl(x, y, radius)
    local surface = game.surfaces[1]
    local r, area = area_around(x, y, radius)
    local coverage, _, poles, networks = build_power_coverage(surface, area, x, y, r, true)
    return {
        poles = poles,
        coverage = coverage,
        networks = networks,
    }
end

local function get_alerts_impl(x, y, radius)
    local surface = game.surfaces[1]
    local _, area = area_around(x, y, radius)
    local alerts = {}

    for _, entity_type in pairs(POWER_ISSUE_CONSUMER_TYPES) do
        local entities = surface.find_entities_filtered{
            area = area,
            type = entity_type,
            force = "player",
        }
        for _, ent in pairs(entities) do
            if entity_uses_electricity(ent) then
                local status = raw_entity_status(ent)
                if status == defines.entity_status.no_power then
                    table.insert(alerts, {
                        type = "no_power",
                        entity_name = ent.name,
                        position = pos_table(ent.position),
                        unit_number = ent.unit_number,
                    })
                elseif status == defines.entity_status.low_power then
                    table.insert(alerts, {
                        type = "low_power",
                        entity_name = ent.name,
                        position = pos_table(ent.position),
                        unit_number = ent.unit_number,
                    })
                end
            end
        end
    end

    local drills = surface.find_entities_filtered{type = "mining-drill", area = area, force = "player"}
    for _, drill in pairs(drills) do
        if drill.mining_target == nil and raw_entity_status(drill) == defines.entity_status.no_minable_resources then
            table.insert(alerts, {
                type = "empty_drill",
                entity_name = drill.name,
                position = pos_table(drill.position),
                unit_number = drill.unit_number,
            })
        end
    end

    local fuel_entities = surface.find_entities_filtered{
        area = area,
        force = "player",
        type = {"furnace", "boiler"},
    }
    for _, entity in pairs(fuel_entities) do
        if entity.burner then
            local fuel_inv = entity.get_fuel_inventory()
            if fuel_inv and fuel_inv.is_empty() then
                table.insert(alerts, {
                    type = "no_fuel",
                    entity_name = entity.name,
                    position = pos_table(entity.position),
                    unit_number = entity.unit_number,
                })
            end
        end
    end

    local assemblers = surface.find_entities_filtered{type = "assembling-machine", area = area, force = "player"}
    for _, assembler in pairs(assemblers) do
        local status = raw_entity_status(assembler)
        if status == defines.entity_status.no_ingredients then
            local recipe = assembler.get_recipe()
            table.insert(alerts, {
                type = "no_ingredients",
                entity_name = assembler.name,
                position = pos_table(assembler.position),
                unit_number = assembler.unit_number,
                recipe = recipe and recipe.name or nil,
            })
        end
    end

    local enemies = surface.find_entities_filtered{
        force = "enemy",
        area = area,
        limit = 10,
    }
    for _, enemy in pairs(enemies) do
        table.insert(alerts, {
            type = "enemy_nearby",
            entity_name = enemy.name,
            position = pos_table(enemy.position),
            health = enemy.health,
        })
    end
    return alerts
end

local function get_belt_contents_impl(x1, y1, x2, y2)
    local surface = game.surfaces[1]
    local belts = surface.find_entities_filtered{
        area = {{x1, y1}, {x2, y2}},
        type = "transport-belt",
    }
    local belt_items = {}
    local item_totals = {}
    local total_items = 0

    for _, belt in pairs(belts) do
        local belt_data = {
            position = pos_table(belt.position),
            unit_number = belt.unit_number,
            items = {},
        }
        for i = 1, belt.get_max_transport_line_index() do
            local line = belt.get_transport_line(i)
            if line then
                for _, item in pairs(line.get_contents()) do
                    table.insert(belt_data.items, {name = item.name, count = item.count})
                    item_totals[item.name] = (item_totals[item.name] or 0) + item.count
                    total_items = total_items + item.count
                end
            end
        end
        if #belt_data.items > 0 then
            table.insert(belt_items, belt_data)
        end
    end

    local summary = {}
    for item_name, count in pairs(item_totals) do
        table.insert(summary, {name = item_name, count = count})
    end

    return {
        belt_count = #belts,
        total_items = total_items,
        item_summary = summary,
        belts = belt_items,
    }
end

local function get_belt_lane_contents_impl(x1, y1, x2, y2)
    local surface = game.surfaces[1]
    local belts = surface.find_entities_filtered{
        area = {{x1, y1}, {x2, y2}},
        type = "transport-belt",
    }
    local result = {}

    for _, belt in pairs(belts) do
        local left_items = {}
        local right_items = {}
        local left_count = 0
        local right_count = 0

        local line1 = belt.get_transport_line(1)
        if line1 then
            for _, item in pairs(line1.get_contents()) do
                table.insert(left_items, {name = item.name, count = item.count})
                left_count = left_count + item.count
            end
        end

        local line2 = belt.get_transport_line(2)
        if line2 then
            for _, item in pairs(line2.get_contents()) do
                table.insert(right_items, {name = item.name, count = item.count})
                right_count = right_count + item.count
            end
        end

        if #left_items > 0 or #right_items > 0 then
            table.insert(result, {
                position = {
                    x = math.floor(belt.position.x),
                    y = math.floor(belt.position.y),
                },
                unit_number = belt.unit_number,
                direction = belt.direction,
                belt_type = belt.name,
                left_lane = {lane = 1, items = left_items, item_count = left_count},
                right_lane = {lane = 2, items = right_items, item_count = right_count},
            })
        end
    end

    return result
end

local function area_table(x1, y1, x2, y2)
    return {{x1, y1}, {x2, y2}}
end

local function bounding_box_table(bb)
    if not bb then return nil end
    return {
        left_top = pos_table(bb.left_top),
        right_bottom = pos_table(bb.right_bottom),
    }
end

local function entity_summary(entity, include_bounding_box)
    local result = {
        unit_number = entity.unit_number,
        name = entity.name,
        type = entity.type,
        position = pos_table(entity.position),
        direction = entity.direction,
        health = entity.health,
        force = entity.force and entity.force.name or nil,
    }

    if include_bounding_box then
        result.bounding_box = bounding_box_table(entity.bounding_box)
    end

    return result
end

local function get_surfaces_impl()
    local result = {}
    for _, surface in pairs(game.surfaces) do
        table.insert(result, {
            name = surface.name,
            index = surface.index,
            daytime = surface.daytime,
            darkness = surface.darkness,
        })
    end
    return result
end

local function find_entities_impl(x1, y1, x2, y2, entity_type, name)
    local filters = {area = area_table(x1, y1, x2, y2)}
    if entity_type then filters.type = entity_type end
    if name then filters.name = name end

    local result = {}
    for _, entity in pairs(game.surfaces[1].find_entities_filtered(filters)) do
        table.insert(result, entity_summary(entity, true))
    end
    return result
end

local function verify_production_impl(x1, y1, x2, y2)
    local result = {}
    local entities = game.surfaces[1].find_entities_filtered{
        area = area_table(x1, y1, x2, y2),
        force = game.forces.player,
    }

    for _, entity in pairs(entities) do
        local status_value = raw_entity_status(entity)
        if status_value ~= nil then
            local products_finished = nil
            local products_ok, products_value = pcall(function()
                return entity.products_finished
            end)
            if products_ok then
                products_finished = products_value
            end

            table.insert(result, {
                name = entity.name,
                position = pos_table(entity.position),
                status = status_name(status_value),
                products_finished = products_finished,
                working = status_value == defines.entity_status.working,
            })
        end
    end

    return result
end

local function get_entity_impl(unit_number)
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then return nil end
    return entity_summary(entity, false)
end

local function get_entity_drop_position_impl(unit_number)
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found or has no drop_position"}
    end
    if not entity.drop_position then
        return {error = "Entity not found or has no drop_position"}
    end

    local drop_position = entity.drop_position
    local direction = entity.direction
    return {
        drop_x = drop_position.x,
        drop_y = drop_position.y,
        drill_direction = direction,
        belt_direction = direction,
    }
end

local function resource_patch_result(patch)
    return {
        name = patch.name,
        total_amount = patch.total_amount,
        tile_count = patch.tile_count,
        center = {
            x = (patch.min_x + patch.max_x) / 2,
            y = (patch.min_y + patch.max_y) / 2,
        },
        bounding_box = {
            left_top = {x = patch.min_x, y = patch.min_y},
            right_bottom = {x = patch.max_x, y = patch.max_y},
        },
    }
end

local function aggregate_resource_patches(resources)
    local by_name = {}
    for _, resource in pairs(resources) do
        local key = resource.name
        if not by_name[key] then
            by_name[key] = {
                name = resource.name,
                total_amount = 0,
                tile_count = 0,
                min_x = resource.position.x,
                max_x = resource.position.x,
                min_y = resource.position.y,
                max_y = resource.position.y,
            }
        end

        local patch = by_name[key]
        patch.total_amount = patch.total_amount + (resource.amount or 0)
        patch.tile_count = patch.tile_count + 1
        patch.min_x = math.min(patch.min_x, resource.position.x)
        patch.max_x = math.max(patch.max_x, resource.position.x)
        patch.min_y = math.min(patch.min_y, resource.position.y)
        patch.max_y = math.max(patch.max_y, resource.position.y)
    end

    local result = {}
    for _, patch in pairs(by_name) do
        table.insert(result, resource_patch_result(patch))
    end
    return result
end

local function find_resources_impl(x1, y1, x2, y2, resource_type)
    local filters = {
        type = "resource",
        area = area_table(x1, y1, x2, y2),
    }
    if resource_type then filters.name = resource_type end

    local resources = game.surfaces[1].find_entities_filtered(filters)
    return aggregate_resource_patches(resources)
end

local function find_nearest_resource_impl(resource_name, from_x, from_y)
    local nearest = nil
    local nearest_dist = math.huge
    local resources = game.surfaces[1].find_entities_filtered{
        type = "resource",
        name = resource_name,
        position = {from_x, from_y},
        radius = 200,
    }

    for _, resource in pairs(resources) do
        local dx = resource.position.x - from_x
        local dy = resource.position.y - from_y
        local dist = dx * dx + dy * dy
        if dist < nearest_dist then
            nearest = resource
            nearest_dist = dist
        end
    end

    if not nearest then return nil end

    local patch_resources = game.surfaces[1].find_entities_filtered{
        type = "resource",
        name = resource_name,
        position = nearest.position,
        radius = 50,
    }
    local patches = aggregate_resource_patches(patch_resources)
    return patches[1]
end

local function tile_summary(tile, x, y)
    return {
        name = tile.name,
        position = {x = x, y = y},
        collides_with_player = tile.collides_with("player"),
    }
end

local function get_tiles_impl(x1, y1, x2, y2)
    local result = {}
    for x = x1, x2 do
        for y = y1, y2 do
            local tile = game.surfaces[1].get_tile(x, y)
            table.insert(result, tile_summary(tile, x, y))
        end
    end
    return result
end

local function get_tile_impl(x, y)
    local tile = game.surfaces[1].get_tile(x, y)
    return tile_summary(tile, x, y)
end

local function inventory_define_for(inventory_type, default_type)
    local normalized = inventory_type or default_type
    if normalized == "fuel" then return defines.inventory.fuel end
    if normalized == "input" then return defines.inventory.assembling_machine_input end
    if normalized == "output" then return defines.inventory.assembling_machine_output end
    if normalized == "chest" then return defines.inventory.chest end
    if normalized == "furnace_source" then return defines.inventory.furnace_source end
    if normalized == "furnace_result" then return defines.inventory.furnace_result end
    if normalized == "lab_input" then return defines.inventory.lab_input end
    if normalized == "lab_modules" then return defines.inventory.lab_modules end
    return inventory_define_for(default_type, default_type)
end

local function find_factorioctl_character(agent_id)
    if storage.characters then
        local character = storage.characters[agent_id]
        if character and character.valid then return character end
        if agent_id == "default" then
            character = storage.characters["__player__"]
            if character and character.valid then return character end
        elseif agent_id == "__player__" then
            character = storage.characters["default"]
            if character and character.valid then return character end
        end
    end

    if agent_id == "default" or agent_id == "__player__" then
        for _, player in pairs(game.connected_players) do
            if player.character and player.character.valid then
                return player.character
            end
        end
    end

    return nil
end

local function remember_factorioctl_character(agent_id, character)
    storage.characters = storage.characters or {}
    storage.factorioctl_entities = storage.factorioctl_entities or {}
    storage.characters[agent_id] = character
    if agent_id == "__player__" then storage.characters["default"] = character end
    if agent_id == "default" then storage.characters["__player__"] = character end
    if character and character.valid and character.unit_number then
        storage.factorioctl_entities[character.unit_number] = character
    end
end

local function ensure_surface_impl(planet_name)
    local planet = game.planets[planet_name]
    if not planet then return "no_planet" end
    if game.surfaces[planet_name] then return "exists" end
    planet.create_surface()
    return "created"
end

local function pre_place_character_impl(agent_id, planet_name, spawn_x)
    local target_surface = game.surfaces[planet_name]
    if not target_surface then return "surface_not_found" end

    target_surface.request_to_generate_chunks({spawn_x, 0}, 4)
    target_surface.force_generate_chunk_requests()

    local status = nil
    local character = find_factorioctl_character(agent_id)
    if character and character.valid then
        if character.surface.name == planet_name then
            status = "already_placed"
        else
            character.teleport({spawn_x, 0}, target_surface)
            status = "teleported"
        end
    else
        character = target_surface.create_entity{
            name = "character",
            position = {spawn_x, 0},
            force = game.forces.player,
        }
        if character then status = "created" end
    end

    if character and character.valid then
        remember_factorioctl_character(agent_id, character)
        return status
    end

    return "creation_failed"
end

local function live_state_line_impl(agent_id)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then return "" end

    local names = {
        "burner-mining-drill",
        "electric-mining-drill",
        "stone-furnace",
        "assembling-machine-1",
        "transport-belt",
        "burner-inserter",
        "inserter",
        "small-electric-pole",
        "medium-electric-pole",
        "offshore-pump",
        "boiler",
        "steam-engine",
        "pipe",
        "lab",
    }
    local parts = {}
    for _, name in ipairs(names) do
        local count = #character.surface.find_entities_filtered{force = character.force, name = name}
        if count > 0 then parts[#parts + 1] = name .. "=" .. count end
    end

    local summary = ""
    if #parts > 0 then summary = "; player entities: " .. table.concat(parts, ", ") end
    return "Live state: "
        .. character.surface.name
        .. " @ "
        .. string.format("%.1f,%.1f", character.position.x, character.position.y)
        .. summary
end

local function connected_player_count_impl()
    return #game.connected_players
end

local function broadcast_console_impl(message)
    game.print("[Agent] " .. tostring(message or ""))
    return {success = true}
end

local function broadcast_flying_text_impl(message)
    local displayed = 0
    local text = tostring(message or "")
    for _, player in pairs(game.connected_players) do
        if player.character and player.character.valid then
            player.create_local_flying_text{
                text = text,
                position = {
                    player.character.position.x,
                    player.character.position.y - 2,
                },
                color = {r = 0.8, g = 0.8, b = 1.0},
                speed = 0.3,
                time_to_live = 300,
            }
            displayed = displayed + 1
        end
    end
    return {success = true, displayed = displayed}
end

local function get_tick_impl()
    return {tick = game.tick}
end

local function set_tick_paused_impl(paused)
    game.tick_paused = paused and true or false
    return {success = true, tick_paused = game.tick_paused}
end

local function set_game_speed_impl(speed)
    game.speed = tonumber(speed) or game.speed
    return {success = true, speed = game.speed}
end

local function set_walk_target_impl(agent_id, x, y)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {
            success = false,
            error = "no character for agent " .. tostring(agent_id) .. "; spawn first",
        }
    end

    remember_factorioctl_character(agent_id, character)
    storage.walk_targets = storage.walk_targets or {}
    if storage.walk_state then storage.walk_state[agent_id] = nil end
    storage.walk_targets[agent_id] = {
        x = x,
        y = y,
        stuck_ticks = 0,
        expires_tick = game.tick + 7200,
        last_x = character.position.x,
        last_y = character.position.y,
    }
    character.walking_state = {walking = false}
    return {success = true}
end

local function clear_walk_target_impl(agent_id)
    if storage.walk_targets then storage.walk_targets[agent_id] = nil end
    if storage.walk_state then storage.walk_state[agent_id] = nil end
    local character = find_factorioctl_character(agent_id)
    if character and character.valid then
        remember_factorioctl_character(agent_id, character)
        character.walking_state = {walking = false}
    end
    return {success = true}
end

local function init_character_impl(agent_id, x, y)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        character = game.surfaces[1].create_entity{
            name = "character",
            position = {x, y},
            force = "player",
        }
        if not character then
            return {error = "Failed to create character"}
        end
    end

    remember_factorioctl_character(agent_id, character)
    return entity_summary(character, false)
end

local function teleport_character_impl(agent_id, x, y)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    if character.teleport({x, y}) then
        return "ok"
    end
    return {error = "Teleport blocked (target obstructed)"}
end

local function character_status_impl(agent_id)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {valid = false}
    end

    local walking = false
    if character.walking_state then walking = character.walking_state.walking end
    local mining = false
    if character.mining_state then mining = character.mining_state.mining end

    return {
        valid = true,
        unit_number = character.unit_number,
        position = pos_table(character.position),
        health = character.health,
        crafting_queue_size = character.crafting_queue_size,
        walking = walking,
        mining = mining,
    }
end

local function character_inventory_impl(agent_id)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {items = {}, free_slots = 0}
    end

    local inv = character.get_main_inventory()
    if not inv then
        return {items = {}, free_slots = 0}
    end

    return {
        items = inventory_contents(inv),
        free_slots = inv.count_empty_stacks() or 0,
    }
end

local function blueprint_scratch_stack(inv)
    local scratch_temp_inventory = nil
    local slot = inv.find_empty_stack("blueprint")
    if not slot then
        scratch_temp_inventory = game.create_inventory(1)
        slot = scratch_temp_inventory[1]
    end
    slot.set_stack{name = "blueprint"}
    local function cleanup_scratch()
        slot.clear()
        if scratch_temp_inventory then scratch_temp_inventory.destroy() end
    end
    return slot, cleanup_scratch
end

local function register_blueprint_ghosts(ghosts)
    storage.factorioctl_entities = storage.factorioctl_entities or {}
    for _, ghost in pairs(ghosts) do
        if ghost.unit_number then storage.factorioctl_entities[ghost.unit_number] = ghost end
    end
end

local function create_native_blueprint_impl(agent_id, x1, y1, x2, y2)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local inv = character.get_main_inventory()
    if not inv then return {error = "No inventory"} end

    local slot, cleanup_scratch = blueprint_scratch_stack(inv)
    local entities = slot.create_blueprint{
        surface = character.surface,
        force = character.force,
        area = {{x1, y1}, {x2, y2}},
        include_entities = true,
        include_tiles = false,
    }
    local count = #entities

    if count == 0 then
        cleanup_scratch()
        return {error = "No entities in area"}
    end

    local bp_string = slot.export_stack()
    cleanup_scratch()
    return {
        blueprint_string = bp_string,
        entity_count = count,
    }
end

local function save_blueprint_impl(agent_id, name, x1, y1, x2, y2)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {success = false, error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local inv = character.get_main_inventory()
    if not inv then return {success = false, error = "No inventory"} end

    local slot, cleanup_scratch = blueprint_scratch_stack(inv)
    local entities = slot.create_blueprint{
        surface = character.surface,
        force = character.force,
        area = {{x1, y1}, {x2, y2}},
        include_entities = true,
    }
    local count = #entities

    if count == 0 then
        cleanup_scratch()
        return {success = false, error = "No entities in area"}
    end

    storage.blueprints = storage.blueprints or {}
    storage.blueprints[name] = {
        string = slot.export_stack(),
        entity_count = count,
    }
    cleanup_scratch()
    return {success = true, entity_count = count}
end

local function list_blueprints_impl()
    storage.blueprints = storage.blueprints or {}
    local result = {}
    for name, data in pairs(storage.blueprints) do
        table.insert(result, {
            name = name,
            entity_count = data.entity_count,
        })
    end
    return result
end

local function get_blueprint_impl(name)
    storage.blueprints = storage.blueprints or {}
    local data = storage.blueprints[name]
    if data then
        return {
            blueprint_string = data.string,
            entity_count = data.entity_count,
        }
    end
    return {error = "Blueprint not found"}
end

local function place_blueprint_impl(agent_id, name, x, y, direction)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {success = false, error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    storage.blueprints = storage.blueprints or {}
    local data = storage.blueprints[name]
    if not data then return {success = false, error = "Blueprint not found"} end

    local inv = character.get_main_inventory()
    if not inv then return {success = false, error = "No inventory"} end

    local slot, cleanup_scratch = blueprint_scratch_stack(inv)
    local ok = slot.import_stack(data.string)
    if not ok then
        cleanup_scratch()
        return {success = false, error = "Invalid stored blueprint string"}
    end

    local ghosts = slot.build_blueprint{
        surface = character.surface,
        force = character.force,
        position = {x = x, y = y},
        direction = direction,
        force_build = true,
    }

    if #ghosts == 0 then
        cleanup_scratch()
        return {success = false, error = "Blueprint created no ghosts"}
    end

    register_blueprint_ghosts(ghosts)
    cleanup_scratch()
    return {success = true, ghosts_created = #ghosts}
end

local function import_blueprint_impl(agent_id, bp_string, x, y, direction)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {success = false, error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local inv = character.get_main_inventory()
    if not inv then return {success = false, error = "No inventory"} end

    local slot, cleanup_scratch = blueprint_scratch_stack(inv)
    local ok = slot.import_stack(bp_string)
    if not ok then
        cleanup_scratch()
        return {success = false, error = "Invalid blueprint string"}
    end

    local ghosts = slot.build_blueprint{
        surface = character.surface,
        force = character.force,
        position = {x = x, y = y},
        direction = direction,
        force_build = true,
    }

    if #ghosts == 0 then
        cleanup_scratch()
        return {success = false, error = "Invalid or empty blueprint string"}
    end

    register_blueprint_ghosts(ghosts)
    cleanup_scratch()
    return {success = true, ghosts_created = #ghosts}
end

local function delete_blueprint_impl(name)
    storage.blueprints = storage.blueprints or {}
    if storage.blueprints[name] then
        storage.blueprints[name] = nil
        return {success = true}
    end
    return {success = false, error = "Blueprint not found"}
end

local function crafting_queue_summary(character)
    local queue = {}
    if not character then return queue end
    for _, item in pairs(character.crafting_queue) do
        table.insert(queue, {recipe = item.recipe, count = item.count})
    end
    return queue
end

local function craft_failure(character, recipe_name, error)
    return {
        success = false,
        queued = 0,
        queue_size = character and character.crafting_queue_size or 0,
        queue = crafting_queue_summary(character),
        recipe = recipe_name,
        error = error,
    }
end

local function craft_impl(agent_id, recipe_name, count)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return craft_failure(nil, recipe_name, "no character for agent " .. tostring(agent_id) .. "; spawn first")
    end

    if not prototypes.recipe[recipe_name] then
        return craft_failure(character, recipe_name, "Unknown recipe")
    end

    local force_recipe = character.force.recipes[recipe_name]
    if force_recipe and not force_recipe.enabled then
        return craft_failure(character, recipe_name, "Recipe is disabled")
    end

    local ok, crafted_or_error = pcall(function()
        return character.begin_crafting{recipe = recipe_name, count = count}
    end)
    if not ok then
        return craft_failure(character, recipe_name, tostring(crafted_or_error))
    end

    local crafted = crafted_or_error
    local result = {
        success = crafted > 0,
        queued = crafted,
        queue_size = character.crafting_queue_size,
        queue = crafting_queue_summary(character),
        recipe = recipe_name,
    }
    if crafted <= 0 then
        result.error = "Crafting did not start; check ingredients, recipe category, or character craftability"
    end
    return result
end

local function wait_for_crafting_impl(agent_id)
    local character = find_factorioctl_character(agent_id)
    if character and character.valid then
        return tostring(character.crafting_queue_size)
    end
    return "0"
end

local function inventory_item_total(inv)
    local total = 0
    if not inv then return total end
    for _, item in pairs(inv.get_contents()) do
        total = total + item.count
    end
    return total
end

local function find_minable_at(surface, character, x, y, radius)
    local resources = surface.find_entities_filtered{
        position = {x, y},
        radius = radius,
        type = "resource",
    }
    if #resources > 0 then return resources[1] end

    local entities = surface.find_entities_filtered{
        position = {x, y},
        radius = radius,
    }
    for _, entity in pairs(entities) do
        if entity.minable and entity ~= character then
            return entity
        end
    end
    return nil
end

local function mining_failure(character, error)
    local inv = character and character.valid and character.get_main_inventory() or nil
    return {
        success = false,
        mined_count = 0,
        picked_up = 0,
        inventory = inventory_contents(inv),
        error = error,
    }
end

local function start_mining_impl(agent_id, x, y)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {success = false, error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local target = find_minable_at(game.surfaces[1], character, x, y, 1)
    if not target then
        return {success = false, error = "No minable entity at position"}
    end

    local dx = target.position.x - character.position.x
    local dy = target.position.y - character.position.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > character.resource_reach_distance + 0.5 then
        return {
            success = false,
            error = "Too far",
            distance = dist,
            reach = character.resource_reach_distance,
        }
    end

    character.mining_state = {mining = true, position = target.position}
    return {
        success = true,
        target = target.name,
        position = pos_table(target.position),
    }
end

local function stop_mining_impl(agent_id)
    local character = find_factorioctl_character(agent_id)
    if character and character.valid then
        character.mining_state = {mining = false}
        return "ok"
    end
    return "error"
end

local function get_mining_status_impl(agent_id)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {mining = false}
    end
    return {
        mining = character.mining_state.mining,
        position = pos_table(character.position),
    }
end

local function pick_up_item_entity(character, inv, item_entity)
    local stack = item_entity.stack
    if not (stack and stack.valid_for_read and inv) then return 0 end
    local stack_count = stack.count
    local inserted = inv.insert(stack)
    if inserted <= 0 then return 0 end
    if inserted >= stack_count then
        item_entity.destroy()
    else
        stack.count = stack_count - inserted
    end
    return inserted
end

local function mine_at_impl(agent_id, x, y, count, radius)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return mining_failure(nil, "no character for agent " .. tostring(agent_id) .. "; spawn first")
    end

    local inv = character.get_main_inventory()
    local before_count = inventory_item_total(inv)
    local mined = 0
    local picked_up = 0
    local surface = game.surfaces[1]
    local search_radius = radius or 3

    for _ = 1, count do
        local items_on_ground = surface.find_entities_filtered{
            position = {x, y},
            radius = search_radius,
            type = "item-entity",
        }

        if #items_on_ground > 0 then
            picked_up = picked_up + pick_up_item_entity(character, inv, items_on_ground[1])
        else
            local target = find_minable_at(surface, character, x, y, search_radius)
            if not target then break end
            if character.mine_entity(target, true) then
                mined = mined + 1
            else
                break
            end
        end
    end

    local after_count = inventory_item_total(inv)
    local items_gained = after_count - before_count
    local items = inventory_contents(inv)
    local success = items_gained > 0 or picked_up > 0
    local result = {
        success = success,
        mined_count = items_gained,
        mined_entities = mined,
        picked_up = picked_up,
        inventory = items,
    }
    if not success then
        result.error = "No minable entity at position"
    end
    return result
end

local function find_nearest_minable_impl(agent_id, entity_name, radius)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {found = false, error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local entities = game.surfaces[1].find_entities_filtered{
        name = entity_name,
        position = character.position,
        radius = radius or 100,
    }

    local nearest = nil
    local nearest_dist = math.huge
    for _, entity in pairs(entities) do
        if entity.minable then
            local dx = entity.position.x - character.position.x
            local dy = entity.position.y - character.position.y
            local dist = dx * dx + dy * dy
            if dist < nearest_dist then
                nearest = entity
                nearest_dist = dist
            end
        end
    end

    if not nearest then
        return {found = false}
    end
    return {
        found = true,
        name = nearest.name,
        position = pos_table(nearest.position),
        distance = math.sqrt(nearest_dist),
    }
end

local function mine_nearest_impl(agent_id, entity_name, count)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return mining_failure(nil, "no character for agent " .. tostring(agent_id) .. "; spawn first")
    end

    local mined = 0
    for _ = 1, count do
        local nearest = find_nearest_minable_impl(agent_id, entity_name, 100)
        if not nearest.found then break end
        local target = find_minable_at(game.surfaces[1], character, nearest.position.x, nearest.position.y, 0.5)
        if not target then break end
        if character.mine_entity(target, true) then
            mined = mined + 1
        else
            break
        end
    end

    local inv = character.get_main_inventory()
    local result = {
        success = mined > 0,
        mined_count = mined,
        inventory = inventory_contents(inv),
    }
    if mined == 0 then
        result.error = "No minable entity found"
    end
    return result
end

local function clear_area_impl(agent_id, x1, y1, x2, y2, clear_trees, clear_rocks, dry_run)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local surface = game.surfaces[1]
    local area = {{x1, y1}, {x2, y2}}
    local max_distance = 30
    local result = {
        trees_found = 0,
        rocks_found = 0,
        trees_mined = 0,
        rocks_mined = 0,
        dry_run = dry_run,
        too_far = false,
        items_gained = {},
    }

    local area_center_x = (area[1][1] + area[2][1]) / 2
    local area_center_y = (area[1][2] + area[2][2]) / 2
    local dx = character.position.x - area_center_x
    local dy = character.position.y - area_center_y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > max_distance and not dry_run then
        result.too_far = true
        result.distance = dist
        result.max_distance = max_distance
        return result
    end

    local inv = character.get_main_inventory()
    local before = {}
    if inv then
        for _, item in pairs(inv.get_contents()) do
            before[item.name] = item.count
        end
    end

    if clear_trees then
        local trees = surface.find_entities_filtered{type = "tree", area = area}
        result.trees_found = #trees
        if not dry_run then
            for _, tree in pairs(trees) do
                if character.mine_entity(tree, true) then
                    result.trees_mined = result.trees_mined + 1
                end
            end
        end
    end

    if clear_rocks then
        local entities = surface.find_entities_filtered{type = "simple-entity", area = area}
        for _, entity in pairs(entities) do
            if entity.name:find("rock") then
                result.rocks_found = result.rocks_found + 1
                if not dry_run and character.mine_entity(entity, true) then
                    result.rocks_mined = result.rocks_mined + 1
                end
            end
        end
    end

    if not dry_run and inv then
        for _, item in pairs(inv.get_contents()) do
            local gained = item.count - (before[item.name] or 0)
            if gained > 0 then
                table.insert(result.items_gained, {name = item.name, count = gained})
            end
        end
    end

    return result
end

local function placement_entity_result(entity)
    return {
        unit_number = entity.unit_number,
        name = entity.name,
        type = entity.type,
        entity_type = entity.type,
        position = pos_table(entity.position),
        direction = entity.direction,
        health = entity.health,
        force = entity.force and entity.force.name or nil,
    }
end

local function placement_failure(entity_name, position, direction, inventory_count, can_place, error)
    return {
        success = false,
        error = error,
        entity = entity_name,
        position = {x = position[1], y = position[2]},
        direction = direction,
        inventory_count = inventory_count,
        can_place = can_place,
    }
end

local function clear_ground_items_for_placement(character, surface, entity_name, position)
    local proto = prototypes.entity[entity_name]
    if not (proto and proto.collision_box) then return end

    local cb = proto.collision_box
    local clear_area = {
        {position[1] + cb.left_top.x - 0.1, position[2] + cb.left_top.y - 0.1},
        {position[1] + cb.right_bottom.x + 0.1, position[2] + cb.right_bottom.y + 0.1},
    }
    local items_on_ground = surface.find_entities_filtered{
        area = clear_area,
        type = "item-entity",
    }
    for _, item in pairs(items_on_ground) do
        local stack = item.stack
        if stack and stack.valid_for_read then
            local before_count = stack.count
            local inserted = character.insert(stack)
            if inserted > 0 then
                if inserted >= before_count then
                    item.destroy()
                else
                    stack.count = before_count - inserted
                end
            else
                item.destroy()
            end
        else
            item.destroy()
        end
    end
end

local function place_entity_impl(agent_id, entity_name, x, y, direction)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return placement_failure(entity_name, {x, y}, direction, 0, false, "no character for agent " .. tostring(agent_id) .. "; spawn first")
    end

    local inv = character.get_main_inventory()
    local inventory_count = 0
    if inv then inventory_count = inv.get_item_count(entity_name) end
    local position = {x, y}
    if not inv or inventory_count < 1 then
        return placement_failure(entity_name, position, direction, inventory_count, false, "Item not in inventory")
    end

    if not prototypes.entity[entity_name] then
        return placement_failure(entity_name, position, direction, inventory_count, false, "Unknown entity prototype")
    end

    local surface = character.surface
    clear_ground_items_for_placement(character, surface, entity_name, position)

    local can_place_ok, can_place_or_error = pcall(function()
        return surface.can_place_entity{
            name = entity_name,
            position = position,
            direction = direction,
            force = character.force,
            build_check_type = defines.build_check_type.manual,
        }
    end)

    if not can_place_ok or can_place_or_error ~= true then
        return placement_failure(
            entity_name,
            position,
            direction,
            inventory_count,
            false,
            can_place_ok and "Cannot place entity here" or tostring(can_place_or_error)
        )
    end

    local create_ok, created_or_error = pcall(function()
        return surface.create_entity{
            name = entity_name,
            position = position,
            direction = direction,
            force = character.force,
        }
    end)

    if not create_ok then
        return placement_failure(entity_name, position, direction, inventory_count, true, tostring(created_or_error))
    end

    local entity = created_or_error
    if not entity then
        return placement_failure(
            entity_name,
            position,
            direction,
            inventory_count,
            true,
            "create_entity returned nil after can_place_entity succeeded"
        )
    end

    if entity.unit_number then
        storage.factorioctl_entities = storage.factorioctl_entities or {}
        storage.factorioctl_entities[entity.unit_number] = entity
    end
    inv.remove{name = entity_name, count = 1}
    return placement_entity_result(entity)
end

local function place_underground_belt_impl(agent_id, entity_name, x, y, direction, belt_type)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local inv = character.get_main_inventory()
    local inventory_count = 0
    if inv then inventory_count = inv.get_item_count(entity_name) end
    if not inv or inventory_count < 1 then
        return {error = "Item not in inventory"}
    end

    local position = {x, y}
    local surface = character.surface
    local can_place = surface.can_place_entity{
        name = entity_name,
        position = position,
        direction = direction,
        force = character.force,
        build_check_type = defines.build_check_type.manual,
    }

    if not can_place then
        return {error = "Cannot place underground belt here"}
    end

    local entity = surface.create_entity{
        name = entity_name,
        position = position,
        direction = direction,
        type = belt_type,
        force = character.force,
    }

    if not entity then
        return {error = "Failed to create underground belt"}
    end

    if entity.unit_number then
        storage.factorioctl_entities = storage.factorioctl_entities or {}
        storage.factorioctl_entities[entity.unit_number] = entity
    end
    inv.remove{name = entity_name, count = 1}

    local result = placement_entity_result(entity)
    result.belt_to_ground_type = entity.belt_to_ground_type
    return result
end

local function check_entity_placement_impl(agent_id, entity_name, x, y, direction)
    local character = find_factorioctl_character(agent_id)
    local position = {x, y}
    if not (character and character.valid) then
        return {
            factorio_allowed = false,
            entity = entity_name,
            position = {x = x, y = y},
            direction = direction,
            inventory_count = 0,
            item_in_inventory = false,
            error = "no character for agent " .. tostring(agent_id) .. "; spawn first",
        }
    end

    if not prototypes.entity[entity_name] then
        return {
            factorio_allowed = false,
            entity = entity_name,
            position = {x = x, y = y},
            direction = direction,
            inventory_count = 0,
            item_in_inventory = false,
            error = "Unknown entity prototype",
        }
    end

    local inv = character.get_main_inventory()
    local inventory_count = 0
    if inv then inventory_count = inv.get_item_count(entity_name) end

    local ok, can_place_or_error = pcall(function()
        return character.surface.can_place_entity{
            name = entity_name,
            position = position,
            direction = direction,
            force = character.force,
            build_check_type = defines.build_check_type.manual,
        }
    end)

    if not ok then
        return {
            factorio_allowed = false,
            entity = entity_name,
            position = {x = x, y = y},
            direction = direction,
            inventory_count = inventory_count,
            item_in_inventory = inventory_count > 0,
            error = tostring(can_place_or_error),
        }
    end

    local result = {
        factorio_allowed = can_place_or_error == true,
        entity = entity_name,
        position = {x = x, y = y},
        direction = direction,
        inventory_count = inventory_count,
        item_in_inventory = inventory_count > 0,
    }
    if can_place_or_error ~= true then
        result.error = "Factorio cannot place entity here"
    end
    return result
end

local function find_entity_placements_impl(agent_id, entity_name, center_x, center_y, radius, limit)
    local character = find_factorioctl_character(agent_id)
    local center = {center_x, center_y}
    if not (character and character.valid) then
        return {
            success = false,
            error = "no character for agent " .. tostring(agent_id) .. "; spawn first",
            entity = entity_name,
            center = {x = center_x, y = center_y},
            radius = radius,
            placements = {},
        }
    end

    if not prototypes.entity[entity_name] then
        return {
            success = false,
            error = "Unknown entity prototype",
            entity = entity_name,
            center = {x = center_x, y = center_y},
            radius = radius,
            placements = {},
        }
    end

    local inv = character.get_main_inventory()
    local inventory_count = 0
    if inv then inventory_count = inv.get_item_count(entity_name) end

    local directions = {0, 4, 8, 12}
    local placements = {}
    local checked = 0
    local surface = character.surface
    for dx = -radius, radius do
        for dy = -radius, radius do
            local position = {center[1] + dx, center[2] + dy}
            for _, dir in pairs(directions) do
                checked = checked + 1
                local ok, can_place = pcall(function()
                    return surface.can_place_entity{
                        name = entity_name,
                        position = position,
                        direction = dir,
                        force = character.force,
                        build_check_type = defines.build_check_type.manual,
                    }
                end)
                if ok and can_place == true then
                    local distance = math.sqrt(dx * dx + dy * dy)
                    table.insert(placements, {
                        entity = entity_name,
                        factorio_allowed = true,
                        position = {x = position[1], y = position[2]},
                        direction = dir,
                        distance = distance,
                        inventory_count = inventory_count,
                        item_in_inventory = inventory_count > 0,
                    })
                end
            end
        end
    end

    table.sort(placements, function(a, b)
        if a.distance == b.distance then
            return a.direction < b.direction
        end
        return a.distance < b.distance
    end)

    local returned = {}
    for i = 1, math.min(#placements, limit) do
        table.insert(returned, placements[i])
    end

    return {
        success = true,
        entity = entity_name,
        center = {x = center[1], y = center[2]},
        radius = radius,
        checked = checked,
        total = #placements,
        returned = #returned,
        truncated = #placements > #returned,
        placements = returned,
    }
end

local function place_ghost_impl(agent_id, entity_name, x, y, direction)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local entity = character.surface.create_entity{
        name = "entity-ghost",
        inner_name = entity_name,
        position = {x, y},
        direction = direction,
        force = character.force,
    }

    if not entity then
        return {error = "Failed to create ghost"}
    end
    if entity.unit_number then
        storage.factorioctl_entities = storage.factorioctl_entities or {}
        storage.factorioctl_entities[entity.unit_number] = entity
    end
    local result = placement_entity_result(entity)
    result.name = entity.ghost_name or entity_name
    result.entity_type = "entity-ghost"
    result.type = "entity-ghost"
    return result
end

local function build_entity_result(entity)
    return {
        unit_number = entity.unit_number,
        name = entity.name,
        type = entity.type,
        position = pos_table(entity.position),
        direction = entity.direction,
        health = entity.health,
        force = entity.force and entity.force.name or nil,
    }
end

local function direction_from_name(direction_name, default_direction)
    local normalized = string.lower(tostring(direction_name or ""))
    if normalized == "north" or normalized == "n" then return defines.direction.north end
    if normalized == "east" or normalized == "e" then return defines.direction.east end
    if normalized == "south" or normalized == "s" then return defines.direction.south end
    if normalized == "west" or normalized == "w" then return defines.direction.west end
    if normalized == "northeast" or normalized == "ne" then return defines.direction.northeast end
    if normalized == "southeast" or normalized == "se" then return defines.direction.southeast end
    if normalized == "southwest" or normalized == "sw" then return defines.direction.southwest end
    if normalized == "northwest" or normalized == "nw" then return defines.direction.northwest end
    return default_direction
end

local function build_result(placed, total, entities, errors)
    return {
        placed = placed,
        total = total,
        entities = entities,
        errors = errors,
    }
end

local function build_drill_array_impl(agent_id, count, resource, near_x, near_y, drill_type, direction_name)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return build_result(0, count, {}, {"no character for agent " .. tostring(agent_id) .. "; spawn first"})
    end

    local inv = character.get_main_inventory()
    local drill_count = inv and inv.get_item_count(drill_type) or 0
    if drill_count < count then
        return build_result(0, count, {}, {"Not enough drills in inventory (have " .. drill_count .. ")"})
    end

    if count <= 0 then return build_result(0, count, {}, {}) end

    local surface = character.surface
    local origin_x = near_x or 0
    local origin_y = near_y or 0
    local resources = surface.find_entities_filtered{
        name = resource,
        position = {origin_x, origin_y},
        radius = 100,
    }

    if #resources == 0 then
        return build_result(0, count, {}, {"No " .. resource .. " found nearby"})
    end

    table.sort(resources, function(a, b)
        local da = (a.position.x - origin_x) ^ 2 + (a.position.y - origin_y) ^ 2
        local db = (b.position.x - origin_x) ^ 2 + (b.position.y - origin_y) ^ 2
        return da < db
    end)

    local direction = direction_from_name(direction_name, defines.direction.south)
    local placed = 0
    local entities = {}
    local errors = {}
    local used_positions = {}

    for _, resource_entity in pairs(resources) do
        if placed >= count then break end

        local px = math.floor(resource_entity.position.x)
        local py = math.floor(resource_entity.position.y)
        local key = px .. "," .. py
        if not used_positions[key] then
            local can_place = surface.can_place_entity{
                name = drill_type,
                position = {px, py},
                direction = direction,
                force = character.force,
            }

            if can_place then
                local entity = surface.create_entity{
                    name = drill_type,
                    position = {px, py},
                    direction = direction,
                    force = character.force,
                }
                if entity then
                    storage.factorioctl_entities = storage.factorioctl_entities or {}
                    storage.factorioctl_entities[entity.unit_number] = entity
                    inv.remove{name = drill_type, count = 1}
                    placed = placed + 1
                    used_positions[key] = true
                    table.insert(entities, build_entity_result(entity))
                end
            end
        end
    end

    return build_result(placed, count, entities, errors)
end

local function smelter_line_delta(line_direction, spacing)
    local normalized = string.lower(tostring(line_direction or ""))
    if normalized == "west" or normalized == "w" then return -spacing, 0 end
    if normalized == "south" or normalized == "s" then return 0, spacing end
    if normalized == "north" or normalized == "n" then return 0, -spacing end
    return spacing, 0
end

local function build_smelter_line_impl(agent_id, count, start_x, start_y, furnace_type, line_direction, spacing)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return build_result(0, count, {}, {"no character for agent " .. tostring(agent_id) .. "; spawn first"})
    end

    local inv = character.get_main_inventory()
    local furnace_count = inv and inv.get_item_count(furnace_type) or 0
    if furnace_count < count then
        return build_result(0, count, {}, {"Not enough furnaces in inventory (have " .. furnace_count .. ")"})
    end

    local dx, dy = smelter_line_delta(line_direction, spacing)
    local surface = character.surface
    local placed = 0
    local entities = {}
    local errors = {}

    for i = 0, count - 1 do
        local px = start_x + i * dx
        local py = start_y + i * dy
        local can_place = surface.can_place_entity{
            name = furnace_type,
            position = {px, py},
            force = character.force,
        }

        if can_place then
            local entity = surface.create_entity{
                name = furnace_type,
                position = {px, py},
                force = character.force,
            }
            if entity then
                storage.factorioctl_entities = storage.factorioctl_entities or {}
                storage.factorioctl_entities[entity.unit_number] = entity
                inv.remove{name = furnace_type, count = 1}
                placed = placed + 1
                table.insert(entities, build_entity_result(entity))
            end
        else
            table.insert(errors, "Cannot place at " .. px .. "," .. py)
        end
    end

    return build_result(placed, count, entities, errors)
end

local function remove_entity_at_impl(x, y)
    storage.factorioctl_entities = storage.factorioctl_entities or {}
    local entities = game.surfaces[1].find_entities_filtered{
        position = {x, y},
        radius = 0.5,
    }

    for _, entity in pairs(entities) do
        if entity.type ~= "character" then
            if entity.unit_number then storage.factorioctl_entities[entity.unit_number] = nil end
            entity.destroy()
            return "ok"
        end
    end

    return {error = "No entity found"}
end

local function remove_entity_impl(unit_number)
    storage.factorioctl_entities = storage.factorioctl_entities or {}
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found"}
    end

    storage.factorioctl_entities[unit_number] = nil
    entity.destroy()
    return "ok"
end

local function rotate_entity_impl(unit_number, direction)
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found"}
    end

    if not entity.supports_direction then
        return {error = "Entity does not support rotation"}
    end

    entity.direction = direction
    return "ok"
end

local function insert_items_impl(unit_number, item, count, inventory_type)
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found"}
    end

    local inv = entity.get_inventory(inventory_define_for(inventory_type, "fuel"))
    if not inv then
        return {error = "Entity has no such inventory"}
    end

    local inserted = inv.insert{name = item, count = count}
    if inserted == 0 then
        return {error = "Inserted 0 items (inventory full or item not accepted)"}
    end

    return {inserted = inserted}
end

local function extract_items_impl(agent_id, unit_number, item, count, inventory_type)
    local character = find_factorioctl_character(agent_id)
    if not (character and character.valid) then
        return {error = "no character for agent " .. tostring(agent_id) .. "; spawn first"}
    end

    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found"}
    end

    local inv = entity.get_inventory(inventory_define_for(inventory_type, "chest"))
    if not inv then
        return {error = "Entity has no such inventory"}
    end

    local player_inv = character.get_main_inventory()
    if not player_inv then
        return {error = "Character has no inventory"}
    end

    local available = inv.get_item_count(item)
    local to_extract = math.min(count, available)
    if to_extract == 0 then
        return {extracted = 0, available = available, item = item}
    end

    local removed = inv.remove{name = item, count = to_extract}
    local inserted = player_inv.insert{name = item, count = removed}
    if inserted < removed then
        inv.insert{name = item, count = removed - inserted}
    end

    return {extracted = inserted, available = available}
end

local function set_recipe_impl(unit_number, recipe)
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found"}
    end

    if not entity.set_recipe then
        return {error = "Entity cannot have recipes"}
    end

    local result = entity.set_recipe(recipe)
    if result == nil then
        return {error = "Could not set recipe (unknown or incompatible recipe)"}
    end

    return {success = true}
end

local function get_entity_inventory_impl(unit_number)
    local entity = find_entity_by_unit_number(unit_number)
    if not entity then
        return {error = "Entity not found"}
    end

    local result = {
        unit_number = entity.unit_number,
        name = entity.name,
        inventories = {},
    }

    local inventory_types = {
        {name = "fuel", define = defines.inventory.fuel},
        {name = "chest", define = defines.inventory.chest},
        {name = "furnace_source", define = defines.inventory.furnace_source},
        {name = "furnace_result", define = defines.inventory.furnace_result},
        {name = "assembling_machine_input", define = defines.inventory.assembling_machine_input},
        {name = "assembling_machine_output", define = defines.inventory.assembling_machine_output},
        {name = "burnt_result", define = defines.inventory.burnt_result},
    }

    for _, inventory_type in pairs(inventory_types) do
        local ok, inv = pcall(function()
            return entity.get_inventory(inventory_type.define)
        end)
        if ok and inv then
            local items = inventory_contents(inv)
            if #items > 0 then
                result.inventories[inventory_type.name] = items
            end
        end
    end

    return result
end

local function recipe_unlocks(recipe_name)
    local unlocks = {}
    for tech_name, tech in pairs(game.forces.player.technologies) do
        local effects = tech.prototype and tech.prototype.effects or {}
        for _, effect in pairs(effects) do
            if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
                table.insert(unlocks, tech_name)
                break
            end
        end
    end
    table.sort(unlocks)
    return unlocks
end

local function recipe_ingredients(recipe)
    local ingredients = {}
    for _, ingredient in pairs(recipe.ingredients) do
        table.insert(ingredients, {
            type = ingredient.type,
            name = ingredient.name,
            amount = ingredient.amount,
        })
    end
    return ingredients
end

local function recipe_products(recipe)
    local products = {}
    for _, product in pairs(recipe.products) do
        table.insert(products, {
            type = product.type,
            name = product.name,
            amount = product.amount,
            probability = product.probability,
        })
    end
    return products
end

local function recipe_summary(recipe)
    local force_recipe = game.forces.player.recipes[recipe.name]
    return {
        name = recipe.name,
        category = recipe.category,
        energy = recipe.energy,
        enabled = force_recipe and force_recipe.enabled or false,
        unlocked_by = recipe_unlocks(recipe.name),
    }
end

local function recipe_details(recipe)
    local result = recipe_summary(recipe)
    result.ingredients = recipe_ingredients(recipe)
    result.products = recipe_products(recipe)
    return result
end

local function get_recipe_impl(name)
    local recipe = prototypes.recipe[name]
    if not recipe then
        return {error = "Recipe not found"}
    end
    return recipe_details(recipe)
end

local function get_recipes_by_category_impl(category)
    local recipes = {}
    for _, recipe in pairs(prototypes.recipe) do
        if recipe.category == category then
            table.insert(recipes, recipe_summary(recipe))
        end
    end
    return recipes
end

local function get_recipes_for_item_impl(item)
    local recipes = {}
    for _, recipe in pairs(prototypes.recipe) do
        for _, product in pairs(recipe.products) do
            if product.name == item then
                table.insert(recipes, recipe_details(recipe))
                break
            end
        end
    end
    return recipes
end

local function try_get(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function table_keys(map)
    local result = {}
    if not map then return result end
    for key, _ in pairs(map) do
        table.insert(result, key)
    end
    return result
end

local function get_prototype_impl(name)
    local proto = prototypes.entity[name]
    if not proto then
        return {error = "Prototype not found"}
    end

    local result = {
        name = proto.name,
        type = proto.type,
    }

    local collision_box = try_get(function() return proto.collision_box end)
    if collision_box then
        result.size = {
            collision_box.right_bottom.x - collision_box.left_top.x,
            collision_box.right_bottom.y - collision_box.left_top.y,
        }
    end

    local crafting_speed = try_get(function() return proto.get_crafting_speed() end)
    if crafting_speed then result.crafting_speed = crafting_speed end

    local crafting_categories = try_get(function() return proto.crafting_categories end)
    if crafting_categories then result.crafting_categories = table_keys(crafting_categories) end

    local mining_speed = try_get(function() return proto.mining_speed end)
    if mining_speed then result.mining_speed = mining_speed end

    local resource_categories = try_get(function() return proto.resource_categories end)
    if resource_categories then result.resource_categories = table_keys(resource_categories) end

    local rotation_speed = try_get(function() return proto.inserter_rotation_speed end)
    if rotation_speed then result.rotation_speed = rotation_speed end

    local extension_speed = try_get(function() return proto.inserter_extension_speed end)
    if extension_speed then result.extension_speed = extension_speed end

    local belt_speed = try_get(function() return proto.belt_speed end)
    if belt_speed then result.belt_speed = belt_speed end

    local energy_usage = try_get(function() return proto.energy_usage end)
    if energy_usage then result.energy_usage = energy_usage end

    if try_get(function() return proto.burner_prototype end) then
        result.energy_source = "burner"
    elseif try_get(function() return proto.electric_energy_source_prototype end) then
        result.energy_source = "electric"
    elseif try_get(function() return proto.heat_energy_source_prototype end) then
        result.energy_source = "heat"
    elseif try_get(function() return proto.void_energy_source_prototype end) then
        result.energy_source = "void"
    end

    return result
end

local function research_ingredients(tech)
    local ingredients = {}
    for _, ing in pairs(tech.research_unit_ingredients) do
        table.insert(ingredients, {name = ing.name, amount = ing.amount})
    end
    return ingredients
end

local function research_effects(tech)
    local effects = {}
    for _, eff in pairs(tech.prototype.effects) do
        if eff.type == "unlock-recipe" then
            table.insert(effects, {
                type = "unlock-recipe",
                recipe = eff.recipe,
            })
        elseif eff.type == "turret-attack" then
            table.insert(effects, {
                type = "turret-attack",
                turret_id = eff.turret_id,
                modifier = eff.modifier,
            })
        else
            table.insert(effects, {
                type = eff.type,
                modifier = eff.modifier,
            })
        end
    end
    return effects
end

local function lab_has_power(lab)
    local status = lab.status
    return status ~= defines.entity_status.no_power and status ~= defines.entity_status.low_power
end

local function science_totals_from_labs(labs)
    local science_totals = {}
    for _, lab in pairs(labs) do
        local inv = lab.get_inventory(defines.inventory.lab_input)
        if inv then
            for i = 1, #inv do
                local stack = inv[i]
                if stack and stack.valid_for_read then
                    science_totals[stack.name] = (science_totals[stack.name] or 0) + stack.count
                end
            end
        end
    end
    return science_totals
end

local function science_totals_list(science_totals)
    local result = {}
    for name, count in pairs(science_totals) do
        table.insert(result, {name = name, count = count})
    end
    return result
end

local function count_science_from_inventory(inv, science_totals, science_available)
    if not inv then return end
    for _, item in pairs(inv.get_contents()) do
        if item.name:find("science%-pack") or item.name == "automation-science-pack" or item.name == "logistic-science-pack" then
            science_totals[item.name] = (science_totals[item.name] or 0) + item.count
            local found = false
            for _, sci in pairs(science_available) do
                if sci.name == item.name then
                    sci.count = sci.count + item.count
                    sci.in_inventory = item.count
                    found = true
                    break
                end
            end
            if not found then
                table.insert(science_available, {name = item.name, count = item.count, in_inventory = item.count})
            end
        end
    end
end

local function get_research_status_impl()
    local force = game.forces.player
    local surface = game.surfaces[1]
    local result = {
        researched_count = 0,
        total_count = 0,
        current_research = nil,
        research_progress = 0,
        research_queue = {},
        labs = {
            count = 0,
            powered = 0,
            working = 0,
        },
        science_packs_in_labs = {},
    }

    for _, tech in pairs(force.technologies) do
        result.total_count = result.total_count + 1
        if tech.researched then
            result.researched_count = result.researched_count + 1
        end
    end

    if force.current_research then
        local tech = force.current_research
        result.current_research = {
            name = tech.name,
            level = tech.level,
            research_unit_count = tech.research_unit_count,
            ingredients = research_ingredients(tech),
        }
        result.research_progress = force.research_progress
    end

    if force.research_queue then
        for _, tech in pairs(force.research_queue) do
            table.insert(result.research_queue, {
                name = tech.name,
                level = tech.level,
            })
        end
    end

    local labs = surface.find_entities_filtered{type = "lab", force = force}
    result.labs.count = #labs

    local science_totals = science_totals_from_labs(labs)
    for _, lab in pairs(labs) do
        local status = lab.status
        if status == defines.entity_status.working then
            result.labs.working = result.labs.working + 1
            result.labs.powered = result.labs.powered + 1
        elseif lab_has_power(lab) then
            result.labs.powered = result.labs.powered + 1
        end
    end

    result.science_packs_in_labs = science_totals_list(science_totals)

    if result.labs.count == 0 then
        result.message = "No labs found! Build a lab and insert science packs to research."
    elseif result.labs.powered == 0 then
        result.message = "Labs have no power! Connect labs to the power grid."
    elseif result.current_research and #result.science_packs_in_labs == 0 then
        result.message = "Labs are empty! Insert science packs into labs to progress research."
    end

    return result
end

local function get_available_research_impl(agent_id)
    local force = game.forces.player
    local surface = game.surfaces[1]
    local result = {
        technologies = {},
        lab_status = {
            count = 0,
            powered = 0,
        },
        science_available = {},
    }

    local labs = surface.find_entities_filtered{type = "lab", force = force}
    result.lab_status.count = #labs

    local science_totals = science_totals_from_labs(labs)
    for _, lab in pairs(labs) do
        if lab_has_power(lab) then
            result.lab_status.powered = result.lab_status.powered + 1
        end
    end

    result.science_available = science_totals_list(science_totals)

    local character = find_factorioctl_character(agent_id)
    if character and character.valid then
        count_science_from_inventory(character.get_main_inventory(), science_totals, result.science_available)
    end

    for _, tech in pairs(force.technologies) do
        if tech.enabled and not tech.researched then
            local can_research = true
            for _, prereq in pairs(tech.prerequisites) do
                if not prereq.researched then
                    can_research = false
                    break
                end
            end

            if can_research then
                local ingredients = {}
                local has_all_packs = result.lab_status.powered > 0
                for _, ing in pairs(tech.research_unit_ingredients) do
                    local have = science_totals[ing.name] or 0
                    if have < ing.amount then
                        has_all_packs = false
                    end
                    table.insert(ingredients, {
                        name = ing.name,
                        amount = ing.amount,
                        available = have,
                    })
                end

                local ready = "ready"
                local blockers = {}
                if result.lab_status.count == 0 then
                    ready = "blocked"
                    table.insert(blockers, "no labs - build a lab first")
                elseif result.lab_status.powered == 0 then
                    ready = "blocked"
                    table.insert(blockers, "labs have no power")
                end
                if not has_all_packs then
                    ready = "blocked"
                    table.insert(blockers, "missing science packs in labs")
                end

                table.insert(result.technologies, {
                    name = tech.name,
                    level = tech.level,
                    research_unit_count = tech.research_unit_count,
                    ingredients = ingredients,
                    effects = research_effects(tech),
                    ready = ready,
                    blockers = blockers,
                })
            end
        end
    end

    if result.lab_status.count == 0 then
        result.guidance = "To research: 1) Craft a lab (requires iron-gear-wheel, electronic-circuit, transport-belt), 2) Place it with power, 3) Craft science packs, 4) Insert science packs into lab"
    elseif result.lab_status.powered == 0 then
        result.guidance = "Labs need power! Connect them to your power grid (steam engine -> power poles -> lab)"
    elseif #result.science_available == 0 then
        result.guidance = "Craft science packs and insert them into labs. Red science (automation-science-pack) requires iron-gear-wheel + copper-plate"
    end

    return result
end

local function start_research_impl(tech_name)
    local force = game.forces.player
    local surface = game.surfaces[1]
    local tech = force.technologies[tech_name]

    if not tech then
        return {success = false, error = "Technology not found"}
    end

    if tech.researched then
        return {success = false, error = "Already researched"}
    end

    if not tech.enabled then
        return {success = false, error = "Technology not enabled"}
    end

    for _, prereq in pairs(tech.prerequisites) do
        if not prereq.researched then
            return {success = false, error = "Prerequisites not met: " .. prereq.name}
        end
    end

    local labs = surface.find_entities_filtered{type = "lab", force = force}
    if #labs == 0 then
        return {
            success = false,
            error = "No labs found! Build a lab first (requires: 10 iron-gear-wheel, 10 electronic-circuit, 4 transport-belt)",
            action_needed = "build_lab",
        }
    end

    local powered_labs = 0
    for _, lab in pairs(labs) do
        if lab_has_power(lab) then
            powered_labs = powered_labs + 1
        end
    end
    if powered_labs == 0 then
        return {
            success = false,
            error = "Labs have no power! Connect labs to power grid.",
            action_needed = "power_labs",
        }
    end

    local ingredients = research_ingredients(tech)
    local missing_packs = {}
    local science_in_labs = science_totals_from_labs(labs)
    for _, ing in pairs(tech.research_unit_ingredients) do
        local have = science_in_labs[ing.name] or 0
        if have < ing.amount then
            table.insert(missing_packs, ing.name .. " (need " .. ing.amount .. ", have " .. have .. " in labs)")
        end
    end

    if #missing_packs > 0 then
        return {
            success = false,
            error = "Missing science packs in labs: " .. table.concat(missing_packs, ", "),
            action_needed = "insert_science_packs",
            required_packs = ingredients,
            hint = "Craft the required science packs and insert them into your labs",
        }
    end

    local added = force.add_research(tech)
    if added then
        return {
            success = true,
            name = tech.name,
            research_unit_count = tech.research_unit_count,
            ingredients = ingredients,
            message = "Research queued! Labs will now consume science packs to progress.",
        }
    end

    return {success = false, error = "Failed to queue research - check if another research is in progress"}
end

local function is_tech_researched_impl(tech_name)
    local tech = game.forces.player.technologies[tech_name]
    if not tech then
        return {researched = false, error = "Technology not found"}
    end
    return {researched = tech.researched == true}
end

local function eval_production_snapshot_impl(surface_name)
    local surface = game.surfaces[surface_name or "nauvis"]
    if not surface then
        return {produced = {}, rate_per_min = {}}
    end

    local stats = game.forces.player.get_item_production_statistics(surface)
    local precision = defines.flow_precision_index.one_minute
    local produced = {}
    local rate_per_min = {}

    for item, count in pairs(stats.input_counts or {}) do
        local name = type(item) == "string" and item or item.name
        if name then
            produced[name] = count
            rate_per_min[name] = stats.get_flow_count{
                name = name,
                category = "input",
                precision_index = precision,
            }
        end
    end

    return {produced = produced, rate_per_min = rate_per_min}
end

local function json_remote_call(action_name, fn, ...)
    local ok, result_or_error = pcall(fn, ...)
    if not ok then
        return helpers.table_to_json({
            error = tostring(result_or_error),
            action_needed = "fix_" .. action_name,
        })
    end
    if result_or_error == nil then return "null" end
    if type(result_or_error) == "string" then return result_or_error end
    return helpers.table_to_json(result_or_error)
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

    ensure_surface = function(planet_name)
        return ensure_surface_impl(planet_name)
    end,

    pre_place_character = function(agent_id, planet_name, spawn_x)
        return pre_place_character_impl(agent_id, planet_name, spawn_x)
    end,

    live_state_line = function(agent_id)
        return live_state_line_impl(agent_id)
    end,

    connected_player_count = function()
        return connected_player_count_impl()
    end,

    broadcast_console = function(message)
        return json_remote_call("broadcast_console", broadcast_console_impl, message)
    end,

    broadcast_flying_text = function(message)
        return json_remote_call("broadcast_flying_text", broadcast_flying_text_impl, message)
    end,

    get_tick = function()
        return json_remote_call("get_tick", get_tick_impl)
    end,

    set_tick_paused = function(paused)
        return json_remote_call("set_tick_paused", set_tick_paused_impl, paused)
    end,

    set_game_speed = function(speed)
        return json_remote_call("set_game_speed", set_game_speed_impl, speed)
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
        return json_remote_call("set_walk_target", set_walk_target_impl, agent_id, x, y)
    end,

    -- Clear target position AND any leftover walk state for an agent. Must reset
    -- walking_state too, or a stale {walking=true} keeps the orphan character
    -- engine-walking with no target (audit F2 trapdoor).
    clear_walk_target = function(agent_id)
        return json_remote_call("clear_walk_target", clear_walk_target_impl, agent_id)
    end,

    -- Report whether an agent has an active deterministic walk target
    has_walk_target = function(agent_id)
        return storage.walk_targets ~= nil and storage.walk_targets[agent_id] ~= nil
    end,

    chat_capture_status = function()
        return helpers.table_to_json({success = true, registered = true})
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
        return json_remote_call("diagnose_steam_power", diagnose_steam_power_impl, x, y, radius)
    end,

    -- Power diagnostics live in the mod so Rust only emits small remote calls.
    get_power_status = function(x, y, radius)
        return json_remote_call("get_power_status", get_power_status_impl, x, y, radius)
    end,

    get_power_networks = function(x, y, radius)
        return json_remote_call("get_power_networks", get_power_networks_impl, x, y, radius)
    end,

    find_power_issues = function(x, y, radius)
        return json_remote_call("find_power_issues", find_power_issues_impl, x, y, radius)
    end,

    get_power_coverage = function(x, y, radius)
        return json_remote_call("get_power_coverage", get_power_coverage_impl, x, y, radius)
    end,

    get_alerts = function(x, y, radius)
        return json_remote_call("get_alerts", get_alerts_impl, x, y, radius)
    end,

    get_belt_contents = function(x1, y1, x2, y2)
        return json_remote_call("get_belt_contents", get_belt_contents_impl, x1, y1, x2, y2)
    end,

    get_belt_lane_contents = function(x1, y1, x2, y2)
        return json_remote_call("get_belt_lane_contents", get_belt_lane_contents_impl, x1, y1, x2, y2)
    end,

    get_surfaces = function()
        return json_remote_call("get_surfaces", get_surfaces_impl)
    end,

    find_entities = function(x1, y1, x2, y2, entity_type, name)
        return json_remote_call("find_entities", find_entities_impl, x1, y1, x2, y2, entity_type, name)
    end,

    verify_production = function(x1, y1, x2, y2)
        return json_remote_call("verify_production", verify_production_impl, x1, y1, x2, y2)
    end,

    get_entity = function(unit_number)
        return json_remote_call("get_entity", get_entity_impl, unit_number)
    end,

    get_entity_drop_position = function(unit_number)
        return json_remote_call("get_entity_drop_position", get_entity_drop_position_impl, unit_number)
    end,

    find_resources = function(x1, y1, x2, y2, resource_type)
        return json_remote_call("find_resources", find_resources_impl, x1, y1, x2, y2, resource_type)
    end,

    find_nearest_resource = function(resource_name, from_x, from_y)
        return json_remote_call("find_nearest_resource", find_nearest_resource_impl, resource_name, from_x, from_y)
    end,

    get_tiles = function(x1, y1, x2, y2)
        return json_remote_call("get_tiles", get_tiles_impl, x1, y1, x2, y2)
    end,

    get_tile = function(x, y)
        return json_remote_call("get_tile", get_tile_impl, x, y)
    end,

    init_character = function(agent_id, x, y)
        return json_remote_call("init_character", init_character_impl, agent_id, x, y)
    end,

    teleport_character = function(agent_id, x, y)
        return json_remote_call("teleport_character", teleport_character_impl, agent_id, x, y)
    end,

    character_status = function(agent_id)
        return json_remote_call("character_status", character_status_impl, agent_id)
    end,

    character_inventory = function(agent_id)
        return json_remote_call("character_inventory", character_inventory_impl, agent_id)
    end,

    craft = function(agent_id, recipe_name, count)
        return json_remote_call("craft", craft_impl, agent_id, recipe_name, count)
    end,

    wait_for_crafting = function(agent_id)
        return json_remote_call("wait_for_crafting", wait_for_crafting_impl, agent_id)
    end,

    create_native_blueprint = function(agent_id, x1, y1, x2, y2)
        return json_remote_call("create_native_blueprint", create_native_blueprint_impl, agent_id, x1, y1, x2, y2)
    end,

    save_blueprint = function(agent_id, name, x1, y1, x2, y2)
        return json_remote_call("save_blueprint", save_blueprint_impl, agent_id, name, x1, y1, x2, y2)
    end,

    list_blueprints = function()
        return json_remote_call("list_blueprints", list_blueprints_impl)
    end,

    get_blueprint = function(name)
        return json_remote_call("get_blueprint", get_blueprint_impl, name)
    end,

    place_blueprint = function(agent_id, name, x, y, direction)
        return json_remote_call("place_blueprint", place_blueprint_impl, agent_id, name, x, y, direction)
    end,

    import_blueprint = function(agent_id, bp_string, x, y, direction)
        return json_remote_call("import_blueprint", import_blueprint_impl, agent_id, bp_string, x, y, direction)
    end,

    delete_blueprint = function(name)
        return json_remote_call("delete_blueprint", delete_blueprint_impl, name)
    end,

    start_mining = function(agent_id, x, y)
        return json_remote_call("start_mining", start_mining_impl, agent_id, x, y)
    end,

    stop_mining = function(agent_id)
        return json_remote_call("stop_mining", stop_mining_impl, agent_id)
    end,

    get_mining_status = function(agent_id)
        return json_remote_call("get_mining_status", get_mining_status_impl, agent_id)
    end,

    mine_at = function(agent_id, x, y, count, radius)
        return json_remote_call("mine_at", mine_at_impl, agent_id, x, y, count, radius)
    end,

    find_nearest_minable = function(agent_id, entity_name, radius)
        return json_remote_call("find_nearest_minable", find_nearest_minable_impl, agent_id, entity_name, radius)
    end,

    mine_nearest = function(agent_id, entity_name, count)
        return json_remote_call("mine_nearest", mine_nearest_impl, agent_id, entity_name, count)
    end,

    clear_area = function(agent_id, x1, y1, x2, y2, clear_trees, clear_rocks, dry_run)
        return json_remote_call("clear_area", clear_area_impl, agent_id, x1, y1, x2, y2, clear_trees, clear_rocks, dry_run)
    end,

    place_entity = function(agent_id, entity_name, x, y, direction)
        return json_remote_call("place_entity", place_entity_impl, agent_id, entity_name, x, y, direction)
    end,

    place_underground_belt = function(agent_id, entity_name, x, y, direction, belt_type)
        return json_remote_call("place_underground_belt", place_underground_belt_impl, agent_id, entity_name, x, y, direction, belt_type)
    end,

    check_entity_placement = function(agent_id, entity_name, x, y, direction)
        return json_remote_call("check_entity_placement", check_entity_placement_impl, agent_id, entity_name, x, y, direction)
    end,

    find_entity_placements = function(agent_id, entity_name, center_x, center_y, radius, limit)
        return json_remote_call("find_entity_placements", find_entity_placements_impl, agent_id, entity_name, center_x, center_y, radius, limit)
    end,

    place_ghost = function(agent_id, entity_name, x, y, direction)
        return json_remote_call("place_ghost", place_ghost_impl, agent_id, entity_name, x, y, direction)
    end,

    build_drill_array = function(agent_id, count, resource, near_x, near_y, drill_type, direction_name)
        return json_remote_call("build_drill_array", build_drill_array_impl, agent_id, count, resource, near_x, near_y, drill_type, direction_name)
    end,

    build_smelter_line = function(agent_id, count, start_x, start_y, furnace_type, line_direction, spacing)
        return json_remote_call("build_smelter_line", build_smelter_line_impl, agent_id, count, start_x, start_y, furnace_type, line_direction, spacing)
    end,

    remove_entity_at = function(x, y)
        return json_remote_call("remove_entity_at", remove_entity_at_impl, x, y)
    end,

    remove_entity = function(unit_number)
        return json_remote_call("remove_entity", remove_entity_impl, unit_number)
    end,

    rotate_entity = function(unit_number, direction)
        return json_remote_call("rotate_entity", rotate_entity_impl, unit_number, direction)
    end,

    insert_items = function(unit_number, item, count, inventory_type)
        return json_remote_call("insert_items", insert_items_impl, unit_number, item, count, inventory_type)
    end,

    extract_items = function(agent_id, unit_number, item, count, inventory_type)
        return json_remote_call("extract_items", extract_items_impl, agent_id, unit_number, item, count, inventory_type)
    end,

    set_recipe = function(unit_number, recipe)
        return json_remote_call("set_recipe", set_recipe_impl, unit_number, recipe)
    end,

    get_entity_inventory = function(unit_number)
        return json_remote_call("get_entity_inventory", get_entity_inventory_impl, unit_number)
    end,

    get_recipe = function(name)
        return json_remote_call("get_recipe", get_recipe_impl, name)
    end,

    get_recipes_by_category = function(category)
        return json_remote_call("get_recipes_by_category", get_recipes_by_category_impl, category)
    end,

    get_recipes_for_item = function(item)
        return json_remote_call("get_recipes_for_item", get_recipes_for_item_impl, item)
    end,

    get_prototype = function(name)
        return json_remote_call("get_prototype", get_prototype_impl, name)
    end,

    get_research_status = function()
        return json_remote_call("get_research_status", get_research_status_impl)
    end,

    get_available_research = function(agent_id)
        return json_remote_call("get_available_research", get_available_research_impl, agent_id)
    end,

    start_research = function(tech_name)
        return json_remote_call("start_research", start_research_impl, tech_name)
    end,

    is_tech_researched = function(tech_name)
        return json_remote_call("is_tech_researched", is_tech_researched_impl, tech_name)
    end,

    eval_production_snapshot = function(surface_name)
        return json_remote_call("eval_production_snapshot", eval_production_snapshot_impl, surface_name)
    end,

    -- Get character position (read-only, safe from any context)
    get_character_pos = function(agent_id)
        local c = find_factorioctl_character(agent_id)
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
