-- test -dhack/scripts/devel/tests -tdialogs

config.mode = 'fortress'

local gui = require('gui')
local function send_keys(...)
    local keys = {...}
    for _,key in ipairs(keys) do
        gui.simulateInput(dfhack.gui.getCurViewscreen(true), key)
    end
end

local xtest = {} -- use to temporarily disable tests (change `function test.somename` to `function xtest.somename`)
local wait = function(n)
    --delay(n or 30) -- enable for debugging the tests
end

function test.changeOrderDetails()
    --[[ this is not needed because of how gui.simulateInput'D_JOBLIST' works
    -- verify expected starting state
    expect.eq(df.ui_sidebar_mode.Default, df.global.ui.main.mode)
    expect.true_(df.viewscreen_dwarfmodest:is_instance(scr))
    --]]

    -- get into the orders screen
    send_keys('D_JOBLIST', 'UNITJOB_MANAGER')
    expect.true_(df.viewscreen_jobmanagementst:is_instance(dfhack.gui.getCurViewscreen(true)), "We need to be in the jobmanagement/Main screen")
    
    --- create an order
    send_keys('MANAGER_NEW_ORDER')
    for i = 1, 5 do send_keys('STANDARDSCROLL_DOWN') end -- move cursor to CUT SLADE
    send_keys('SELECT') -- select it
    send_keys('SELECT') -- accept 0 quantity = perpetual order
    wait()
    send_keys('STANDARDSCROLL_UP') -- move cursor to newly created CUT SLADE
    wait()
    send_keys('MANAGER_DETAILS')
    expect.true_(df.viewscreen_workquota_detailsst:is_instance(dfhack.gui.getCurViewscreen(true)), "We need to be in the workquota_details screen")
    local job = dfhack.gui.getCurViewscreen(true).order
    local item = job.items[0]
    
    dfhack.run_command 'gui/workorder-finetune'
    --[[
    input item: boulder
    material:   slade
    traits:     none
    ]]
    expect.ne(-1, item.item_type, "Input should not be 'any item'")
    expect.ne(-1, item.mat_type, "Material should not be 'any material'")
    expect.false_(item.flags2.allow_artifact, "Trait allow_artifact should not be set")
    
    wait()
    send_keys('CUSTOM_I', 'SELECT') -- change input to 'any item'
    wait()
    send_keys('CUSTOM_M', 'SELECT') -- change material to 'any material'
    wait()
    send_keys('CUSTOM_T', 'STANDARDSCROLL_DOWN', 'STANDARDSCROLL_DOWN', 'SELECT', 'LEAVESCREEN') -- change traits to 'allow_artifact'
    --[[
    input item: any item
    material:   any material
    traits:     allow_artifact
    ]]
    expect.eq(-1, item.item_type, "Input item should change to 'any item'")
    expect.eq(-1, item.mat_type, "Material should change to 'any material'")
    expect.true_(item.flags2.allow_artifact, "Trait allow_artifact should change to set")
    
    -- cleanup
    wait()
    send_keys('LEAVESCREEN', 'LEAVESCREEN', 'MANAGER_REMOVE')
    -- go back to map screen
    wait()
    send_keys('LEAVESCREEN', 'LEAVESCREEN')
end
