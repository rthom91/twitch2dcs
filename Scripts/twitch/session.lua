local base = _G

module("twitch.session")

local os = base.os

local Session = {}
local Session_mt = { __index = Session }

function Session:new(config, tracer)
	local self = base.setmetatable({}, Session_mt)

	self.config = config
	self.tracer = tracer
	self.client = nil

	self.manualDisconnect = false

	self.credentialsInvalidSince = 0
	self.CREDENTIALS_CLEAR_DELAY = 10
	self.pendingCredentialReconnect = false
	self.credentialsRestoredSince = 0
	self.prevCanLogin = nil
	self.cachedCanLogin = false

	self.authFailureRecovery = false
	self.authFailureAttempts = 0
	self.lastAuthFailureAttempt = 0
	self.AUTH_FAILURE_MAX_ATTEMPTS = 3
	self.AUTH_FAILURE_INTERVAL = 10

	self.connectionLostRecovery = false
	self.connectionLostAttempts = 0
	self.lastConnectionLostAttempt = 0
	self.CONNECTION_LOST_MAX_ATTEMPTS = 3
	self.CONNECTION_LOST_INTERVAL = 10

	self.credentialsVerified = false
	self.authPending = false
	self.authStartTime = 0
	self.AUTH_TIMEOUT = 15

	self.connectedUsername = nil
	self.connectedToken = nil

	self.lastViewerCountCheckTime = os.time()

	return self
end

function Session:setClient(client)
	self.client = client
end

function Session:canLogin()
	local auth = self.config:getAuthInfo()
	return self.config:isEnabled()
		and auth.username and auth.username ~= ""
		and auth.accessToken and auth.accessToken ~= ""
end

function Session:initLoginCache()
	self.cachedCanLogin = self:canLogin()
	self.prevCanLogin = self.cachedCanLogin
	return self.cachedCanLogin
end

function Session:shouldReceive()
	return self.cachedCanLogin
		and not self.manualDisconnect
		and self.client
		and self.client.server
		and self.client.server.isConnected
end

function Session:onAuthFailed()
	if not self.authFailureRecovery then
		self.authFailureRecovery = true
		self.authFailureAttempts = 0
		self.lastAuthFailureAttempt = os.time()
		self.connectionLostRecovery = false
		self.tracer:warn("Authentication failed. Entering recovery.")
	end
	self.credentialsVerified = false
	self.authPending = false
	self.connectedUsername = nil
	self.connectedToken = nil
end

function Session:onManualDisconnect()
	self.manualDisconnect = true
	self.pendingCredentialReconnect = false
	self.authFailureRecovery = false
	self.connectionLostRecovery = false
	self.credentialsVerified = false
	self.authPending = false
	self.connectedUsername = nil
	self.connectedToken = nil
end

function Session:onManualConnect()
	self.manualDisconnect = false
	self.pendingCredentialReconnect = false
	self.authFailureRecovery = false
	self.connectionLostRecovery = false
	self.credentialsVerified = false
	self.authPending = false
	self.connectedUsername = nil
	self.connectedToken = nil
	self.credentialsRestoredSince = 0
end

function Session:onConnectStart()
	self.credentialsVerified = false
	self.authPending = true
	self.authStartTime = os.time()
	self.connectedUsername = nil
	self.connectedToken = nil
end

function Session:isVerified()
	return self.credentialsVerified
end

function Session:markVerified()
	if self.credentialsVerified then
		return
	end

	local client = self.client
	if not client or not client.server or not client.server.isConnected then
		return
	end

	local configured = (client.username or ""):lower()
	local realLogin  = (client.authenticatedLogin or ""):lower()

	if realLogin ~= "" and configured ~= "" and realLogin ~= configured then
		self.tracer:warn("Token account (" .. realLogin .. ") does not match configured username (" .. configured .. ")")
		if client.ui then
			client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Token belongs to a different account (" .. realLogin .. "). Disconnecting.", nil)
		end
		client.server:reset()
		self:onAuthFailed()
		return
	end

	if realLogin == "" then
		return
	end

	if client.ui then
		client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connected. Credentials verified.", nil)
	end

	self.credentialsVerified = true
	self.authPending = false
	self.authFailureRecovery = false
	self.connectionLostRecovery = false
	self.manualDisconnect = false
	self.pendingCredentialReconnect = false

	local auth = self.config:getAuthInfo()
	self.connectedUsername = auth.username
	self.connectedToken = auth.accessToken

	self.tracer:info("Successfully connected and authenticated as " .. (client.authenticatedDisplayName or auth.username))
end

function Session:tick(now)
	local client = self.client
	if not client then return end

	local config = self.config
	local tracer = self.tracer

	self.cachedCanLogin = self:canLogin()

	if self.credentialsVerified and client.server and client.server.isConnected then
		local auth = config:getAuthInfo()
		if (auth.username or "") ~= (self.connectedUsername or "") or
		   (auth.accessToken or "") ~= (self.connectedToken or "") then
			if client.ui then
				client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Login credentials changed. Disconnecting.", nil)
				client.ui:setTitle(0)
			end
			client.server:reset()
			self.manualDisconnect = true
			self.credentialsVerified = false
			self.authPending = false
			self.authFailureRecovery = false
			self.connectionLostRecovery = false
			self.connectedUsername = nil
			self.connectedToken = nil
			if not self.cachedCanLogin then
				self.pendingCredentialReconnect = true
				self.credentialsRestoredSince = 0
			end
			tracer:info("Disconnected because login credentials were changed while connected.")
		end
	end

	if self.prevCanLogin == false and self.cachedCanLogin == true then
		if not client.server.isConnected and not self.credentialsVerified
		   and not self.authFailureRecovery and not self.connectionLostRecovery then
			self.pendingCredentialReconnect = true
			self.credentialsRestoredSince = 0
			tracer:info("New credentials entered. Reconnecting.")
		end
	end
	self.prevCanLogin = self.cachedCanLogin

	if self.credentialsVerified and client.server and not client.server.isConnected
	   and not self.manualDisconnect and not self.authFailureRecovery and not self.connectionLostRecovery then
		self.connectionLostRecovery = true
		self.connectionLostAttempts = 0
		self.lastConnectionLostAttempt = now
		self.credentialsVerified = false
		if client.ui then
			client.ui:setTitle(0)
		end
		tracer:warn("Connection lost. Entering recovery.")
	end

	if self.authPending and client.server and client.server.isConnected
	   and not self.authFailureRecovery and not self.connectionLostRecovery then
		if now - self.authStartTime >= self.AUTH_TIMEOUT and not self.credentialsVerified then
			client.server:reset()
			self.authPending = false
			self.credentialsVerified = false
			self.connectedUsername = nil
			self.connectedToken = nil
			if not self.authFailureRecovery then
				self.authFailureRecovery = true
				self.authFailureAttempts = 0
				self.lastAuthFailureAttempt = now
				tracer:warn("Authentication failed. Entering recovery.")
			end
		end
	end

	if client.server and client.server.isConnected and client.authenticatedDisplayName then
		self:markVerified()
	end

	if self.authFailureRecovery and not client.server.isConnected then
		if now - self.lastAuthFailureAttempt >= self.AUTH_FAILURE_INTERVAL then
			if self.authFailureAttempts < self.AUTH_FAILURE_MAX_ATTEMPTS then
				self.authFailureAttempts = self.authFailureAttempts + 1
				self.lastAuthFailureAttempt = now

				if client.ui then
					client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connection attempt (" .. self.authFailureAttempts .. "/3)", nil)
				end
				tracer:info("Recovery attempt " .. self.authFailureAttempts .. "/" .. self.AUTH_FAILURE_MAX_ATTEMPTS)

				client:reconnect()
			else
				self.authFailureRecovery = false
				self.credentialsVerified = false
				self.connectedUsername = nil
				self.connectedToken = nil
				self.pendingCredentialReconnect = false
				self.manualDisconnect = true

				if client.ui then
					client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Authentication failed. Type /connect to retry.", nil)
				end
				tracer:warn("Max recovery attempts reached.")
			end
		end
	end

	if self.connectionLostRecovery and not client.server.isConnected then
		if now - self.lastConnectionLostAttempt >= self.CONNECTION_LOST_INTERVAL then
			if self.connectionLostAttempts < self.CONNECTION_LOST_MAX_ATTEMPTS then
				self.connectionLostAttempts = self.connectionLostAttempts + 1
				self.lastConnectionLostAttempt = now

				if client.ui then
					client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connection attempt (" .. self.connectionLostAttempts .. "/3)", nil)
				end
				tracer:info("Recovery attempt " .. self.connectionLostAttempts .. "/" .. self.CONNECTION_LOST_MAX_ATTEMPTS)

				client:reconnect()
			else
				self.connectionLostRecovery = false
				self.credentialsVerified = false
				self.connectedUsername = nil
				self.connectedToken = nil
				self.manualDisconnect = true

				if client.ui then
					client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connection lost. Type /connect to retry.", nil)
				end
				tracer:warn("Max recovery attempts reached.")
			end
		end
	end

	if client.server and not self.authFailureRecovery and not self.connectionLostRecovery then
		if client.server.isConnected and not self.cachedCanLogin then
			if self.credentialsInvalidSince == 0 then
				self.credentialsInvalidSince = now
			end

			if now - self.credentialsInvalidSince >= self.CREDENTIALS_CLEAR_DELAY then
				if client.ui then
					client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Login credentials changed. Disconnecting.", nil)
					client.ui:setTitle(0)
				end
				client.server:reset()
				self.manualDisconnect = true
				self.pendingCredentialReconnect = true
				self.credentialsInvalidSince = 0
				self.credentialsRestoredSince = 0
				self.credentialsVerified = false
				self.authPending = false
				self.authFailureRecovery = false
				self.connectionLostRecovery = false
				self.connectedUsername = nil
				self.connectedToken = nil
				tracer:info("Disconnected due to changed login credentials.")
			end
		else
			self.credentialsInvalidSince = 0
		end
	end

	if self.pendingCredentialReconnect and not client.server.isConnected and self.cachedCanLogin then
		if self.credentialsRestoredSince == 0 then
			self.credentialsRestoredSince = now
		end

		if now - self.credentialsRestoredSince >= 3 then
			if client.ui then
				client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Login credentials entered. Connecting.", nil)
			end
			self.manualDisconnect = false
			self.pendingCredentialReconnect = false
			self.credentialsRestoredSince = 0
			self.credentialsVerified = false
			self.authFailureRecovery = false
			self.connectionLostRecovery = false
			client:connect()
		end
	end

	if client.pendingClearRequest and client.clearRequestTime then
		if now - client.clearRequestTime >= 90 then
			client.pendingClearRequest = false
			client.clearRequestTime = nil

			if client.ui then
				client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Confirmation timed out.", nil)
			end

			client:logChat("SYSTEM", "Clear chat confirmation timed out.")
			self.tracer:info("CLEARCHAT confirmation timed out.")
		end
	end

	if self.cachedCanLogin and self.credentialsVerified and now - self.lastViewerCountCheckTime >= 90 then
		client:checkViewerCountTimer()
		self.lastViewerCountCheckTime = now
	end
end

return Session