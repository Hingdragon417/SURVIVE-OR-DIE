local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapEnums = require(ReplicatedStorage.Shared.MapEnums)

local RoundService = Knit.CreateService({
    Name = "RoundService",
    Client = { 
        StatusChanged = Knit.CreateSignal(),
        VoteChanged = Knit.CreateSignal(),
        RoleAssigned = Knit.CreateSignal()
    },
    Status = "Waiting",
    _connections = {}
})

RoundService.Votes = {0, 0, 0}
RoundService.PlayerVotes = {}
RoundService.SelectedMaps = {}

function RoundService:GetRandomMaps()
    local maps = ReplicatedStorage.Maps:GetChildren()
    if #maps == 0 then return {} end
    
    local selected, used = {}, {}
    local count = math.min(3, #maps)
    
    for i = 1, count do
        local index
        local attempts = 0
        
        repeat
            index = math.random(#maps)
            attempts += 1
            if attempts > 100 then return selected end
        until not used[index]
        
        used[index] = true
        if maps[index] then
            table.insert(selected, maps[index])
        end
    end
    
    return selected
end

function RoundService:UpdateMapBoards(maps)
    local mapVote = Workspace:FindFirstChild("MapVote")
    if not mapVote then return end
    
    local boards = mapVote:FindFirstChild("MapBoards")
    if not boards then return end
    
    for i, board in ipairs(boards:GetChildren()) do
        local map = maps[i]
        if not map then continue end
        
        local mapGui = board:FindFirstChild("MapGui")
        if not mapGui then continue end
        
        local mapImage = mapGui:FindFirstChild("MapImage")
        local mapName = mapGui:FindFirstChild("MapName")
        
        if mapImage and MapEnums[map.Name] then 
            mapImage.Image = MapEnums[map.Name].Image
        end
        
        if mapName then 
            mapName.Text = map.Name
        end
        
        task.wait()
    end
end

function RoundService:SetStatus(newStatus)
    task.spawn(function()
        if newStatus == "Intermission" then
            self.SelectedMaps = self:GetRandomMaps()
            self:UpdateMapBoards(self.SelectedMaps)
            
            for i = 30, 1, -1 do
                self.Status = string.format("Intermission (%d)", i)
                self.Client.StatusChanged:FireAll(self.Status)
                task.wait(1)
            end
            
            self:SetStatus("RoundStarting")
        elseif newStatus == "RoundStarting" then
            local winningMap = self:GetWinningMap()
            if winningMap then
                self:LoadMap(winningMap.Name)
                local killer = self:SelectKiller()
                
                for _, player in Players:GetPlayers() do
                    local role = if player == killer then "Killer" else "Survivor"
                    self.Client.RoleAssigned:Fire(player, role)
                end
                
                task.wait(3)
                self:SpawnPlayers(Workspace:FindFirstChild(winningMap.Name), killer)
                
                -- Start 5 minute round countdown
                self:SetStatus("RoundInProgress")
            else
                self:SetStatus("Intermission")
            end
        elseif newStatus == "RoundInProgress" then
            -- 5 minute countdown (300 seconds)
            for i = 300, 1, -1 do
                local minutes = math.floor(i / 60)
                local seconds = i % 60
                self.Status = string.format("Round (%d:%02d)", minutes, seconds)
                self.Client.StatusChanged:FireAll(self.Status)
                task.wait(1)
            end
            
            -- Round ended
            self:CleanupRound()
            self:SetStatus("Intermission")
        else
            self.Status = newStatus
            self.Client.StatusChanged:FireAll(self.Status)
        end
    end)
end

function RoundService:UpdateVoteDisplays()
    local mapVote = Workspace:FindFirstChild("MapVote")
    if not mapVote then return end
    
    local votePads = mapVote:FindFirstChild("MapVotePads")
    if not votePads then return end
    
    for i, pad in ipairs(votePads:GetChildren()) do
        local display = pad:FindFirstChild("Display")
        if display then
            local voteDisplay = display:FindFirstChild("VotedAmount")
            if voteDisplay and voteDisplay:IsA("TextLabel") then
                voteDisplay.Text = tostring(self.Votes[i] or 0)
            end
        end
    end
end

function RoundService:HandleVote(player, padIndex)
    if not self.PlayerVotes[player] then
        self.PlayerVotes[player] = padIndex
        self.Votes[padIndex] += 1
    else
        local oldVote = self.PlayerVotes[player]
        if oldVote ~= padIndex then
            self.Votes[oldVote] -= 1
            self.Votes[padIndex] += 1
            self.PlayerVotes[player] = padIndex
        end
    end
    
    self.Client.VoteChanged:FireAll(self.Votes)
    task.spawn(function()
        self:UpdateVoteDisplays()
    end)
end

function RoundService:SetupVotePads()
    local mapVote = Workspace:FindFirstChild("MapVote")
    if not mapVote then return end
    
    local votePads = mapVote:FindFirstChild("MapVotePads")
    if not votePads then return end
    
    -- Clean up existing connections
    for _, connection in self._connections do
        connection:Disconnect()
    end
    table.clear(self._connections)
    
    for i, pad in ipairs(votePads:GetChildren()) do
        local connection = pad.Touched:Connect(function(hit)
            local player = game.Players:GetPlayerFromCharacter(hit.Parent)
            if player then
                self:HandleVote(player, i)
            end
        end)
        table.insert(self._connections, connection)
    end
    
    self:UpdateVoteDisplays()
end

function RoundService:GetWinningMap()
    local highestVotes = 0
    local winningIndex = 1
    
    for i, votes in ipairs(self.Votes) do
        if votes > highestVotes then
            highestVotes = votes
            winningIndex = i
        end
    end
    
    return self.SelectedMaps[winningIndex]
end

function RoundService:LoadMap(mapName)
    local map = ReplicatedStorage.Maps:FindFirstChild(mapName)
    if not map then return end
    
    local mapClone = map:Clone()
    mapClone.Parent = Workspace
end

function RoundService:SelectKiller()
    local players = Players:GetPlayers()
    if #players == 0 then return end
    return players[math.random(#players)]
end

function RoundService:KnitStart()
    self:SetupVotePads()
    self:SetStatus("Intermission")
end

function RoundService:KnitInit()
    self._dataService = Knit.GetService("DataService")
    game:BindToClose(function()
        for _, connection in self._connections do
            connection:Disconnect()
        end
    end)
end

function RoundService:SpawnPlayers(map, killer)
    local spawnPoints = map:FindFirstChild("SpawnPoints")
    if not spawnPoints then return end
    
    local spawns = spawnPoints:GetChildren()
    if #spawns == 0 then return end
    
    for _, player in Players:GetPlayers() do
        
        local randomSpawn = spawns[math.random(#spawns)]
        if player.Character then
            player.Character:PivotTo(randomSpawn.CFrame)
        end
    end
end

function RoundService:CleanupRound()
    -- Remove the loaded map
    for _, child in Workspace:GetChildren() do
        if ReplicatedStorage.Maps:FindFirstChild(child.Name) then
            child:Destroy()
        end
    end
    
    -- Reset votes
    self.Votes = {0, 0, 0}
    table.clear(self.PlayerVotes)
    self:UpdateVoteDisplays()
end

return RoundService
