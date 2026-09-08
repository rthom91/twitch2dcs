local base = _G

module("twitch.ui")

local require = base.require
local string = base.string
local tostring = base.tostring
local math = base.math
local table = base.table
local pairs = base.pairs
local ipairs = base.ipairs

local os = require("os")
local lfs = require("lfs")
local DCS = require("DCS")
local Skin = require("Skin")
local Gui = require("dxgui")
local DialogLoader = require("DialogLoader")
local EditBox = require("EditBox")
local Input = require("Input")

local Config = require("twitch.config")
local tracer = require("twitch.tracer")
local Sanitizer = require("twitch.sanitizer")

local MAX_DISPLAYED_MESSAGES = 150
local MAX_MESSAGE_LENGTH = 500	-- Enforced by Twitch
local DEFAULT_WINDOW_WIDTH = 360
local DEFAULT_WINDOW_HEIGHT = 455
local MINI_WINDOW_WIDTH = 36
local MINI_WINDOW_HEIGHT = 85

local modes = {
	hidden = "hidden",
	read = "read",
	write = "write",
}

local keyboardLocked = false

local UI = {
	_isWindowCreated = false,
	_currentWheelValue = 0,
	_listStatics = {},
	_listMessages = {},
	_currentMode = modes.read,

	_x = 0,
	_y = 0,
	widthChat = 0,
	heightChat = 0,

	viewerCount = 0,
	fontSize = 14,
	noReadMsg = 0,
	lockUIPosition = false,
	inactiveMinutes = 0,

	lastActivityTime = 0,
	lastHideTimer = 0,
	lastHotkey = nil,
	lastLockPosition = false,
	lastShowViewerCount = nil,
	lastColorMode = nil,
	pendingScrollToBottom = false,
	_forceBottomScroll = false,

	_lastStartMsg = 0,
	_lastTotal = 0,
	_lastWidgetCount = 0,

	window = nil,
	box = nil,
	btnMail = nil,
	pNoVisible = nil,
	pMsg = nil,
	vsScroll = nil,
	pDown = nil,
	eMessage = nil,
	pBtn = nil,
	tbAll = nil,
	sAll = nil,
	sAllies = nil,

	testStatic = nil,
	testE = nil,
	eMx = 0, eMy = 0, eMw = 0,

	messageSkin = nil,
	skinFactory = nil,
	skinModeWrite = nil,
	skinModeRead = nil,
	skinMail = nil,

	config = nil,
	callbacks = nil,
	hotkeyCallback = nil,
}

local UI_mt = { __index = UI }

local function unlockKeyboardInput(releaseKeyboardKeys)
	if keyboardLocked then
		DCS.unlockKeyboardInput(releaseKeyboardKeys)
		keyboardLocked = false
	end
end

local function lockKeyboardInput()
	if keyboardLocked then return end

	local keyboardEvents = Input.getDeviceKeys(Input.getKeyboardDeviceName())
	local inputActions = Input.getEnvTable().Actions

	local function removeCommandEvents(commandEvents)
		if not commandEvents then return end
		for _, cmd in ipairs(commandEvents) do
			for j = #keyboardEvents, 1, -1 do
				if keyboardEvents[j] == cmd then
					table.remove(keyboardEvents, j)
					break
				end
			end
		end
	end

	removeCommandEvents(Input.getUiLayerCommandKeyboardKeys(inputActions.iCommandChat))
	removeCommandEvents(Input.getUiLayerCommandKeyboardKeys(inputActions.iCommandAllChat))
	removeCommandEvents(Input.getUiLayerCommandKeyboardKeys(inputActions.iCommandFriendlyChat))
	removeCommandEvents(Input.getUiLayerCommandKeyboardKeys(inputActions.iCommandChatShowHide))

	DCS.lockKeyboardInput(keyboardEvents)
	keyboardLocked = true
end

function UI:_applyTransparentSkin()
	local skin = Skin.windowSkinTransparent()
	local header = skin.skinData.skins.header.skinData.states

	header.disabled[1].bkg.center_center = 0x00000000
	header.released[1].bkg.center_center = 0x00000000
	header.released[2].bkg.center_center = 0x00000000

	return skin
end

function UI:new()
	local ui = base.setmetatable({}, UI_mt)
	ui.config = Config:new()

	local position = ui.config:getPosition()
	ui._x = position.x or 0
	ui._y = position.y or 0

	local cdata = cdata or {}

	ui.window = DialogLoader.spawnDialogFromFile(lfs.writedir() .. "Scripts\\dialogs\\TwitchChat.dlg", cdata)
	ui.box = ui.window.Box
	ui.btnMail = ui.window.btnMail
	ui.pNoVisible = ui.window.pNoVisible
	ui.pMsg = ui.box.pMsg
	ui.vsScroll = ui.box.vsScroll
	ui.pDown = ui.box.pDown
	ui.eMessage = ui.pDown.eMessage
	ui.pBtn = ui.pDown.pBtn
	ui.tbAll = ui.pBtn.tbAll
	ui.sAll = ui.pBtn.sAll
	ui.sAllies = ui.pBtn.sAllies

	ui.btnMail.onChange = function()
		if ui._currentMode == modes.hidden then
			ui:readMode()
		else
			ui:hideMode()
		end
	end

	ui.vsScroll.onChange = function() ui:onChange_vsScroll() end

	ui.pMsg:addMouseWheelCallback(function(self, x, y, clicks)
		ui:onMouseWheel(clicks)
	end)

	ui.hotkeyCallback = function()
		ui:nextMode()
	end

	local hideShowHotkey = ui.config:getHideShowHotkey()
	if hideShowHotkey and hideShowHotkey ~= "" and hideShowHotkey ~= "NONE" then
		ui.window:addHotKeyCallback(hideShowHotkey, ui.hotkeyCallback)
	end

	ui.eMessage.onKeyDown = function(_, key)
		if key == "return" or key == "enter" then
			ui:sendMessage()
			return true
		end
	end

	ui.eMessage.onChange = function()
		local text = ui.eMessage:getText() or ""
		text = string.gsub(text, "[\r\n]+", " ")

		if #text > MAX_MESSAGE_LENGTH then
			text = string.sub(text, 1, MAX_MESSAGE_LENGTH)
		end

		if text ~= ui.eMessage:getText() then
			ui.eMessage:setText(text)

			local lastLine = ui.eMessage:getLineCount() - 1
			if lastLine >= 0 then
				local lineLen = ui.eMessage:getLineTextLength(lastLine)
				ui.eMessage:setSelectionNew(lastLine, lineLen, lastLine, lineLen)
			end
		end

		ui:resizeEditMessage()
	end

	ui.tbAll.onChange = function() ui:onChange_tbAll() end

	ui.vsScroll:setRange(1, 1)
	ui.vsScroll:setValue(1)
	ui.vsScroll:setThumbValue(1)
	ui._currentWheelValue = 1

	ui.widthChat, ui.heightChat = ui.pMsg:getSize()

	ui:_setupSkins()
	ui:_createMessageWidgets()

	ui:setFontSize(ui.config:getFontSize())

	ui.w, ui.h = Gui.GetWindowSize()

	ui.window:setBounds(ui._x, ui._y, DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT)
	ui.box:setBounds(0, 0, DEFAULT_WINDOW_WIDTH, 400)
	if ui.btnMail then
		ui.btnMail:setBounds(12, 0, 24, 55)
	end

	local x, y, w, _ = ui.eMessage:getBounds()
	ui.eMx, ui.eMy, ui.eMw = x, y, w

	ui.lockUIPosition = ui.config:getLockUIPosition()
	ui.inactiveMinutes = ui.config:getHideInactiveTimer() or 0
	ui.lastHideTimer = ui.inactiveMinutes
	ui.lastHotkey = ui.config:getHideShowHotkey()
	ui.lastLockPosition = ui.lockUIPosition
	ui.lastActivityTime = os.time()
	ui.lastColorMode = ui.config:getColorMode()

	ui.lockKeyboardInput = lockKeyboardInput
	ui.unlockKeyboardInput = unlockKeyboardInput

	ui:writeMode()
	ui:readMode()

	ui.window:addPositionCallback(function() ui:positionCallback() end)

	ui._isWindowCreated = true
	tracer:info("UI initialized.")
	ui:setVisible(true)

	return ui
end

function UI:_setupSkins()
	self.skinFactory = self.window.pNoVisible.eWhiteText
	self.skinModeWrite = self.pNoVisible.pModeWrite:getSkin()
	self.skinModeRead = self.pNoVisible.pModeRead:getSkin()
	self.skinMail = self.btnMail:getSkin()

	local msgSkin = self.skinFactory:getSkin()
	msgSkin.skinData.states.released[2].text.color = "0xddddddff"
	self.messageSkin = msgSkin
end

function UI:_createMessageWidgets()
	self.testStatic = EditBox.new()
	self.testStatic:setReadOnly(true)
	self.testStatic:setTextWrapping(true)
	self.testStatic:setMultiline(true)
	self.testStatic:setBounds(0, 0, self.widthChat, 20)

	self.testE = EditBox.new()
	self.testE:setTextWrapping(true)
	self.testE:setMultiline(true)
	self.testE:setBounds(0, 0, 281, 20)

	if self.eMessage then
		self.testE:setSkin(self.eMessage:getSkin())
	end

	for i = 1, 60 do
		local staticNew = EditBox.new()
		table.insert(self._listStatics, staticNew)
		staticNew:setReadOnly(true)
		staticNew:setTextWrapping(true)
		staticNew:setMultiline(true)
		self.pMsg:insertWidget(staticNew)
	end
end

function UI:resetInactivityTimer()
	self.lastActivityTime = os.time()
end

function UI:checkInactivity()
	if self.inactiveMinutes <= 0 or self._currentMode ~= modes.read then
		return
	end

	local now = os.time()
	local inactiveSeconds = now - self.lastActivityTime
	local timeoutSeconds = self.inactiveMinutes * 60

	if inactiveSeconds > timeoutSeconds then
		self:hideMode()
		tracer:info("Overlay hidden due to inactivity.")
	end
end

function UI:clearChat()
	self._listMessages = {}
	self._currentWheelValue = 0
	self.noReadMsg = 0
	self.vsScroll:setRange(1, 1)
	self.vsScroll:setValue(1)
	self.vsScroll:setThumbValue(1)

	self._lastStartMsg = 0
	self._lastTotal = 0
	self._lastWidgetCount = 0

	self:updateListM(true)
	self:updateNoReadMsg()
end

function UI:removeMessage(msgId)
	if not msgId then return end
	for i = #self._listMessages, 1, -1 do
		if self._listMessages[i].msgId == msgId then
			table.remove(self._listMessages, i)
			break
		end
	end
	self.vsScroll:setRange(1, math.max(#self._listMessages, 1))
	self:updateListM(true)
end

function UI:removeMessagesByUser(login)
	login = (login or ""):lower()
	if login == "" then return end

	local i = 1
	while i <= #self._listMessages do
		if self._listMessages[i].login == login then
			table.remove(self._listMessages, i)
		else
			i = i + 1
		end
	end

	local total = #self._listMessages
	self.vsScroll:setRange(1, math.max(total, 1))
	if self.vsScroll:getValue() > total then
		self.vsScroll:setValue(total)
	end
	self:updateListM(true)
end

function UI:isScrolledToBottom()
	local total = #self._listMessages
	if total == 0 then return true end
	local current = self.vsScroll:getValue() + (self.vsScroll:getThumbValue() or 1)
	return current >= total - 1
end

function UI:scrollToBottom()
	local total = #self._listMessages
	self.vsScroll:setValue(total)
	self._currentWheelValue = total
end

function UI:shouldUpdateVisibleList()
	local total = #self._listMessages
	if total == 0 then return false end
	local currentTop = self.vsScroll:getValue()
	return currentTop + 5 >= total
end

function UI:addMessage(userPrefix, fullMessage, userSkin, msgId, login)
	self:resetInactivityTimer()

	local displayUser = Sanitizer.sanitizeMessage(userPrefix)
	local displayText = Sanitizer.sanitizeMessage(fullMessage)

	self.testStatic:setText(displayText)
	local _, newH = self.testStatic:calcSize()

	local msg = {
		user = displayUser,
		message = displayText,
		userSkin = userSkin or self.messageSkin,
		messageSkin = self.messageSkin,
		height = newH,
		timeStart = os.time(),
		msgId = msgId,
		login = (login or ""):lower()
	}

	table.insert(self._listMessages, msg)

	if #self._listMessages > MAX_DISPLAYED_MESSAGES then
		table.remove(self._listMessages, 1)
	end

	local total = #self._listMessages
	self.vsScroll:setRange(1, total)

	if self:isScrolledToBottom() or self._forceBottomScroll then
		self:scrollToBottom()
		self._forceBottomScroll = false
		self:updateListM(true)
	else
		self.vsScroll:setThumbValue(1)
		if self:shouldUpdateVisibleList() then
			self:updateListM(true)
		end
	end

	if self._currentMode == modes.hidden then
		self.noReadMsg = self.noReadMsg + 1
		self:updateNoReadMsg()
	end
end

function UI:updateListM(force)
	local total = #self._listMessages
	if total == 0 then
		for _, w in ipairs(self._listStatics) do
			w:setText("")
		end
		self._lastStartMsg = 0
		self._lastTotal = 0
		self._lastWidgetCount = 0
		return
	end

	local thumb = self.vsScroll:getThumbValue() or 1
	local startMsg = self.vsScroll:getValue() + thumb
	if startMsg > total then startMsg = total end

	if not force and self._lastStartMsg == startMsg and self._lastTotal == total then
		return
	end

	if force then
		for _, w in ipairs(self._listStatics) do
			w:setText("")
		end
	end

	self._lastStartMsg = startMsg
	self._lastTotal = total

	local offset = 0
	local widgetIndex = 1
	local maxWidgets = #self._listStatics

	local function ensureFontSize(skin)
		if skin and skin.skinData
			and skin.skinData.states
			and skin.skinData.states.released
			and skin.skinData.states.released[2]
			and skin.skinData.states.released[2].text
			and skin.skinData.states.released[2].text.fontSize ~= self.fontSize then
			skin.skinData.states.released[2].text.fontSize = self.fontSize
		end
	end

	while startMsg >= 1 and widgetIndex + 1 <= maxWidgets do
		local msg = self._listMessages[startMsg]

		if offset + msg.height > self.heightChat then
			break
		end

		local messageSkin = msg.messageSkin or self.messageSkin
		local userSkin = msg.userSkin or self.messageSkin

		ensureFontSize(messageSkin)
		ensureFontSize(userSkin)

		local msgWidget = self._listStatics[widgetIndex]
		msgWidget:setSkin(messageSkin)
		msgWidget:setBounds(0, self.heightChat - offset - msg.height, self.widthChat, msg.height)
		msgWidget:setText(msg.message)

		local userWidget = self._listStatics[widgetIndex + 1]
		userWidget:setSkin(userSkin)
		userWidget:setBounds(0, self.heightChat - offset - msg.height, self.widthChat, msg.height)
		userWidget:setText(msg.user)

		offset = offset + msg.height
		startMsg = startMsg - 1
		widgetIndex = widgetIndex + 2
	end

	for i = widgetIndex, maxWidgets do
		self._listStatics[i]:setText("")
	end

	self._lastWidgetCount = widgetIndex - 1
end

function UI:recalculateAllMessageHeights()
	if not self.testStatic or #self._listMessages == 0 then
		return
	end

	for _, msg in ipairs(self._listMessages) do
		if msg.message and msg.message ~= "" then
			self.testStatic:setText(msg.message)
			local _, newH = self.testStatic:calcSize()
			msg.height = newH
		end
	end
end

function UI:refreshAllMessageSkins(getSkinForUser)
	for _, msg in ipairs(self._listMessages) do
		if msg.login and msg.login ~= "" and getSkinForUser then
			msg.userSkin = getSkinForUser(msg.login)
		end

		local function forceFont(skin)
			if skin and skin.skinData
				and skin.skinData.states
				and skin.skinData.states.released
				and skin.skinData.states.released[2]
				and skin.skinData.states.released[2].text then
				skin.skinData.states.released[2].text.fontSize = self.fontSize
			end
		end

		forceFont(msg.userSkin)
		forceFont(msg.messageSkin)
	end

	self:updateListM(true)
end

function UI:setFontSize(fontSize)
	self.fontSize = fontSize

	local testSkin = self.skinFactory:getSkin()
	testSkin.skinData.states.released[2].text.fontSize = fontSize
	self.testStatic:setSkin(testSkin)

	if self.messageSkin
		and self.messageSkin.skinData
		and self.messageSkin.skinData.states
		and self.messageSkin.skinData.states.released
		and self.messageSkin.skinData.states.released[2]
		and self.messageSkin.skinData.states.released[2].text then
		self.messageSkin.skinData.states.released[2].text.fontSize = fontSize
	end

	self:recalculateAllMessageHeights()
	self:refreshAllMessageSkins(nil)
	self:updateListM(true)
end

function UI:updateCursor()
	if self.lockUIPosition and (self._currentMode == modes.read or self._currentMode == modes.hidden) then
		self.window:setHasCursor(false)
	else
		self.window:setHasCursor(true)
	end
end

function UI:writeMode()
	self._currentMode = modes.write
	tracer:info("UI → write mode")

	self:setVisible(true)
	self.box:setVisible(true)
	self.pDown:setVisible(true)
	self.eMessage:setVisible(true)
	self.eMessage:setFocused(true)
	self.window:setSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT)
	self.box:setBounds(0, 0, DEFAULT_WINDOW_WIDTH, 400)
	self.box:setSkin(self.skinModeWrite)
	self.window:setSkin(Skin.windowSkinChatWrite())
	self.vsScroll:setVisible(true)
	self:lockKeyboardInput()
	self:resetInactivityTimer()

	if self.pendingScrollToBottom then
		self:scrollToBottom()
		self.pendingScrollToBottom = false
	end

	self:updateListM(true)
	self:resizeEditMessage()
	self:updateCursor()
end

function UI:readMode()
	self._currentMode = modes.read
	tracer:info("UI → read mode")

	self:setVisible(true)
	self:setTitle(self.viewerCount)
	self.box:setVisible(true)
	self.pDown:setVisible(false)
	self.box:setSkin(self.skinModeRead)
	self.window:setSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT)
	self.box:setBounds(0, 0, DEFAULT_WINDOW_WIDTH, 400)
	self.window:setSkin(self:_applyTransparentSkin())
	self.vsScroll:setVisible(false)
	self:setVisibleBtnMail(false)
	self:unlockKeyboardInput(true)
	self:resetInactivityTimer()

	if self.pendingScrollToBottom then
		self:scrollToBottom()
		self.pendingScrollToBottom = false
	end

	self:updateListM(true)
	self.noReadMsg = 0
	self:updateCursor()
end

function UI:hideMode()
	self._currentMode = modes.hidden
	tracer:info("UI → hidden mode")

	self.box:setVisible(false)
	self.pDown:setVisible(false)
	self.window:setText("")
	self.window:setSkin(self:_applyTransparentSkin())
	self.vsScroll:setVisible(false)
	self.window:setSize(MINI_WINDOW_WIDTH, MINI_WINDOW_HEIGHT)
	self.btnMail:setBounds(12, 0, 24, 55)
	self:setVisibleBtnMail(true)
	self:unlockKeyboardInput(true)

	self.pendingScrollToBottom = true
	self:updateCursor()

	if self.config then
		self.config:setPosition({ x = self._x, y = self._y })
	end
end

function UI:nextMode()
	if self._currentMode == modes.hidden then
		self:readMode()
	elseif self._currentMode == modes.read then
		self:writeMode()
	else
		self:hideMode()
	end
end

function UI:checkSettingChanges()
	local currentTimer = self.config:getHideInactiveTimer() or 0
	local currentHotkey = self.config:getHideShowHotkey()
	local currentLock = self.config:getLockUIPosition()
	local currentViewerCount = self.config:getShowViewerCount()
	local currentFontSize = self.config:getFontSize()
	local currentColorMode = self.config:getColorMode()

	if currentLock ~= self.lastLockPosition then
		self.lastLockPosition = currentLock
		self.lockUIPosition = currentLock
		self:updateCursor()
	end

	if currentTimer ~= self.lastHideTimer then
		self.lastHideTimer = currentTimer
		self.inactiveMinutes = currentTimer
		self:resetInactivityTimer()
	end

	if currentHotkey ~= self.lastHotkey then
		if self.lastHotkey and self.lastHotkey ~= "" and self.lastHotkey ~= "NONE" then
			self.window:removeHotKeyCallback(self.lastHotkey, self.hotkeyCallback)
		end

		if currentHotkey and currentHotkey ~= "" and currentHotkey ~= "NONE" then
			self.window:addHotKeyCallback(currentHotkey, self.hotkeyCallback)
		end

		self.lastHotkey = currentHotkey
	end

	if self.lastShowViewerCount == nil or currentViewerCount ~= self.lastShowViewerCount then
		self.lastShowViewerCount = currentViewerCount
		self:setTitle(self.viewerCount)
	end

	if currentFontSize ~= self.fontSize then
		self:setFontSize(currentFontSize)
	end

	if currentColorMode ~= self.lastColorMode then
		self.lastColorMode = currentColorMode
		self:onCallback("onUIColorModeChanged", {})
		self:updateListM(true)
	end
end

function UI:setTitle(viewerCount)
	self.viewerCount = viewerCount or 0
	if self._currentMode == modes.read or self._currentMode == modes.write then
		if self.config:getShowViewerCount() and self.viewerCount > 0 then
			self.window:setText(" Twitch (" .. self.viewerCount .. ")")
		else
			self.window:setText(" Twitch")
		end
	end
end

function UI:setCallbacks(callbacks)
	self.callbacks = callbacks
end

function UI:onCallback(callback, args)
	if self.callbacks and self.callbacks[callback] then
		self.callbacks[callback](args)
	end
end

function UI:sendMessage()
	if self._currentMode ~= modes.write or not self.eMessage then return end

	local msg = self.eMessage:getText() or ""
	msg = string.gsub(msg, "[\r\n]+", " ")
	msg = string.match(msg, "^%s*(.-)%s*$") or ""

	if msg == "" then return end
	if #msg > MAX_MESSAGE_LENGTH then
		msg = string.sub(msg, 1, MAX_MESSAGE_LENGTH)
	end

	local original = msg
	local display = Sanitizer.sanitizeMessage(msg)

	self._forceBottomScroll = true
	self:onCallback("onUISendMessage", {
		message = original,
		displayMessage = display
	})
	self.eMessage:setText("")
	self:resizeEditMessage()
	self:scrollToBottom()
end

function UI:resizeEditMessage()
	if not self.eMessage or not self.testE then return end

	local text = self.eMessage:getText() or ""
	self.testE:setText(text)
	local _, newH = self.testE:calcSize()

	self.eMessage:setBounds(self.eMx, self.eMy, self.eMw, newH)

	local px, py, pw, ph = self.pBtn:getBounds()
	self.pBtn:setBounds(px, self.eMy + newH + 20, pw, ph)

	local bx, by, bw, _ = self.box:getBounds()
	local newBoxH = self.eMy + newH + 317
	self.box:setBounds(bx, 0, bw, newBoxH)

	local dx, dy, dw, _ = self.pDown:getBounds()
	self.pDown:setBounds(dx, dy, dw, self.eMy + newH + 117)

	self.window:setSize(DEFAULT_WINDOW_WIDTH, newBoxH + 55)
end

function UI:onChange_tbAll()
	if self.tbAll:getState() then
		self.sAll:setSkin(self.pNoVisible.sSelAll:getSkin())
		self.sAllies:setSkin(self.pNoVisible.sNoSelAllies:getSkin())
	else
		self.sAll:setSkin(self.pNoVisible.sNoSelAll:getSkin())
		self.sAllies:setSkin(self.pNoVisible.sSelAllies:getSkin())
	end
end

function UI:setVisible(b)
	self.window:setVisible(b)
end

function UI:setVisibleBtnMail(b)
	if not self.btnMail then return end
	self.btnMail:setVisible(b and self.noReadMsg > 0)
end

function UI:updateNoReadMsg()
	if not self.btnMail then return end

	local txt = self.noReadMsg >= 100 and "99+" or tostring(self.noReadMsg)
	self.btnMail:setText(txt)

	if self._currentMode == modes.hidden and self.noReadMsg > 0 then
		self.btnMail:setVisible(true)
	end
end

function UI:positionCallback()
	local x, y = self.window:getPosition()

	if self.lockUIPosition then
		self.window:setPosition(self._x, self._y)
		return
	end

	x = math.max(math.min(x, self.w - DEFAULT_WINDOW_WIDTH), 0)
	y = math.max(math.min(y, self.h - 400), 0)

	if x ~= self._x or y ~= self._y then
		self._x = x
		self._y = y
		self.window:setPosition(x, y)
		self:onCallback("onUIPositionChanged", { x = x, y = y })
	end
end

function UI:onChange_vsScroll()
	self._currentWheelValue = self.vsScroll:getValue()
	self:updateListM(true)
end

function UI:onMouseWheel(clicks)
	local step = -clicks
	local minR, maxR = self.vsScroll:getRange()
	local newVal = self.vsScroll:getValue() + step

	if newVal < minR then newVal = minR end
	if newVal > maxR then newVal = maxR end

	self.vsScroll:setValue(newVal)
	self._currentWheelValue = newVal
	self:updateListM(true)
end

function UI:resize(w, h)
	self.window:setBounds(self._x, self._y, DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT)
	self.box:setBounds(0, 0, DEFAULT_WINDOW_WIDTH, 400)
	if self.btnMail then
		self.btnMail:setBounds(12, 0, 24, 55)
	end
end

return UI