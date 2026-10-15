--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))
local CornAppearance = require(GameShared:WaitForChild("Game"):WaitForChild("CornAppearance"))

local CornField = {}
local PROJECT_ID = "children_of_corn"
local OWNER_ATTRIBUTE = "CornRuntimeArtOwned"

function CornField.Prepare(): boolean
	if
		not RunService:IsStudio()
		or Config.Environment ~= "DEV"
		or (Config.Game.SessionMode ~= "solo_local" and Config.Game.SessionMode ~= "team_local")
	then
		return false
	end
	local sources: { Instance } = {}
	for _, item in ServerStorage:GetChildren() do
		if item.Name == "CornPlantTemplate" or item.Name == "SM_Prop_Plant_Corn_01_L" then
			table.insert(sources, item)
		end
	end
	if #sources ~= 1 then
		warn(
			"[CornField] Expected exactly one ServerStorage CornPlantTemplate or SM_Prop_Plant_Corn_01_L art source"
		)
		return false
	end
	local prepared, problem = CornLayout.PrepareTemplate(sources[1])
	if not prepared then
		warn("[CornField] " .. (problem or "Could not prepare corn art"))
		return false
	end
	if
		not prepared:IsA("MeshPart")
		or prepared.MeshId ~= CornAppearance.MeshId
		or (prepared.TextureID ~= CornAppearance.GreenTextureId and prepared.TextureID ~= CornAppearance.DryTextureId)
		or prepared:FindFirstChildWhichIsA("SurfaceAppearance")
	then
		prepared:Destroy()
		warn("[CornField] Unknown corn appearance; existing prepared art was preserved")
		return false
	end
	-- Both renderers inherit yellow before the template can replicate or be cloned.
	prepared.TextureID = CornAppearance.DryTextureId
	local folder: Instance? = nil
	for _, item in ReplicatedStorage:GetChildren() do
		if item.Name == "CornRuntimeArt" then
			if folder then
				prepared:Destroy()
				warn(
					"[CornField] Duplicate CornRuntimeArt containers; existing contents were preserved"
				)
				return false
			end
			folder = item
		end
	end
	if
		folder
		and (
			not folder:IsA("Folder")
			or folder:GetAttribute(OWNER_ATTRIBUTE) ~= true
			or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
		)
	then
		prepared:Destroy()
		warn("[CornField] Refused to overwrite an unowned CornRuntimeArt container")
		return false
	end
	if folder then
		for _, item in folder:GetChildren() do
			if
				item.Name == "CornPlantTemplate"
				and item:GetAttribute("CornPlantTemplateOwned") ~= true
			then
				prepared:Destroy()
				warn("[CornField] Refused to overwrite unowned CornPlantTemplate art")
				return false
			end
		end
	else
		folder = Instance.new("Folder")
		folder.Name = "CornRuntimeArt"
		folder:SetAttribute(OWNER_ATTRIBUTE, true)
		folder:SetAttribute("corn_project_id", PROJECT_ID)
	end
	prepared.Name = "CornPlantTemplate"
	prepared:SetAttribute("CornPlantTemplateOwned", true)
	prepared:SetAttribute("CornPlantHeight", CornLayout.Height)
	for _, item in folder:GetChildren() do
		if
			item.Name == "CornPlantTemplate"
			and item:GetAttribute("CornPlantTemplateOwned") == true
		then
			item:Destroy()
		end
	end
	prepared.Parent = folder
	folder.Parent = ReplicatedStorage
	print("[CornField] Prepared a corn art clone; ServerStorage source is unchanged")
	return true
end

return CornField
