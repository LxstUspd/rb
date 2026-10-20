--!strict
-- WaveManager.server.lua — генератор волн, спавн врагов, цикл движения и начисление наград.
-- ServerScriptService.Server.WaveManager
--
-- Поток данных:
--   WaveManager --spawn--> Enemy (через класс Enemy) + registry[part] = enemy
--   Movement loop (1 цикл на 30 Гц для ВСЕХ врагов; не Heartbeat на врага!)
--   Смерть -> EconomyManager.awardKill(ownerless: shared co-op pool) -> gold
--   Дошёл до конца -> урон ядру; все группы отработаны и поле пусто -> waveCompleted

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Shared = Modules:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local EnemyModule = require(Modules:WaitForChild("Enemy"):WaitForChild("Enemy"))
local ProjectileModule = require(Modules:WaitForChild("Projectile"):WaitForChild("Projectile"))

type EnemyKind = Types.EnemyKind
type WaypointData = EnemyModule.WaypointData
type Enemy = EnemyModule.Enemy

local Server = ServerScriptService:WaitForChild("Server")
local PathRuntime = require(Server:WaitForChild("PathRuntime"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaveEvents = Remotes:WaitForChild("WaveEvents") :: RemoteEvent
local EconomyUpdate = Remotes:WaitForChild("EconomyUpdate") :: RemoteEvent
local RequestWaveStart = Remotes:WaitForChild("RequestWaveStart") :: RemoteFunction

---------------------------------------------------------------------------
-- Состояние
---------------------------------------------------------------------------
local activeEnemies: { [Enemy]: boolean } = {}      -- множество живых объектов
local partRegistry: { [BasePart]: Enemy } = {}      -- part -> Enemy (для башен/AoE)
local projectiles: { ProjectileModule.Projectile } = {}

local currentWave = 0
local inIntermission = true
local coreHP = Config.GAME.CORE_HP
local gameOver = false

local runtimeFolder = workspace:WaitForChild("Runtime")
local enemyStorage = runtimeFolder:WaitForChild("EnemyPool")   -- неактивные модели
local enemyArchetypes = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Enemies")

-- Пул моделей врагов: переиспользуем вместо Clone/Destroy каждый спавн
local PoolModule = require(Modules:WaitForChild("Projectile"):WaitForChild("Pool"))
local enemyPools: { [EnemyKind]: PoolModule.Pool } = {}
for kind, _ in Config.ENEMIES :: { [EnemyKind]: any } do
	local archetype = enemyArchetypes:FindFirstChild(kind) :: Model?
	if archetype then
		enemyPools[kind] = PoolModule.new(archetype, enemyStorage, 40)
		enemyPools[kind]:prefill(20)
	end
end

---------------------------------------------------------------------------
-- Генерация состава волны (процедурно по правилам GDD)
---------------------------------------------------------------------------
local function buildWave(wave: number): Types.WaveDefinition
	local groups: { Types.WaveGroup } = {}

	table.insert(groups, {
		kind = "Runner",
		count = 6 + math.floor(wave * 1.8),
		interval = math.max(0.35, 1.1 - wave * 0.02),
		startDelay = 0,
	})
	if wave >= 4 then
		table.insert(groups, {
			kind = "Golem",
			count = 2 + math.floor((wave - 4) / 3),
			interval = 2.2,
			startDelay = 4,
		})
	end
	if wave >= 7 then
		table.insert(groups, {
			kind = "Drone",
			count = 3 + math.floor((wave - 7) / 2),
			interval = 0.9,
			startDelay = 8,
		})
	end
	if wave % 10 == 0 then -- каждая 10-я волна — босс
		table.insert(groups, { kind = "Boss", count = wave // 10, interval = 12, startDelay = 10 })
	end

	return { groups = groups }
end

---------------------------------------------------------------------------
-- Спавн/смерть
---------------------------------------------------------------------------
local function despawnEnemy(enemy: Enemy, killedByTower: boolean)
	activeEnemies[enemy] = nil
	partRegistry[enemy.humanoidRoot] = nil
	enemy:destroy()

	if killedByTower then
		-- Награда делится на всех игроков (co-op общий банк волны)
		local reward = math.floor(enemy.reward * Config.SCALING.reward(currentWave))
		for _, player in Players:GetPlayers() do
			EconomyUpdate:FireClient(player, "+kill", reward)
		end
	end

	local pool = enemyPools[enemy.kind]
	if pool then
		pool:release(enemy.model)
	else
		enemy.model:Destroy()
	end
end

local function spawnEnemy(kind: EnemyKind)
	local path: WaypointData = PathRuntime.getPath()
	local pool = enemyPools[kind]
	local model = if pool then pool:get() else nil
	if not model then
		model = (enemyArchetypes:FindFirstChild(kind) :: Model):Clone()
	end

	local enemy = EnemyModule.new(kind, currentWave, path, model, runtimeFolder)
	activeEnemies[enemy] = true
	partRegistry[enemy.humanoidRoot] = enemy
end

---------------------------------------------------------------------------
-- Циклы: движение врагов + снаряды (ОДИН цикл на систему, не на сущность)
---------------------------------------------------------------------------
task.spawn(function()
	local dt = Config.GAME.MOVE_TICK_DT
	while not gameOver do
		task.wait(dt)

		-- движение
		for enemy in activeEnemies do
			enemy:update(dt)
			if not enemy.alive then
				if enemy.reachedEnd then
					coreHP -= enemy.coreDamage
					warn(`[WaveManager] Core hit! HP={coreHP}`)
					despawnEnemy(enemy, false)
				else
					despawnEnemy(enemy, true) -- умер от урона башни
				end
			end
		end

		-- снаряды
		local i = 1
		while i <= #projectiles do
			if projectiles[i]:update(dt) then
				table.remove(projectiles, i)
			else
				i += 1
			end
		end

		if coreHP <= 0 then
			gameOver = true
			WaveEvents:FireAllClients("gameOver", currentWave)
		end
	end
end)

-- Реестр part->enemy публикуем для TowerSystem (другой скрипт читает через эту таблицу)
_G.NND_partRegistry = partRegistry -- TODO: в проде заменить на Dependency Injection через Main

---------------------------------------------------------------------------
-- Волновой цикл
---------------------------------------------------------------------------
local function runWave(wave: number)
	currentWave = wave
	inIntermission = false
	WaveEvents:FireAllClients("waveStarted", wave)

	local definition = buildWave(wave)

	-- параллельные группы спавна
	local threadsRemaining = 0
	for _, group in definition.groups do
		threadsRemaining += 1
		task.spawn(function()
			task.delay(group.startDelay, function()
				for _ = 1, group.count do
					if gameOver then break end
					spawnEnemy(group.kind :: EnemyKind)
					task.wait(group.interval)
				end
				threadsRemaining -= 1
			end)
		end)
	end

	-- ждём: все заспавнены и все зачищены
	while threadsRemaining > 0 and not gameOver do
		task.wait(0.2)
	end
	repeat
		local aliveCount = 0
		for _ in activeEnemies do aliveCount += 1 end
		task.wait(0.25)
	until aliveCount == 0 or gameOver

	if gameOver then return end

	-- бонус за волну + interest
	local bonus = Config.GAME.WAVE_BONUS_BASE + wave * Config.GAME.WAVE_BONUS_PER_WAVE
	for _, player in Players:GetPlayers() do
		EconomyUpdate:FireClient(player, "+waveBonus", bonus)
	end
	WaveEvents:FireAllClients("waveCompleted", wave, bonus)
end

local function intermission(seconds: number)
	inIntermission = true
	for t = seconds, 1, -1 do
		if gameOver then return end
		WaveEvents:FireAllClients("countdown", t)
		task.wait(1)
	end
end

-- Early call: клиент просит начать волну досрочно (только во время intermission)
RequestWaveStart.OnServerInvoke = function(player: Player)
	if not inIntermission or gameOver then return false end
	EconomyUpdate:FireClient(player, "+earlyCall", Config.GAME.EARLY_CALL_BONUS)
	return true
end

-- Главный игровой луп
task.spawn(function()
	PathRuntime.precompute() -- читаем Waypoints один раз при старте
	ProjectileModule.initPool(
		ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Projectiles"):WaitForChild("Bolt") :: Model,
		runtimeFolder:WaitForChild("ProjectilePool")
	)

	intermission(5) -- короткая пауза на билд перед волной 1
	local wave = 1
	while not gameOver do
		runWave(wave)
		if gameOver then break end
		if wave >= Config.GAME.TOTAL_WAVES and wave % 10 ~= 0 then
			-- endless-режим после 30 волн продолжается бесконечно
		end
		intermission(Config.GAME.INTERMISSION_TIME)
		wave += 1
	end
end)
