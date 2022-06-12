-- adjust work orders' input item, material, traits
--[====[

gui/workorder-details
=====================
Adjust input items, material, or traits for work orders. Actual
jobs created for it will inherit the details.

This is the equivalent of `gui/workshop-job` for work orders,
with the additional possibility to set input items' traits.

It has to be run from a work order's detail screen
(:kbd:`j-m`, select work order, :kbd:`d`).

For best experience add the following to your ``dfhack*.init``::

    keybinding add D@workquota_details gui/workorder-details

]====]

--[[
Credit goes to the author of `gui/workshop-job`, it showed
me the way. Also, a huge chunk of code could be reused.
]]

local utils = require 'utils'
local gui = require 'gui'
local guimat = require 'gui.materials'
local widgets = require 'gui.widgets'
local dlg = require 'gui.dialogs'

local wsj = reqscript 'gui/workshop-job'

local JobDetails = defclass(JobDetails, gui.FramedScreen)

JobDetails.focus_path = 'workorder-details'

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
    guimat.ItemTraitsDialog{
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
