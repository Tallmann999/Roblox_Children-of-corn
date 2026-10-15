-- Run on the Studio Client after a real cold Play or Retry; read-only state audit.
-- This checks URI and ownership, not the cloud texture pixels or first RenderStepped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Appearance = require(ReplicatedStorage.GameShared.Game.CornAppearance)
local map = assert(Workspace:FindFirstChild("CornMap"), "CornMap missing")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong CornMap project")
assert(
	not Workspace:FindFirstChild("Asmr_Base") and not Workspace:FindFirstChild("ASMR_Models"),
	"Another game is open"
)
local art = assert(ReplicatedStorage:FindFirstChild("CornRuntimeArt"))
assert(art:GetAttribute("CornRuntimeArtOwned") == true, "Runtime art ownership missing")
assert(art:GetAttribute("corn_project_id") == "children_of_corn", "Runtime art project missing")
local template = assert(art:FindFirstChild("CornPlantTemplate"))
assert(template:IsA("MeshPart") and template.MeshId == Appearance.MeshId, "Unexpected corn mesh")
assert(template.TextureID == Appearance.DryTextureId, "Published template is green")
assert(template:GetAttribute("CornPlantTemplateOwned") == true, "Template ownership missing")
local report = { status = "PASS", prepared = template.TextureID, roots = {} }
for _, name in { "EditorFieldOverview", "EditorPreview", "CornClientPlants", "CornClientBackdrop" } do
	local folder = map:FindFirstChild(name)
	if folder then
		assert(folder:IsA("Folder"), name .. " is not a Folder")
		assert(
			folder:GetAttribute("corn_project_id") == "children_of_corn",
			name .. " project missing"
		)
		local count = 0
		for _, part in folder:GetDescendants() do
			if part:IsA("MeshPart") and part.MeshId == Appearance.MeshId then
				assert(
					not part:FindFirstChildWhichIsA("SurfaceAppearance"),
					"Unexpected SurfaceAppearance: " .. part:GetFullName()
				)
				assert(
					part.TextureID == Appearance.DryTextureId,
					"Non-yellow corn: " .. part:GetFullName()
				)
				count += 1
			end
		end
		report.roots[name] = count
	end
end
assert(
	report.roots.EditorFieldOverview and report.roots.EditorFieldOverview > 0,
	"Saved overview empty"
)
assert(report.roots.CornClientPlants and report.roots.CornClientPlants > 0, "Near plants empty")
assert(
	report.roots.CornClientBackdrop and report.roots.CornClientBackdrop > 0,
	"Backdrop plants empty"
)
return report
