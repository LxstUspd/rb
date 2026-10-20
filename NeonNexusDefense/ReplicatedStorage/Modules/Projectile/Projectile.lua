--!strict
-- Projectile.lua — снаряд с линейным лерпом (без физики) и пулингом.
-- ReplicatedStorage.Modules.Projectile.Projectile
--
-- Снаряд летит из точки A в предсказанную точку B с постоянной скоростью;
-- по прибытии вызывает onHit(origin, targetPosition). Модель берётся из Pool.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules")
	:WaitForChild("Shared"):WaitForChild("Types"))
local PoolModule = require(script.Parent:WaitForChild("Pool"))
local EnemyModule = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules")
	:WaitForChild("Enemy"):WaitForChild("Enemy"))

type Enemy = EnemyModule.Enemy

export type Projectile = {
	active: boolean,
	from: Vector3,
	to: Vector3,
	speed: number,
	travelled: number,
	distance: number,
	model: Model?,
	onHit: (from: Vector3, to: Vector3, target: Enemy?) -> (),
	target: Types.EnemyKind?,
	_targetRef: Enemy?,
}

local ProjectileClass = {}
ProjectileClass.__index = ProjectileClass

local projectilePool: PoolModule.Pool? = nil

--- Инициализация пула снарядов (вызвать один раз в Main.server.lua)
function ProjectileClass.initPool(archetype: Model, storage: Folder)
	projectilePool = PoolModule.new(archetype, storage, 200)
	projectilePool:prefill(60)
end

function ProjectileClass.fire(
	from: Vector3,
	to: Vector3,
	speed: number,
	target: Enemy?,
	onHit: (from: Vector3, to: Vector3, target: Enemy?) -> ()
): Projectile?
	if not projectilePool then error("Projectile.initPool was not called") end
	local model = projectilePool:get()
	if not model then return nil end -- пул пуст -> graceful skip (визуал важнее, чем лаг)

	local dist = (to - from).Magnitude
	local self: Projectile = setmetatable({
		active = true,
		from = from,
		to = to,
		speed = speed,
		travelled = 0,
		distance = math.max(dist, 0.001),
		model = model,
		onHit = onHit,
		target = if target then target.kind else nil,
	}, ProjectileClass)

	model.Parent = workspace:FindFirstChild("Runtime") or workspace
	model:PivotTo(CFrame.lookAt(from, to))
	self._targetRef = target -- сохраняем ссылку: при попадании пересчитаем текущую позицию
	return self
end

--- Серверный тик: продвигает все активные снаряды. Возвращает true, если снаряд завершился.
function ProjectileClass.update(self: Projectile, dt: number): boolean
	if not self.active then return true end
	self.travelled += self.speed * dt
	local t = self.travelled / self.distance

	if t >= 1 then
		self.active = false
		local target = self._targetRef
		self.onHit(self.from, self.to, target)
		if self.model and projectilePool then
			projectilePool:release(self.model)
		end
		self.model = nil
		self._targetRef = nil
		return true
	end

	-- позиционируем снаряд по пути
	if self.model then
		self.model:PivotTo(CFrame.lookAt(self.from:Lerp(self.to, t), self.to))
	end
	return false
end

return ProjectileClass
