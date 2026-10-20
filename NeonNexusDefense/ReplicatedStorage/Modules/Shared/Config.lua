--!strict
-- Config.lua — единый источник баланса (ReplicatedStorage.Modules.Shared).
-- Сервер и клиент require-ят один модуль => цифры всегда синхронны.

local Types = require(script.Parent.Types)

local Config = {
	GAME = {
		STARTING_GOLD = 300,
		CORE_HP = 20,
		TOTAL_WAVES = 30,
		INTERMISSION_TIME = 15,
		EARLY_CALL_BONUS = 25,
		WAVE_BONUS_BASE = 50,
		WAVE_BONUS_PER_WAVE = 10,
		INTEREST_RATE = 0.05,
		INTEREST_CAP = 150,
		SELL_REFUND_RATIO = 0.6,
		TOWER_TICK_HZ = 10,          -- частота тика башен (сек 0.1)
		MOVE_TICK_DT = 1 / 30,       -- серверный цикл движения врагов
	},

	-- Множители сложности по номеру волны
	SCALING = {
		hp = function(wave: number): number
			return 1 + 0.18 * wave + 0.006 * wave ^ 2
		end,
		speed = function(wave: number): number
			return math.min(1 + 0.012 * wave, 1.45)
		end,
		reward = function(wave: number): number
			return 1 + 0.02 * wave
		end,
	},

	ENEMIES = {
		Runner = { health = 45, speed = 12, reward = 8, flying = false, coreDamage = 1, slowResist = 0 } :: Types.EnemyStats,
		Golem  = { health = 320, speed = 4.5, reward = 25, flying = false, coreDamage = 2, slowResist = 0.5 } :: Types.EnemyStats,
		Drone  = { health = 90, speed = 9, reward = 15, flying = true, coreDamage = 1, slowResist = 0 } :: Types.EnemyStats,
		Boss   = { health = 2560, speed = 3.5, reward = 200, flying = false, coreDamage = 5, slowResist = 0.8 } :: Types.EnemyStats,
	} :: { [Types.EnemyKind]: Types.EnemyStats },

	TOWERS = {
		Pulse = { cost = 100, damage = 22, cooldown = 0.6, range = 16, splashRadius = 0,
		          slowPercent = 0, slowDuration = 0, pierce = 0, defaultTarget = "First",
		          hitscan = false, canHitAir = true } :: Types.TowerStats,
		Mortar = { cost = 250, damage = 35, cooldown = 1.6, range = 20, splashRadius = 6,
		          slowPercent = 0, slowDuration = 0, pierce = 0, defaultTarget = "First",
		          hitscan = false, canHitAir = false } :: Types.TowerStats,
		Cryo = { cost = 180, damage = 8, cooldown = 0.9, range = 14, splashRadius = 0,
		          slowPercent = 0.45, slowDuration = 2, pierce = 0, defaultTarget = "Strongest",
		          hitscan = false, canHitAir = true } :: Types.TowerStats,
		Railgun = { cost = 400, damage = 180, cooldown = 2.8, range = 34, splashRadius = 0,
		          slowPercent = 0, slowDuration = 0, pierce = 1, defaultTarget = "Strongest",
		          hitscan = true, canHitAir = true } :: Types.TowerStats,
	} :: { [Types.TowerKind]: Types.TowerStats },

	UPGRADE = {
		DAMAGE_MULT = 1.75,
		RANGE_MULT = 1.10,
		COOLDOWN_MULT = 0.90,
		COST_RATIOS = { 0.7, 1.2 }, -- цена апгрейда до L2 и L3 от базы
		MAX_LEVEL = 3,
	},
}

return Config
