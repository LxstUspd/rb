--!strict
-- Types.lua — общие типы для Neon Nexus Defense (ReplicatedStorage.Modules.Shared)

export type EnemyKind = "Runner" | "Golem" | "Drone" | "Boss"
export type TowerKind = "Pulse" | "Mortar" | "Cryo" | "Railgun"
export type TargetMode = "First" | "Last" | "Strongest" | "Weakest"

export type EnemyStats = {
	health: number,
	speed: number,          -- studs/sec
	reward: number,         -- базовое золото
	flying: boolean,        -- игнорирует ground-only таргетинг Mortar
	coreDamage: number,     -- урон ядру при доходе
	slowResist: number,     -- 0..1, доля иммунитета к замедлению
}

export type TowerStats = {
	cost: number,
	damage: number,
	cooldown: number,       -- сек между выстрелами
	range: number,          -- studs
	splashRadius: number,   -- 0 = без AoE
	slowPercent: number,    -- 0 = не стадит
	slowDuration: number,
	pierce: number,         -- снайпер: доп. цели на линии
	defaultTarget: TargetMode,
	hitscan: boolean,
	canHitAir: boolean,
}

export type WaveGroup = {
	kind: EnemyKind,
	count: number,
	interval: number,       -- сек между спавнами в группе
	startDelay: number,     -- запуск группы относительно начала волны
}

export type WaveDefinition = {
	groups: {WaveGroup},
}

return {
	EnemyKind = nil :: any, -- type-only placeholder (не используется в рантайме)
}
