-- adjust work orders' input item, material, traits

--@ module = true

--[[
Credit goes to the author of `gui/workshop-job`, it showed
me the way. Also, a huge chunk of code could be reused.
]]

local overlay = require('plugins.overlay')

local utils = require 'utils'
local gui = require 'gui'
local guimat = require 'gui.materials'
local widgets = require 'gui.widgets'

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

function JobDetails:onChangeTrait()
    local idx, obj = self.subviews.list:getSelected()
    guimat.ItemTraitsDialog{
        job_item = obj.iobj,
        prompt = 'Please select traits for input '..idx,
        none_caption = 'no traits',
    }:show()
end

local function ScrJobDetails()
    return df.global.game.main_interface.job_details
end

local function show_job_details()
    local scr = ScrJobDetails()
    if not scr.open -- dfhack.gui.matchFocusString('dwarfmode/JobDetails')
        or scr.context ~= df.job_details_context_type.MANAGER_WORK_ORDER
    then
        qerror("This script needs to be run from a work order details screen")
    end

    -- by opening the viewscreen_workquota_detailsst the
    -- work order's .items array is initialized
    JobDetails{ job = scr.wq }:show()
end

-- -------------------
-- RecheckOverlay
--

local focusStrings = 'dwarfmode/JobDetails'

DetailsHotkeyOverlay = defclass(DetailsHotkeyOverlay, overlay.OverlayWidget)
DetailsHotkeyOverlay.ATTRS{
    default_pos={x=5,y=7},
    default_enabled=true,
    viewscreens=focusStrings,
    frame={w=1+6+2+(7)+1, h=3},
}

function DetailsHotkeyOverlay:init()
    self:addviews{
        widgets.TextButton{
            view_id = 'button',
            frame={t=0, l=0, r=0, h=1},
            label='details',
            key='CUSTOM_CTRL_D',
            on_activate=show_job_details,
        },
    }
end

function DetailsHotkeyOverlay:onRenderBody(dc)
    local scr = ScrJobDetails()

    if (scr.context ~= df.job_details_context_type.MANAGER_WORK_ORDER) then
        self.subviews.button.visible = false
        return
    else
        self.subviews.button.visible = true
    end

    DetailsHotkeyOverlay.super.onRenderBody(self, dc)
end

-- -------------------

OVERLAY_WIDGETS = {
    details=DetailsHotkeyOverlay,
}

if dfhack_flags.module then
    return
end

show_job_details()
