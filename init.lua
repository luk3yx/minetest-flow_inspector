--
-- Minetest flow inspector
--
-- Copyright © 2023 by luk3yx
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--

-- Note: A lot of this code relies on undocumented features and implementation
-- details of flow, this may break in the future (and please don't rely on
-- the hacks used here in other mods).

flow_inspector = {}

local S = minetest.get_translator("flow_inspector")
local gui = flow.widgets

local in_terminal = os.getenv("TERM") ~= nil and os.getenv("TERM") ~= ""

-- Returns a human-readable type for the node
local type_cache = {}
local function human_readable_type(node)
    -- Allow overriding the displayed type
    if node.inspector_type then
        return node.inspector_type
    end

    if node.type == "tooltip" and node.visible == false and
            node.gui_element_name == nil and node.tooltip_text == nil then
        return "Nil"
    end

    if node.type == "container" and #node == 0 and node.visible == false then
        return "Spacer"
    end

    local t = node.type or "?"
    if not type_cache[t] then
        if t == "vbox" or t == "hbox" then
            type_cache[t] = t:sub(1, 2):upper() .. t:sub(3)
        else
            local t2 = t:sub(2):gsub("([a-z])_([a-z])", function(a, b)
                return a .. b:upper()
            end)
            type_cache[t] = t:sub(1, 1):upper() .. t2
        end
    end
    return type_cache[t]
end

local function build_elements(node, elements, cells, parents, indexes, indent)
    if node.inspector_hidden then
        indent = indent - 1
    else
        -- Detect ScrollableVBox
        if node.type == "hbox" and #node == 3 and
                node[1].type == "scroll_container" and #node[1] == 1 and
                node[1][1].type == "vbox" and node[1][1].name and
                node[2].type == "scrollbaroptions" and
                node[3].type == "scrollbar" then
            node.inspector_type = "ScrollableVBox"
            node[1].inspector_hidden = true
            node[1][1].inspector_type = "(internal container)"
            node[2].inspector_hidden = true
            node[3].inspector_type = "(internal scrollbar)"
        end

        elements[#elements + 1] = node
        cells[#cells + 1] = indent
        cells[#cells + 1] = node.visible == false and "#aaa" or "#fff"
        cells[#cells + 1] = human_readable_type(node)
        cells[#cells + 1] = "#888"
        if node.name and not node.inspector_type then
            cells[#cells + 1] = ("%q"):format(node.name)
        else
            cells[#cells + 1] = ""
        end
    end

    for i, n in ipairs(node) do
        build_elements(n, elements, cells, parents, indexes, indent + 1)
        parents[n] = node
        indexes[n] = i
    end
end

local function build_path(node, parents, indexes)
    local path = {}
    while parents[node] do
        table.insert(path, 1, indexes[node])
        node = parents[node]
    end
    return path
end

local function path_to_elem(path, elem)
    for _, idx in ipairs(path) do
        elem = elem[idx]
        if not elem then return end
    end
    return elem
end

-- Used as a key to store flow_inspector's own data in ctx to prevent conflicts
local ctx_key = {}

-- Allow loading flow_inspector multiple times to inspect itself
local table_name = ("flow_inspector:%x"):format(math.random(0, 2^30))
local tabheader_name = table_name .. "_tab"

local auto_align_centre = {
    image = true, animated_image = true, model = true,
    item_image_button = true, list = true
}
local function get_geometry(node, parents)
    local x, y, w, h = node.x, node.y, node.w, node.h
    local align_h, align_v = node.align_h, node.align_v
    if node.type == "label" then
        y = y - 0.2
        if align_h == "centre" or align_h == "center" then
            align_h = "fill"
        elseif not align_h or align_h == "auto" and parents[node] and
                parents[node].type == "vbox" then
            align_h = "start"
            node.align_h = "start"
        end
    elseif node.type == "checkbox" then
        y = y - h / 2
    elseif node.type == "list" then
        w, h = w * 1.25 - 0.25, h * 1.25 - 0.25
    elseif node.type == "tabheader" and (w or 0) > 0 and (h or 0) > 0 then
        y = y - h
    end

    if ((not align_h or align_h == "auto") and auto_align_centre[node.type]) or
            (align_h == "fill" and node.type == "list") then
        align_h = "centre"
    end
    if ((not align_v or align_v == "auto") and (auto_align_centre[node.type] or
            node.type == "label" or node.type == "checkbox")) or
            (align_v == "fill" and (node.type == "list" or
            node.type == "label" or node.type == "checkbox")) then
        align_v = "centre"
    end

    return x, y, w, h, align_h, align_v
end

-- This function builds a container with buttons to be overlayed on top of the
-- form for "pick element" functionality
local btn_id = 0
local tooltip_properties = {"padding", "expand", "align_h", "align_v",
    "texture_name", "item_name", "color", "on_event", "inventory_location",
    "list_name"}
local function build_overlay(node, elements, parents)
    btn_id = btn_id + 1
    local btn_name = "flow_inspector:" .. btn_id
    local padding = node.padding or 0
    local btn = {
        type = "button", x = -padding, y = -padding, w = 0, h = 0,
        expand = true, padding = -padding, name = btn_name,
        visible = not node.inspector_hidden,
        on_event = function(_, ctx)
            ctx.form[table_name] = table.indexof(elements, node)
            ctx[ctx_key].show_picker = nil
            return true
        end
    }

    local container
    if #node > 0 then
        -- Container element
        container = {type = node.type, w = node.w, h = node.h,
            spacing = node.spacing, orientation = node.orientation,
            scrollbar_name = node.scrollbar_name}

        -- Copy properties to the overlay
        for _, n in ipairs(node) do
            if n.x then
                container[#container + 1] = build_overlay(n, elements, parents)
            end
        end
    end

    -- Create a tooltip with a subset of the properties
    local tooltip = {human_readable_type(node)}
    if node.name and not node.inspector_type then
        tooltip[#tooltip + 1] = ("\tname = %q,"):format(node.name)
    end
    if node.visible == false then
        tooltip[#tooltip + 1] = "\tvisible = false,"
    end
    for _, prop in ipairs(tooltip_properties) do
        if node[prop] then
            tooltip[#tooltip + 1] = ("\t%s = %s,"):format(prop,
                dump(node[prop]):gsub("\n", "\n\t"))
        end
    end

    if #tooltip > 1 then
        tooltip[1] = tooltip[1] .. "{"
        tooltip[#tooltip + 1] = "}"
    end

    local overlay = {
        type = "stack", expand = node.expand, padding = node.padding,
        btn,
        {type = "tooltip", gui_element_name = btn_name,
            tooltip_text = table.concat(tooltip, "\n")},
        container
    }

    overlay.x, overlay.y, overlay.w, overlay.h, overlay.align_h,
        overlay.align_v = get_geometry(node, parents)

    if node._padding_top then
        overlay.y = overlay.y - node._padding_top
        overlay.h = overlay.h + node._padding_top
    end

    return overlay
end

-- Opens a debug shell
local function run_debug_shell(player, ctx)
    print()
    print("The server will be unresponsive while the debug shell is running.")
    print("Press Ctrl+D to exit the debug shell.")
    local name = player:get_player_name()
    if minetest.global_exists("dbg") then
        dbg.dd()
    else
        -- Use rawset to bypass undeclared global variable warnings
        rawset(_G, "player", player)
        rawset(_G, "name", name)
        rawset(_G, "ctx", ctx)
        debug.debug()
        rawset(_G, "player", nil)
        rawset(_G, "name", nil)
        rawset(_G, "ctx", nil)

    end

    print()
    print("Debug shell exited")

    -- Redraw the form in case something in ctx was changed
    return true
end

local function hot_reload(player, ctx)
    local ictx = ctx[ctx_key]

    -- Figure out where the .lua file is
    local info = debug.getinfo(ictx.inspected_form._build)
    if info.source:sub(1, 1) ~= "@" then
        ictx.error = S("Could not get source code location!")
        return true
    end

    -- Load the file
    local f, load_err = loadfile(info.source:sub(2))
    if not f then
        ictx.error = tostring(load_err)
        return true
    end

    -- Override flow.make_gui to get the GUI object from the file
    local old_make_gui = flow.make_gui
    local new_form
    function flow.make_gui(...)
        assert(new_form == nil,
            "flow.make_gui called multiple times in the file!")
        new_form = old_make_gui(...)
        return new_form
    end

    -- Run the file
    local ok, err = xpcall(f, debug.traceback)

    -- Restore the original flow.make_gui
    flow.make_gui = old_make_gui

    -- Show an error or switch to the new form
    if not ok then
        ictx.error = err
        minetest.log("error", "Error hot reloading form: " .. err)
    elseif not new_form then
        ictx.error = S("No flow.make_gui call found!")
    else
        ictx.error = nil
        ictx.inspected_form = new_form
    end
    return true
end

-- HACK: Use a metatable so that warnings can be modified until it has to be
-- converted to a string
local warnings_mt = {
    __tostring = function(self)
        if #self == 0 then
            return S("No warnings.")
        end
        return table.concat(self, "\n\n")
    end
}

local sort_order = {}
for i, key in ipairs({"w", "h", "name", "align_h", "align_v", "padding",
        "spacing"}) do
    sort_order[key] = ("\1%02x"):format(i)
end

local inspector_players = {}
local inspector
inspector = flow.make_gui(function(player, ctx)
    -- Catch any warnings printed
    local ictx = ctx[ctx_key]
    local warnings
    if not ictx.error then
        warnings = setmetatable({}, warnings_mt)
        local old_log = minetest.log
        function minetest.log(...)
            local level, msg = ...
            if (level == "warning" or level == "deprecated" or
                    level == "error") and msg then
                warnings[#warnings + 1] = msg
            end
            return old_log(...)
        end
        minetest.after(0, function() minetest.log = old_log end)
    end

    local name = player:get_player_name()

    local t1 = minetest.get_us_time()
    local ok, tree = xpcall(function()
        return ictx.inspected_form._build(player, ctx)
    end, debug.traceback)
    local elapsed = minetest.get_us_time() - t1

    -- Show any errors
    if not ok then
        ictx.error = tree
        tree = gui.Spacer{inspector_type = "(error building GUI)"}
    end

    tree.padding = tree.padding or 0.3
    local add_bgimg = not tree.bgimg and not tree.no_prepend
    local elements, cells, parents, indexes = {}, {}, {}, {}
    build_elements(tree, elements, cells, parents, indexes, 0)


    local tree_idx = ctx.form[table_name] or 1
    if tree_idx ~= ictx.last_elem then
        -- Store the path of the selected element
        ictx.last_elem = tree_idx
        local selected_elem = (ictx.prev_elements or elements)[tree_idx]
        ictx.path = build_path(selected_elem, ictx.prev_parents or parents,
            ictx.prev_indexes or indexes)
    end

    -- Store the previous parents/indexes to figure out the path with
    ictx.prev_elements, ictx.prev_parents, ictx.prev_indexes =
        elements, parents, indexes

    -- Update the selected element based on the path
    local node = path_to_elem(ictx.path, tree)
    tree_idx = table.indexof(elements, node)
    ctx.form[table_name] = tree_idx

    -- HACK: Force flow to calculate the size of all elements
    gui.Flow{w = 999, tree}

    if ictx.show_picker then
        -- Build an overlay
        tree = gui.Stack{
            tree,
            gui.StyleType{
                selectors = {"button"},
                props = {border = false, bgimg = "", bgimg_middle = 8,
                    bgimg_hovered = "flow_inspector_selection.png"},
            },
            gui.StyleType{
                selectors = {"button:hovered", "button:pressed"},
                props = {bgimg = "flow_inspector_selection.png", border = false,
                    bgimg_middle = 8},
            },
            build_overlay(tree, elements, parents)
        }
    elseif node and node.x and node.y and node.w and node.h and
            parents[node] then
        -- Show a border around the selected element
        -- The position and size are copied from the element in case it has
        -- already been rendered
        local x, y, w, h, align_h, align_v = get_geometry(node, parents)

        local padding = node.padding or 0
        local padding_top = node._padding_top or 0
        x = x - padding
        y = y - padding - padding_top
        w = w + padding * 2
        h = h + padding * 2 + padding_top
        node.x, node.y = padding, node.y - y

        local stack = gui.Stack{
            x = x, y = y, w = w, h = h, expand = node.expand,
            bgcolor = "#030",
            gui.Stack{
                x = 0, y = 0, w = w, h = h,
                align_h = align_h, align_v = align_v,
                node,
                gui.Image{
                    x = 0, y = 0, w = 0, h = 0,
                    align_h = "fill", align_v = "fill",
                    texture_name = "flow_inspector_padding.png", middle_x = 8
                },
                gui.Image{
                    x = padding, y = padding, w = 0, h = 0, padding = padding,
                    align_h = "fill", align_v = "fill",
                    texture_name = "flow_inspector_selection.png", middle_x = 8
                },
            },
        }

        parents[node][indexes[node]] = stack
    end

    local selected_info = {}
    if ctx.form[tabheader_name] == 2 then
        -- Hide the inspector's own context and ctx.form (since ctx.form gets
        -- replaced with a wrapper object)
        local form = ctx.form
        ctx[ctx_key], ctx.form = nil, nil
        selected_info[1] = dump(ctx)
        ctx[ctx_key], ctx.form = ictx, form
    elseif node and not ictx.show_picker then
        local keys = {}
        for k, v in pairs(node) do
            if type(k) == "string" and k ~= "type" and k:sub(1, 1) ~= "_" and
                    k:sub(1, 10) ~= "inspector_" and k ~= "x" and k ~= "y" and
                    (k ~= "name" or not node.inspector_type) then
                local msg = ("\t%s = %s,"):format(k, dump(v):gsub("\n", "\n\t"))
                if k == "w" or k == "h" then
                    msg = msg .. " -- Before expansion"
                end
                keys[msg] = k
                selected_info[#selected_info + 1] = msg
            end
        end
        table.sort(selected_info, function(a, b)
            a, b = keys[a], keys[b]
            return (sort_order[a] or a) < (sort_order[b] or b)
        end)
        table.insert(selected_info, 1, S("@1{", human_readable_type(node)))
        selected_info[#selected_info + 1] = "}"
    end

    -- Centre the form and add a background if required
    tree.expand = true
    tree.align_h = "centre"
    tree.align_v = "centre"
    if add_bgimg then
        tree.bgimg = "flow_inspector_bg.png"
        tree.bgimg_middle = 32
    end

    local win_info = minetest.get_player_window_information and
        minetest.get_player_window_information(name)
    local size = win_info and win_info.max_formspec_size or {x = 0, y = 0}
    return gui.HBox{
        no_prepend = true, bg_fullscreen = true, spacing = 1, padding = 0,
        min_w = size.x, min_h = size.y,

        -- Left side pane
        gui.VBox{
            bgimg = "flow_inspector_bg.png", bgimg_middle = 32, padding = 0.3,
            gui.Label{label = S("Flow inspector")},
            gui.TableColumns{
                tablecolumns = {
                    {type = "tree", opts = {}},
                    {type = "color", opts = {}},
                    {type = "text", opts = {align = "inline"}},
                    {type = "color", opts = {}},
                    {type = "text", opts = {}},
                },
            },
            gui.Table{
                w = 6, h = 10, expand = true, cells = cells,
                name = table_name,
            },
            gui.Label{label = ("Build time: %.1f ms"):format(elapsed / 1000)},
            gui.Checkbox{
                name = table_name .. "hide_right_pane",
                label = S("Hide side pane"),
            },
            gui.Button{
                label = ictx.show_picker and S("Cancel") or S("Pick element"),
                on_event = function()
                    ictx.show_picker = not ictx.show_picker
                    return true
                end,
            },
        },
        tree,

        -- Reset styles
        gui.StyleType{
            selectors = {"button", "button:hovered", "button:pressed"},
            props = {bgimg = "", border = ""},
        },

        -- Right side pane
        ctx.form[table_name .. "hide_right_pane"] and gui.Nil{} or gui.VBox{
            bgimg = "flow_inspector_bg.png", bgimg_middle = 32, padding = 0.3,
            gui.Tabheader{
                w = 6, h = 0.6, name = tabheader_name,
                captions = {S("Selected element"), S("Context")},
                draw_border = false
            },
            gui.Textarea{w = 6, h = 3, expand = true,
                default = table.concat(selected_info, "\n")},
            gui.Label{label = ictx.error and S("Error") or S("Warnings")},
            gui.Textarea{w = 6, h = 3, default = ictx.error or warnings},
            gui.Button{
                label = S("Hot reload"),
                on_event = hot_reload,
            },

            -- Only show debug button when running in terminal
            in_terminal and gui.Button{
                name = table_name .. "debug",
                label = S("Open debug shell"),
                on_event = run_debug_shell,
            } or gui.Nil{},
            in_terminal and gui.Tooltip{
                gui_element_name = table_name .. "debug",
                tooltip_text = S("The debug shell will be opened in " ..
                    "Minetest's console.\nThe server will be unresponsive " ..
                    "until the debug shell is exited.")
            } or gui.Nil{},

            gui.Button{
                label = ictx.confirm_disable and S("Click again to confirm") or
                    S("Disable inspector"),
                on_event = function(player)
                    if ictx.confirm_disable then
                        inspector_players[name] = nil
                        ctx[ctx_key] = nil
                        ictx.inspected_form:show(player, ctx)
                        return
                    end

                    ictx.confirm_disable = true
                    minetest.after(3, function()
                        player = minetest.get_player_by_name(name)
                        if player then
                            ictx.confirm_disable = nil
                            inspector:update(player)
                        end
                    end)
                    return true
                end,
            },
        },
    }
end)

function flow_inspector.enable(player)
    inspector_players[player:get_player_name()] = true
end

function flow_inspector.disable(player)
    inspector_players[player:get_player_name()] = nil
end

function flow_inspector.inspect(player, form)
    return inspector:show(player, {[ctx_key] = {inspected_form = form}})
end

local Form = getmetatable(inspector).__index

-- Monkey patch form:show to load the inspector if enabled
local old_show = Form.show
function Form:show(player, ctx)
    if self ~= inspector and inspector_players[player:get_player_name()] then
        ctx = ctx or {}
        ctx[ctx_key] = ctx[ctx_key] or {}
        ctx[ctx_key].inspected_form = self
        self = inspector
    end
    return old_show(self, player, ctx)
end

local old_update = Form.update
function Form:update(player)
    if self ~= inspector then
        inspector:update_where(function(player2, ctx)
            return ctx[ctx_key].inspected_form == self and
                player:get_player_name() == player2:get_player_name()
        end)
    end
    return old_update(self, player)
end

local old_update_where = Form.update_where
function Form:update_where(func)
    if self ~= inspector then
        inspector:update_where(function(player, ctx)
            if ctx[ctx_key].inspected_form == self then
                return func(player, ctx)
            end
        end)
    end
    return old_update_where(self, func)
end

local old_close = Form.close
function Form:close(player)
    if self ~= inspector then
        inspector:update_where(function(player2, ctx)
            if ctx[ctx_key].inspected_form == self and
                    player:get_player_name() == player2:get_player_name() then
                inspector:close(player)
            end
        end)
    end
    return old_close(self, player)
end

minetest.register_chatcommand("inspector", {
    privs = {server = true},
    description = S("Toggles the flow inspector"),
    func = function(name, param)
        if param == "" then
            inspector_players[name] = not inspector_players[name] or nil
            return true, inspector_players[name] and S("Inspector enabled!") or
                S("Inspector disabled!")
        end

        return false
    end,
})

minetest.register_on_leaveplayer(function(player)
    inspector_players[player:get_player_name()] = nil
end)
