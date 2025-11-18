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
local completedQuests = {}

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
    
    local killerQuest = getRandomQuest("Killer")
    if killerQuest then
        table.insert(questNames, killerQuest)
    end
    
    local survivorQuest = getRandomQuest("Survivor")
    if survivorQuest then
        table.insert(questNames, survivorQuest)
    end
    
    local allQuestNames = {}
    for questName, _ in pairs(QuestEnums) do
        if not table.find(questNames, questName) then
            table.insert(allQuestNames, questName)
        end
    end
    
    if #allQuestNames > 0 then
        local randomQuestName = allQuestNames[math.random(#allQuestNames)]
        table.insert(questNames, randomQuestName)
    end
    
    local uniqueQuestNames = {}
    local seen = {}
    for _, questName in ipairs(questNames) do
        if not seen[questName] then
            seen[questName] = true
            table.insert(uniqueQuestNames, questName)
        end
    end
    questNames = uniqueQuestNames
    
    session.Data.ActiveQuests = questNames
    session.Data.LastQuestResetTime = os.time()
    session.Data.QuestProgress = {}
    
    local quests = {}
    for _, questName in questNames do
        table.insert(quests, {
            Name = questName,
            Data = QuestEnums[questName]
        })
    end
    
    self.Client.QuestsUpdated:Fire(player, quests, session.Data.LastQuestResetTime)
end

function QuestService:GetActiveQuests(player: Player)
    if not DataService then return {}, 0 end
    
    local session = DataService.waitForSession(player, 10)
    if not session or not session.Data then return {}, 0 end
    
    if not session.Data.ActiveQuests or not session.Data.LastQuestResetTime then
        self:GenerateQuestsForPlayer(player)
    else
        local currentTime = os.time()
        if currentTime - session.Data.LastQuestResetTime >= RESET_INTERVAL then
            self:GenerateQuestsForPlayer(player)
        end
    end
    
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
    
    self.Client.ProgressUpdated:Fire(player, questName, progress)
    
    local questData = QuestEnums[questName]
    local completionKey = player.UserId .. "_" .. questName
    if questData and progress >= questData.Goal and not completedQuests[completionKey] then
        completedQuests[completionKey] = true
        self:CompleteQuest(player, questName)
    end
    
    return progress
end

function QuestService:ResetCompletionTracking()
    table.clear(completedQuests)
end

function QuestService:CompleteQuest(player: Player, questName: string)
    local questData = QuestEnums[questName]
    if not questData or not DataService then return end
    
    local session = DataService.getSession(player)
    if session and session.Data then
        if not session.Data.Cash then
            session.Data.Cash = 0
        end
        session.Data.Cash = session.Data.Cash + questData.Reward
        DataService:Replicate(player, "Cash")
    end
end

function QuestService.Client:GetActiveQuests(player: Player)
    return self.Server:GetActiveQuests(player)
end

function QuestService.Client:GetPlayerProgress(player: Player)
    return self.Server:GetPlayerProgress(player)
end

function QuestService:KnitStart()
    task.spawn(function()
        while true do
            task.wait(30)
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
