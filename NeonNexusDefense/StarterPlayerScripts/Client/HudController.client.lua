--!strict
-- HudController.client.lua — HUD: золото, HP ядра, волна, таймер, кнопка early-call.
-- StarterPlayerScripts.Client.HudController (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaveEvents = Remotes:WaitForChild("WaveEvents") :: RemoteEvent
local EconomyUpdate = Remotes:WaitForChild("EconomyUpdate") :: RemoteEvent
local RequestWaveStart = Remotes:WaitForChild("RequestWaveStart") :: RemoteFunction

---------------------------------------------------------------------------
-- Построение UI кодом (в проде лучше класть ScreenGui в StarterGui и искать через Wait)
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "NND_Hud"
gui.ResetOnSpawn = false
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local function makeLabel(name: string, text: string, pos: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Size = UDim2.new(0, 220, 0, 34)
	l.Position = pos
	l.BackgroundColor3 = Color3.fromRGB(15, 18, 30)
	l.BackgroundTransparency = 0.25
	l.TextColor3 = Color3.fromRGB(0, 255, 200) -- neon
	l.Font = Enum.Font.Code
	l.TextSize = 18
	l.Parent = gui
	return l
end

local goldLabel = makeLabel("Gold", "💰 0", UDim2.new(0, 16, 0, 16))
local waveLabel = makeLabel("Wave", "Wave: —", UDim2.new(0, 16, 0, 54))
local timerLabel = makeLabel("Timer", "", UDim2.new(0, 16, 0, 92))

local earlyBtn = Instance.new("TextButton")
earlyBtn.Name = "EarlyCall"
earlyBtn.Text = "⚡ START WAVE (+25g)"
earlyBtn.Size = UDim2.new(0, 200, 0, 40)
earlyBtn.Position = UDim2.new(0, 16, 0, 130)
earlyBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 90)
earlyBtn.TextColor3 = Color3.new(1, 1, 1)
earlyBtn.Visible = false
earlyBtn.Parent = gui

---------------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------------
local gold = 0

EconomyUpdate.OnClientEvent:Connect(function(kind: string, amount: number)
	if kind == "set" then
		gold = amount
	elseif kind == "+kill" or kind == "+waveBonus" or kind == "+earlyCall" then
		gold += amount
	end
	goldLabel.Text = `💰 {gold}`
end)

WaveEvents.OnClientEvent:Connect(function(event: string, a: number?, _b: number?)
	if event == "waveStarted" then
		waveLabel.Text = `Wave: {a} ⚔️`
		timerLabel.Text = ""
		earlyBtn.Visible = false
	elseif event == "countdown" then
		timerLabel.Text = `Следующая волна: {a}с`
		earlyBtn.Visible = true
	elseif event == "waveCompleted" then
		waveLabel.Text = `Wave {a} cleared! +{_b}g`
	elseif event == "gameOver" then
		timerLabel.Text = `☠ CORE BREACHED at wave {a}`
		earlyBtn.Visible = false
	end
end)

earlyBtn.Activated:Connect(function()
	local ok = RequestWaveStart:InvokeServer()
	if ok then
		earlyBtn.Visible = false
		timerLabel.Text = "Волна вызвана досрочно!"
	end
end)
