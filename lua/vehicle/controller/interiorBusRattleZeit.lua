-- basically all code is taken from "vehicle/sounds.lua"
-- usually I'd put the "DO NOT USE WITHOUT PERMISSION"
-- stuff here but most is not mine lol

local M = {}

local rattleSoundTimer = 0
local beamSounds = {}
local node1 = 0
local node2 = 0

local function updateGFX(dt)
    for bi, snd in ipairs(beamSounds) do
        local beamVel = math.min(1, math.abs(obj:getBeamVelocity(snd.beam)))
        local currentStress = clamp(obj:getBeamStress(snd.beam) / snd.maxStress, -1, 1) * beamVel * beamVel -- find the stress on the current sound beam (unsmoothed)
        local smoothStress = snd.smoothing:get(currentStress, dt)
        local impulse = math.min(math.abs(smoothStress - currentStress), math.abs(smoothStress)) -- beam stress difference between instananeous stress and smooth stress
        local volume = snd.volumeFactor * impulse -- normalize volume (cancel out maxStress factor)

        -- one shot cabin rattles
        -- Teri - things required please - the event needs to be set per vehicle, potentially in x_interior.jbeam - also, should the emitters be on different nodes (they are currently set as suspension.
        rattleSoundTimer = rattleSoundTimer + dt
        if rattleSoundTimer > 0.08 then
            rattleSoundTimer = 0
            if volume > 0.25 then
                volume = linearScale(volume,0.25,0.95,0,1)

                if node1 ~= 0 then
                    sounds.playSoundOnceAtNode("event:>Vehicle>Interior>Rattles>car>multi_test", node1, volume * 10)
                end
                if node2 ~= 0 then
                    sounds.playSoundOnceAtNode("event:>Vehicle>Interior>Rattles>car>multi_test", node2, volume * 10)
                end

                -- sounds.playSoundOnceAtNode("event:>Vehicle>Interior>Rattles>car>cabrat_race", 0, volume)
                -- sounds.playSoundOnceAtNode("event:>Vehicle>Interior>Rattles>car>cabrat_small", 0, volume)
                -- sounds.playSoundOnceAtNode("event:>Vehicle>Interior>Rattles>car>cabrat_vintage", 0, volume)
                -- sounds.playSoundOnceAtNode("event:>Vehicle>Interior>Rattles>car>seb_test", 0, volume)
            end
        end
    end
end

local function init(jbeamData)
    rattleSoundTimer = 0
    beamSounds = sounds.getBeamSounds()

    node1 = jbeamData.nodeID1 or 0
    node2 = jbeamData.nodeID2 or 0
end

-- public interface
M.updateGFX = updateGFX
M.init = init

return M