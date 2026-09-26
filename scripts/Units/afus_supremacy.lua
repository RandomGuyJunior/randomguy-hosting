local base = piece("base")
local emit = piece("emit")

local function consumeAFUS()
	Sleep(1)
	if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
		Spring.DestroyUnit(unitID, false, true)
	end
end

function script.Create()
end

function script.Activate()
	return 1
end

function script.Deactivate()
	return 0
end

function script.AimFromWeapon1()
	return emit or base
end

function script.QueryWeapon1()
	return emit or base
end

function script.AimWeapon1(heading, pitch)
	return true
end

function script.FireWeapon1()
	StartThread(consumeAFUS)
end

function script.AimFromWeapon2()
	return emit or base
end

function script.QueryWeapon2()
	return emit or base
end

function script.AimWeapon2(heading, pitch)
	return true
end

function script.FireWeapon2()
	StartThread(consumeAFUS)
end
