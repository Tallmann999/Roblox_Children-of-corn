--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {
	Name = "NetworkService",
	Order = 10,
}

local root: Folder

function NetworkService:Init(_context: any)
	local existing = ReplicatedStorage:FindFirstChild("GameRemotes")
	if existing and not existing:IsA("Folder") then
		error("ReplicatedStorage.GameRemotes exists but is not a Folder")
	end
	if existing then
		root = existing
	else
		root = Instance.new("Folder")
		root.Name = "GameRemotes"
		root.Parent = ReplicatedStorage
	end
end

function NetworkService:GetEvent(name: string): RemoteEvent
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s is not a RemoteEvent", name))
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = root
	return event
end

function NetworkService:GetFunction(name: string): RemoteFunction
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteFunction"), string.format("%s is not a RemoteFunction", name))
		return existing
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = root
	return fn
end

return NetworkService
