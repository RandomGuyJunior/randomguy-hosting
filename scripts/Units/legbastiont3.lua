local base = piece("base")
local piston1 = piece("piston1")
local piston2 = piece("piston2")
local turret = piece("turret")
local aimingArm = piece("aiming_arm")
local ring = piece("ring")
local ring2 = piece("ring2")
local ring3 = piece("ring3")
local ring4 = piece("ring4")
local aimFrom = piece("aimfromy")
local aimSweet = piece("aimy")
local flare = piece("flare")
local fireline = piece("fireline")
local lineflare = piece("lineflare")
local lightpoint = piece("lightpoint")
local ambienttop = piece("ambienttop")
local topArmsPivot = piece("topArmsPivot")
local leftAimingArm = piece("leftAimingArm")
local rightAimingArm = piece("rightAimingArm")
local bottomAimingArm = piece("bottomAimingArm")

local SIG_AIM = 1
local SIG_RING = 2

local active = true
local alive = true
local deployed = false
local deploying = false
local firing = false
local fireSerial = 0

local fireTimeFrames = 96 -- overwritten from sweepfire_firetime (3.2s * 30fps)
local fireWindowMs = 3200
local lastFiredFrame = -10000
local idleDockFrames = 120 -- ~4 seconds at 30 game frames/second
local lastCombatFrame = 0

local oldHeading
local targetSwap = false

local rings = {
	{ piece = ring,  axis = y_axis, idle = 120, firing = 180 },
	{ piece = ring2, axis = x_axis, idle = 90,  firing = 120 },
	{ piece = ring3, axis = x_axis, idle = 60,  firing = 90  },
	{ piece = ring4, axis = z_axis, idle = 30,  firing = 60  },
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

local function CenterRings(y, speed)
	for i = 1, #rings do
		local p = rings[i].piece
		Move(p, x_axis, 0, speed)
		Move(p, z_axis, 0, speed)
		Move(p, y_axis, y, speed)
	end
end

local function DockRings()
	Signal(SIG_RING)
	SetSignalMask(SIG_RING)

	deploying = false
	SetFiringState(false)

	if not deployed then
		StopRings()
		CenterRings(-10, 20)
		SetHoverState(false)
		return
	end

	StopRings()
	CenterRings(-10, 20)

	for i = 1, #rings do
		WaitForMove(rings[i].piece, y_axis)
	end

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

	-- All four rings share one geometric centre. They begin rotating
	-- immediately, then accelerate progressively while the assembly rises.
	CenterRings(24, 18)
	SpinRings(false, 0.16)
	Sleep(320)
	SpinRings(false, 0.34)
	Sleep(320)
	SpinRings(false, 0.52)
	Sleep(320)
	SpinRings(false, 0.70)
	Sleep(320)
	SpinRings(false, 0.86)

	for i = 1, #rings do
		WaitForMove(rings[i].piece, y_axis)
	end

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
			local gameFrame = Spring.GetGameFrame()

			if target ~= nil or firing then
				lastCombatFrame = gameFrame
			elseif deployed and gameFrame - lastCombatFrame >= idleDockFrames then
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
				-- Same mechanism used by BAR's stock Legion Bastion:
				-- FIRE_W1 forces additional beam segments during sweepfire.
				EmitSfx(fireline, 2048)
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

function script.Create()
	Show(ring)
	Show(ring2)
	Show(ring3)
	Show(ring4)

	Hide(flare)
	Hide(fireline)
	Hide(lineflare)
	Hide(lightpoint)
	Hide(ambienttop)

	Move(turret, y_axis, 6)
	Turn(leftAimingArm, z_axis, math.rad(45))
	Turn(rightAimingArm, z_axis, math.rad(-45))
	Turn(bottomAimingArm, x_axis, 0)

	-- Epic resting pose: the four gyroscopic rings remain concentric and
	-- lowered into the cradle rather than being pulled sideways from centre.
	CenterRings(-10, 0)
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
	Signal(SIG_AIM)
	StartThread(DockRings)
	return 0
end

function script.AimFromWeapon1()
	return aimFrom
end

function script.QueryWeapon1()
	return lineflare
end

function script.AimWeapon1(heading, pitch)
	if not active then
		return false
	end

	Signal(SIG_AIM)
	SetSignalMask(SIG_AIM)

	MarkCombatActivity()
	EnsureDeploying()

	-- Stock Bastion treats a meaningful heading change as sweepfire activity.
	if oldHeading == nil or HeadingDelta(oldHeading, heading) > math.rad(2.75) then
		targetSwap = true
	end
	oldHeading = heading

	Turn(turret, y_axis, heading, math.rad(25))
	Turn(aimingArm, x_axis, -pitch, math.rad(10))
	Turn(topArmsPivot, x_axis, -pitch, math.rad(10))

	WaitForTurn(turret, y_axis)
	WaitForTurn(aimingArm, x_axis)

	-- Do not release the weapon until all four rings have completed the lift.
	while active and alive and not deployed do
		Sleep(30)
	end

	return active and alive
end

function script.FireWeapon1()
	MarkCombatActivity()
	lastFiredFrame = Spring.GetGameFrame()
	targetSwap = true -- guarantee the full sustained sweep, including the first target

	fireSerial = fireSerial + 1
	SetFiringState(true)
	SpinRings(true, 1.0)
	StartThread(ClearFiring, fireSerial)
end

function script.SetSweepfireTimeWeapon1(fireTimeValue, reloadTimeValue)
	if fireTimeValue and fireTimeValue > 0 then
		-- LUS receives sweepfire custom time in game frames.
		fireTimeFrames = math.max(1, fireTimeValue)
		fireWindowMs = math.max(250, math.floor((fireTimeFrames / 30) * 1000 + 0.5))
	end
end

function script.SweetSpot()
	return aimSweet
end

function script.Killed(recentDamage, maxHealth)
	alive = false
	Signal(SIG_AIM)
	Signal(SIG_RING)
	SetHoverState(false)
	SetFiringState(false)

	local severity = recentDamage / maxHealth
	local fx = SFX.FALL + SFX.SMOKE + SFX.FIRE
	if severity > 0.5 then
		fx = fx + SFX.EXPLODE
	end

	Explode(ring, fx)
	Explode(ring2, fx)
	Explode(ring3, fx)
	Explode(ring4, fx)
	Explode(turret, fx)
	Explode(aimingArm, fx)
	Explode(leftAimingArm, fx)
	Explode(rightAimingArm, fx)
	Explode(bottomAimingArm, fx)

	if severity <= 0.5 then
		return 1
	end
	return 2
end
