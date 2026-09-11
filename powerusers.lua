local everything = {
	give = true,
	undo = true,
	cmd = true,
	devhelpers = true, -- catch-all for all dev helper commands
	-- granular devhelper sub-permissions (checked when devhelpers is false):
	-- devhelpers_units = true,	-- givecat, xpunits, destroyunits, removeunits, reclaimunits, transferunits, wreckunits, spawnceg, spawnunitexplosion, removeunitdef
	-- devhelpers_teams = true,	-- playertoteam, killteam
	-- devhelpers_terrain = true,	-- benchmark, globallos, clearwrecks, reducewrecks
	-- devhelpers_test = true,	-- desync
	playerdata = true,
	waterlevel = true,
	modmarker = true,
	sysinfo = true,
	volcano = true,
}
local moderator = {
	give = false,
	undo = true,
	cmd = false,
	devhelpers = false,
	playerdata = true,
	waterlevel = false,
	modmarker = true,
	sysinfo = true,
	volcano = true,
}
local eventmanager = {
	give = true,
	undo = true,
	cmd = false,
	devhelpers = false,
	devhelpers_units = true, -- givecat, xpunits, destroyunits, removeunits, reclaimunits, transferunits, wreckunits, spawnceg, spawnunitexplosion, removeunitdef
	devhelpers_teams = true, -- playertoteam, killteam
	playerdata = false,
	waterlevel = true,
	modmarker = true,
	sysinfo = false,
	volcano = true,
}
local singleplayer = { -- note: these permissions override others when singleplayer
	give = true,
	undo = true,
	cmd = true,
	devhelpers = true,
	waterlevel = true,
	modmarker = true,
	playerdata = true,
	sysinfo = false,
	volcano = true,
}

-- Trusted playernames as fallback when accountID is unavailable (-1) This occurs when joining an already running game.
-- Only applied when no accountID-based entry already exists for the player.
local trustedNames = {
	["[Cookie]RandomGuy"] = everything,
}

return {
	trustedNames = trustedNames,
	[-1] = singleplayer, -- SPECIAL NAME/ADDITION: dont change it

	-- admins
	[52] = everything, -- [Cookie]RandomGuy
}