local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local DATA_TEMPLATE = require(Shared.Data.Template)

local IS_STUDIO = RunService:IsStudio()
local STORE_NAME = if IS_STUDIO then "TESTSTUDIO2222232221211" else "TESTGAME11111"
local STORE_VERSION = if IS_STUDIO then "1.2.7" else "1.1.0"
local METADATA_INDEX_VERSION = if IS_STUDIO then "STUDIO_DATA_VERSION" else "GAME_DATA_VERSION"
local SHOULD_SAVE = true

local MAX_RETRIES = 10
local RETRY_DELAY = 1.5

local DataService = Knit.CreateService({
	Name = "DataService",
	Client = {
		ReplicateData = Knit.CreateSignal(),
		UsePerks = Knit.CreateSignal(),
		GetPlayerData = Knit.CreateSignal(),
	},
})

function DataService.clearSession(player: Player)
	DataService._cache[player] = nil
end

function DataService.setSession(player: Player, session: Types.Session)
	DataService._cache[player] = session
end

function DataService.getSession(player: Player)
	return DataService._cache[player]
end

function DataService.waitForSession(player: Player, timeout: number?)
	timeout = timeout or 60
	local start = os.clock()
	local session = DataService.getSession(player)
	while not session and (os.clock() - start < timeout) do
		task.wait()
		session = DataService.getSession(player)
	end
	return session
end

function DataService.onPlayerAdded(player: Player)
	local userId = tostring(player.UserId)
	local session
	for _ = 1, MAX_RETRIES do
		session = DataService._store:StartSessionAsync(userId, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if session then break end
		task.wait(RETRY_DELAY)
	end

	if not session then
		return player:Kick("Issue with loading data, please rejoin.")
	end

	session:AddUserId(player.UserId)

	session.OnSessionEnd:Connect(function()
		DataService.onPlayerRemoving(player)
	end)

	if player.Parent ~= Players then
		return session:EndSession()
	end

	if session.RobloxMetaData[METADATA_INDEX_VERSION] ~= STORE_VERSION or not SHOULD_SAVE then
		session.RobloxMetaData[METADATA_INDEX_VERSION] = STORE_VERSION
		session.Data = TableUtil.DeepCopy(DATA_TEMPLATE)
		print("[DataService] Reset data to template for", player.Name, "- Coins:", session.Data.Coins)
	end

	session:Reconcile()
	
	if not session.Data.Coins then
		session.Data.Coins = DATA_TEMPLATE.Coins
		print("[DataService] Added missing Coins for", player.Name, "- Value:", session.Data.Coins)
	end
	
	print("[DataService] Final Coins for", player.Name, ":", session.Data.Coins)
	
	DataService._cache[player] = session
	
	task.wait(1)
	DataService:Replicate(player)
	
	DataService._onPlayerDataLoaded:Fire(player)
end

function DataService:Replicate(player: Player, index: (string | { string })?)
	task.spawn(function()
		local currentSession = self.getSession(player)
		if not currentSession or not currentSession.Data then
			return
		end
		
		if not index then
			self.Client.ReplicateData:Fire(player, currentSession.Data)
			return
		end
		
		local updateData = {}
		local indices = type(index) == "table" and index or {index}
		local shouldSyncShopAndPerks = table.find(indices, "Shop") or table.find(indices, "Perks")
		
		if shouldSyncShopAndPerks then
			updateData.Shop = currentSession.Data.Shop
			updateData.Perks = currentSession.Data.Perks
			self.Client.ReplicateData:Fire(player, {Shop = currentSession.Data.Shop}, "Shop")
			task.wait()
			self.Client.ReplicateData:Fire(player, {Perks = currentSession.Data.Perks}, "Perks")
			
			for _, key in ipairs(indices) do
				if key ~= "Shop" and key ~= "Perks" then
					self.Client.ReplicateData:Fire(player, {[key] = currentSession.Data[key]}, key)
				end
			end
		else
			for _, key in ipairs(indices) do
				updateData[key] = currentSession.Data[key]
			end
			
			for _, key in ipairs(indices) do
				self.Client.ReplicateData:Fire(player, {[key] = currentSession.Data[key]}, key)
			end
		end
	end)
end

function DataService.onPlayerRemoving(player: Player)
	local currentSession = DataService.getSession(player)
	if currentSession then
		DataService._onPlayerRemoving:Fire(player)
		currentSession:EndSession()
		DataService.clearSession(player)
	end
end

function DataService:OnPlayerRemoving(player: Player, callback: () -> nil)
	local connection
	connection = self._onPlayerRemoving:Connect(function(_player: Player)
		if player == _player then
			callback()
			connection:Disconnect()
			connection = nil
		end
	end)
	return connection
end

function DataService:KnitInit()
	self._store = ProfileStore.New(STORE_NAME, DATA_TEMPLATE)
	self._cache = {}
	self._onPlayerRemoving = Signal.new()
	self._onPlayerDataLoaded = Signal.new()
	Players.PlayerAdded:Connect(self.onPlayerAdded)
	Players.PlayerRemoving:Connect(self.onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(self.onPlayerAdded, player)
	end
end

function DataService.Client:GetPlayerData(player)
	local session = DataService.getSession(player)
	if session and session.Data then
		return session.Data
	end
	return nil
end

function DataService:UpdatePlayerData(player: Player, data)
	local session = self.getSession(player)
	if session then
		session.Data = data
		self:Replicate(player)
		return true
	end
	return false
end

function DataService.Client:UseSurvivorPerk(player: Player, slotName: string)
	local session = DataService.getSession(player)
	if not session or not session.Data.SurvivorPerks then
		return false, "No player data found"
	end

	local perkSlot = session.Data.SurvivorPerks[slotName]
	if not perkSlot or perkSlot.Name == "" or perkSlot.Quantity <= 0 then
		return false, "No survivor perk found in slot"
	end

	perkSlot.Quantity -= 1
	
	if perkSlot.Quantity <= 0 then
		perkSlot.Name = ""
		perkSlot.Quantity = 0
	end
	
	local QuestService = Knit.GetService("QuestService")
	if QuestService then
		QuestService:UpdateProgress(player, "Use 10 Perks", 1)
	end
	
	DataService:Replicate(player, "SurvivorPerks")
	return true, "Success"
end

function DataService.Client:UseKillerPerk(player: Player, slotName: string)
	local session = DataService.getSession(player)
	if not session or not session.Data.Perks then
		return false, "No player data found"
	end

	local perkSlot = session.Data.Perks[slotName]
	if not perkSlot or perkSlot.Name == "" or perkSlot.Quantity <= 0 then
		return false, "No perk found in slot"
	end

	perkSlot.Quantity -= 1
	
	if perkSlot.Quantity <= 0 then
		perkSlot.Name = ""
		perkSlot.Quantity = 0
	end
	
	local QuestService = Knit.GetService("QuestService")
	if QuestService then
		QuestService:UpdateProgress(player, "Use 10 Perks", 1)
	end
	
	DataService:Replicate(player, "Perks")
	return true, "Success"
end

return DataService
