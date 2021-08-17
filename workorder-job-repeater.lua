-- simulates workshop's "repeat" for infinite work orders

local function print_help()
    print[====[

workorder-job-repeater
======================
This script recreates workshop jobs upon completion in case
they come from a work order with amount set to infinite. Usually
a job for an infinite work order is only created once a day,
resulting in dwarfs lazying around (this doesn't apply to non-infinite
work orders). This script makes the dwarfes work harder.

For best experience add following to your ``onMapLoad*.init``::

    workorder-job-repeater start

Optional second parameter lets you control how frequent the check
is made, in game ticks. Default is 10.
    
    workorder-job-repeater start 10
]====]
end

local utils = require 'utils'
local eventful = require 'plugins.eventful'

local DEBUG = 1
local INFO = 2
local WARN = 3
local ERROR = 4
local OFF = 6

local verbosity = INFO

local function log(level, ...)
    if level < verbosity then return end
    print (...)
end

local findManagerOrderById = function (id)
    for _, o in ipairs(df.global.world.manager_orders) do
        if o.id == id then
            return o
        end
    end
    return nil
end

local findBuildingById = function (id)
    return df.building.find(id)
end

local findJobById = function (id)
    for _link, j in utils.listpairs(df.global.world.jobs.list) do
        if j.id == id then
            return j
        end
    end
    return nil
end

local only_infty = true -- we will only repeat jobs which work order's amount is set to infinity. Or not.

-- from http://www.bay12forums.com/smf/index.php?topic=164123.msg8300009#msg8300009
--[[ "I don't fully understand how this works, so this might be horribly wrong
      The DF job assigner needs a job to be in postings for it to automatically be assigned to a unit."(c)
--]]
function addJobToPostings(job)
    local addedIndex = false
    -- Find the first free empty postings to add a job to
    for index, posting in ipairs(df.global.world.jobs.postings) do
        if posting.job == nil then
            -- It's free real estate!
            posting.job = job
            posting.anon_1 = 0
            posting.flags.dead = false
            
            job.posting_index = posting.idx
            addedIndex = posting.idx
            break
        end
    end
    if addedIndex then
        log(DEBUG, "Added job " .. job.id .. " to postings as index " .. addedIndex)
    else
        log(DEBUG, "Couldn't find posting slot to add in job " .. job.id)
    end
    
    return addedIndex
end

local function repeatJob(order, job)
    if not (job and order) then
        -- should never ever happen #hope
        qerror("both job and order are nil")
        return
    end
    
    if only_infty and 0 ~= order.amount_total then
        log(DEBUG, "skipping job " .. dfhack.job.getName(job) .. " (id " .. job.id .. "): order.amount_total > 0")
        return
    end
    
    if not (order.status.validated and order.status.active) then
        log(DEBUG, "skipping job " .. dfhack.job.getName(job) .. " (id " .. job.id .. ") from order " .. order.id .. " because of order.status")
        return
    end
    
    -- for debug purposes: pause the game
    --df.global.pause_state = true

    log(DEBUG, "Repeat job " .. dfhack.job.getName(job) .. " (id " .. job.id .. ") from order " .. order.id)
    
    -- we need a clone because original(which itself is a copy) is destroyed or something.
    -- cloneJobStruct doesn't copy flags over.
    local by_manager = job.flags.by_manager
    local do_now = job.flags.do_now
    job = dfhack.job.cloneJobStruct(job)
    job.flags.by_manager = by_manager
    job.flags.do_now = do_now
    
    -- step 0: adjust what we can right now
    job.flags.working = false
    job.completion_timer = -1
    job.items:resize(0) -- remove old items we worked upon
    
    local workshop = nil
    local ixs = {}
    for ix, gref in ipairs(job.general_refs) do
        if gref:getType() == df.general_ref_type.BUILDING_HOLDER then
            local building = gref:getBuilding()
            if building then
                log(DEBUG, "Building from gref: " .. building.id)
                workshop = building
            else
                -- should never ever happen, I think
                log(WARN, "Building from gref not found: ", gref.building_id)
            end
        else
            ixs[ix] = true
        end
    end
    for ix in pairs(ixs) do
        log(DEBUG, "Removing from gref: ", job.general_refs[ix])
        job.general_refs:erase(ix)
    end
    log(DEBUG, "#gref: " .. #job.general_refs .. " (should be 1)")
    
    -- step 1: associate a posting with it
    local ok = addJobToPostings(job)
    if not ok then
        log(ERROR, "Couldn't add job of order.id " .. order.id .. " to a posting")
        return
    end
    
    -- step 2: add the job to the job list
    local ok = dfhack.job.linkIntoWorld(job, false) -- we don't need a new id, I think?
    if not ok then -- fallback just in case
        log(DEBUG, "Couldn't add the job using job.id " .. job.id .. ". Requesting new id.")
        dfhack.job.linkIntoWorld(job, true)
    end
    log(DEBUG, "Job " .. job.id .. " is linked.")

    -- step 3: if a building is associated with the work order, find it
    if order.workshop_id < 0 then
        log(DEBUG, "Ignore work orders not associated with workshops")
        return
    end
    
    if not workshop then
        log(WARN, "No workshop despite order.workshop_id " .. order.workshop_id .. " -- restoring")
        workshop = findBuildingById(order.workshop_id)
    end
    log(DEBUG, "Associated workshop: " .. workshop.id)
    
    -- step 4: add this job to the workshop's job list.
    workshop.jobs:insert('#', job)
    log(DEBUG, "Added job " .. job.id .. " to workshop.jobs")
end

local function start(N)
    N = tonumber(N) or 10
    eventful.onJobCompleted.workorder_repeat_job_immediately = function(job)
        local order_id = job.order_id
        local order = order_id > 0 and findManagerOrderById(order_id)
        if order then
            -- log(DEBUG, "work order", order_id, order)
            repeatJob(order, job)
        end
    end
    eventful.enableEvent(eventful.eventType.JOB_COMPLETED, N) -- check every N ticks

    log(INFO, "job repeater started")
end

local function stop()
    eventful.onJobCompleted.workorder_repeat_job_immediately = nil
    
    log(INFO, "job repeater stopped")
end

local default_action = print_help
local actions = {
    -- help
    ["-?"] = print_help,
    ["?"] = print_help,
    ["--help"] = print_help,
    ["help"] = print_help,
    --
    ["default"] = print_help,
    --
    ["enable"] = start,
    ["start"] = start,
    ["disable"] = stop,
    ["stop"] = stop,
}

-- Lua is beautiful.
(actions[ (...) or "default" ] or default_action)(select(2,...))
