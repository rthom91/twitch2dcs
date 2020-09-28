declare_plugin("Twitch2DCS",
{
	dirName = current_mod_path,
	developerName = _("Jabbers"),
	developerLink = _("https://github.com/jeffboulanger/twitch2dcs"),
	displayName = _("Twitch2DCS"),
	state = "installed",
	version = "1.1.3a",
	Options = {
		{
			name = _("Twitch2DCS"),
			nameId = "Twitch2DCS",
			dir = "Options",
			CLSID = "{Twitch2DCS options}",
			icon = current_mod_path.."/Options/icon.png",
			allow_in_simulation = true;
		},
	},
})

plugin_done()