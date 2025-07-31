-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local max = math.max
local min = math.min
local abs = math.abs
local floor = math.floor

local constants = {rpmToAV = 0.104719755, avToRPM = 9.549296596425384}

local motors = nil

local sharedFunctions = nil
local gearboxAvailableLogic = nil
local gearboxLogic = nil

M.gearboxHandling = nil
M.timer = nil
M.timerConstants = nil
M.inputValues = nil
M.shiftPreventionData = nil
M.shiftBehavior = nil
M.smoothedValues = nil

M.currentGearIndex = 0
M.maxGearIndex = 1
M.minGearIndex = -1
M.throttle = 0
M.brake = 0
M.regen = 0
M.clutchRatio = 1
M.shiftingAggression = 0
M.throttleInput = 0
M.isArcadeSwitched = false
M.isSportModeActive = false

M.smoothedAvgAVInput = 0
M.rpm = 0
M.idleRPM = 0
M.maxRPM = 0

M.engineThrottle = 0
M.engineLoad = 0
M.engineTorque = 0
M.flywheelTorque = 0
M.gearboxTorque = 0

M.ignition = true
M.isEngineRunning = 0

M.oilTemp = 0
M.waterTemp = 0
M.checkEngine = false

M.energyStorages = {}

local automaticHandling = {
  availableModes = {"P", "R", "N", "D"},
  hShifterModeLookup = {[-1] = "R", [0] = "N", "P", "D"},
  gearIndexLookup = {P = -2, R = -1, N = 0, D = 1},
  availableModeLookup = {},
  existingModeLookup = {},
  modeIndexLookup = {},
  modes = {},
  mode = nil,
  modeIndex = 0,
  maxAllowedGearIndex = 0,
  minAllowedGearIndex = 0
}

local generator = {
  flood = false,
  hydrolockThreshold = 0.005,
  device = {},
  active = false,
  battery = {}
}

local function getGearName()
  return automaticHandling.mode
end

local function getGearPosition()
  return (automaticHandling.modeIndex - 1) / (#automaticHandling.modes - 1), automaticHandling.modeIndex
end

local function gearboxBehaviorChanged(behavior)
  gearboxLogic = gearboxAvailableLogic[behavior]
  M.updateGearboxGFX = gearboxLogic.inGear
  M.shiftUp = gearboxLogic.shiftUp
  M.shiftDown = gearboxLogic.shiftDown
  M.shiftToGearIndex = gearboxLogic.shiftToGearIndex
end

local function applyGearboxMode()
  local autoIndex = automaticHandling.modeIndexLookup[automaticHandling.mode]
  if autoIndex then
    automaticHandling.modeIndex = min(max(autoIndex, 1), #automaticHandling.modes)
    automaticHandling.mode = automaticHandling.modes[automaticHandling.modeIndex]
  end

  local motorDirection = 1 --D
  if automaticHandling.mode == "P" then
    motorDirection = 0
  elseif automaticHandling.mode == "N" then
    motorDirection = 0
  elseif automaticHandling.mode == "R" then
    motorDirection = -1
  end

  for _, v in ipairs(motors) do
    v.motorDirection = motorDirection
  end

  M.isSportModeActive = automaticHandling.mode == "S"
end

local function shiftUp()
  if automaticHandling.mode == "N" then
    M.timer.gearChangeDelayTimer = M.timerConstants.gearChangeDelay
  end

  automaticHandling.modeIndex = min(automaticHandling.modeIndex + 1, #automaticHandling.modes)
  automaticHandling.mode = automaticHandling.modes[automaticHandling.modeIndex]

  applyGearboxMode()
end

local function shiftDown()
  if automaticHandling.mode == "N" then
    M.timer.gearChangeDelayTimer = M.timerConstants.gearChangeDelay
  end

  automaticHandling.modeIndex = max(automaticHandling.modeIndex - 1, 1)
  automaticHandling.mode = automaticHandling.modes[automaticHandling.modeIndex]

  applyGearboxMode()
end

local function shiftToGearIndex(index)
  local desiredMode = automaticHandling.hShifterModeLookup[index]
  if not desiredMode or not automaticHandling.existingModeLookup[desiredMode] then
    if desiredMode and not automaticHandling.existingModeLookup[desiredMode] then
      guihooks.message({txt = "vehicle.vehicleController.cannotShiftAuto", context = {mode = desiredMode}}, 2, "vehicle.shiftLogic.cannotShift")
    end
    desiredMode = "N"
  end
  automaticHandling.mode = desiredMode

  applyGearboxMode()
end

local function updateExposedData()
  local motorCount = 0
  M.rpm = 0
  local load = 0
  local motorTorque = 0
  for _, v in ipairs(motors) do
    M.rpm = max(M.rpm, abs(v.outputAV1) * constants.avToRPM)
    load = load + (v.engineLoad or 0)
    motorTorque = motorTorque + (v.outputTorque1 or 0)
    motorCount = motorCount + 1
  end
  load = load / motorCount

  M.smoothedAvgAVInput = sharedFunctions.updateAvgAVDeviceCategory("engine")
  M.waterTemp = 0
  M.oilTemp = 0
  M.checkEngine = 0
  M.ignition = electrics.values.ignitionLevel > 1
  M.engineThrottle = M.throttle
  M.engineLoad = load
  M.running = electrics.values.ignitionLevel > 1
  M.engineTorque = motorTorque
  M.flywheelTorque = motorTorque
  M.gearboxTorque = motorTorque
  M.isEngineRunning = 1
end

local function updateGen()
  if generator.device then
    if generator.device.isDisabled == false and generator.device.outputAV1 * constants.avToRPM >= 1000 and generator.flood == false then
      generator.device.friction = 170
      local generateAmount = generator.battery.remainingRatio + generator.device.lastOutputTorque * 0.0001
      generator.battery:setRemainingRatio(generateAmount)
    else
      generator.device.friction = 30
    end

    if generator.device.floodLevel > generator.hydrolockThreshold then
      generator.device.isDisabled = true
      generator.device.friction = 370
      generator.device.engineBrakeTorque = 360
      generator.flood = true
      electrics.values.checkengine = false
    end

    if electrics.values.forceUnlock == 1 then
      generator.device.isDisabled = false
      generator.device.friction = 30
      generator.device.engineBrakeTorque = 60
      generator.flood = false
      generator.device.floodLevel = 0
    end
  else
    generator.battery:setRemainingRatio(1)
  end
end

local function updateInGearArcade(dt)
  M.throttle = M.inputValues.throttle
  M.brake = M.inputValues.brake
  M.isArcadeSwitched = false
  M.clutchRatio = 1
  updateGen()

  local gearIndex = automaticHandling.gearIndexLookup[automaticHandling.mode]
  gearIndex = (automaticHandling.mode == "N" or automaticHandling.mode == "P") and 0 or gearIndex --adjust lookup so that P and N return 0, it's needed for following code
  -- driving backwards? - only with automatic shift - for obvious reasons ;)
  if (gearIndex < 0 and M.smoothedValues.avgAV <= 0.8) or (gearIndex <= 0 and M.smoothedValues.avgAV < -1) then
    M.throttle, M.brake = M.brake, M.throttle
    M.isArcadeSwitched = true
  end

  -- neutral gear handling
  if M.timer.neutralSelectionDelayTimer <= 0 then
    if automaticHandling.mode ~= "P" and abs(M.smoothedValues.avgAV) < M.gearboxHandling.arcadeAutoBrakeAVThreshold and M.throttle <= 0 then
      M.brake = max(M.brake, M.gearboxHandling.arcadeAutoBrakeAmount)
    end

    if automaticHandling.mode ~= "N" and abs(M.smoothedValues.avgAV) < M.gearboxHandling.arcadeAutoBrakeAVThreshold and M.smoothedValues.throttle <= 0 then
      gearIndex = 0
      automaticHandling.mode = "N"
      applyGearboxMode()
    else
      if M.smoothedValues.throttleInput > 0 and M.inputValues.throttle > 0 and M.smoothedValues.brakeInput <= 0 and M.smoothedValues.avgAV > -1 and gearIndex < 1 then
        gearIndex = 1
        M.timer.neutralSelectionDelayTimer = M.timerConstants.neutralSelectionDelay
        automaticHandling.mode = "D"
        applyGearboxMode()
      end

      if M.smoothedValues.brakeInput > 0.1 and M.inputValues.brake > 0 and M.smoothedValues.throttleInput <= 0 and M.smoothedValues.avgAV <= 0.5 and gearIndex > -1 then
        gearIndex = -1
        M.timer.neutralSelectionDelayTimer = M.timerConstants.neutralSelectionDelay
        automaticHandling.mode = "R"
        applyGearboxMode()
      end
    end

    if electrics.values.ignitionLevel <= 1 and automaticHandling.mode ~= "P" then
      gearIndex = 0
      M.timer.neutralSelectionDelayTimer = M.timerConstants.neutralSelectionDelay
      automaticHandling.mode = "P"
      applyGearboxMode()
    end
  end

  if automaticHandling.mode == "P" then
    M.brake = max(M.brake, M.gearboxHandling.arcadeAutoBrakeAmount)
  end

  M.currentGearIndex = (automaticHandling.mode == "N" or automaticHandling.mode == "P") and 0 or gearIndex
  updateExposedData()
end

local function updateInGear(dt)
  M.throttle = M.inputValues.throttle
  M.brake = M.inputValues.brake
  M.isArcadeSwitched = false
  M.clutchRatio = 1
  updateGen()

  if electrics.values.ignitionLevel <= 1 and automaticHandling.mode ~= "P" then
    M.timer.neutralSelectionDelayTimer = M.timerConstants.neutralSelectionDelay
    automaticHandling.mode = "P"
    applyGearboxMode()
  end
  local gearIndex = automaticHandling.gearIndexLookup[automaticHandling.mode]
  M.currentGearIndex = (automaticHandling.mode == "N" or automaticHandling.mode == "P") and 0 or gearIndex
  if automaticHandling.mode == "P" then
    M.brake = max(M.brake, M.gearboxHandling.arcadeAutoBrakeAmount)
  end
  updateExposedData()
end

local function sendTorqueData()
  for _, v in ipairs(motors) do
    v:sendTorqueData()
  end
end

local function setGenStarter(enabled)
  if generator.device.starterMaxAV then
    if enabled and (generator.device.outputAV1 < generator.device.starterMaxAV * 0.8) then
      generator.device:activateStarter()
    else
      generator.device:deactivateStarter()
    end
  end
end

local function setIgnition(enabled)
  for _, motor in ipairs(motors) do
    motor:setIgnition(enabled and 1 or 0)
  end

  if generator.active ~= enabled then
    generator.device:setIgnition(enabled and 1 or 0)
    setGenStarter(enabled)
  end
  generator.active = enabled
end

local function resetGen()
  if not generator.device then return end
  generator.device.isDisabled = false
  generator.device.friction = 30
  generator.device.engineBrakeTorque = 60
  generator.flood = false
end

local function init(jbeamData, sharedFunctionTable)
  sharedFunctions = sharedFunctionTable

  M.currentGearIndex = 0
  M.throttle = 0
  M.brake = 0
  M.regen = 0
  M.clutchRatio = 1

  gearboxAvailableLogic = {
    arcade = {
      inGear = updateInGearArcade,
      shiftUp = sharedFunctions.warnCannotShiftSequential,
      shiftDown = sharedFunctions.warnCannotShiftSequential,
      shiftToGearIndex = sharedFunctions.switchToRealisticBehavior
    },
    realistic = {
      inGear = updateInGear,
      shiftUp = shiftUp,
      shiftDown = shiftDown,
      shiftToGearIndex = shiftToGearIndex
    }
  }

  motors = {}
  generator.device = powertrain.getDevice(jbeamData.generatorName or "generator")
  generator.battery = energyStorage.getStorage(jbeamData.batteryName or "mainBattery")
  local motorNames = jbeamData.motorNames or {"mainMotor"}
  for _, v in ipairs(motorNames) do
    local motor = powertrain.getDevice(v)
    if motor then
      M.maxRPM = max(M.maxRPM, motor.maxAV * constants.avToRPM)
      table.insert(motors, motor)
    end
  end

  if #motors <= 0 then
    log("E", "shiftLogic-electricMotor", "No motors have been specified, functionality will be limited!")
  end

  -- determine maximum available friction brake torque
  local totalMaxBrakeTorque = 0
  for _, wd in pairs(wheels.wheels) do
    totalMaxBrakeTorque = totalMaxBrakeTorque + wd.brakeTorque * (wd.brakeInputSplit + (1 - wd.brakeInputSplit) * wd.brakeSplitCoef)
  end

  -- create two complimentary curves to map between a "brake input" coefficient and the resulting actual brake torque
  local tempFrictionCoefToTorqueMap = {}
  local tempFrictionTorqueToCoefMap = {}
  for i = 0, 100 do
    local brakeCoef = i / 100
    local totalBrakeTorque = 0
    for _, wd in pairs(wheels.wheels) do
      totalBrakeTorque = totalBrakeTorque + wd.brakeTorque * (min(brakeCoef, wd.brakeInputSplit) + max(brakeCoef - wd.brakeInputSplit, 0) * wd.brakeSplitCoef)
    end
    table.insert(tempFrictionCoefToTorqueMap, {i * 10, totalBrakeTorque})
    table.insert(tempFrictionTorqueToCoefMap, {totalBrakeTorque, brakeCoef})
  end

  -- create a curve to map between a desired regen torque and the necessary "regen throttle" (or "coefficient") to achieve that torque
  local tempRegenCoefToTorqueMap = {}
  local tempRegenTorqueToCoefMap = {}
  for i = 0, 100 do
    local regenCoef = i / 100
    local totalRegenTorque = 0
    for _, motor in pairs(motors) do
      totalRegenTorque = totalRegenTorque + regenCoef * motor.maxRegenTorque * motor.cumulativeGearRatio
    end
    table.insert(tempRegenCoefToTorqueMap, {i * 10, totalRegenTorque})
    table.insert(tempRegenTorqueToCoefMap, {totalRegenTorque, regenCoef})
  end

  automaticHandling.availableModeLookup = {}
  for _, v in pairs(automaticHandling.availableModes) do
    automaticHandling.availableModeLookup[v] = true
  end

  automaticHandling.modes = {}
  automaticHandling.modeIndexLookup = {}
  local modes = jbeamData.automaticModes or "PRND"
  local modeCount = #modes
  local modeOffset = 0
  for i = 1, modeCount do
    local mode = modes:sub(i, i)
    if automaticHandling.availableModeLookup[mode] then
      automaticHandling.modes[i + modeOffset] = mode
      automaticHandling.modeIndexLookup[mode] = i + modeOffset
      automaticHandling.existingModeLookup[mode] = true
    else
      print("unknown auto mode: " .. mode)
    end
  end

  local defaultMode = jbeamData.defaultAutomaticMode or "P"
  automaticHandling.modeIndex = string.find(modes, defaultMode)
  automaticHandling.mode = automaticHandling.modes[automaticHandling.modeIndex]
  automaticHandling.maxGearIndex = 1
  automaticHandling.minGearIndex = -1

  M.idleRPM = 0
  M.maxGearIndex = automaticHandling.maxGearIndex
  M.minGearIndex = abs(automaticHandling.minGearIndex)
  M.energyStorages = sharedFunctions.getEnergyStorages(motors)

  resetGen()
  applyGearboxMode()
end

local function onDeserialize(data)
end

local function onSerialize()
end

local function getState()
  local data = {grb_mde = automaticHandling.mode}

  return tableIsEmpty(data) and nil or data
end

local function setState(data)
  if data.grb_mde then
    automaticHandling.mode = data.grb_mde
    automaticHandling.modeIndex = automaticHandling.modeIndexLookup[automaticHandling.mode]
    applyGearboxMode()
  end
end

M.init = init
M.reset = resetGen

M.gearboxBehaviorChanged = gearboxBehaviorChanged
M.shiftUp = shiftUp
M.shiftDown = shiftDown
M.shiftToGearIndex = shiftToGearIndex
M.updateGearboxGFX = nop
M.getGearName = getGearName
M.getGearPosition = getGearPosition
M.sendTorqueData = sendTorqueData
M.setIgnition = setIgnition
M.onDeserialize = onDeserialize
M.onSerialize = onSerialize

M.getState = getState
M.setState = setState

return M
