--!strict
-- Main.server.lua — bootstrap: создаёт Remotes, папки Runtime, запускает системы.
-- ВАЖНО: WaveManager требует существующие RemoteEvents, поэтому они создаются ЗДЕСЬ,
-- до require(WaveManager). В проде можно задать их прямо в Studio через Explorer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------------------------------------------------------------------
-- 1. Remotes (Folder ReplicatedStorage.Remotes)
---------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local function ensureRemote(name: string, className: string): Instance
	local existing = remotesFolder:FindFirstChild(name)
	if existing then return existing end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = remotesFolder
	return inst
end

ensureRemote("TowerActions", "RemoteEvent")     -- C->S: buy/upgrade/sell/setTarget
ensureRemote("WaveEvents", "RemoteEvent")       -- S->All: waveStarted/completed/countdown/gameOver
ensureRemote("EconomyUpdate", "RemoteEvent")    -- S->C: золотые события (только владельцу)
ensureRemote("EnemyFX", "RemoteEvent")          -- S->All: визуальные события
ensureRemote("RequestWaveStart", "RemoteFunction") -- C->S: early call

---------------------------------------------------------------------------
-- 2. Runtime-папки (Workspace)
---------------------------------------------------------------------------
local runtime = workspace:FindFirstChild("Runtime") or Instance.new("Folder")
runtime.Name = "Runtime"
runtime.Parent = workspace

for _, sub in { "EnemyPool", "ProjectilePool", "Towers" } do
	if not runtime:FindFirstChild(sub) then
		local f = Instance.new("Folder")
		f.Name = sub
		f.Parent = runtime
	end
end

---------------------------------------------------------------------------
-- 3. Экономика (общий co-op банк; серверный авторитет)
---------------------------------------------------------------------------
local EconomyManager = {}
EconomyManager.gold = 0 :: number

local TowerActions = remotesFolder:WaitForChild("TowerActions") :: RemoteEvent
local EconomyUpdate = remotesFolder:WaitForChild("EconomyUpdate") :: RemoteEvent

local function broadcastGold()
	for _, player in game:GetService("Players"):GetPlayers() do
		EconomyUpdate:FireClient(player, "set", EconomyManager.gold)
	end
end

game:GetService("Players").PlayerAdded:Connect(function()
	task.delay(0.5, broadcastGold) -- отдать текущий баланс новому игроку
end)

EconomyUpdate.OnServerEvent:Connect(function(_player, kind: string, amount: number)
	-- этот канал используется ТОЛЬКО сервером на запись; входящие игнорируем (анти-exploit)
end)

-- Реальный источник начислений — вызовы из WaveManager идут через FireClient выше;
-- для однопользовательского банка слушаем собственный сигнал:
local function award(amount: number)
	EconomyManager.gold += amount
	broadcastGold()
end
local function trySpend(amount: number): boolean
	if EconomyManager.gold < amount then return false end
	EconomyManager.gold -= amount
	broadcastGold()
	return true
end

---------------------------------------------------------------------------
-- 4. Башни: реестр клеток + обработка действий клиента с полной валидацией
---------------------------------------------------------------------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Shared"):WaitForChild("Config"))
local Types = require(Modules:WaitForChild("Shared"):WaitForChild("Types"))
local TowerModule = require(Modules:WaitForChild("Tower"):WaitForChild("Tower"))

type TowerKind = Types.TowerKind

local towersByCell: { [string]: TowerModule.Tower } = {}
local towerArchetypes = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Towers")
local towersFolder = runtime:WaitForChild("Towers")

-- rate-limit против спама запросами
local lastActionAt: { [number]: number } = {}
local function rateLimited(userId: number): boolean
	local now = os.clock()
	if now - (lastActionAt[userId] or 0) < 0.15 then return true end
	lastActionAt[userId] = now
	return false
end

TowerActions.OnServerEvent:Connect(function(player: Player, action: string, ...)
	if rateLimited(player.UserId) then return end
	local args = { ... }

	if action == "buy" then
		local kind, cellId = args[1] :: TowerKind, args[2] :: string
		local cell = workspace:FindFirstChild("BuildGrid"):FindFirstChild(cellId)
		if not cell then return end                                  -- клетки с таким id нет
		if towersByCell[cellId] then return end                      -- клетка занята
		if (cell.Position - player.Character:GetPivot().Position).Magnitude > 60 then
			return                                                   -- слишком далеко от строителя
		end
		local cost = Config.TOWERS[kind].cost
		if not trySpend(cost) then return end                        -- не хватает золота

		local archetype = towerArchetypes:FindFirstChild(kind) :: Model?
		if not archetype then return end
		local model = archetype:Clone()
		model:PivotTo(cell.CFrame)
		model.Parent = towersFolder

		local tower = TowerModule.new(kind, model, cellId, player.UserId)
		tower.totalInvested = cost
		towersByCell[cellId] = tower

	elseif action == "upgrade" then
		local cellId = args[1] :: string
		local tower = towersByCell[cellId]
		if not tower then return end
		local cost = tower:getUpgradeCost()
		if cost and trySpend(cost) then
			tower:upgrade()
		end

	elseif action == "sell" then
		local cellId = args[1] :: string
		local tower = towersByCell[cellId]
		if not tower then return end
		award(math.floor(tower.totalInvested * Config.GAME.SELL_REFUND_RATIO))
		towersByCell[cellId] = nil
		tower.model:Destroy()

	elseif action == "setTarget" then
		local cellId, mode = args[1] :: string, args[2] :: Types.TargetMode
		local tower = towersByCell[cellId]
		if tower and (mode == "First" or mode == "Last" or mode == "Strongest" or mode == "Weakest") then
			tower.targetMode = mode
		end
	end
end)

---------------------------------------------------------------------------
-- 5. TowerSystem: тик всех башен 10 Гц (registry даёт WaveManager)
---------------------------------------------------------------------------
task.spawn(function()
	-- ждём появления реестра от WaveManager
	local registry: { [BasePart]: any }? = nil
	repeat
		task.wait(0.5)
		registry = _G.NND_partRegistry
	until registry ~= nil

	while true do
		task.wait(1 / Config.GAME.TOWER_TICK_HZ)
		for _, tower in towersByCell do
			tower:tick(1 / Config.GAME.TOWER_TICK_HZ, registry :: any)
		end
	end
end)

---------------------------------------------------------------------------
-- 6. Запуск волновой системы
---------------------------------------------------------------------------
require(script:WaitForChild("WaveManager"))
print("[NND] Server bootstrap complete")
