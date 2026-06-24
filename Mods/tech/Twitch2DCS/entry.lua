declare_plugin("Twitch2DCS",
{
	dirName = current_mod_path,
	developerName = _("Tailhook / Jabbers"),
	developerLink = _("https://github.com/rthom91/twitch2dcs"),
	displayName = _("Twitch2DCS"),
	state = "installed",
	version = "2.1.0",
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