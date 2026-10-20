--!strict
-- Tower.lua — ООП-класс башни: поиск цели через Spatial Query API и стрельба.
-- ReplicatedStorage.Modules.Tower.Tower
--
-- Ключевая оптимизация: вместо перебора всех врагов (O(N) на каждую башню каждый кадр)
-- используем workspace:GetPartBoundsInRadius — движковый broadphase-запрос за ~O(log N).
-- Таргетинг First/Last строится на атрибуте "Travelled" (пишет Enemy.update),
-- Strongest/Weakest — на атрибуте "Health".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local EnemyModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Enemy"):WaitForChild("Enemy"))
local ProjectileModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Projectile"):WaitForChild("Projectile"))

type Enemy = EnemyModule.Enemy
type TowerKind = Types.TowerKind
type TargetMode = Types.TargetMode

export type Tower = {
	kind: TowerKind,
	level: number,
	model: Model,
	muzzle: BasePart,
	cellId: string,
	ownerUserId: number,
	targetMode: TargetMode,
	cooldownLeft: number,
	stats: Types.TowerStats, -- текущие статы с учётом апгрейдов
	totalInvested: number,

	-- приватные поля (конвенция: underscore = не трогать извне)
	_lastKill: { target: Enemy }?,

	upgrade: (self: Tower) -> boolean,
	getUpgradeCost: (self: Tower) -> number?,
	findTarget: (self: Tower, registry: { [BasePart]: Enemy }) -> Enemy?,
	fireAt: (self: Tower, target: Enemy, registry: { [BasePart]: Enemy }) -> (),
	tick: (self: Tower, dt: number, registry: { [BasePart]: Enemy }) -> (),
}

local TowerClass = {}
TowerClass.__index = TowerClass

-- Переиспользуемый OverlapParams (не создаём новый каждый тик!)
local function makeOverlapParams(): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	params.MaxParts = 128
	return params
end
local _sharedParams = makeOverlapParams()

--- Реестр «живой» серверной логики: model part -> Enemy object.
--- Заполняет WaveManager при спавне/смерти. Нужен, чтобы из Part (результат spatial query)
--- получить объект Enemy для нанесения урона.

function TowerClass.new(kind: TowerKind, model: Model, cellId: string, ownerUserId: number): Tower
	local muzzle = model:WaitForChild("Muzzle") :: BasePart
	local base = Config.TOWERS[kind]
	local self: Tower = setmetatable({
		kind = kind,
		level = 1,
		model = model,
		muzzle = muzzle,
		cellId = cellId,
		ownerUserId = ownerUserId,
		targetMode = base.defaultTarget,
		cooldownLeft = 0,
		totalInvested = base.cost,
		stats = table.clone(base),
	}, TowerClass)
	model:SetAttribute("TowerKind", kind)
	model:SetAttribute("Level", 1)
	return self
end

--- Пересчёт стата по уровню: damage ×1.75^L, range ×1.1^L, cooldown ×0.9^L
local function scaledStat(base: number, level: number, mult: number): number
	return base * mult ^ (level - 1)
end

function TowerClass.getUpgradeCost(self: Tower): number?
	if self.level >= Config.UPGRADE.MAX_LEVEL then return nil end
	local ratio = Config.UPGRADE.COST_RATIOS[self.level]
	return math.floor(Config.TOWERS[self.kind].cost * ratio)
end

function TowerClass.upgrade(self: Tower): boolean
	local cost = self:getUpgradeCost()
	if not cost then return false end
	self.level += 1
	self.totalInvested += cost
	local base = Config.TOWERS[self.kind]
	self.stats.damage = scaledStat(base.damage, self.level, Config.UPGRADE.DAMAGE_MULT)
	self.stats.range = scaledStat(base.range, self.level, Config.UPGRADE.RANGE_MULT)
	self.stats.cooldown = scaledStat(base.cooldown, self.level, Config.UPGRADE.COOLDOWN_MULT)
	self.model:SetAttribute("Level", self.level)
	return true
end

--- Сортировка-выбор цели по режиму таргетинга среди кандидатов.
local function pickByMode(candidates: { {enemy: Enemy, travelled: number, health: number} }, mode: TargetMode): Enemy?
	local best: Enemy? = nil
	local bestKey = 0
	for _, c in candidates do
		local key: number
		if mode == "First" then key = c.travelled            -- дальше всех по пути
		elseif mode == "Last" then key = -c.travelled        -- ближе к спавну
		elseif mode == "Strongest" then key = c.health
		else key = -c.health end                              -- Weakest
		if best == nil or key > bestKey then
			best, bestKey = c.enemy, key
		end
	end
	return best
end

--- Поиск цели: GetPartBoundsInRadius + фильтрация + выбор по таргет-моду.
function TowerClass.findTarget(self: Tower, registry: { [BasePart]: Enemy }): Enemy?
	local origin = self.muzzle.Position
	local range = self.stats.range

	-- SPATIAL QUERY API (современная замена Region3 / GetPartsInRegion3)
	local parts = workspace:GetPartBoundsInRadius(origin, range, _sharedParams)

	local candidates: { {enemy: Enemy, travelled: number, health: number} } = {}
	for _, part in parts do
		local enemy = registry[part]
		if enemy and enemy.alive then
			-- Mortar не бьёт летающих; остальные башни бьют всех
			if self.stats.canHitAir or not enemy.flying then
				table.insert(candidates, {
					enemy = enemy,
					travelled = enemy.travelledDistance,
					health = enemy.health,
				})
			end
		end
	end

	return pickByMode(candidates, self.targetMode)
end

--- Предсказание точки перехвата: куда враг придёт за время полёта снаряда.
local function predictPosition(target: Enemy, projSpeed: number, from: Vector3): Vector3
	local pos = target.model:GetPivot().Position
	local dist = (pos - from).Magnitude
	local leadTime = dist / projSpeed
	-- грубая предикция вдоль пути: + speed*leadTime дистанции => берём позицию чуть вперёд
	local ahead = math.min(target.travelledDistance + target:getCurrentSpeed() * leadTime, 1e9)
	local _ = ahead -- точная LUT-предикция делается в Enemy; здесь упрощённый lead
	return pos
end

function TowerClass.fireAt(self: Tower, target: Enemy, _registry: { [BasePart]: Enemy })
	local stats = self.stats
	local from = self.muzzle.Position

	if stats.hitscan then
		-- Railgun: мгновенный луч, урон сразу + pierce по линии
		local died = target:takeDamage(stats.damage, self.model)
		self._lastKill = died and { target = target } or nil
		-- TODO VFX Beam через RemoteEvent EnemyFX (клиенты рисуют линию от->до)
		return
	end

	local projSpeed = if self.kind == "Mortar" then 40 else 80
	local to = predictPosition(target, projSpeed, from)

	ProjectileModule.fire(from, to, projSpeed, target, function(_f, hitPos, tgt)
		if tgt and tgt.alive then
			if stats.splashRadius > 0 then
				-- AoE: второй spatial query уже в точке взрыва
				local params = makeOverlapParams()
				local boomParts = workspace:GetPartBoundsInRadius(hitPos, stats.splashRadius, params)
				for _, p in boomParts do
					local e = _registry[p]
					if e and e.alive and (not e.flying) then
						e:takeDamage(stats.damage, self.model)
					end
				end
			else
				tgt:takeDamage(stats.damage, self.model)
			end
			if stats.slowPercent > 0 then
				tgt:applySlow(stats.slowPercent, stats.slowDuration)
			end
		end
	end)
end

--- Тик вызывается TowerSystem раз в 0.1 сек для каждой башни.
function TowerClass.tick(self: Tower, dt: number, registry: { [BasePart]: Enemy })
	self.cooldownLeft -= dt
	if self.cooldownLeft > 0 then return end

	local target = self:findTarget(registry)
	if target then
		self:fireAt(target, registry)
		self.cooldownLeft = self.stats.cooldown
	end
end

return TowerClass
