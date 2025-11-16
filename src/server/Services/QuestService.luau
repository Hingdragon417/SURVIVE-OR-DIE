local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local QuestEnums = require(Shared.Data.QuestEnums)

local QuestService = Knit.CreateService({
    Name = "QuestService",
    Client = {
        QuestsUpdated = Knit.CreateSignal(),
        ProgressUpdated = Knit.CreateSignal(),
    }
})

local RESET_INTERVAL = 1800 -- 30 minutes in seconds
local DataService

local function getQuestsByType(questType)
    local quests = {}
    for questName, questData in pairs(QuestEnums) do
        if questData.Type == questType then
            table.insert(quests, questName)
        end
    end
    return quests
end

local function getRandomQuest(questType)
    local quests = getQuestsByType(questType)
    if #quests > 0 then
        return quests[math.random(#quests)]
    end
    return nil
end

function QuestService:GenerateQuestsForPlayer(player: Player)
    if not DataService then return end
    
    local session = DataService.getSession(player)
    if not session or not session.Data then return end
    
    local questNames = {}
    
    -- Generate 1 Killer quest
    local killerQuest = getRandomQuest("Killer")
    if killerQuest then
        table.insert(questNames, killerQuest)
    end
    
    -- Generate 1 Survivor quest
    local survivorQuest = getRandomQuest("Survivor")
    if survivorQuest then
        table.insert(questNames, survivorQuest)
    end
    
    -- Generate 1 random quest from any type
    local allQuestNames = {}
    for questName, _ in pairs(QuestEnums) do
        table.insert(allQuestNames, questName)
    end
    
    if #allQuestNames > 0 then
        local randomQuestName = allQuestNames[math.random(#allQuestNames)]
        table.insert(questNames, randomQuestName)
    end
    
    -- Save only quest names to player data
    session.Data.ActiveQuests = questNames
    session.Data.LastQuestResetTime = os.time()
    session.Data.QuestProgress = {}
    
    -- Build full quest data for client
    local quests = {}
    for _, questName in questNames do
        table.insert(quests, {
            Name = questName,
            Data = QuestEnums[questName]
        })
    end
    
    -- Notify client
    self.Client.QuestsUpdated:Fire(player, quests, session.Data.LastQuestResetTime)
end

function QuestService:GetActiveQuests(player: Player)
    if not DataService then return {}, 0 end
    
    -- Wait for session to be ready
    local session = DataService.waitForSession(player, 10)
    if not session or not session.Data then return {}, 0 end
    
    -- Generate quests if player doesn't have any or if they need to be reset
    if not session.Data.ActiveQuests or not session.Data.LastQuestResetTime then
        self:GenerateQuestsForPlayer(player)
    else
        -- Check if quests need to be reset (30 minutes have passed)
        local currentTime = os.time()
        if currentTime - session.Data.LastQuestResetTime >= RESET_INTERVAL then
            self:GenerateQuestsForPlayer(player)
        end
    end
    
    -- Build full quest data from saved quest names
    local quests = {}
    if session.Data.ActiveQuests then
        for _, questName in session.Data.ActiveQuests do
            if QuestEnums[questName] then
                table.insert(quests, {
                    Name = questName,
                    Data = QuestEnums[questName]
                })
            end
        end
    end
    
    return quests, session.Data.LastQuestResetTime or 0
end

function QuestService:GetPlayerProgress(player: Player)
    if not DataService then return {} end
    
    local session = DataService.getSession(player)
    if not session or not session.Data then return {} end
    
    return session.Data.QuestProgress or {}
end

function QuestService:UpdateProgress(player: Player, questName: string, amount: number)
    if not DataService then return 0 end
    
    local session = DataService.getSession(player)
    if not session or not session.Data then return 0 end
    
    if not session.Data.QuestProgress then
        session.Data.QuestProgress = {}
    end
    
    local progress = session.Data.QuestProgress[questName] or 0
    progress = progress + amount
    
    session.Data.QuestProgress[questName] = progress
    
    -- Fire the progress update signal to the specific player
    self.Client.ProgressUpdated:Fire(player, questName, progress)
    
    local questData = QuestEnums[questName]
    if questData and progress >= questData.Goal then
        self:CompleteQuest(player, questName)
    end
    
    return progress
end

function QuestService:CompleteQuest(player: Player, questName: string)
    local questData = QuestEnums[questName]
    if not questData or not DataService then return end
    
    -- Add cash reward
    local session = DataService.getSession(player)
    if session and session.Data then
        session.Data.Cash = session.Data.Cash + questData.Reward
        DataService:Replicate(player, "Cash")
        
        -- Reset quest progress
        if session.Data.QuestProgress then
            session.Data.QuestProgress[questName] = 0
        end
    end
end

function QuestService.Client:GetActiveQuests(player: Player)
    return self.Server:GetActiveQuests(player)
end

function QuestService.Client:GetPlayerProgress(player: Player)
    return self.Server:GetPlayerProgress(player)
end

function QuestService:KnitStart()
    -- Check all players' quests periodically
    task.spawn(function()
        while true do
            task.wait(30) -- Check every 30 seconds
            if DataService then
                for _, player in Players:GetPlayers() do
                    local session = DataService.getSession(player)
                    if session and session.Data and session.Data.LastQuestResetTime then
                        local currentTime = os.time()
                        if currentTime - session.Data.LastQuestResetTime >= RESET_INTERVAL then
                            self:GenerateQuestsForPlayer(player)
                        end
                    end
                end
            end
        end
    end)
end

function QuestService:KnitInit() 
    DataService = Knit.GetService("DataService")
end

return QuestService
