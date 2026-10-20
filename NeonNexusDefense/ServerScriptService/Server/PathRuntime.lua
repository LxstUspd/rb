--!strict
-- PathRuntime.lua — предрассчёт статического пути из Part'ов Workspace.Waypoints.
-- Вызывается ОДИН раз при старте сервера; дальше только читается.
-- Если путь станет динамическим (мазы, разрушаемые мосты) — сюда же встраивается
-- PathfindingService:CreatePath(AgentParams) + PathModifiers, но для TD это избыточно.

local waypointsFolder = workspace:WaitForChild("Waypoints")

export type PathData = {
	positions: {Vector3},
	cumulative: {number},
	totalLength: number,
}

local PathRuntime = {}
local cached: PathData? = nil

function PathRuntime.precompute(): PathData
	-- сортируем части по имени W1, W2, ... (числовой суффикс)
	local parts: {Part} = {}
	for _, obj in waypointsFolder:GetChildren() do
		if obj:IsA("BasePart") then
			table.insert(parts, obj :: Part)
		end
	end
	table.sort(parts, function(a, b)
		local na = tonumber(a.Name:gmatch("%d+")()) or 0
		local nb = tonumber(b.Name:gmatch("%d+")()) or 0
		return na < nb
	end)

	local positions: {Vector3} = {}
	local cumulative: {number} = {}
	local total = 0
	for i, part in parts do
		table.insert(positions, part.Position)
		if i == 1 then
			table.insert(cumulative, 0)
		else
			total += (positions[i] - positions[i - 1]).Magnitude
			table.insert(cumulative, total)
		end
	end

	cached = { positions = positions, cumulative = cumulative, totalLength = total }
	return cached
end

function PathRuntime.getPath(): PathData
	if not cached then return PathRuntime.precompute() end
	return cached
end

return PathRuntime
