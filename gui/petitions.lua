-- Show fort's petitions, pending and fulfilled.
--[====[

gui/petitions
=============
Show fort's petitions, pending and fulfilled.

For best experience add following to your ``dfhack*.init``::

    keybinding add Alt-P@dwarfmode/Default gui/petitions

]====]

local gui = require 'gui'
local utils = require 'utils'

-- local args = utils.invert({...})

--[[
[lua]# @ df.agreement_details_type
<type: agreement_details_type>
0                        = JoinParty
1                        = DemonicBinding
2                        = Residency
3                        = Citizenship
4                        = Parley
5                        = PositionCorruption
6                        = PlotStealArtifact
7                        = PromisePosition
8                        = PlotAssassination
9                        = PlotAbduct
10                       = PlotSabotage
11                       = PlotConviction
12                       = Location
13                       = PlotInfiltrationCoup
14                       = PlotFrameTreason
15                       = PlotInduceWar
]]

if not dfhack.world.isFortressMode() then return end

-- from gui/unit-info-viewer.lua
do -- for code folding
--------------------------------------------------
---------------------- Time ----------------------
--------------------------------------------------
local TU_PER_DAY = 1200
--[[
if advmode then TU_PER_DAY = 86400 ? or only for cur_year_tick?
advmod_TU / 72 = ticks
--]]
local TU_PER_MONTH = TU_PER_DAY * 28
local TU_PER_YEAR = TU_PER_MONTH * 12

local MONTHS = {
 'Granite',
 'Slate',
 'Felsite',
 'Hematite',
 'Malachite',
 'Galena',
 'Limestone',
 'Sandstone',
 'Timber',
 'Moonstone',
 'Opal',
 'Obsidian',
}
Time = defclass(Time)
function Time:init(args)
 self.year = args.year or 0
 self.ticks = args.ticks or 0
end
function Time:getDays() -- >>float<< Days as age (including years)
 return self.year * 336 + (self.ticks / TU_PER_DAY)
end
function Time:getDayInMonth()
 return math.floor ( (self.ticks % TU_PER_MONTH) / TU_PER_DAY ) + 1
end
function Time:getMonths() -- >>int<< Months as age (not including years)
 return math.floor (self.ticks / TU_PER_MONTH)
end
function Time:getMonthStr() -- Month as date
 return MONTHS[self:getMonths()+1] or 'error'
end
function Time:getDayStr() -- Day as date
 local d = math.floor ( (self.ticks % TU_PER_MONTH) / TU_PER_DAY ) + 1
 if d == 11 or d == 12 or d == 13 then
  d = tostring(d)..'th'
 elseif d % 10 == 1 then
  d = tostring(d)..'st'
 elseif d % 10 == 2 then
  d = tostring(d)..'nd'
 elseif d % 10 == 3 then
  d = tostring(d)..'rd'
 else
  d = tostring(d)..'th'
 end
 return d
end
--function Time:__add()
--end
function Time:__sub(other)
 if DEBUG then print(self.year,self.ticks) end
 if DEBUG then print(other.year,other.ticks) end
 if self.ticks < other.ticks then
  return Time{ year = (self.year - other.year - 1) , ticks = (TU_PER_YEAR + self.ticks - other.ticks) }
 else
  return Time{ year = (self.year - other.year) , ticks = (self.ticks - other.ticks) }
 end
end
--------------------------------------------------
--------------------------------------------------
end

local we = df.global.ui.group_id

local function getAgreementDetails(a)
    local sb = {} -- StringBuilder

    sb[#sb+1] = {{text = "Agreement #" ..a.id, pen = COLOR_RED}}
    sb[#sb+1] = NEWLINE

    local us = "Us"
    local them = "Them"
    for i, p in ipairs(a.parties) do
        local e_descr = {}
        local our = false
        for _, e_id in ipairs(p.entity_ids) do
            local e = df.global.world.entities.all[e_id]
            e_descr[#e_descr+1] = table.concat{"The ", df.historical_entity_type[e.type], " ", dfhack.TranslateName(e.name, true)}
            if we == e_id then our = true end
        end
        if our then
            us = table.concat(e_descr, ", ")
        else
            them = table.concat(e_descr, ", ")
        end
    end
    sb[#sb+1] = (them .. " petitioned " .. us)
    sb[#sb+1] = NEWLINE
    for _, d in ipairs (a.details) do
        local petition_date = Time{year = d.year, ticks = d.year_tick}
        local petition_date_str = petition_date:getDayStr()..' of '..petition_date:getMonthStr()..' in the year '..tostring(petition_date.year)
        local cur_date = Time{year = df.global.cur_year, ticks = df.global.cur_year_tick}
        sb[#sb+1] = ("On " .. petition_date_str)
        sb[#sb+1] = NEWLINE
        local diff = (cur_date - petition_date)
        if diff:getDays() < 1.0 then
            sb[#sb+1] = ("(this was today)")
        elseif diff:getMonths() == 0 then
            sb[#sb+1] = ("(this was " .. math.floor( diff:getDays() ) .. " days ago)" )
        else
            sb[#sb+1] = ("(this was " .. diff:getMonths() .. " months and " ..  diff:getDayInMonth() .. " days ago)" )
        end
        sb[#sb+1] = NEWLINE
        
        sb[#sb+1] = ("Petition type: " .. df.agreement_details_type[d.type])
        sb[#sb+1] = NEWLINE
        if d.type == df.agreement_details_type.Location then
            local details = d.data.Location
            local msg = {}
            msg[#msg+1] = "Provide a " .. df.abstract_building_type[details.type]
            msg[#msg+1] = " of tier " .. details.tier
            if details.deity_type ~= -1 then
                msg[#msg+1] = " of a " .. df.temple_deity_type[details.deity_type] -- None/Deity/Religion
            else
                msg[#msg+1] = " for " .. df.profession[details.profession]
            end
            sb[#sb+1] = (table.concat(msg))
            sb[#sb+1] = NEWLINE
        end
    end

    local petition = {}

    if a.flags.petition_not_accepted then
        sb[#sb+1] = {{text = "This petition wasn't accepted yet!", pen = COLOR_YELLOW}}
        petition.status = 'PENDING'
    elseif a.flags.convicted_accepted then
        sb[#sb+1] = {{text = "This petition was fulfilled!", pen = COLOR_GREEN}}
        petition.status = 'FULFILLED'
    else
        petition.status = 'ACCEPTED'
    end
    
    petition.text = sb
    
    return petition
end

local getAgreements = function()
    local list = {}

    local ags = df.global.world.agreements.all
    for i, a in ipairs(ags) do
        for _, p in ipairs(a.parties) do
            for _, e in ipairs(p.entity_ids) do
                if e == we then
                    list[#list+1] = getAgreementDetails(a)
                end
            end
        end
    end
    
    return list
end

local petitions = defclass(petitions, gui.FramedScreen)
petitions.ATTRS = {
    frame_style = gui.GREY_LINE_FRAME,
    frame_title = 'Petitions',
    frame_width = 20,
    frame_height = 18,
    frame_inset = 1,
    focus_path = 'petitions',
}

function petitions:init(args)
    self.start = 1
    self.list = args.list
    local lines = {}
    for _, p in ipairs(args.list) do
        local width = 0
        for _, t in ipairs(p.text) do
            if t == NEWLINE then
                self.frame_width = math.max(self.frame_width, width + 2)
                width = 0
            elseif type(t) == 'string' then
                width = width + #t + 1
            else
                for _, tok in ipairs(t) do
                    width = width + #tok.text + 1
                end
            end
        end
        self.frame_width = math.max(self.frame_width, width + 2)
    end
    self.frame_height = 18
    self.frame_width = math.min(df.global.gps.dimx - 2, self.frame_width)
end

function paint_token(p, t)
    if type(t) == 'table' then
        for _, tok in ipairs(t) do
            p:string(tok.text, tok.pen)
        end
    else
        p:string(t)
    end
end

function petitions:onRenderBody(painter)
    local n = 1
    local first = false
    for _, p in ipairs(self.list) do
        if p.status == 'FULFILLED' and not self.fulfilled then goto continue end
        for _, t in ipairs(p.text) do
            if self.start <= n and n <= self.start + self.frame_height then
                if first then
                    painter:newline()
                    n = n + 1
                    first = false
                end
                if t == NEWLINE then
                    painter:newline()
                else
                    paint_token(painter,t)
                    painter:string(' ')
                end
            end
            if t == NEWLINE then n = n + 1 end
        end
        first = true
    ::continue::
    end
    self.max_start = math.max(1, n - self.frame_height + 1)
    
    if n > self.frame_height then
        if self.start > 1 then
            painter:seek(self.frame_width - 1, 0):string(string.char(24), COLOR_LIGHTCYAN) -- up
        end
        if self.start < self.max_start then
            painter:seek(self.frame_width - 1, self.frame_height - 1):string(string.char(25), COLOR_LIGHTCYAN) -- down
        end
    end
end

function petitions:onRenderFrame(p, frame)
    petitions.super.onRenderFrame(self, p, frame)
    p:seek(frame.x1 + 2, frame.y1+frame.height-1):key_string('CUSTOM_F', "toggle fulfilled")
end

function petitions:onInput(keys)
    if keys.LEAVESCREEN or keys.SELECT then
        self:dismiss()
    elseif keys.CURSOR_UP or keys.STANDARDSCROLL_UP then
        self.start = math.max(1, self.start - 1)
    elseif keys.CURSOR_DOWN or keys.STANDARDSCROLL_DOWN then
        self.start = math.min(self.start + 1, self.max_start)
    elseif keys.CUSTOM_F then
        self.fulfilled = not self.fulfilled
    end
end

df.global.pause_state = true
petitions{list=getAgreements()}:show()
