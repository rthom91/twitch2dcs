### Purpose
For content creators of DCS World who fly in VR to interact with their audience without needing to take off the headset or use a TTS engine. VR is not required and will work on a standard monitor setup.

### Features
* Native DCS chat overlay
* Twitch IRCv3 support
* Read, write, and hide modes
* Raid, Sub, Bit/Cheer alerts
* Robust connection logic
* Lockable window position
* Color selection option
* Viewer count in title
* Adjustable font size
* Inactivity auto-hide
* Mode hotkey selection
* Basic emoji support
* Mouse wheel scrolling
* Clearable chat messages
* Separate Mod/Chat logging

### Limitations
* DCS World 2.9+ environment does not support HTTPS/TLS needed for Helix/EventSub API.
* Slash commands via IRC was deprecated by Twitch in 2023. Mod now ignores them.
* Clearing with /clear will not be received by Twitch. Use website or external app.
* Self messages lack a msgID and cannot be cleared if deleted from website chat.

### Install / Update
1. Go to C:/Users/ _username_ /Saved Games/DCS
2. Remove old Twitch2DCS files from inside "/Mods/Tech" and "/Scripts" folders if any exist. *Recommended* 
3. Extract downloaded release zip, copy then paste both "Mods" and "Scripts" folders inside Saved Games/DCS/
4. Launch DCS World, go to Options, Special, Twitch2DCS, follow step-up instructions.

### Commands
* Active moderators = /listmods
* Connection overrides = /connect or /reconnect or /disconnect
* Wipe entire chat history (locally) = /clear

### Links
* DCS Files - https://www.digitalcombatsimulator.com/en/files/3350538
* Support - https://forum.dcs.world/topic/389097-twitch2dcs-v2-rewrite-a-native-solution-for-twitch-chat-inside-dcs

### Credits
* Original mod concept by Jabbers
* Overhauled and modernized by Tailhook

### Donate
If you enjoy this free mod and want to support continued development.

https://streamelements.com/tailhook/tip