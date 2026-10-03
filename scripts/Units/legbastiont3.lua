local base = piece("base")
local turret = piece("turret")
local aimingArm = piece("aiming_arm")
local aimSweet = piece("aimy")

local ringAnchor = piece("ringanchor")
local ring = piece("ring")
local ring2 = piece("ring2")
local ring3 = piece("ring3")
local ring4 = piece("ring4")
local beamPitch = piece("beam_pitch")
local beamMuzzle = piece("beam_muzzle")

local gaussLYaw = piece("gaussL_yaw")
local gaussLPitch = piece("gaussL_pitch")
local gaussLBarrel = piece("gaussL_barrel")
local gaussLMuzzle = piece("gaussL_muzzle")
local gaussRYaw = piece("gaussR_yaw")
local gaussRPitch = piece("gaussR_pitch")
local gaussRBarrel = piece("gaussR_barrel")
local gaussRMuzzle = piece("gaussR_muzzle")

local epicStrutL = piece("epic_strut_l")
local epicStrutR = piece("epic_strut_r")
local epicPodL = piece("epic_pod_l")
local epicPodR = piece("epic_pod_r")
local epicToroidL = piece("epic_toroid_l")
local epicToroidR = piece("epic_toroid_r")

local SIG_AIM_MAIN = 1
local SIG_RING = 2
local SIG_GAUSS_L = 4
local SIG_GAUSS_R = 8

local active = true
local alive = true
local deployed = false
local deploying = false
local firing = false
local fireSerial = 0

local RING_RISE = 38
local RING_RISE_SPEED = 22

local fireTimeFrames = 96
local fireWindowMs = 3200
local lastFiredFrame = -10000
local idleDockFrames = 120
local lastCombatFrame = 0

local oldHeading
local targetSwap = false

local rings = {
	{ piece = ring, axis = y_axis, idle = 120, firing = 180 },
	{ piece = ring2, axis = x_axis, idle = 90, firing = 120 },
	{ piece = ring3, axis = x_axis, idle = 60, firing = 90 },
	{ piece = ring4, axis = z_axis, idle = 30, firing = 60 },
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

local function SpinRings(firingMode, fraction)
	fraction = fraction or 1
	local accel = math.rad(200)
	for i = 1, #rings do
		local data = rings[i]
		local target = firingMode and data.firing or data.idle
		Spin(data.piece, data.axis, math.rad(target * fraction), accel)
	end
end

local function StopRings()
	for i = 1, #rings do
		local data = rings[i]
		StopSpin(data.piece, data.axis, math.rad(100))
		Turn(data.piece, data.axis, 0, math.rad(85))
	end
end

local function DockRings()
	Signal(SIG_RING)
	SetSignalMask(SIG_RING)

	deploying = false
	SetFiringState(false)
	StopRings()

	Move(ringAnchor, y_axis, 0, RING_RISE_SPEED)
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

	-- The model now gives every ring the same local origin under ringanchor.
	-- Move the anchor, never the individual rings: this guarantees one centre.
	Move(ringAnchor, y_axis, RING_RISE, RING_RISE_SPEED)

	-- Rotation starts immediately and ramps while the anchor rises.
	SpinRings(false, 0.14)
	Sleep(280)
	SpinRings(false, 0.30)
	Sleep(280)
	SpinRings(false, 0.47)
	Sleep(280)
	SpinRings(false, 0.64)
	Sleep(280)
	SpinRings(false, 0.82)

	WaitForMove(ringAnchor, y_axis)
	SpinRings(false, 1.0)

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
		Sleep(250)
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
		SpinRings(false, 1.0)
	end
end

local function SweepFireLoop()
	while alive do
		if firing and targetSwap then
			local frame = Spring.GetGameFrame()
			if frame < lastFiredFrame + fireTimeFrames then
				-- BAR Bastion sweepfire mechanism, now emitted from the
				-- exact centre of the raised ring assembly.
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

local function AimGauss(yawPiece, pitchPiece, signal, heading, pitch)
	-- 270 degree traverse: everything except a 90 degree rear blind wedge.
	if math.abs(heading) > GAUSS_HALF_ARC then
		return false
	end

	Signal(signal)
	SetSignalMask(signal)
	Turn(yawPiece, y_axis, heading, math.rad(70))
	Turn(pitchPiece, x_axis, -pitch, math.rad(48))
	WaitForTurn(yawPiece, y_axis)
	WaitForTurn(pitchPiece, x_axis)
	return alive and active
end

local function GaussRecoil(barrel, muzzle)
	EmitSfx(muzzle, 1024)
	Move(barrel, z_axis, -4.5, 85)
	Sleep(70)
	Move(barrel, z_axis, 0, 24)
end

function script.Create()
	Show(ring)
	Show(ring2)
	Show(ring3)
	Show(ring4)
	Show(epicStrutL)
	Show(epicStrutR)
	Show(epicPodL)
	Show(epicPodR)
	Show(epicToroidL)
	Show(epicToroidR)
	Show(gaussLYaw)
	Show(gaussRYaw)

	Move(ringAnchor, y_axis, 0)
	Turn(beamPitch, x_axis, 0)
	StopRings()

	SetHoverState(false)
	SetFiringState(false)
	lastCombatFrame = Spring.GetGameFrame()

	StartThread(SweepFireLoop)
	StartThread(CombatIdleLoop)
end

function script.Activate()
	active = true
	return 1
end

function script.Deactivate()
	active = false
	Signal(SIG_AIM_MAIN)
	Signal(SIG_GAUSS_L)
	Signal(SIG_GAUSS_R)
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

	Turn(turret, y_axis, heading, math.rad(25))
	Turn(beamPitch, x_axis, -pitch, math.rad(12))

	WaitForTurn(turret, y_axis)
	WaitForTurn(beamPitch, x_axis)

	while active and alive and not deployed do
		Sleep(30)
	end

	return active and alive
end

function script.FireWeapon1()
	MarkCombatActivity()
	lastFiredFrame = Spring.GetGameFrame()
	targetSwap = true

	fireSerial = fireSerial + 1
	SetFiringState(true)
	SpinRings(true, 1.0)
	StartThread(ClearFiring, fireSerial)
end

function script.SetSweepfireTimeWeapon1(fireTimeValue, reloadTimeValue)
	if fireTimeValue and fireTimeValue > 0 then
		fireTimeFrames = math.max(1, fireTimeValue)
		fireWindowMs = math.max(250, math.floor((fireTimeFrames / 30) * 1000 + 0.5))
	end
end

function script.AimFromWeapon2()
	return gaussLYaw
end

function script.QueryWeapon2()
	return gaussLMuzzle
end

function script.AimWeapon2(heading, pitch)
	return AimGauss(gaussLYaw, gaussLPitch, SIG_GAUSS_L, heading, pitch)
end

function script.FireWeapon2()
	StartThread(GaussRecoil, gaussLBarrel, gaussLMuzzle)
end

function script.AimFromWeapon3()
	return gaussRYaw
end

function script.QueryWeapon3()
	return gaussRMuzzle
end

function script.AimWeapon3(heading, pitch)
	return AimGauss(gaussRYaw, gaussRPitch, SIG_GAUSS_R, heading, pitch)
end

function script.FireWeapon3()
	StartThread(GaussRecoil, gaussRBarrel, gaussRMuzzle)
end

function script.SweetSpot()
	return aimSweet
end

function script.Killed(recentDamage, maxHealth)
	alive = false
	Signal(SIG_AIM_MAIN)
	Signal(SIG_RING)
	Signal(SIG_GAUSS_L)
	Signal(SIG_GAUSS_R)
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
	Explode(gaussLYaw, fx)
	Explode(gaussLBarrel, fx)
	Explode(gaussRYaw, fx)
	Explode(gaussRBarrel, fx)
	Explode(epicPodL, fx)
	Explode(epicPodR, fx)
	Explode(turret, fx)
	Explode(aimingArm, fx)

	if severity <= 0.5 then
		return 1
	end
	return 2
end
