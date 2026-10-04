local base = piece("base")
local turret = piece("turret")
local aimSweet = piece("aimy")

local armPivot2 = piece("armPivot2")
local armPivot3 = piece("armPivot3")
local coreGlowLow = piece("coreglow_low")
local coreGlowMid = piece("coreglow_mid")
local coreGlowHigh = piece("coreglow_high")

local beamYaw = piece("beam_yaw")
local ringAnchor = piece("ringanchor")
local ring = piece("ring")
local ring2 = piece("ring2")
local ring3 = piece("ring3")
local ring4 = piece("ring4")
local beamPitch = piece("beam_pitch")
local beamMuzzle = piece("beam_muzzle")

local extension1 = piece("extension_root_1")
local extension2 = piece("extension_root_2")
local extension3 = piece("extension_root_3")

local gauss1Yaw = piece("gauss1_yaw")
local gauss1Pitch = piece("gauss1_pitch")
local gauss1Barrel = piece("gauss1_barrel")
local gauss1Muzzle = piece("gauss1_muzzle")

local gauss2Yaw = piece("gauss2_yaw")
local gauss2Pitch = piece("gauss2_pitch")
local gauss2Barrel = piece("gauss2_barrel")
local gauss2Muzzle = piece("gauss2_muzzle")

local gauss3Yaw = piece("gauss3_yaw")
local gauss3Pitch = piece("gauss3_pitch")
local gauss3Barrel = piece("gauss3_barrel")
local gauss3Muzzle = piece("gauss3_muzzle")

local SIG_AIM_MAIN = 1
local SIG_RING = 2
local SIG_GAUSS_1 = 4
local SIG_GAUSS_2 = 8
local SIG_GAUSS_3 = 16

local active = true
local alive = true
local deployed = false
local deploying = false
local firing = false
local fireSerial = 0

local RING_REST = -10
local RING_RISE = 38
local RING_RISE_SPEED = 44 -- twice the previous deployment speed

local fireTimeFrames = 96
local fireWindowMs = 3200
local lastFiredFrame = -10000
local idleDockFrames = 90 -- 3 seconds at 30 game frames/second
local lastCombatFrame = 0

local oldHeading
local targetSwap = false

local rings = {
	{ piece = ring, axis = y_axis, idle = 660, firing = 1040 },
	{ piece = ring2, axis = x_axis, idle = 500, firing = 780 },
	{ piece = ring3, axis = x_axis, idle = 380, firing = 600 },
	{ piece = ring4, axis = z_axis, idle = 220, firing = 380 },
}

local function SetVisualParam(name, value)
	if Spring.SetUnitRulesParam then
		Spring.SetUnitRulesParam(unitID, name, value, { inlos = true })
	end
end

local function SetHoverState(value)
	SetVisualParam("epic_bastion_hover", value and 1 or 0)
end

local function SetFiringState(value)
	firing = value
	SetVisualParam("epic_bastion_firing", value and 1 or 0)
end

local function SpinRings(firingMode)
	local accel = math.rad(600)
	for i = 1, #rings do
		local data = rings[i]
		local target = firingMode and data.firing or data.idle
		Spin(data.piece, data.axis, math.rad(target), accel)
	end
end

local function StopRings()
	for i = 1, #rings do
		local data = rings[i]
		StopSpin(data.piece, data.axis, math.rad(180))
		Turn(data.piece, data.axis, 0, math.rad(120))
	end
end

local function DockRings()
	Signal(SIG_RING)
	SetSignalMask(SIG_RING)

	deploying = false
	SetFiringState(false)
	StopRings()

	Move(ringAnchor, y_axis, RING_REST, RING_RISE_SPEED)
	WaitForMove(ringAnchor, y_axis)

	deployed = false
	SetHoverState(false)
end

local function DeployRings()
	if deployed or deploying then
		return
	end

	Signal(SIG_RING)
	SetSignalMask(SIG_RING)
	deploying = true

	-- Full idle rotation begins immediately; no staged acceleration.
	SpinRings(false)
	Move(ringAnchor, y_axis, RING_RISE, RING_RISE_SPEED)
	WaitForMove(ringAnchor, y_axis)

	deploying = false
	deployed = true
	SetHoverState(true)
end

local function EnsureDeploying()
	if not deployed and not deploying then
		StartThread(DeployRings)
	end
end

local function MarkCombatActivity()
	lastCombatFrame = Spring.GetGameFrame()
end

local function CombatIdleLoop()
	while alive do
		if (deployed or deploying) and active then
			local _, _, target = Spring.GetUnitWeaponTarget(unitID, 1)
			local frame = Spring.GetGameFrame()
			if target ~= nil or firing then
				lastCombatFrame = frame
			elseif deployed and frame - lastCombatFrame >= idleDockFrames then
				StartThread(DockRings)
			end
		end
		Sleep(200)
	end
end

local function ClearFiring(serial)
	Sleep(fireWindowMs)
	if serial ~= fireSerial then
		return
	end
	SetFiringState(false)
	targetSwap = false
	if deployed then
		SpinRings(false)
	end
end

local function SweepFireLoop()
	while alive do
		if firing and targetSwap then
			local frame = Spring.GetGameFrame()
			if frame < lastFiredFrame + fireTimeFrames then
				EmitSfx(beamMuzzle, 2048)
			end
		end
		Sleep(20)
	end
end

local function HeadingDelta(a, b)
	if not a or not b then
		return math.huge
	end
	local twoPi = math.pi * 2
	local d = math.abs(a - b) % twoPi
	if d > math.pi then
		d = twoPi - d
	end
	return d
end

local GAUSS_HALF_ARC = math.rad(135)

local function NormalizeAngle(angle)
	local twoPi = math.pi * 2
	while angle > math.pi do angle = angle - twoPi end
	while angle < -math.pi do angle = angle + twoPi end
	return angle
end

local function AimGauss(yawPiece, pitchPiece, signal, parentHeading, heading, pitch)
	local localHeading = NormalizeAngle(heading - parentHeading)

	-- Exactly 270 degrees of traverse: 90 degree blind wedge directly behind
	-- each radial turret extension.
	if math.abs(localHeading) > GAUSS_HALF_ARC then
		return false
	end

	Signal(signal)
	SetSignalMask(signal)
	Turn(yawPiece, y_axis, localHeading, math.rad(75))
	Turn(pitchPiece, x_axis, -pitch, math.rad(52))
	WaitForTurn(yawPiece, y_axis)
	WaitForTurn(pitchPiece, x_axis)
	return alive and active
end

local function GaussRecoil(barrel, muzzle)
	EmitSfx(muzzle, 1024)
	Move(barrel, z_axis, -4.5, 90)
	Sleep(70)
	Move(barrel, z_axis, 0, 26)
end

local function CorePulseLoop()
	while alive do
		EmitSfx(coreGlowLow, 1025)
		Sleep(170)
		EmitSfx(coreGlowMid, 1025)
		Sleep(170)
		EmitSfx(coreGlowHigh, 1025)
		Sleep(900)
	end
end

function script.Create()
	Show(ring)
	Show(ring2)
	Show(ring3)
	Show(ring4)
	Show(gauss1Yaw)
	Show(gauss2Yaw)
	Show(gauss3Yaw)

	-- Existing lower Bastion frame keeps its three-way stance.
	Turn(armPivot2, y_axis, math.rad(120))
	Turn(armPivot3, y_axis, math.rad(-120))

	-- New turret extensions are three identical radial assemblies.
	Turn(extension1, y_axis, 0)
	Turn(extension2, y_axis, math.rad(120))
	Turn(extension3, y_axis, math.rad(-120))

	-- The visible head stays fixed. Only these invisible beam pivots aim.
	Turn(beamYaw, y_axis, 0)
	Turn(beamPitch, x_axis, 0)
	Move(ringAnchor, y_axis, RING_REST)
	StopRings()

	SetHoverState(false)
	SetFiringState(false)
	lastCombatFrame = Spring.GetGameFrame()

	StartThread(SweepFireLoop)
	StartThread(CombatIdleLoop)
	StartThread(CorePulseLoop)
end

function script.Activate()
	active = true
	return 1
end

function script.Deactivate()
	active = false
	Signal(SIG_AIM_MAIN)
	Signal(SIG_GAUSS_1)
	Signal(SIG_GAUSS_2)
	Signal(SIG_GAUSS_3)
	StartThread(DockRings)
	return 0
end

function script.AimFromWeapon1()
	return ringAnchor
end

function script.QueryWeapon1()
	return beamMuzzle
end

function script.AimWeapon1(heading, pitch)
	if not active then
		return false
	end

	Signal(SIG_AIM_MAIN)
	SetSignalMask(SIG_AIM_MAIN)

	MarkCombatActivity()
	EnsureDeploying()

	if oldHeading == nil or HeadingDelta(oldHeading, heading) > math.rad(2.75) then
		targetSwap = true
	end
	oldHeading = heading

	-- Invisible internal aiming only. 'turret' is intentionally never turned.
	Turn(beamYaw, y_axis, heading, math.rad(30))
	Turn(beamPitch, x_axis, -pitch, math.rad(15))

	WaitForTurn(beamYaw, y_axis)
	WaitForTurn(beamPitch, x_axis)

	while active and alive and not deployed do
		Sleep(20)
	end

	return active and alive
end

function script.FireWeapon1()
	MarkCombatActivity()
	lastFiredFrame = Spring.GetGameFrame()
	targetSwap = true

	fireSerial = fireSerial + 1
	SetFiringState(true)
	SpinRings(true)
	StartThread(ClearFiring, fireSerial)
end

function script.SetSweepfireTimeWeapon1(fireTimeValue, reloadTimeValue)
	if fireTimeValue and fireTimeValue > 0 then
		fireTimeFrames = math.max(1, fireTimeValue)
		fireWindowMs = math.max(250, math.floor((fireTimeFrames / 30) * 1000 + 0.5))
	end
end

function script.AimFromWeapon2() return gauss1Yaw end
function script.QueryWeapon2() return gauss1Muzzle end
function script.AimWeapon2(heading, pitch)
	return AimGauss(gauss1Yaw, gauss1Pitch, SIG_GAUSS_1, 0, heading, pitch)
end
function script.FireWeapon2()
	StartThread(GaussRecoil, gauss1Barrel, gauss1Muzzle)
end

function script.AimFromWeapon3() return gauss2Yaw end
function script.QueryWeapon3() return gauss2Muzzle end
function script.AimWeapon3(heading, pitch)
	return AimGauss(gauss2Yaw, gauss2Pitch, SIG_GAUSS_2, math.rad(120), heading, pitch)
end
function script.FireWeapon3()
	StartThread(GaussRecoil, gauss2Barrel, gauss2Muzzle)
end

function script.AimFromWeapon4() return gauss3Yaw end
function script.QueryWeapon4() return gauss3Muzzle end
function script.AimWeapon4(heading, pitch)
	return AimGauss(gauss3Yaw, gauss3Pitch, SIG_GAUSS_3, math.rad(-120), heading, pitch)
end
function script.FireWeapon4()
	StartThread(GaussRecoil, gauss3Barrel, gauss3Muzzle)
end

function script.SweetSpot()
	return aimSweet
end

function script.Killed(recentDamage, maxHealth)
	alive = false
	Signal(SIG_AIM_MAIN)
	Signal(SIG_RING)
	Signal(SIG_GAUSS_1)
	Signal(SIG_GAUSS_2)
	Signal(SIG_GAUSS_3)
	SetHoverState(false)
	SetFiringState(false)

	local severity = recentDamage / maxHealth
	local fx = SFX.FALL + SFX.SMOKE + SFX.FIRE
	if severity > 0.5 then
		fx = fx + SFX.EXPLODE
	end

	for i = 1, #rings do
		Explode(rings[i].piece, fx)
	end
	Explode(gauss1Yaw, fx)
	Explode(gauss1Barrel, fx)
	Explode(gauss2Yaw, fx)
	Explode(gauss2Barrel, fx)
	Explode(gauss3Yaw, fx)
	Explode(gauss3Barrel, fx)
	Explode(turret, fx)

	if severity <= 0.5 then
		return 1
	end
	return 2
end
