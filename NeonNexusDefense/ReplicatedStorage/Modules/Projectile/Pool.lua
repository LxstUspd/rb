--!strict
-- Pool.lua — generic object pool для моделей (враги, снаряды, VFX).
-- ReplicatedStorage.Modules.Projectile.Pool
--
-- Проблема без пула: на каждой волне сотни Instance.new/Clone + Destroy ->
-- spikes сборщика мусора и просадки репликации. Пул переиспользует модели:
-- Release() убирает их в «карман» ниже карты (Parent = storage), Get() достаёт.

export type Pool = {
	get: (self: Pool) -> Model?,           -- nil, если пул пуст (создавайте через prefill)
	release: (self: Pool, obj: Model) -> (),
	size: (self: Pool) -> number,
	prefill: (self: Pool, count: number) -> (),
}

local PoolClass = {}
PoolClass.__index = PoolClass

--- archetype: шаблон-модель (ReplicatedStorage.Asets...), storage: хранилище неактивных объектов
function PoolClass.new(archetype: Model, storage: Folder, maxIdle: number?): Pool
	local self = setmetatable({
		_archetype = archetype,
		_storage = storage,
		_free = {} :: {Model},
		_maxIdle = maxIdle or 50,
	}, PoolClass) :: any
	return self :: Pool
end

function PoolClass.get(self: Pool): Model?
	local free = (self :: any)._free :: {Model}
	local n = #free
	if n == 0 then
		return nil -- пул исчерпан: сервер должен создать новый или дождаться release
	end
	local obj = free[n]
	table.remove(free)
	obj:PivotTo(CFrame.identity)
	return obj
end

function PoolClass.release(self: Pool, obj: Model)
	local free = (self :: any)._free :: {Model}
	if #free >= (self :: any)._maxIdle then
		obj:Destroy() -- пул переполнен — реально удаляем
		return
	end
	-- чистим состояние перед возвратом в пул
	for _, d in obj:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	obj.Parent = (self :: any)._storage :: Folder
	table.insert(free, obj)
end

function PoolClass.size(self: Pool): number
	return #(self :: any)._free :: {Model}
end

--- Предзаполнение: вызывается на запуске сервера, чтобы первые волны были без аллокаций
function PoolClass.prefill(self: Pool, count: number)
	for _ = 1, count do
		local clone = ((self :: any)._archetype :: Model):Clone()
		clone.Parent = (self :: any)._storage :: Folder
		table.insert((self :: any)._free :: {Model}, clone)
	end
end

return PoolClass
