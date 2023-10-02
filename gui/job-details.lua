-- Show and modify properties of jobs in a workshop or of manager orders.

--[[
    Credit goes to the author of `gui/workshop-job`.
    This is the gui/workshop-job.lua with gui/workorder-details.lua added on top
    and updated to the DF50.
]]

--@ module = true

local overlay = require('plugins.overlay')

local utils = require 'utils'
local gui = require 'gui'
local guimat = require 'gui.materials'
local widgets = require 'gui.widgets'
local dlg = require 'gui.dialogs'

JobDetails = defclass(JobDetails, gui.ZScreenModal)

JobDetails.focus_path = 'job-details'

JobDetails.ATTRS {
    job = DEFAULT_NIL,
    context = DEFAULT_NIL,
    frame_inset = 1,
    frame_background = COLOR_BLACK,
}

function JobDetails:isManagerOrder()
    return self.context == df.job_details_context_type.MANAGER_WORK_ORDER
end

function JobDetails:init(args)
    local status
    if not self:isManagerOrder() then
        status = { text = 'No worker', pen = COLOR_DARKGREY }
        local worker = dfhack.job.getWorker(self.job)
        if self.job.flags.suspend then
            status = { text = 'Suspended', pen = COLOR_RED }
        elseif worker then
            status = { text = dfhack.TranslateName(dfhack.units.getVisibleName(worker)), pen = COLOR_GREEN }
        end
    end

    local window = widgets.Window{
        frame_title='Details',
        resizable = true,
        resize_min={w=50, h=20},
        frame = { l = 10, w = 50 },
    }
    window:addviews{
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
            scroll_keys = widgets.SECONDSCROLL,
        },
        widgets.Label{
            frame = { l = 0, b = 0 },
            text = {
                { key = 'LEAVESCREEN', text = ': Back',
                  on_activate = self:callback('dismiss')
                }
            }
        },
    }

    self:addviews{window}
    self.list = window.subviews.list

    self:initListChoices()

    local h = 2 -- window border
        + self.list.frame.t -- everything above the list
        + 4 * #self.list.choices -- list body
        + 2 -- LEAVESCREEN
        + 2 -- window border
    window.frame.h = h
end

local function describe_item_type(iobj)
    local itemline = 'any item'
    if iobj.item_type >= 0 then
        itemline = df.item_type.attrs[iobj.item_type].caption or iobj.item_type
        local def = dfhack.items.getSubtypeDef(iobj.item_type, iobj.item_subtype)
        local count = dfhack.items.getSubtypeCount(iobj.item_type, iobj.item_subtype)
        if def then
            itemline = def.name
        elseif count >= 0 then
            itemline = 'any '..itemline
        end
    end
    return itemline
end

local function is_caste_mat(iobj)
    return dfhack.items.isCasteMaterial(iobj.item_type)
end

local function describe_material(iobj)
    local matline = 'any material'
    if is_caste_mat(iobj) then
        matline = 'material not applicable'
    elseif iobj.mat_type >= 0 then
        local info = dfhack.matinfo.decode(iobj.mat_type, iobj.mat_index)
        if info then
            matline = info:toString()
        else
            matline = iobj.mat_type..':'..iobj.mat_index
        end
    end
    return matline
end

local function list_flags(list, bitfield)
    for name,val in pairs(bitfield) do
        if val then
            table.insert(list, name)
        end
    end
end

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
    local headers = {}
    local job_items
    if self:isManagerOrder() then
        if not self.job.items then
            self.list:setChoices({})
            return
        end

        job_items = self.job.items
        for i,iobj in ipairs(job_items) do
            local head = 'Item '..(i+1)..' x'..iobj.quantity
            if iobj.min_dimension > 0 then
                head = head .. ' (size '..iobj.min_dimension..')'
            end

            headers[i] = head
        end
    else
        local items = {}
        for i,ref in ipairs(self.job.items) do
            local idx = ref.job_item_idx
            if idx >= 0 then
                items[idx] = (items[idx] or 0) + 1
            end
        end

        job_items = self.job.job_items
        for i,iobj in ipairs(job_items) do
            local head = 'Item '..(i+1)..': '..(items[i] or 0)..' of '..iobj.quantity
            if iobj.min_dimension > 0 then
                head = head .. ' (size '..iobj.min_dimension..')'
            end

            headers[i] = head
        end
    end

    local choices = {}
    for i,iobj in ipairs(job_items) do
        local head = headers[i]

        table.insert(choices, {
            index = i,
            iobj = iobj,
            text = {
                head, NEWLINE,
                '  ', { text = curry(describe_item_type, iobj) }, NEWLINE,
                '  ', { text = curry(describe_material, iobj) }, NEWLINE,
                '  ', { text = curry(describe_item_traits, iobj) }, NEWLINE,
            }
        })
    end

    self.list:setChoices(choices)
end

function JobDetails:canChangeIType()
    local idx, obj = self.list:getSelected()
    return obj ~= nil
end

function JobDetails:setItemType(obj, item_type, item_subtype)
    obj.iobj.item_type = item_type
    obj.iobj.item_subtype = item_subtype

    if is_caste_mat(obj.iobj) then
        self:setMaterial(obj, -1, -1)
    end
end

function JobDetails:onChangeIType()
    local idx, obj = self.list:getSelected()
    guimat.ItemTypeDialog{
        prompt = 'Please select a new item type for input '..idx,
        none_caption = 'any item',
        item_filter = curry(dfhack.job.isSuitableItem, obj.iobj),
        on_select = self:callback('setItemType', obj)
    }:show()
end

function JobDetails:canChangeMat()
    local idx, obj = self.list:getSelected()
    return obj ~= nil and not is_caste_mat(obj.iobj)
end

function JobDetails:setMaterial(obj, mat_type, mat_index)
    if  obj.index == 0
    and self.job.mat_type == obj.iobj.mat_type
    and self.job.mat_index == obj.iobj.mat_index
    and self.job.job_type ~= df.job_type.PrepareMeal
    then
        self.job.mat_type = mat_type
        self.job.mat_index = mat_index
    end

    obj.iobj.mat_type = mat_type
    obj.iobj.mat_index = mat_index
end

function JobDetails:findUnambiguousItem(iobj)
    local count = 0
    local itype

    for i = 0,df.item_type._last_item do
        if dfhack.job.isSuitableItem(iobj, i, -1) then
            count = count + 1
            if count > 1 then return nil end
            itype = i
        end
    end

    return itype
end

function JobDetails:onChangeMat()
    local idx, obj = self.list:getSelected()

    if obj.iobj.item_type == -1 and obj.iobj.mat_type == -1 then
        -- If the job allows only one specific item type, use it
        local vitype = self:findUnambiguousItem(obj.iobj)

        if vitype then
            obj.iobj.item_type = vitype
        else
            dlg.showMessage(
                'Bug Alert',
                { 'Please set a specific item type first.\n\n',
                  'Otherwise the material will be matched\n',
                  'incorrectly due to a limitation in DF code.' },
                COLOR_YELLOW
            )
            return
        end
    end

    guimat.MaterialDialog{
        prompt = 'Please select a new material for input '..idx,
        none_caption = 'any material',
        mat_filter = function(mat,parent,mat_type,mat_index)
            return dfhack.job.isSuitableMaterial(obj.iobj, mat_type, mat_index, obj.iobj.item_type)
        end,
        on_select = self:callback('setMaterial', obj)
    }:show()
end

function JobDetails:canChangeTrait()
    local idx, obj = self.list:getSelected()
    return obj ~= nil and not is_caste_mat(obj.iobj)
end

function JobDetails:onChangeTrait()
    local idx, obj = self.list:getSelected()
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
    then
        qerror("This script needs to be run from a job details screen")
    end

    local job
    if scr.context == df.job_details_context_type.BUILDING_TASK_LIST then
        job = scr.jb
    elseif scr.context == df.job_details_context_type.MANAGER_WORK_ORDER then
        job = scr.wq
    end
    if job == nil then
        qerror("Unhandled screen context: ".. df.job_details_context_type[scr.context])
    end

    JobDetails{ job = job, context = scr.context }:show()
end

-- --------------------
-- DetailsHotkeyOverlay
--

local focusStrings = 'dwarfmode/JobDetails'

DetailsHotkeyOverlay = defclass(DetailsHotkeyOverlay, overlay.OverlayWidget)
DetailsHotkeyOverlay.ATTRS{
    default_pos={x=0,y=0},
    default_enabled=true,
    viewscreens=focusStrings,
    frame={w= 1   -- [
            + 6   -- Ctrl+d
            + 2   -- :_
            + (7) -- details
            + 1   -- ]
         , h= 1
        },
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

DetailsHotkeyOverlay_ManagerWorkOrder = defclass(DetailsHotkeyOverlay_ManagerWorkOrder, DetailsHotkeyOverlay)
DetailsHotkeyOverlay_ManagerWorkOrder.ATTRS{
    default_pos={x=5, y=5}, -- {x=5, y=5} is right above the job title
    viewscreens='dwarfmode/JobDetails/MANAGER_WORK_ORDER',
}

DetailsHotkeyOverlay_BuildingTask = defclass(DetailsHotkeyOverlay_BuildingTask, DetailsHotkeyOverlay)
DetailsHotkeyOverlay_BuildingTask.ATTRS{
    default_pos={x=-120, y=6}, -- {x=-120, y=6} is right above the job title on all but smallest widths
    viewscreens='dwarfmode/JobDetails/BUILDING_TASK_LIST',
}

-- -------------------

OVERLAY_WIDGETS = {
    job_details=DetailsHotkeyOverlay_BuildingTask,
    workorder_details=DetailsHotkeyOverlay_ManagerWorkOrder,
}

if dfhack_flags.module then
    return
end

show_job_details()
