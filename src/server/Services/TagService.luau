--!strict

local CollectionService = game:GetService("CollectionService")

local TagService = {
	Name = "TagService",
	Order = 20,
}

local connections: { RBXScriptConnection } = {}

function TagService:Bind(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		)
	end
end

function TagService:Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return TagService
