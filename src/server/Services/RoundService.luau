local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapEnums = require(ReplicatedStorage.Shared.MapEnums)

local RoundService = Knit.CreateService({
    Name = "RoundService",
    Client = { 
        StatusChanged = Knit.CreateSignal(),
        VoteChanged = Knit.CreateSignal(),
        RoleAssigned = Knit.CreateSignal(),
        GeneratorsCompleted = Knit.CreateSignal()
    },
    Status = "Waiting",
    _connections = {}
})

RoundService.Votes = {0, 0, 0}
RoundService.PlayerVotes = {}
RoundService.SelectedMaps = {}
RoundService.CompletedGenerators = {}
RoundService.CompletedGeneratorCount = 0
RoundService.CurrentMap = nil
RoundService.PlayersInRound = {}
RoundService.EscapedPlayers = {}
RoundService.Killer = nil
RoundService._gateConnections = {}
RoundService._playerRemovedConnection = nil
RoundService._roundActive = false
RoundService._roundEnding = false

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
            
            for i = 20, 1, -1 do
                self.Status = string.format("Intermission (%d)", i)
                self.Client.StatusChanged:FireAll(self.Status)
                task.wait(1)
            end
            
            self:SetStatus("RoundStarting")
        elseif newStatus == "RoundStarting" then
            local winningMap = self:GetWinningMap()
            if winningMap then
                self._roundActive = false
                self._roundEnding = false
                
                self:LoadMap(winningMap.Name)
                local killer = self:SelectKiller()
                self.Killer = killer
                
                local GeneratorService = Knit.GetService("GeneratorService")
                
                table.clear(self.PlayersInRound)
                table.clear(self.EscapedPlayers)
                for _, player in Players:GetPlayers() do
                    table.insert(self.PlayersInRound, player)
                    local role = if player == killer then "Killer" else "Survivor"
                    self.Client.RoleAssigned:Fire(player, role)
                    GeneratorService:SetPlayerRole(player, role)
                end
                
                self:SetupGateEscape()
                self:SetupPlayerTracking()
                
                task.wait(3)
                self:SpawnPlayers(Workspace:FindFirstChild(winningMap.Name), killer)
                
                self:SetStatus("RoundInProgress")
            else
                self:SetStatus("Intermission")
            end
        elseif newStatus == "RoundInProgress" then
            self._roundActive = true
            
            for i = 300, 1, -1 do
                if not self._roundActive then
                    return
                end
                
                local minutes = math.floor(i / 60)
                local seconds = i % 60
                self.Status = string.format("Round (%d:%02d)", minutes, seconds)
                self.Client.StatusChanged:FireAll(self.Status)
                task.wait(1)
            end
            
            if self._roundActive then
                self:EndRound("Time Up!", "TimeUp")
            end
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
    self.CurrentMap = mapName
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

function RoundService:RemovePlayerFromRound(player: Player)
    for i, p in ipairs(self.PlayersInRound) do
        if p == player then
            table.remove(self.PlayersInRound, i)
            break
        end
    end
    
    -- Check if round should end (only if round is active and not already ending)
    if self._roundActive and not self._roundEnding then
        task.spawn(function()
            task.wait(0.1) -- Small delay to batch multiple deaths
            if self._roundActive and not self._roundEnding then
                self:CheckRoundEnd()
            end
        end)
    end
end

function RoundService:TeleportToLobby(player: Player)
    local lobby = Workspace:FindFirstChild("Lobby")
    if lobby and player.Character then
        local spawnPoint = lobby:FindFirstChild("TP")
        if spawnPoint then
            player.Character:PivotTo(spawnPoint.CFrame)
        end
    end
end

function RoundService:SetupPlayerTracking()
    -- Disconnect old connection if exists
    if self._playerRemovedConnection then
        self._playerRemovedConnection:Disconnect()
    end
    
    -- Track player leaving
    self._playerRemovedConnection = Players.PlayerRemoving:Connect(function(player)
        if not self._roundActive or self._roundEnding then return end
        
        -- Check if it's the killer leaving
        if player == self.Killer then
            self:EndRound("Killer Left", "KillerLeft")
        else
            self:RemovePlayerFromRound(player)
        end
    end)
    
    -- Track player deaths
    for _, player in Players:GetPlayers() do
        if player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid.Died:Connect(function()
                    if not self._roundActive or self._roundEnding then return end
                    
                    if player ~= self.Killer then
                        self:RemovePlayerFromRound(player)
                        task.wait(1)
                        self:TeleportToLobby(player)
                    end
                end)
            end
        end
    end
end

function RoundService:SetupGateEscape()
    -- Clean up old connections
    for _, connection in self._gateConnections do
        connection:Disconnect()
    end
    table.clear(self._gateConnections)
    
    if not self.CurrentMap then return end
    
    local mapInWorkspace = Workspace:FindFirstChild(self.CurrentMap)
    if not mapInWorkspace then return end
    
    local gate = mapInWorkspace:FindFirstChild("Gate")
    if not gate then return end
    
    local touchPart = gate:FindFirstChild("TouchPart")
    if not touchPart then return end
    
    local escapeDebounce = {}
    
    local connection = touchPart.Touched:Connect(function(hit)
        local player = Players:GetPlayerFromCharacter(hit.Parent)
        if not player then return end
        
        -- Debounce check
        if escapeDebounce[player] then return end
        
        -- Check if round is active
        if not self._roundActive or self._roundEnding then return end
        
        -- Check if player is a survivor and all gens are done
        if player ~= self.Killer and self.CompletedGeneratorCount >= 5 then
            -- Check if not already escaped and still in round
            if not table.find(self.EscapedPlayers, player) and table.find(self.PlayersInRound, player) then
                escapeDebounce[player] = true
                table.insert(self.EscapedPlayers, player)
                
                -- Give 100 cash
                if self._dataService then
                    local success, err = pcall(function()
                        local session = self._dataService.getSession(player)
                        if session and session.Data then
                            session.Data.Cash = session.Data.Cash + 100
                            self._dataService:Replicate(player, "Cash")
                        end
                    end)
                    if not success then
                        warn("[RoundService] Failed to add cash:", err)
                    end
                end
                
                -- Remove from round
                self:RemovePlayerFromRound(player)
                
                -- Teleport to lobby
                task.wait(0.5)
                self:TeleportToLobby(player)
            end
        end
    end)
    
    table.insert(self._gateConnections, connection)
end

function RoundService:CheckRoundEnd()
    if not self._roundActive or self._roundEnding then return end
    
    -- Count survivors still in round (not including killer)
    local survivorsLeft = 0
    for _, player in self.PlayersInRound do
        if player ~= self.Killer then
            survivorsLeft += 1
        end
    end
    
    -- If no survivors left in round
    if survivorsLeft == 0 then
        -- Check if any survivors escaped
        if #self.EscapedPlayers > 0 then
            self:EndRound("Survivors Escaped!", "SurvivorWin")
        else
            self:EndRound("Killer Wins!", "KillerWin")
        end
    end
end

function RoundService:EndRound(message: string, reason: string)
    if self._roundEnding then return end
    
    self._roundEnding = true
    self._roundActive = false
    
    self.Status = message
    self.Client.StatusChanged:FireAll(self.Status)
    
    task.wait(3)
    
    self:CleanupRound()
    self:SetStatus("Intermission")
end

function RoundService:CleanupRound()
    -- Disconnect gate connections
    for _, connection in self._gateConnections do
        connection:Disconnect()
    end
    table.clear(self._gateConnections)
    
    -- Disconnect player tracking
    if self._playerRemovedConnection then
        self._playerRemovedConnection:Disconnect()
        self._playerRemovedConnection = nil
    end
    
    -- Teleport all players back to lobby
    for _, player in Players:GetPlayers() do
        self:TeleportToLobby(player)
    end
    
    for _, child in Workspace:GetChildren() do
        if ReplicatedStorage.Maps:FindFirstChild(child.Name) then
            child:Destroy()
        end
    end
    
    self.Votes = {0, 0, 0}
    table.clear(self.PlayerVotes)
    self:UpdateVoteDisplays()
    
    table.clear(self.CompletedGenerators)
    self.CompletedGeneratorCount = 0
    self.Client.GeneratorsCompleted:FireAll(0)
    self.CurrentMap = nil
    table.clear(self.PlayersInRound)
    table.clear(self.EscapedPlayers)
    self.Killer = nil
    self._roundActive = false
    self._roundEnding = false
end

function RoundService:MarkGeneratorCompleted(generatorId: string)
    if not self.CompletedGenerators[generatorId] then
        self.CompletedGenerators[generatorId] = true
        self.CompletedGeneratorCount = self.CompletedGeneratorCount + 1
        self.Client.GeneratorsCompleted:FireAll(self.CompletedGeneratorCount)
        
        if self.CompletedGeneratorCount >= 5 then
            self:OpenGate()
        end
    end
end

function RoundService:OpenGate()
    if not self.CurrentMap then return end
    
    local mapInWorkspace = Workspace:FindFirstChild(self.CurrentMap)
    if not mapInWorkspace then return end
    
    local gate = mapInWorkspace:FindFirstChild("Gate")
    if not gate then return end
    
    local gateDoor = gate:FindFirstChild("GateDoor")
    local gateDoor2 = gate:FindFirstChild("GateDoor2")
    local gateDoorOpen = gate:FindFirstChild("GateDoorOpen")
    local gateDoorOpen2 = gate:FindFirstChild("GateDoorOpen2")
    
    if gateDoor and gateDoorOpen and gateDoor:IsA("Model") then
        local tweenInfo = TweenInfo.new(
            2,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        )
        
        if gateDoor.PrimaryPart then
            local currentRotation = gateDoor.PrimaryPart.CFrame - gateDoor.PrimaryPart.Position
            local targetPosition = gateDoorOpen.Position
            local targetCFrame = currentRotation + targetPosition
            
            local tween = TweenService:Create(gateDoor.PrimaryPart, tweenInfo, {CFrame = targetCFrame})
            tween:Play()
        end
    end
    
    if gateDoor2 and gateDoorOpen2 and gateDoor2:IsA("Model") then
        local tweenInfo = TweenInfo.new(
            2,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        )
        
        if gateDoor2.PrimaryPart then
            local currentRotation = gateDoor2.PrimaryPart.CFrame - gateDoor2.PrimaryPart.Position
            local targetPosition = gateDoorOpen2.Position
            local targetCFrame = currentRotation + targetPosition
            
            local tween = TweenService:Create(gateDoor2.PrimaryPart, tweenInfo, {CFrame = targetCFrame})
            tween:Play()
        end
    end
end

function RoundService:GetCompletedGeneratorCount(): number
    return self.CompletedGeneratorCount
end

function RoundService.Client:GetPlayersInRound(player: Player)
    return self.Server.PlayersInRound
end

return RoundService
