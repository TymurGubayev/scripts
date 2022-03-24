-- gives dwarves unique nicknames
--[====[

autonick
========
Gives dwarves unique nicknames chosen randomly from ``dfhack-config/autonick.txt``.

One nickname per line.
Empty lines, lines beginning with ``#`` and repeat entries are discarded.

Dwarves with manually set nicknames are ignored.

If there are fewer available nicknames than dwarves, the remaining
dwarves will go un-nicknamed.

You may wish to use this script with the "repeat" command, e.g:
``repeat -name autonick -time 3 -timeUnits months -command [ autonick ]``

]====]

local seen = {}
--check current nicknames
for _,unit in ipairs(df.global.world.units.active) do
    if dfhack.units.isCitizen(unit) and
    unit.name.nickname ~= "" then
        seen[unit.name.nickname] = true
    end
end

local names = {}
-- grab list, put in array
local path = dfhack.getDFPath () .. "/dfhack-config/autonick.txt";
for line in io.lines(path) do
    line = line:trim()
    if (line ~= "")
    and (not line:startswith('#'))
    and (not seen[line]) then
        table.insert(names, line)
        seen[line] = true
    end
end

--assign names
for _,unit in ipairs(df.global.world.units.active) do
    if (#names == 0) then break end
    --if there are any names left
    if dfhack.units.isCitizen(unit) and
    unit.name.nickname == "" then
        newnameIndex = math.random (#names)
        dfhack.units.setNickname(unit, names[newnameIndex])
        table.remove(names, newnameIndex)
    end
end

