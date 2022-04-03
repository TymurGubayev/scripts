-- adjust work orders' input item, material, traits
--[====[

gui/workorder-finetune
======================
Adjust input items, material, or traits for work orders. Actual
jobs created for it will inherit the details.

This is the equivalent of `gui/workshop-job` for work orders,
with the additional possibility to set input items' traits.

It has to be run from a work order's detail screen
(:kbd:`j-m`, select work order, :kbd:`d`).

For best experience add the following to your ``dfhack*.init``::

    keybinding add D@workquota_details gui/workorder-finetune

]====]

--[[
credit goes to the author of `gui/workshop-job` where the majority
of the code here comes from.
]]

local utils = require 'utils'
local gui = require 'gui'
local guimat = require 'gui.materials'
local widgets = require 'gui.widgets'
local dlg = require 'gui.dialogs'

local wsj = reqscript 'gui/workshop-job'

-- start gui.materials.ItemTraitDialog
--------------------------------------
local job_item_flags_map = {}
for i = 1, 3 do
    for _, f in ipairs(df['job_item_flags'..i]) do
        if f then
            job_item_flags_map[f] = 'flags'..i
        end
    end
end
local job_item_flags = {}
for k, _ in pairs(job_item_flags_map) do
    job_item_flags[#job_item_flags + 1] = k
end
table.sort(job_item_flags)
--------------------------------------
local tool_uses = {}
for i, _ in ipairs(df.tool_uses) do
    tool_uses[#tool_uses + 1] = df.tool_uses[i]
end
local restore_none = false
if tool_uses[1] == 'NONE' then
    restore_none = true
    table.remove(tool_uses, 1)
end
table.sort(tool_uses)
if restore_none then
    table.insert(tool_uses, 1, 'NONE')
end
--------------------------------------
local set_ore_ix = {}
for i, raw in ipairs(df.global.world.raws.inorganics) do
    for _, ix in ipairs(raw.metal_ore.mat_index) do
        set_ore_ix[ix] = true
    end
end
local ores = {}
for ix in pairs(set_ore_ix) do
    local raw = df.global.world.raws.inorganics[ix]
    ores[#ores+1] = {mat_index = ix, name = raw.material.state_name.Solid}
end
table.sort(ores, function(a,b) return a.name < b.name end)

--------------------------------------
-- CALCIUM_CARBONATE, CAN_GLAZE, FAT, FLUX,
-- GYPSUM, PAPER_PLANT, PAPER_SLURRY, TALLOW, WAX
local reaction_classes_set = {}
for ix,reaction in ipairs(df.global.world.raws.reactions.reactions) do
    if #reaction.reagents > 0 then
        for _, r in ipairs(reaction.reagents) do
            if r.reaction_class and r.reaction_class ~= '' then
                reaction_classes_set[r.reaction_class] = true
            end
        end
    end --if
end
local reaction_classes = {}
for k in pairs(reaction_classes_set) do
    reaction_classes[#reaction_classes + 1] = k
end
table.sort(reaction_classes)
--------------------------------------
-- PRESS_LIQUID_MAT, TAN_MAT, BAG_ITEM etc
local product_materials_set = {}
for ix,reaction in ipairs(df.global.world.raws.reactions.reactions) do
    if #reaction.products > 0 then
        --for _, p in ipairs(reaction.products) do
        -- in the list in work order conditions there is no SEED_MAT.
        -- I think it's because the game doesn't iterate over all products.
            local p = reaction.products[0]
            local mat = p.get_material
            if mat and mat.product_code ~= '' then
                product_materials_set[mat.product_code] = true
            end
        --end
    end --if
end
local product_materials = {}
for k in pairs(product_materials_set) do
    product_materials[#product_materials + 1] = k
end
table.sort(product_materials)
--==================================--

local function set_search_keys(choices)
    for _, choice in ipairs(choices) do
        if not choice.search_key then
            if type(choice.text) == 'table' then
                local search_key = {}
                for _, token in ipairs(choice.text) do
                    search_key[#search_key+1] = string.lower(token.text or '')
                end
                choice.search_key = table.concat(search_key, ' ')
            elseif choice.text then
                choice.search_key = string.lower(choice.text)
            end
        end
    end
end

guimat.ItemTraitDialog = function(args)
    args.text = args.prompt or 'Type or select an item trait'
    args.text_pen = COLOR_WHITE
    args.with_filter = true
    args.icon_width = 2
    args.dismiss_on_select = false

    local pen_active = COLOR_LIGHTCYAN
    local pen_active_d = COLOR_CYAN
    local pen_not_active = COLOR_LIGHTRED
    local pen_not_active_d = COLOR_RED
    local pen_action = COLOR_WHITE
    local pen_action_d = COLOR_GREY

    local job_item = args.job_item
    local choices = {}

    local pen_cb = function(args, fnc)
        if not (args and fnc) then
            return COLOR_YELLOW
        end
        return fnc(args) and pen_active or pen_not_active
    end
    local pen_d_cb = function(args, fnc)
        if not (args and fnc) then
            return COLOR_YELLOW
        end
        return fnc(args) and pen_active_d or pen_not_active_d
    end
    local icon_cb = function(args, fnc)
        if not (args and fnc) then
            return '\19' -- ‼
        end
        -- '\251' is a checkmark
        -- '\254' is a square
        return fnc(args) and '\251' or '\254'
    end

    if not args.hide_none then
        table.insert(choices, {
            icon = '!',
            text = {{text = args.none_caption or 'none', pen = pen_action, dpen = pen_action_d}},
            reset_all_traits = true
        })
    end

    local isActiveFlag = function (obj)
        return obj.job_item[obj.ffield][obj.flag]
    end
    table.insert(choices, {
        icon = '!',
        text = {{text = 'unset flags', pen = pen_action, dpen = pen_action_d}},
        reset_flags = true
    })
    for _, flag in ipairs(job_item_flags) do
        local ffield = job_item_flags_map[flag]
        local text = 'is ' .. (value and '' or 'any ') .. string.lower(flag)
        local args = {job_item=job_item, ffield=ffield, flag=flag}
        table.insert(choices, {
            icon = curry(icon_cb, args, isActiveFlag),
            text = {{text = text,
                    pen = curry(pen_cb, args, isActiveFlag),
                    dpen = curry(pen_d_cb, args, isActiveFlag),
            }},
            ffield = ffield, flag = flag
        })
    end

    local isActiveTool = function (args)
        return df.tool_uses[args.tool_use] == args.job_item.has_tool_use
    end
    for _, tool_use in ipairs(tool_uses) do
        if tool_use == 'NONE' then
            table.insert(choices, {
                icon = '!',
                text = {{text = 'unset use', pen = pen_action, dpen = pen_action_d}},
                tool_use = tool_use
            })
        else
            local args = {job_item = job_item, tool_use=tool_use}
            table.insert(choices, {
                icon = ' ',
                text = {{text = 'has use ' .. tool_use,
                        pen = curry(pen_cb, args, isActiveTool),
                        dpen = curry(pen_d_cb, args, isActiveTool),
                }},
                tool_use = tool_use
            })
        end
    end

    local isActiveOre = function(args)
        return (args.job_item.metal_ore == args.mat_index)
    end
    table.insert(choices, {
            icon = '!',
            text = {{text = 'unset ore', pen = pen_action, dpen = pen_action_d}},
            ore_ix = -1
        })
    for _, ore in ipairs(ores) do
        local args = {job_item = job_item, mat_index=ore.mat_index}
        table.insert(choices, {
            icon = ' ',
            text = {{text = 'ore of ' .. ore.name,
                    pen = curry(pen_cb, args, isActiveOre),
                    dpen = curry(pen_d_cb, args, isActiveOre),
            }},
            ore_ix = ore.mat_index
        })
    end
    
    local isActiveReactionClass = function(args)
        return (args.job_item.reaction_class == args.reaction_class)
    end
    table.insert(choices, {
            icon = '!',
            text = {{text = 'unset reaction class', pen = pen_action, dpen = pen_action_d}},
            reaction_class = ''
        })
    for _, reaction_class in ipairs(reaction_classes) do
        local args = {job_item = job_item, reaction_class=reaction_class}
        table.insert(choices, {
            icon = ' ',
            text = {{text = 'reaction class ' .. reaction_class,
                    pen = curry(pen_cb, args, isActiveReactionClass),
                    dpen = curry(pen_d_cb, args, isActiveReactionClass)
            }},
            reaction_class = reaction_class
        })
    end
    
    local isActiveProduct = function(args)
        return (args.job_item.has_material_reaction_product == args.product_materials)
    end
    table.insert(choices, {
            icon = '!',
            text = {{text = 'unset producing', pen = pen_action, dpen = pen_action_d}},
            product_materials = ''
        })
    for _, product_materials in ipairs(product_materials) do
        local args = {job_item = job_item, product_materials=product_materials}
        table.insert(choices, {
            icon = ' ',
            text = {{text = product_materials .. '-producing',
                    pen = curry(pen_cb, args, isActiveProduct),
                    dpen = curry(pen_d_cb, args, isActiveProduct)
            }},
            product_materials = product_materials
        })
    end

    set_search_keys(choices)
    args.choices = choices

    if args.on_select then
        local cb = args.on_select
        args.on_select = function(idx, obj)
            return cb(obj)
        end
    end

    return dlg.ListBox(args)
end
-- end gui.materials.ItemTraitDialog

local JobDetails = defclass(JobDetails, gui.FramedScreen)

JobDetails.focus_path = 'workorder-finetune'

JobDetails.ATTRS {
    job = DEFAULT_NIL,
    frame_inset = 1,
    frame_background = COLOR_BLACK,
}

function JobDetails:init(args)
    self:addviews{
        widgets.Label{
            frame = { l = 0, t = 0 },
            text = {
                { text = df.job_type.attrs[self.job.job_type].caption }, NEWLINE, NEWLINE,
                '  ', status
            }
        },
        widgets.Label{
            frame = { l = 0, t = 4 },
            text = {
                { key = 'CUSTOM_I', text = ': Input item, ',
                  enabled = self:callback('canChangeIType'),
                  on_activate = self:callback('onChangeIType') },
                { key = 'CUSTOM_M', text = ': Material, ',
                  enabled = self:callback('canChangeMat'),
                  on_activate = self:callback('onChangeMat') },
                { key = 'CUSTOM_T', text = ': Traits',
                  enabled = self:callback('canChangeTrait'),
                  on_activate = self:callback('onChangeTrait') }
            }
        },
        widgets.List{
            view_id = 'list',
            frame = { t = 6, b = 2 },
            row_height = 4,
        },
        widgets.Label{
            frame = { l = 0, b = 0 },
            text = {
                { key = 'LEAVESCREEN', text = ': Back',
                  on_activate = self:callback('dismiss') }
            }
        },
    }

    self:initListChoices()
end

function JobDetails:onGetSelectedJob()
    return self.job
end

local describe_item_type = wsj.describe_item_type
local is_caste_mat = wsj.is_caste_mat
local describe_material = wsj.describe_material
local list_flags = wsj.list_flags

local function describe_item_traits(iobj)
    local line1 = {}
    local reaction = df.reaction.find(iobj.reaction_id)
    if reaction and #iobj.contains > 0 then
        for _,ri in ipairs(iobj.contains) do
            table.insert(line1, 'has '..utils.call_with_string(
                reaction.reagents[ri],'getDescription',iobj.reaction_id
            ))
        end
    end
    if iobj.metal_ore >= 0 then
        local ore = dfhack.matinfo.decode(0, iobj.metal_ore)
        if ore then
            table.insert(line1, 'ore of '..ore:toString())
        end
    end
    if iobj.has_material_reaction_product ~= '' then
        table.insert(line1, iobj.has_material_reaction_product .. '-producing')
    end
    if iobj.reaction_class ~= '' then
        table.insert(line1, 'reaction class '..iobj.reaction_class)
    end
    if iobj.has_tool_use >= 0 then
        table.insert(line1, 'has use '..df.tool_uses[iobj.has_tool_use])
    end

    list_flags(line1, iobj.flags1)
    list_flags(line1, iobj.flags2)
    list_flags(line1, iobj.flags3)

    if #line1 == 0 then
        table.insert(line1, 'no traits')
    end
    return table.concat(line1, ', ')
end

function JobDetails:initListChoices()
    if not self.job.items then
        self.subviews.list:setChoices({})
        return
    end

    local choices = {}
    for i,iobj in ipairs(self.job.items) do
        local head = 'Item '..(i+1)..' x'..iobj.quantity
        if iobj.min_dimension > 0 then
            head = head .. '(size '..iobj.min_dimension..')'
        end

        table.insert(choices, {
            index = i,
            iobj = iobj,
            text = {
                head, NEWLINE,
                '  ', { text = curry(describe_item_type, iobj) }, NEWLINE,
                '  ', { text = curry(describe_material, iobj) }, NEWLINE,
                '  ', { text = curry(describe_item_traits, iobj) }, NEWLINE
            }
        })
    end

    self.subviews.list:setChoices(choices)
end

JobDetails.canChangeIType = wsj.JobDetails.canChangeIType
JobDetails.setItemType = wsj.JobDetails.setItemType
JobDetails.onChangeIType = wsj.JobDetails.onChangeIType
JobDetails.canChangeMat = wsj.JobDetails.canChangeMat
JobDetails.setMaterial = wsj.JobDetails.setMaterial
JobDetails.findUnambiguousItem = wsj.JobDetails.findUnambiguousItem
JobDetails.onChangeMat = wsj.JobDetails.onChangeMat

function JobDetails:onInput(keys)
    JobDetails.super.onInput(self, keys)
end

function JobDetails:canChangeTrait()
    local idx, obj = self.subviews.list:getSelected()
    return obj ~= nil and not is_caste_mat(obj.iobj)
end

function JobDetails:toggleFlag(obj, ffield, flag)
    local job_item = obj.iobj
    job_item[ffield][flag] = not job_item[ffield][flag]
end

function JobDetails:toggleToolUse(obj, tool_use)
    local job_item = obj.iobj
    tool_use = df.tool_uses[tool_use]
    if job_item.has_tool_use == tool_use then
        job_item.has_tool_use = df.tool_uses.NONE
    else
        job_item.has_tool_use = tool_use
    end
end

function JobDetails:toggleMetalOre(obj, ore_ix)
    local job_item = obj.iobj
    if job_item.metal_ore == ore_ix then
        job_item.metal_ore = -1
    else
        job_item.metal_ore = ore_ix
    end
end

function JobDetails:toggleReactionClass(obj, reaction_class)
    local job_item = obj.iobj
    if job_item.reaction_class == reaction_class then
        job_item.reaction_class = ''
    else
        job_item.reaction_class = reaction_class
    end
end

function JobDetails:toggleProductMaterial(obj, product_materials)
    local job_item = obj.iobj
    if job_item.has_material_reaction_product == product_materials then
        job_item.has_material_reaction_product = ''
    else
        job_item.has_material_reaction_product = product_materials
    end
end

function JobDetails:unsetFlags(obj)
    local job_item = obj.iobj
    for flag, ffield in pairs(job_item_flags_map) do
        if job_item[ffield][flag] then
            JobDetails:toggleFlag(obj, ffield, flag)
        end
    end
end

function JobDetails:setTrait(obj, sel)
    if sel.ffield then
        --print('toggle flag', sel.ffield, sel.flag)
        JobDetails:toggleFlag(obj, sel.ffield, sel.flag)
    elseif sel.reset_flags then
        --print('reset every flag')
        JobDetails:unsetFlags(obj)
    elseif sel.tool_use then
        --print('toggle tool_use', sel.tool_use)
        JobDetails:toggleToolUse(obj, sel.tool_use)
    elseif sel.ore_ix then
        --print('toggle ore', sel.ore_ix)
        JobDetails:toggleMetalOre(obj, sel.ore_ix)
    elseif sel.reaction_class then
        --print('toggle reaction class', sel.reaction_class)
        JobDetails:toggleReactionClass(obj, sel.reaction_class)
    elseif sel.product_materials then
        --print('toggle product materials', sel.product_materials)
        JobDetails:toggleProductMaterial(obj, sel.product_materials)
    elseif sel.reset_all_traits then
        --print('reset every trait')
        -- flags
        JobDetails:unsetFlags(obj)
        -- tool use
        JobDetails:toggleToolUse(obj, 'NONE')
        -- metal ore
        JobDetails:toggleMetalOre(obj, -1)
        -- reaction class
        JobDetails:toggleReactionClass(obj, '')
        -- producing
        JobDetails:toggleProductMaterial(obj, '')
    else
        print('unknown sel')
        printall(sel)
    end
end

function JobDetails:onChangeTrait()
    local idx, obj = self.subviews.list:getSelected()
    guimat.ItemTraitDialog{
        job_item = obj.iobj,
        prompt = 'Please select traits for input '..idx,
        none_caption = 'no traits',
        on_select = self:callback('setTrait', obj)
    }:show()
end

local scr = dfhack.gui.getCurViewscreen()
if not df.viewscreen_workquota_detailsst:is_instance(scr) then
    qerror("This script needs to be run from a work order details screen")
end

-- by opening the viewscreen_workquota_detailsst the
-- work order's .items array is initialized
JobDetails{ job = scr.order }:show()
