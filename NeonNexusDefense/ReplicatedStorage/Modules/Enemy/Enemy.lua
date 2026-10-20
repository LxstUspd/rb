--!strict
-- Enemy.lua — ООП-класс врага с движением по статическим waypoints.
-- ReplicatedStorage.Modules.Enemy.Enemy
--
-- Идея оптимизации: путь предрассчитан один раз (PathRuntime), массив кумулятивных
-- дистанций позволяет по travelledDistance за O(log n) найти сегмент и интерполировать
-- позицию. Никаких BodyPosition/AlignCFrame/PathfindingService на каждого врага.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

export type WaypointData = {
	positions: {Vector3},   -- точки пути
	cumulative: {number},   -- кумулятивные дистанции: cumulative[i] = длина пути до точки i
	totalLength: number,
}

export type Enemy = {
	-- публичные поля (для систем сервера)
	kind: Types.EnemyKind,
	model: Model,
	humanoidRoot: BasePart,
	maxHealth: number,
	health: number,
	baseSpeed: number,
	reward: number,
	flying: boolean,
	coreDamage: number,
	travelledDistance: number,
	alive: boolean,
	reachedEnd: boolean,

	-- приватные поля (leading underscore — конвенция «не трогать извне»)
	_path: WaypointData?,
	_slowUntil: number?,
	_slowPercent: number?,

	-- методы
	update: (self: Enemy, dt: number) -> (),
	takeDamage: (self: Enemy, amount: number, source: Instance?) -> boolean,
	applySlow: (self: Enemy, percent: number, duration: number) -> (),
	getCurrentSpeed: (self: Enemy) -> number,
	destroy: (self: Enemy) -> (),
}

local EnemyClass = {}
EnemyClass.__index = EnemyClass

-- Бинарный поиск сегмента пути по дистанции
local function findSegment(cumulative: {number}, distance: number): number
	local lo, hi = 1, #cumulative - 1
	while lo < hi do
		local mid = (lo + hi) // 2
		if cumulative[mid] < distance then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return lo
end

--- Фабрика врага. path — предрассчитанные waypoints; waveNumber — для скейлинга HP.
function EnemyClass.new(kind: Types.EnemyKind, waveNumber: number, path: WaypointData, archetype: Model, parent: Instance): Enemy
	local stats: Types.EnemyStats = Config.ENEMIES[kind]
	local hpMult = Config.SCALING.hp(waveNumber)
	local speedMult = Config.SCALING.speed(waveNumber)

	local model = archetype:Clone()
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	model:PivotTo(CFrame.new(path.positions[1]))
	model.Parent = parent

	-- Анти-фликер: модель не участвует в физике, позиция ставим руками
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = true          -- важно: GetPartBoundsInRadius должен её видеть
			part.CanTouch = false
			part.CastShadow = false
			part.AssemblyLinearVelocity = Vector3.zero
		end
	end
	model:AddTag("Enemy")
	model:SetAttribute("Flying", stats.flying)
	model:SetAttribute("Travelled", 0)

	local self: Enemy = setmetatable({
		kind = kind,
		model = model,
		humanoidRoot = root,
		maxHealth = math.floor(stats.health * hpMult),
		health = math.floor(stats.health * hpMult),
		baseSpeed = stats.speed * speedMult,
		reward = stats.reward,
		flying = stats.flying,
		coreDamage = stats.coreDamage,
		travelledDistance = 0,
		alive = true,
		reachedEnd = false,
	}, EnemyClass)

	-- приватные данные храним в weak-tables вне публичного типа
	self._path = path
	self._slowUntil = 0
	self._slowPercent = 0
	return self
end

function EnemyClass.getCurrentSpeed(self: Enemy): number
	local now = os.clock()
	if now < (self._slowUntil or 0) then
		local resist = Config.ENEMIES[self.kind].slowResist
		return self.baseSpeed * (1 - (self._slowPercent or 0) * (1 - resist))
	end
	return self.baseSpeed
end

function EnemyClass.applySlow(self: Enemy, percent: number, duration: number)
	if self.flying and self.kind == "Drone" then
		percent = math.min(percent, 0.3) -- дроны слабо замедляются
	end
	-- стаки: берём более сильный slow и продлеваем время
	self._slowPercent = math.max(self._slowPercent or 0, percent)
	self._slowUntil = math.max(self._slowUntil or 0, os.clock() + duration)
end

--- Вызывается серверным MovementSystem раз в ~30 Гц для всех живых врагов одним циклом.
function EnemyClass.update(self: Enemy, dt: number)
	if not self.alive then return end

	self.travelledDistance += self:getCurrentSpeed() * dt
	local path = self._path :: WaypointData

	if self.travelledDistance >= path.totalLength then
		self.reachedEnd = true
		self.alive = false
		return
	end

	-- LUT-интерполяция позиции
	local seg = findSegment(path.cumulative, self.travelledDistance)
	local a, b = path.positions[seg], path.positions[seg + 1]
	local segLen = path.cumulative[seg + 1] - path.cumulative[seg]
	local alpha = if segLen > 0 then (self.travelledDistance - path.cumulative[seg]) / segLen else 0
	local pos = a:Lerp(b, math.clamp(alpha, 0, 1))

	-- Летающие идут по «воздушной» высоте и срезают углы
	if self.flying then
		pos = pos + Vector3.new(0, 6, 0)
		self.model:PivotTo(CFrame.lookAt(pos, b + Vector3.new(0, 6, 0)))
	else
		self.model:PivotTo(CFrame.lookAt(pos, b))
	end

	self.model:SetAttribute("Travelled", self.travelledDistance) -- для таргетинга First/Last
end

--- Возвращает true, если враг умер от этого урона.
function EnemyClass.takeDamage(self: Enemy, amount: number, _source: Instance?): boolean
	if not self.alive then return false end
	self.health -= amount
	if self.health <= 0 then
		self.health = 0
		self.alive = false
		return true
	end
	return false
end

function EnemyClass.destroy(self: Enemy)
	self._path = nil
	self._slowUntil = nil
	self._slowPercent = nil
end

return EnemyClass
