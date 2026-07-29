local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local Types = require(Shared.Types)

local DataService

local DataController = Knit.CreateController({
	Name = "DataController",
})

function DataController.waitForData(): Types.Data
	while not DataController.getData() do
		task.wait()
	end
	return DataController.getData()
end

function DataController.getData(): Types.Data?
	return DataController._cache
end

function DataController.reconcileTables(target, template)
	if type(target) ~= "table" or type(template) ~= "table" then
		return template
	end

	for key in pairs(target) do
		if template[key] == nil then
			target[key] = nil
		end
	end

	for key, value in pairs(template) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			target[key] = DataController.reconcileTables(target[key], value)
		else
			if target[key] ~= value then
				target[key] = value
			end
		end
	end

	return target
end

function DataController.onReplicated(checkIndex: (string | { string })?)
	return {
		Connect = function(_, callback: () -> any)
			return DataController._onReplicate:Connect(function(index: string?)
				if not checkIndex then
					callback()
				else
					local valid = if type(checkIndex) == "table" then table.find(checkIndex, index) else index == checkIndex
					if valid then
						callback()
					end
				end
			end)
		end,
	}
end

function DataController.onReplicate(data: { [string]: any }, index: string?)
	if not DataController._cache then
		DataController._cache = {}
	end

	if not index then
		DataController._cache = data
		if data.Shop then
			DataController._onReplicate:Fire("Shop")
		end
		return
	end

	if type(data) == "table" then
		for key, value in pairs(data) do
			if type(value) == "table" and type(DataController._cache[key]) == "table" then
				DataController._cache[key] = DataController.reconcileTables(DataController._cache[key], value)
			else
				DataController._cache[key] = value
			end
		end
	end

	if index then
		DataController._onReplicate:Fire(index)
		if index == "Shop" then
			task.defer(function()
				DataController._onReplicate:Fire("Perks")
			end)
		end
	end
end

function DataController:KnitStart()
	DataService.ReplicateData:Connect(function(data, index)
		self.onReplicate(data, index)
	end)
end

function DataController:KnitInit()
	self._cache = nil
	self._onReplicate = Signal.new()
	DataService = Knit.GetService("DataService")
end

return DataController
