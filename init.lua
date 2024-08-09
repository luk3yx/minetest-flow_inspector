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
local type_cache = {
    tablecolumns = "TableColumns",
    tableoptions = "TableOptions",
    scrollbaroptions = "ScrollbarOptions",
}
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

-- These icons are from Glade under the LGPL v2 license, see LICENSE.md for
-- more information.
local icons = {
    Button = "flow_inspector_widget_button.png",
    ButtonExit = "flow_inspector_widget_button.png",
    Checkbox = "flow_inspector_widget_checkbutton.png",
    Container = "flow_inspector_widget_fixed.png",
    Dropdown = "flow_inspector_widget_combobox.png",
    Field = "flow_inspector_widget_entry.png",
    HBox = "flow_inspector_widget_hbox.png",
    Hypertext = "flow_inspector_widget_recentchooser.png",
    Image = "flow_inspector_widget_image.png",
    ImageButton = "flow_inspector_widget_filechooserbutton.png",
    ImageButtonExit = "flow_inspector_widget_filechooserbutton.png",
    ItemImage = "flow_inspector_widget_image.png",
    ItemImageButton = "flow_inspector_widget_filechooserbutton.png",
    Label = "flow_inspector_widget_label.png^[colorize:#fff",
    List = "flow_inspector_widget_flowbox.png",
    Model = "flow_inspector_widget_glarea.png",
    Padding = "flow_inspector_widget_deprecated.png",
    Pwdfield = "flow_inspector_widget_entry.png",
    ScrollableVBox = "flow_inspector_widget_scrollablevbox.png",
    Scrollbar = "flow_inspector_widget_vscrollbar.png",
    ScrollbarOptions = "flow_inspector_widget_treestore.png",
    Stack = "flow_inspector_widget_stack.png",
    Style = "flow_inspector_widget_drawingarea.png",
    StyleType = "flow_inspector_widget_drawingarea.png",
    Tabheader = "flow_inspector_widget_notebook.png",
    Table = "flow_inspector_widget_treeviewcolumn.png",
    TableColumns = "flow_inspector_widget_treestore.png^[invert:rgb",
    TableOptions = "flow_inspector_widget_treestore.png^[invert:rgb",
    Textarea = "flow_inspector_widget_textview.png",
    Textlist = "flow_inspector_widget_treestore.png^[invert:rgb",
    Tooltip = "flow_inspector_widget_texttag.png",
    VBox = "flow_inspector_widget_vbox.png",
    Vertlabel = "flow_inspector_widget_label.png^[colorize:#fff^[transform3",
}

local function build_elements(node, elements, cells, parents, indexes,
        id_to_icon, icon_to_id, indent)
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
            node[1][1].inspector_icon = icons.VBox
            node[2].inspector_hidden = true
            node[3].inspector_type = "(internal scrollbar)"
            node[3].inspector_icon = icons.Scrollbar
        end

        elements[#elements + 1] = node

        cells[#cells + 1] = indent

        local readable_type = human_readable_type(node)
        local icon = node.inspector_icon or icons[readable_type] or
            "flow_inspector_widget_default.png"
        if node.type == "box" and not node.inspector_icon and node.color
                and node.color:match("^[A-Za-z0-9#]+$") then
            icon = icon .. "^[multiply:" .. node.color
        end
        if node.visible == false then
            icon = icon .. "^[multiply:#aaa"
        end

        -- Dynamically allocate icon IDs as needed
        if not icon_to_id[icon] then
            icon_to_id[icon] = #id_to_icon + 1
            id_to_icon[#id_to_icon + 1] = icon
        end
        cells[#cells + 1] = icon_to_id[icon]

        cells[#cells + 1] = node.visible == false and "#aaa" or "#fff"
        cells[#cells + 1] = readable_type
        cells[#cells + 1] = "#888"
        if node.name and not node.inspector_type then
            cells[#cells + 1] = ("%q"):format(node.name)
        else
            cells[#cells + 1] = ""
        end
    end

    for i, n in ipairs(node) do
        build_elements(n, elements, cells, parents, indexes, id_to_icon,
            icon_to_id, indent + 1)
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
local tooltip_properties = {"padding", "expand", "align_h", "align_v",
    "texture_name", "item_name", "color", "on_event", "inventory_location",
    "list_name"}
local function build_overlay(node, elements, parents)
    local padding = node.padding or 0

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

    local btn = {
        type = "button", x = -padding, y = -padding, w = 0, h = 0,
        expand = true, padding = -padding,
        visible = not node.inspector_hidden,
        tooltip = table.concat(tooltip, "\n"),
        on_event = function(_, ctx)
            ctx.form[table_name] = table.indexof(elements, node)
            ctx[ctx_key].show_picker = nil
            return true
        end
    }

    local overlay = {
        type = "stack", expand = node.expand, padding = node.padding,
        btn, container
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
    print("Type 'cont' to exit the debug shell.")

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

-- Detects errors in flow and translates them into something that makes sense
local function translate_error_message(err)
    if err:find("attempt to get length of local", 1, true) and
            err:find(DIR_DELIM .. "flow" .. DIR_DELIM ..
                "[^\n]-: in function 'naive_str_width'") then
        err = "A value in an attribute of an element is not a string, but " ..
            "flow expects it to be one.\nFull error:\n" .. err
    end

    return err
end

local inspector, debug_infos
local function get_element_source(debug_info)
    if debug_info and debug_info.currentline > 0 then
        local src = debug_info.short_src:gsub("^%.%.%..-" .. DIR_DELIM ..
            "mods" .. DIR_DELIM, "..." .. DIR_DELIM)
        return S("Created on line @1 in @2", debug_info.currentline, src)
    end
end

-- HACK: Use a metatable so that warnings can be modified until it has to be
-- converted to a string
local warnings_mt = {
    __tostring = function(self)
        if self.error then
            -- Show the error message after warnings, the warnings might help
            -- to figure out what is causing the error
            self[#self + 1] = translate_error_message(self.error)
            self.error = nil
        elseif #self == 0 then
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
local old_log = minetest.log
inspector = flow.make_gui(function(player, ctx)
    -- Catch any warnings printed
    local ictx = ctx[ctx_key]
    local warnings = setmetatable({}, warnings_mt)
    function minetest.log(...)
        local level, msg = ...
        if (level == "warning" or level == "deprecated" or
                level == "error") and msg then
            warnings[#warnings + 1] = msg
        end
        return old_log(...)
    end
    minetest.after(0, function() minetest.log = old_log end)

    local name = player:get_player_name()

    -- Create the debug_infos table if it will be used
    if not ictx.show_picker then
        debug_infos = {}
    end

    -- local t1 = minetest.get_us_time()
    local ok, tree = xpcall(function()
        return ictx.inspected_form._build(player, ctx)
    end, debug.traceback)
    -- local elapsed = minetest.get_us_time() - t1

    -- Show any errors
    if not ok then
        ictx.error = tree
        tree = gui.Spacer{inspector_type = "(error building GUI)"}
    end

    tree.padding = tree.padding or 0.3
    local add_bgimg = not tree.bgimg and not tree.no_prepend
    local elements, cells, parents, indexes = {}, {}, {}, {}
    local id_to_icon = {align = "inline"}
    build_elements(tree, elements, cells, parents, indexes, id_to_icon, {}, 0)

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

    -- Get the debug info for the selected node
    local debug_info = debug_infos and debug_infos[node]
    debug_infos = nil

    -- HACK: Force flow to calculate the size of all elements
    local layout_ok, err = xpcall(function()
        gui.Flow{w = 999, tree}
    end, debug.traceback)
    if not layout_ok then
        ictx.error = err
        -- The inspector does not like a non-box element being the root
        tree = gui.Stack{
            min_h = 1,
            gui.Label{
                label = S("Error when laying out GUI"),
                align_h = "centre"
            }
        }
    end

    -- Show the error message after any warnings
    warnings.error = ictx.error

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
        local source = get_element_source(debug_info)
        if source then
            selected_info[#selected_info + 1] = source
        end
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
            gui.TableOptions{
                opts = {opendepth = 3},
            },
            gui.TableColumns{
                tablecolumns = {
                    {type = "tree", opts = {}},
                    {type = "image", opts = id_to_icon},
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

            -- The debug.getinfo code will add some overhead making this
            -- inaccurate
            -- gui.Label{
            --     label = ("Build time: %.1f ms"):format(elapsed / 1000)
            -- },

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
            gui.Textarea{w = 6, h = 3, expand = ictx.error == nil,
                default = table.concat(selected_info, "\n")},
            gui.Label{label = ictx.error and S("Error") or S("Warnings")},
            gui.Textarea{w = 6, h = 3, default = warnings,
                expand = ictx.error ~= nil},
            gui.Button{
                label = S("Hot reload"),
                on_event = hot_reload,
            },

            -- Only show debug button when running in terminal
            in_terminal and gui.Button{
                label = S("Open debug shell"),
                tooltip = S("The debug shell will be opened in Minetest's " ..
                    "console.\nThe server will be unresponsive until the " ..
                    "debug shell is exited."),
                on_event = run_debug_shell,
            } or gui.Nil{},

            gui.Button{
                label = ictx.confirm_disable and S("Click again to confirm") or
                    S("Disable inspector"),
                on_event = function(player)
                    if ictx.confirm_disable then
                        inspector_players[name] = nil
                        ctx[ctx_key] = nil
                        local form = ictx.inspected_form
                        form[ictx.show_func](form, player, ctx)
                        return
                    end

                    ictx.confirm_disable = true
                    minetest.after(3, function()
                        player = minetest.get_player_by_name(name)
                        if player and ctx[ctx_key] == ictx then
                            ictx.confirm_disable = nil
                            if ictx.show_func == "set_as_inventory_for" then
                                inspector:set_as_inventory_for(player, ctx)
                            else
                                inspector:update(player)
                            end
                        end
                    end)
                    return true
                end,
            },
        },
    }
end)

-- Store the line number of created widgets
local commonly_incorrect_types = {"name", "label", "default"}
local function wrap_func(func)
    if type(func) ~= "function" then return func end
    return function(def, ...)
        local node = func(def, ...)
        if debug_infos and type(def) == "table" then
            local info = debug.getinfo(2, "Sl")
            debug_infos[node] = info

            -- Show warnings for types that are wrong (flow does not do this
            -- due to performance concerns)
            for _, key in pairs(commonly_incorrect_types) do
                if node[key] ~= nil and type(node[key]) ~= "string" then
                    local source = get_element_source(info) or "unknown location"
                    local msg = debug.traceback(
                        "[flow_inspector] The \"" .. key ..
                        "\" attribute in a " .. human_readable_type(node) ..
                        " element (" .. source .. ") should be a string, " ..
                        "not \"" .. type(node[key]) .. "\". This may lead " ..
                        "to errors or unexpected behaviour.", 2
                    )

                    -- Remove flow_inspector from the traceback
                    msg = msg:match("(.-)\n\t%[C%]: in function 'xpcall'\n" ..
                        "[^\n]+flow_inspector") or msg

                    minetest.log("warning", msg)
                end
            end
        end

        return node
    end
end

local gui_mt = getmetatable(gui)
local old_gui_index = gui_mt.__index
function gui_mt:__index(key)
    local res = wrap_func(old_gui_index(self, key))
    gui[key] = res
    return res
end

for k, v in pairs(gui) do
    gui[k] = wrap_func(v)
end

-- API functions
function flow_inspector.enable(player)
    inspector_players[player:get_player_name()] = true
end

function flow_inspector.disable(player)
    inspector_players[player:get_player_name()] = nil
end

function flow_inspector.inspect(player, form)
    return inspector:show(player, {[ctx_key] = {inspected_form = form}})
end

-- Monkey patch form:show to load the inspector if enabled
local Form = getmetatable(inspector).__index
for _, func in ipairs({"show", "set_as_inventory_for"}) do
    local old_func = Form[func]
    Form[func] = function(self, player, ctx)
        if self ~= inspector and
                inspector_players[player:get_player_name()] then
            ctx = ctx or {}
            ctx[ctx_key] = ctx[ctx_key] or {show_func = func}
            ctx[ctx_key].inspected_form = self
            self = inspector
        end
        return old_func(self, player, ctx)
    end
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
