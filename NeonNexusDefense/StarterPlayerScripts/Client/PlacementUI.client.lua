--!strict
-- PlacementUI.client.lua — выбор клетки и башни, «призрак», отправка намерений серверу.
-- Клиент НИКОГДА не решает сам, можно ли строить: он лишь шлёт (kind, cellId),
-- сервер валидирует (Main.server.lua). Призрак — чисто визуальный фидбек.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("Types"))
local localPlayer = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("Config"))
local TowerActions = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerActions") :: RemoteEvent

---------------------------------------------------------------------------
-- Панель выбора башни (упрощённо — 4 кнопки)
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "NND_Build"
gui.ResetOnSpawn = false
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Size = UDim2.new(0, 440, 0, 70)
bar.Position = UDim2.new(0.5, -220, 1, -90)
bar.BackgroundColor3 = Color3.fromRGB(12, 14, 24)
bar.Parent = gui

local selectedKind: Types.TowerKind? = nil

local x = 4
for _, kind in { "Pulse", "Mortar", "Cryo", "Railgun" } do
	local stats = Config.TOWERS[kind]
	local btn = Instance.new("TextButton")
	btn.Name = kind
	btn.Text = `{kind}\n{stats.cost}g`
	btn.Size = UDim2.new(0, 105, 0, 62)
	btn.Position = UDim2.new(0, x, 0, 4)
	btn.BackgroundColor3 = Color3.fromRGB(30, 36, 60)
	btn.TextColor3 = Color3.fromRGB(0, 230, 255)
	btn.AutoButtonColor = true
	btn.Parent = bar
	x += 110

	btn.Activated:Connect(function()
		selectedKind = kind :: Types.TowerKind
		for _, sib in bar:GetChildren() do
			if sib:IsA("TextButton") then
				sib.BackgroundColor3 = if sib == btn
					then Color3.fromRGB(0, 120, 100) else Color3.fromRGB(30, 36, 60)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Raycast по сетке + призрак
---------------------------------------------------------------------------
local ghost: Model? = nil
local currentCell: BasePart? = nil

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function refreshGhost()
	local mousePos = UserInputService:GetMouseLocation()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local ray = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)

	currentCell = nil
	if hit and hit.Instance.Name:match("^Cell_") and selectedKind then
		currentCell = hit.Instance
		if not ghost then
			ghost = (ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Towers")
				:WaitForChild(selectedKind) :: Model):Clone()
			for _, p in ghost:GetDescendants() do
				if p:IsA("BasePart") then
					p.Transparency = 0.5
					p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
				end
			end
			ghost.Parent = workspace
		end
		ghost:PivotTo(currentCell.CFrame)
	else
		if ghost then ghost:Destroy(); ghost = nil end
	end
end

RunService.RenderStepped:Connect(refreshGhost)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if selectedKind and currentCell then
		-- отправляем НАМЕРЕНИЕ; сервер проверит деньги/дальность/занятость
		TowerActions:FireServer("buy", selectedKind, currentCell.Name)
	end
end)
