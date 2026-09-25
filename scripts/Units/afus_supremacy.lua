local base = piece("base")
local emit = piece("emit")

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
	return true
end

function script.Shot1()
	if GG and GG.KamikazeLauncherInterceptors then
		GG.KamikazeLauncherInterceptors.Consume(unitID)
	end
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
	return true
end

function script.Shot2()
	if GG and GG.KamikazeLauncherInterceptors then
		GG.KamikazeLauncherInterceptors.Consume(unitID)
	end
end
