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
local SIG_RESTORE = 2

local active = true
local deployed = false
local fireSerial = 0
local fireWindowMs = 3200

local function SetVisualParam(name, value)
	if Spring.SetUnitRulesParam then
		Spring.SetUnitRulesParam(unitID, name, value, { inlos = true })
	end
end

local function SetHoverState(value)
	SetVisualParam("epic_bastion_hover", value and 1 or 0)
end

local function SetFiringState(value)
	SetVisualParam("epic_bastion_firing", value and 1 or 0)
end

local function HoverSpin()
	Spin(ring, y_axis, math.rad(190), math.rad(320))
	Spin(ring2, x_axis, math.rad(-165), math.rad(320))
end

local function FiringSpin()
	Spin(ring, y_axis, math.rad(360), math.rad(520))
	Spin(ring2, x_axis, math.rad(-315), math.rad(520))
end

local function DockRings()
	if not deployed then
		SetHoverState(false)
		SetFiringState(false)
		return
	end

	SetFiringState(false)
	StopSpin(ring, y_axis, math.rad(360))
	StopSpin(ring2, x_axis, math.rad(360))

	Turn(ring, y_axis, 0, math.rad(160))
	Turn(ring2, x_axis, 0, math.rad(160))
	Turn(ring, x_axis, math.rad(78), math.rad(110))
	Turn(ring2, z_axis, math.rad(-78), math.rad(110))

	Move(ring, x_axis, -5, 20)
	Move(ring2, x_axis, 5, 20)
	Move(ring, y_axis, -9, 20)
	Move(ring2, y_axis, -12, 20)

	WaitForMove(ring, y_axis)
	WaitForMove(ring2, y_axis)
	deployed = false
	SetHoverState(false)
end

local function DeployRings()
	if deployed then
		return
	end

	Turn(ring, x_axis, 0, math.rad(135))
	Turn(ring2, z_axis, 0, math.rad(135))
	Move(ring, x_axis, -7, 16)
	Move(ring2, x_axis, 7, 16)
	Move(ring, y_axis, 20, 18)
	Move(ring2, y_axis, 28, 18)

	WaitForMove(ring, y_axis)
	WaitForMove(ring2, y_axis)
	WaitForTurn(ring, x_axis)
	WaitForTurn(ring2, z_axis)

	deployed = true
	SetHoverState(true)
	HoverSpin()
end

local function RestoreAfterDelay()
	Signal(SIG_RESTORE)
	SetSignalMask(SIG_RESTORE)
	Sleep(3800)
	if active then
		DockRings()
	end
end

local function ClearFiring(serial)
	Sleep(fireWindowMs)
	if serial ~= fireSerial then
		return
	end
	SetFiringState(false)
	if deployed then
		HoverSpin()
	end
end

function script.Create()
	Hide(ring3)
	Hide(ring4)
	Hide(flare)
	Hide(fireline)
	Hide(lineflare)
	Hide(lightpoint)
	Hide(ambienttop)

	Move(turret, y_axis, 6)
	Turn(leftAimingArm, z_axis, math.rad(45))
	Turn(rightAimingArm, z_axis, math.rad(-45))
	Turn(bottomAimingArm, x_axis, 0)

	-- Resting pose: two large donuts visibly lie in the cradle rather than being
	-- mechanically attached to one another.
	Move(ring, x_axis, -5)
	Move(ring2, x_axis, 5)
	Move(ring, y_axis, -9)
	Move(ring2, y_axis, -12)
	Turn(ring, x_axis, math.rad(78))
	Turn(ring2, z_axis, math.rad(-78))

	SetHoverState(false)
	SetFiringState(false)
end

function script.Activate()
	active = true
	return 1
end

function script.Deactivate()
	active = false
	Signal(SIG_AIM)
	Signal(SIG_RESTORE)
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

	DeployRings()

	Turn(turret, y_axis, heading, math.rad(24))
	Turn(aimingArm, x_axis, -pitch, math.rad(12))
	Turn(topArmsPivot, x_axis, -pitch, math.rad(12))

	WaitForTurn(turret, y_axis)
	WaitForTurn(aimingArm, x_axis)

	StartThread(RestoreAfterDelay)
	return true
end

function script.FireWeapon1()
	fireSerial = fireSerial + 1
	SetFiringState(true)
	FiringSpin()
	EmitSfx(lineflare, 1024)
	StartThread(ClearFiring, fireSerial)
	StartThread(RestoreAfterDelay)
end

function script.SetSweepfireTimeWeapon1(fireTimeValue, reloadTimeValue)
	if fireTimeValue and fireTimeValue > 0 then
		-- Sweepfire reports frames in the classic script interface.
		fireWindowMs = math.max(800, math.floor(fireTimeValue * 33.333))
	end
end

function script.SweetSpot()
	return aimSweet
end

function script.Killed(recentDamage, maxHealth)
	SetHoverState(false)
	SetFiringState(false)

	local severity = recentDamage / maxHealth
	local fx = SFX.FALL + SFX.SMOKE + SFX.FIRE
	if severity > 0.5 then
		fx = fx + SFX.EXPLODE
	end

	Explode(ring, fx)
	Explode(ring2, fx)
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
