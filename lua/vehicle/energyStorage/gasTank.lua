-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
-- by Zeit

local M = {}

local max = math.max
local min = math.min

local function updateGFX(storage, dt)
  storage.remainingVolume = storage.initialStoredEnergy > 0 and storage.storedEnergy / (storage.fuelLiquidDensity * storage.energyDensity) or 0
  storage.remainingRatio = storage.initialStoredEnergy > 0 and storage.storedEnergy / storage.initialStoredEnergy or 0

  for k, v in pairs(storage.fuelNodes) do
    obj:setNodeMass(k, v + storage.storedEnergy * storage.fuelNodeMassCoef)
  end

  if storage.currentLeakRate > 0 then
    storage:setRemainingVolume(storage.remainingVolume - storage.currentLeakRate * dt)
  end
end

local function setRemainingVolume(storage, volume)
  storage.storedEnergy = min(max(volume, 0), storage.capacity) * storage.fuelLiquidDensity * storage.energyDensity
end

local function setRemainingRatio(storage, ratio)
  storage.storedEnergy = storage.initialStoredEnergy * min(max(ratio, 0), 1)
end

local function onBreak(storage)
  storage.currentLeakRate = storage.brokenLeakRate
end

local function registerDevice(storage, device)
  storage.assignedDevices[device.name] = device
end

local function setPartCondition(storage, odometer, integrity, visual)
  local integrityState = integrity
  if type(integrity) == "number" then
    local integrityValue = integrity
    integrityState = {
      remainingVolume = storage.capacity * integrityValue,
      currentLeakRate = integrityValue == 0 and storage.brokenLeakRate or 0
    }
  end

  storage:setRemainingVolume(integrityState.remainingVolume or storage.capacity)
  storage.currentLeakRate = integrityState.currentLeakRate or 0
end

local function getPartCondition(storage)
  local integrityState = {
    remainingVolume = storage.remainingVolume,
    currentLeakRate = storage.currentLeakRate
  }
  local integrityValue = storage.currentLeakRate > 0 and 0 or 1

  return integrityValue, integrityState
end

local function reset(storage)
  storage.currentLeakRate = 0
  storage.storedEnergy = storage.startingCapacity * storage.fuelLiquidDensity * storage.energyDensity

  --apply final weight as soon as possible
  for k, v in pairs(storage.fuelNodes) do
    obj:setNodeMass(k, v + storage.storedEnergy * storage.fuelNodeMassCoef)
  end

  storage.remainingRatio = storage.initialStoredEnergy > 0 and storage.storedEnergy / storage.initialStoredEnergy or 0
end

local function deserialize(storage, data)
  if data.remainingVolume then
    storage:setRemainingVolume(data.remainingVolume)
  end
end

local function serialize(storage)
  return {remainingVolume = storage.remainingVolume}
end

local function new(jbeamData)
  local storage = {
    name = jbeamData.name,
    type = jbeamData.type,
    energyType = jbeamData.energyType or "cng",
    assignedDevices = {},
    remainingRatio = 1,
    remainingVolume = 1,
    currentLeakRate = 0,
    breakTriggerBeam = jbeamData.breakTriggerBeam,
    jbeamData = jbeamData,
    updateGFX = updateGFX,
    setRemainingVolume = setRemainingVolume,
    setRemainingRatio = setRemainingRatio,
    deserialize = deserialize,
    serialize = serialize,
    registerDevice = registerDevice,
    onBreak = onBreak,
    reset = reset,
    setPartCondition = setPartCondition,
    getPartCondition = getPartCondition
  }

  if storage.energyType == "cng" then
    storage.energyDensity = 41 * 1000000 --MJ/kg
    storage.fuelLiquidDensity = 0.13
  elseif storage.energyType == "lpg" then

    storage.energyDensity = 46 * 1000000 --MJ/kg

    storage.fuelLiquidDensity = 0.49
  end
  storage.energyDensity = jbeamData.energyDensity or storage.energyDensity or 0 --MJ/kg
  storage.fuelLiquidDensity = jbeamData.fuelLiquidDensity or storage.fuelLiquidDensity or 0 --kg/L, TODO: take tEnv into account

  storage.capacity = jbeamData.fuelCapacity or 0
  storage.startingCapacity = min(jbeamData.startingFuelCapacity or storage.capacity, storage.capacity)
  storage.storedEnergy = storage.startingCapacity * storage.fuelLiquidDensity * storage.energyDensity

  storage.brokenLeakRate = storage.capacity / 60 --drain tank in 60 seconds, no matter how much fuel is in there

  storage.fuelNodeMassCoef = 0
  storage.fuelNodes = {}
  local fuelNodeCount = 0
  if jbeamData.fuel and jbeamData.fuel._engineGroup_nodes then
    for _, n in pairs(jbeamData.fuel._engineGroup_nodes) do
      storage.fuelNodes[n] = v.data.nodes[n].nodeWeight --save initial mass as the offset for the fuel node weights
      fuelNodeCount = fuelNodeCount + 1
    end
    if fuelNodeCount > 0 and storage.energyDensity > 0 then
      storage.fuelNodeMassCoef = 1 / (storage.energyDensity * fuelNodeCount) --calculate weight per energy left
    end
  end

  --apply final weight as soon as possible
  for k, v in pairs(storage.fuelNodes) do
    obj:setNodeMass(k, v + storage.storedEnergy * storage.fuelNodeMassCoef)
  end

  storage.initialStoredEnergy = storage.capacity * storage.fuelLiquidDensity * storage.energyDensity
  storage.remainingRatio = storage.initialStoredEnergy > 0 and storage.storedEnergy / storage.initialStoredEnergy or 0

  storage.jbeamData = jbeamData

  return storage
end

M.new = new

return M
