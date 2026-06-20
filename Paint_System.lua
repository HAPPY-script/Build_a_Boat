-- Paint system
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local BlocksFolder = Workspace:WaitForChild("Blocks")

_G.HasPaint = (_G.HasPaint ~= false)

local DEBUG = true

local BATCH_SIZE = 100
local CHECK_DELAY = 1.0
local POLL_STEP = 0.15
local SNAPSHOT_TIMEOUT = 2.0
local EPSILON = 0.001

local function logInfo(...)
	if DEBUG then
		print("[PaintBlock]", ...)
	end
end

local function logWarn(...)
	warn("[PaintBlock]", ...)
end

local function colorTableToColor3(t)
	if typeof(t) == "Color3" then
		return t
	end

	if type(t) ~= "table" then
		logWarn("colorTableToColor3: invalid color table, using white")
		return Color3.fromRGB(255, 255, 255)
	end

	local r = tonumber(t.R or t.r or t[1]) or 255
	local g = tonumber(t.G or t.g or t[2]) or 255
	local b = tonumber(t.B or t.b or t[3]) or 255

	r = math.clamp(math.floor(r + 0.5), 0, 255)
	g = math.clamp(math.floor(g + 0.5), 0, 255)
	b = math.clamp(math.floor(b + 0.5), 0, 255)

	return Color3.fromRGB(r, g, b)
end

local function color3Close(a, b)
	if typeof(a) ~= "Color3" or typeof(b) ~= "Color3" then
		return false
	end

	return math.abs(a.R - b.R) <= EPSILON
		and math.abs(a.G - b.G) <= EPSILON
		and math.abs(a.B - b.B) <= EPSILON
end

local function getPaintToolRF()
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local backpack = LocalPlayer:WaitForChild("Backpack")

	local tool = character:FindFirstChild("PaintingTool") or backpack:FindFirstChild("PaintingTool")
	while not tool do
		task.wait(POLL_STEP)
		character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
		tool = character:FindFirstChild("PaintingTool") or backpack:FindFirstChild("PaintingTool")
	end

	local rf = tool:FindFirstChild("RF")
	if not rf then
		logWarn("RF not found inside PaintingTool")
		return nil
	end

	logInfo("RF Found:", rf:GetFullName())
	return rf
end

local function getCurrentLeaderFolder()
	if not _G.ChangeData then
		return nil
	end

	local team = LocalPlayer.Team
	if not team then
		logWarn("LocalPlayer.Team = nil")
		return nil
	end

	local teamObj = Teams:FindFirstChild(team.Name) or team
	if not teamObj then
		logWarn("Team object missing:", team.Name)
		return nil
	end

	local leaderValue = teamObj:FindFirstChild("TeamLeader")
	if not leaderValue then
		logWarn("TeamLeader missing in team:", teamObj.Name)
		return nil
	end

	local rawValue = leaderValue.Value
	local leaderName = (typeof(rawValue) == "Instance") and rawValue.Name or tostring(rawValue)

	if leaderName == "" or leaderName == "nil" then
		logWarn("Invalid TeamLeader value")
		return nil
	end

	local leaderFolder = BlocksFolder:FindFirstChild(leaderName)
	if not leaderFolder then
		logWarn("Leader folder missing:", leaderName)
		return nil
	end

	return leaderFolder
end

local function snapshotChangeData(timeout)
	local useChangeData = (_G.ChangeData == true)
	logInfo("Snapshot ChangeData:", tostring(useChangeData))

	if not useChangeData then
		return false, nil
	end

	local startTime = os.clock()
	while os.clock() - startTime < timeout do
		local leaderFolder = getCurrentLeaderFolder()
		if leaderFolder then
			logInfo("Leader folder resolved:", leaderFolder.Name)
			return true, leaderFolder
		end
		task.wait(0.05)
	end

	logWarn("Leader resolve timeout")
	return true, nil
end

local function resolvePathFromFolder(root, path)
	if not root or type(path) ~= "string" or path == "" then
		return nil
	end

	local current = root
	for segment in path:gmatch("[^/]+") do
		if segment ~= "" and segment ~= "." then
			current = current:FindFirstChild(segment)
			if not current then
				return nil
			end
		end
	end

	return current
end

local function getPathNames(inst)
	local names = {}
	while inst do
		table.insert(names, 1, inst.Name)
		inst = inst.Parent
	end
	return names
end

local function resolveModelFromEntry(entry)
	if type(entry) ~= "table" then
		return nil
	end

	if typeof(entry.model) == "Instance" and entry.model:IsA("Model") then
		return entry.model
	end

	if typeof(entry.placedBlock) == "Instance" and entry.placedBlock:IsA("Model") then
		return entry.placedBlock
	end

	if typeof(entry.block) == "Instance" and entry.block:IsA("Model") then
		return entry.block
	end

	return nil
end

local function resolveModelByWorkspacePath(model, targetName)
	local path = getPathNames(model)

	local blocksIndex = nil
	for i, name in ipairs(path) do
		if name == "Blocks" then
			blocksIndex = i
			break
		end
	end

	if not blocksIndex or not path[blocksIndex + 1] then
		return nil
	end

	path[blocksIndex + 1] = targetName

	local current = Workspace
	for i = 2, #path do
		current = current:FindFirstChild(path[i])
		if not current then
			return nil
		end
	end

	if current and current:IsA("Model") then
		return current
	end

	return nil
end

local function resolveModelBySourcePath(sourcePath, targetName)
	if type(sourcePath) ~= "string" or sourcePath == "" then
		return nil
	end

	local parts = {}
	for segment in sourcePath:gmatch("[^/]+") do
		parts[#parts + 1] = segment
	end

	if #parts == 0 then
		return nil
	end

	parts[1] = targetName

	local current = BlocksFolder
	for i = 1, #parts do
		current = current:FindFirstChild(parts[i])
		if not current then
			return nil
		end
	end

	if current and current:IsA("Model") then
		return current
	end

	return nil
end

local function resolveTargetModel(entry, useChangeData, leaderFolder)
	local model = resolveModelFromEntry(entry)
	if not model then
		return nil
	end

	if not useChangeData then
		return model
	end

	if leaderFolder and model:IsDescendantOf(leaderFolder) then
		return model
	end

	-- fallback cuối cùng: vẫn trả model nếu nó tồn tại
	return model
end

local function getPaintColorFromModel(model)
	local ppart = model and model:FindFirstChild("PPart", true)
	if ppart and ppart:IsA("BasePart") then
		return ppart.Color
	end
	return Color3.fromRGB(255, 255, 255)
end

local function getCurrentPaintValue(model)
	return getPaintColorFromModel(model)
end

local function normalizeColorInput(v)
	if typeof(v) == "Color3" then
		return v
	end
	return colorTableToColor3(v)
end

local function normalizePayload(raw)
	if type(raw) ~= "table" then
		return nil
	end

	if type(raw.blocks) == "table" then
		return raw.blocks, raw
	end

	return raw, raw
end

local function getRemoteNameForPaint()
	return true
end

local function collectPaintTasks(payloadBlocks, useChangeData, leaderFolder)
	local tasks = {}
	local normalized = {}

	local resolvedCount = 0
	local missingModelCount = 0
	local alreadyMatchedCount = 0

	for _, entry in ipairs(payloadBlocks) do
		if type(entry) == "table" then
			local model = resolveTargetModel(entry, useChangeData, leaderFolder)
			local desiredColor = normalizeColorInput(entry.color)

			if not model then
				missingModelCount += 1
				logWarn("Không resolve được model:", entry.uid or "no-uid", tostring(entry.blockName or "Unknown"))
			elseif not desiredColor then
				missingModelCount += 1
				logWarn("Thiếu/không hợp lệ color:", entry.uid or "no-uid", tostring(entry.blockName or "Unknown"))
			else
				resolvedCount += 1

				local blockName = entry.blockName or model.Name
				normalized[#normalized + 1] = {
					entry = entry,
					model = model,
					blockName = blockName,
					desiredColor = desiredColor,
				}

				local currentColor = getCurrentPaintValue(model)
				logInfo(
					("CHECK | %s | current=%s | desired=%s"):format(
						tostring(entry.uid or "no-uid"),
						tostring(currentColor),
						tostring(desiredColor)
					)
				)

				if not color3Close(currentColor, desiredColor) then
					tasks[#tasks + 1] = {
						uid = entry.uid,
						model = model,
						blockName = blockName,
						desiredColor = desiredColor,
					}
				else
					alreadyMatchedCount += 1
				end
			end
		end
	end

	logInfo(
		("Resolved=%d | MissingModel=%d | AlreadyMatched=%d | Tasks=%d"):format(
			resolvedCount,
			missingModelCount,
			alreadyMatchedCount,
			#tasks
		)
	)

	table.sort(tasks, function(a, b)
		if a.blockName == b.blockName then
			return tostring(a.uid or a.model) < tostring(b.uid or b.model)
		end
		return a.blockName < b.blockName
	end)

	return tasks, normalized, resolvedCount, missingModelCount, alreadyMatchedCount
end

local function allBlocksMatched(normalizedBlocks)
	for _, item in ipairs(normalizedBlocks) do
		local model = item.model
		if not model or not model.Parent then
			return false
		end

		local currentColor = getCurrentPaintValue(model)
		if not color3Close(currentColor, item.desiredColor) then
			return false
		end
	end

	return true
end

local function invokePaintRemote(rf, taskInfo)
	if not taskInfo or not taskInfo.model or not taskInfo.model.Parent then
		return false
	end

	local ok, result = pcall(function()
		return rf:InvokeServer({
			{
				taskInfo.model,
				taskInfo.desiredColor,
			}
		})
	end)

	if ok then
		logInfo("Invoke Success:", taskInfo.blockName, result)
	else
		logWarn("Invoke Failed:", taskInfo.blockName, result)
	end

	return ok
end

local function collectPendingBatchRecords(batchRecords)
	local pending = {}

	for _, item in ipairs(batchRecords) do
		local model = item.model
		if model and model.Parent then
			local currentColor = getCurrentPaintValue(model)
			if not color3Close(currentColor, item.desiredColor) then
				pending[#pending + 1] = item
			end
		end
	end

	return pending
end

local function dispatchPaintBatch(rf, batchRecords)
	for _, taskInfo in ipairs(batchRecords) do
		task.spawn(function()
			invokePaintRemote(rf, taskInfo)
		end)
	end
end

local function processPaintPayload(rawPayload)
	logInfo("========== PAINT START ==========")

	local payloadBlocks = normalizePayload(rawPayload)
	if type(payloadBlocks) ~= "table" then
		logWarn("Payload không hợp lệ")
		_G.PaintBlock = false
		return
	end

	logInfo("Số entry trong payload:", #payloadBlocks)

	local rf = getPaintToolRF()
	if not rf then
		logWarn("RF unavailable")
		_G.PaintBlock = false
		return
	end

	local useChangeData, leaderFolder = snapshotChangeData(SNAPSHOT_TIMEOUT)

	logInfo("Final ChangeData:", tostring(useChangeData))
	if leaderFolder then
		logInfo("Final LeaderFolder:", leaderFolder:GetFullName())
	else
		logInfo("Final LeaderFolder: nil")
	end

	local tasks, normalizedBlocks, resolvedCount = collectPaintTasks(payloadBlocks, useChangeData, leaderFolder)

	if resolvedCount == 0 then
		logWarn("Không resolve được block nào từ payload")
		_G.PaintBlock = false
		return
	end

	if #tasks == 0 then
		logInfo("Tất cả block đã khớp sẵn")
		_G.PaintBlock = false
		return
	end

	logInfo(("Bắt đầu xử lý %d block cần paint"):format(#normalizedBlocks))

	local totalSent = 0
	local batchIndex = 0

	for startIndex = 1, #normalizedBlocks, BATCH_SIZE do
		batchIndex += 1

		local endIndex = math.min(startIndex + BATCH_SIZE - 1, #normalizedBlocks)
		local batchRecords = {}

		for i = startIndex, endIndex do
			batchRecords[#batchRecords + 1] = normalizedBlocks[i]
		end

		logInfo(("BATCH %d | start | size=%d"):format(batchIndex, #batchRecords))

		while true do
			if _G.PaintBlock == false then
				return
			end

			local pendingTasks = collectPendingBatchRecords(batchRecords)
			logInfo(("BATCH %d | pending=%d"):format(batchIndex, #pendingTasks))

			if #pendingTasks == 0 then
				break
			end

			dispatchPaintBatch(rf, pendingTasks)
			totalSent += #pendingTasks

			logInfo(("BATCH %d | sent=%d | totalSent=%d"):format(batchIndex, #pendingTasks, totalSent))

			task.wait(CHECK_DELAY)
		end

		logInfo(("BATCH %d DONE"):format(batchIndex))
	end

	_G.PaintBlock = false
	logInfo("Hoàn tất PaintBlock")
	logInfo("========== PAINT END ==========")
end

local function waitForPayloadLoop()
	while true do
		local payload = _G.PaintBlock
		if type(payload) == "table" then
			if not _G.__PaintBlockRunning then
				_G.__PaintBlockRunning = true
				task.spawn(function()
					processPaintPayload(payload)
					_G.__PaintBlockRunning = false
				end)
			end
		end
		task.wait(POLL_STEP)
	end
end

print("PaintBlock ready")
waitForPayloadLoop()
