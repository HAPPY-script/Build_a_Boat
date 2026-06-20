-- Properties system
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

_G.HasProperties = (_G.HasProperties ~= false)

local BATCH_SIZE = 100
local CHECK_DELAY = 1.0
local POLL_STEP = 0.15
local EPSILON = 0.001

local PROPERTY_REMOTE_NAMES = {
	Aim = "Aim",

	Anchored = "Anchored",
	CanCollide = "Collision",
	Transparency = "Transparency",
	CastShadow = "Cast shadow",

	MaxForce = "Jet force",
	FuseTime = "Fuse time",
	FlightDistance = "Flight distance",
	ShowCrosshairs = "Crosshairs",
	WaitDuration = "Delay time",

	SemitoneOffset = "Key",

	ReverseRotation = "Reverse rotation",

	TargetAngle = "Servo angle",
	AngularSpeed = "Servo speed",
	ServoMaxTorque = "Servo torque",

	ExtendLength = "Piston length",
	Speed = "Piston speed",

	ReverseSpin = "Reverse spin",

	DepthScale = "Shrink depth scale",
	HeadScale = "Shrink head scale",
	HeightScale = "Shrink height scale",
	WidthScale = "Shrink width scale",

	MotorMaxTorque = "Wheel torque",
}

local MAX_SPEED_REMOTE_NAMES = {
	JetTurbine = "Jet speed",
	BackWheel = "Wheel speed",
	FrontWheel = "Wheel speed",
	BackWheelMint = "Wheel speed",
	FrontWheelMint = "Wheel speed",
	Motor = "Wheel speed",
}

local MAIN_PROPS = {
	Anchored = true,
	CanCollide = true,
	Transparency = true,
	CastShadow = true,
}

local MAIN_PROP_ALIASES = {
	Anchor = "Anchored",
	Anchored = "Anchored",

	CanCollide = "CanCollide",
	Cancollide = "CanCollide",
	Collision = "CanCollide",

	Transparency = "Transparency",
	CastShadow = "CastShadow",
}

local SPECIAL_BLOCK_PARTS = {
	Seat = "Union",
	Helm = "Union",
	Mast = "Railing",
	Cannon = "Barrel",
}

local function logInfo(...)
	print("[PropertiesBlock]", ...)
end

local function logWarn(...)
	warn("[PropertiesBlock]", ...)
end

local function isCloseNumber(a, b)
	local na = tonumber(a)
	local nb = tonumber(b)
	if na == nil or nb == nil then
		return false
	end
	return math.abs(na - nb) <= EPSILON
end

local function valuesEqual(a, b)
	local ta = typeof(a)
	local tb = typeof(b)

	if ta ~= tb then
		if type(a) == "number" and type(b) == "number" then
			return isCloseNumber(a, b)
		end
		return false
	end

	if type(a) == "number" then
		return isCloseNumber(a, b)
	end

	return a == b
end

local function getTeamLeaderName()
	if not _G.ChangeData then
		return LocalPlayer.Name
	end

	local teams = LocalPlayer:FindFirstChild("Teams")
	local leaderName = teams
		and teams:FindFirstChild("TeamLeader")
		and teams.TeamLeader.Value

	if typeof(leaderName) == "string" and leaderName ~= "" then
		return leaderName
	end

	return LocalPlayer.Name
end

local function getTargetPlayer()
	local name = getTeamLeaderName()
	return Players:FindFirstChild(name) or LocalPlayer
end

local function getTargetPlayerName()
	return getTeamLeaderName()
end

local function getBlocksRoot()
	return Workspace:WaitForChild("Blocks")
end

local function getPropertiesToolRF()
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local backpack = LocalPlayer:WaitForChild("Backpack")

	local tool = character:FindFirstChild("PropertiesTool") or backpack:FindFirstChild("PropertiesTool")
	while not tool do
		task.wait(POLL_STEP)
		character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
		tool = character:FindFirstChild("PropertiesTool") or backpack:FindFirstChild("PropertiesTool")
	end

	return tool:WaitForChild("SetPropertieRF")
end

local SetPropertieRF = getPropertiesToolRF()

local function findDescendantByName(root, name)
	if not root then
		return nil
	end

	if root.Name == name then
		return root
	end

	for _, inst in ipairs(root:GetDescendants()) do
		if inst.Name == name then
			return inst
		end
	end

	return nil
end

local function findPartByName(model, partName)
	if not model then
		return nil
	end

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == partName then
			return inst
		end
	end

	return nil
end

local function readValue(inst)
	if not inst then
		return nil
	end

	if inst:IsA("ValueBase") then
		return inst.Value
	end

	local vb = inst:FindFirstChildWhichIsA("ValueBase")
	if vb then
		return vb.Value
	end

	return nil
end

local function readMainPartProperty(ppart, propName)
	if propName == "Anchored" then
		return ppart.Anchored
	elseif propName == "CanCollide" then
		return ppart.CanCollide
	elseif propName == "Transparency" then
		return ppart.Transparency
	elseif propName == "CastShadow" then
		return ppart.CastShadow
	end
	return nil
end

local function getPPart(model)
	if not model then
		return nil
	end

	local blockName = model.Name
	local specialPartName = SPECIAL_BLOCK_PARTS[blockName]

	if specialPartName then
		local specialPart = findPartByName(model, specialPartName)
		if specialPart then
			return specialPart
		end
	end

	local ppart = model:FindFirstChild("PPart", true)
	if ppart and ppart:IsA("BasePart") then
		return ppart
	end

	return nil
end

local function getValueNodeForProperty(model, propName)
	local ppart = getPPart(model)
	if not ppart then
		return nil, nil
	end

	if MAIN_PROPS[propName] then
		return ppart, "part"
	end

	local parent = ppart.Parent
	if not parent then
		return nil, nil
	end

	if propName == "ServoMaxTorque" or propName == "AngularSpeed" then
		local semitoneNode = findDescendantByName(ppart, "SemitoneOffset") or findDescendantByName(parent, "SemitoneOffset")
		if semitoneNode then
			local node = findDescendantByName(semitoneNode, propName)
			if node then
				return node, "value"
			end
		end
		return nil, nil
	end

	if propName == "MotorMaxTorque" then
		local hingeNode = findDescendantByName(ppart, "HingeConstraint") or findDescendantByName(parent, "HingeConstraint")
		if hingeNode then
			local node = findDescendantByName(hingeNode, propName)
			if node then
				return node, "value"
			end
		end
		return nil, nil
	end

	local direct = parent:FindFirstChild(propName)
	if direct then
		return direct, "value"
	end

	local found = findDescendantByName(parent, propName) or findDescendantByName(ppart, propName)
	if found then
		return found, "value"
	end

	return nil, nil
end

local function getCurrentPropertyValue(model, propName)
	local node, kind = getValueNodeForProperty(model, propName)
	if not node then
		return nil
	end

	if kind == "part" then
		return readMainPartProperty(node, propName)
	end

	return readValue(node)
end

local function getRemoteName(blockName, propName)
	if propName == "MaxSpeed" then
		return MAX_SPEED_REMOTE_NAMES[blockName]
	end
	return PROPERTY_REMOTE_NAMES[propName]
end

local function collectDesiredProperties(entry)
	local desired = {}

	local function ingestProps(props)
		if type(props) ~= "table" then
			return
		end

		for propName, wanted in pairs(props) do
			if wanted ~= nil then
				local canonical = MAIN_PROP_ALIASES[propName] or propName
				if MAIN_PROPS[canonical] then
					desired[canonical] = wanted
				end
			end
		end
	end

	ingestProps(entry.properties)
	ingestProps(entry.Properties)
	ingestProps(entry.props)
	ingestProps(entry.expectedProperties)
	ingestProps(entry.sourceProperties)

	for rawName, canonical in pairs(MAIN_PROP_ALIASES) do
		local v = entry[rawName]
		if v ~= nil and MAIN_PROPS[canonical] then
			desired[canonical] = v
		end
	end

	return desired
end

local function hasAnyPropertyToCheck(desired)
	for _ in pairs(desired) do
		return true
	end
	return false
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

local function resolveTargetModel(entry)
	local model = resolveModelFromEntry(entry)
	if not model then
		return nil
	end

	if not _G.ChangeData then
		return model
	end

	local targetName = getTargetPlayerName()
	local blocksRoot = getBlocksRoot()

	-- Cách 1: lấy theo đường dẫn cũ rồi thay tên player ở nhánh Blocks
	local path = getPathNames(model)
	local blocksIndex = nil
	for i, name in ipairs(path) do
		if name == "Blocks" then
			blocksIndex = i
			break
		end
	end

	if blocksIndex and path[blocksIndex + 1] then
		path[blocksIndex + 1] = targetName

		local current = Workspace
		for i = 2, #path do
			current = current:FindFirstChild(path[i])
			if not current then
				break
			end
		end

		if current and current:IsA("Model") then
			return current
		end
	end

	-- Cách 2: tìm theo tên block trong folder của target
	local targetFolder = blocksRoot:FindFirstChild(targetName)
	if targetFolder then
		local blockName = entry.blockName or model.Name
		local direct = targetFolder:FindFirstChild(blockName, true)
		if direct and direct:IsA("Model") then
			return direct
		end
	end

	-- fallback
	return model
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

local function buildPendingTasks(payloadBlocks)
	local tasks = {}
	local normalized = {}
	local resolvedCount = 0
	local missingRemoteCount = 0
	local missingModelCount = 0
	local alreadyMatchedCount = 0

	for _, entry in ipairs(payloadBlocks) do
		if type(entry) == "table" then
			local model = resolveTargetModel(entry)
			local blockName = entry.blockName or (model and model.Name) or "Unknown"
			local desired = collectDesiredProperties(entry)

			if not model then
				missingModelCount += 1
				logWarn("Không resolve được model:", entry.uid or "no-uid", blockName)
			elseif hasAnyPropertyToCheck(desired) then
				resolvedCount += 1
				normalized[#normalized + 1] = {
					entry = entry,
					model = model,
					blockName = blockName,
					desired = desired,
				}

				for propName, desiredValue in pairs(desired) do
					local remoteName = getRemoteName(blockName, propName)
					if not remoteName then
						missingRemoteCount += 1
						logWarn("Không map được remote name:", entry.uid or "no-uid", blockName, propName)
					else
						local currentValue = getCurrentPropertyValue(model, propName)
						logInfo(
							("CHECK | %s | %s | current=%s | desired=%s | remote=%s"):format(
								tostring(entry.uid or "no-uid"),
								tostring(propName),
								tostring(currentValue),
								tostring(desiredValue),
								tostring(remoteName)
							)
						)

						if not valuesEqual(currentValue, desiredValue) then
							tasks[#tasks + 1] = {
								uid = entry.uid,
								model = model,
								blockName = blockName,
								propName = propName,
								remoteName = remoteName,
								desiredValue = desiredValue,
							}
						else
							alreadyMatchedCount += 1
						end
					end
				end
			end
		end
	end

	logInfo(("Resolved=%d | MissingModel=%d | MissingRemote=%d | AlreadyMatched=%d | Tasks=%d"):format(
		resolvedCount,
		missingModelCount,
		missingRemoteCount,
		alreadyMatchedCount,
		#tasks
	))

	table.sort(tasks, function(a, b)
		if a.blockName == b.blockName then
			if a.propName == b.propName then
				return tostring(a.uid or a.model) < tostring(b.uid or b.model)
			end
			return a.propName < b.propName
		end
		return a.blockName < b.blockName
	end)

	return tasks, normalized, resolvedCount, missingRemoteCount, missingModelCount, alreadyMatchedCount
end

local function allBlocksMatched(normalizedBlocks)
	for _, item in ipairs(normalizedBlocks) do
		local model = item.model
		if not model or not model.Parent then
			return false
		end

		for propName, desiredValue in pairs(item.desired) do
			local remoteName = getRemoteName(item.blockName, propName)
			if remoteName then
				local currentValue = getCurrentPropertyValue(model, propName)
				if not valuesEqual(currentValue, desiredValue) then
					return false
				end
			end
		end
	end

	return true
end

local function invokePropertyRemote(taskInfo)
	if not taskInfo or not taskInfo.model or not taskInfo.model.Parent then
		return false
	end

	local targetName = getTargetPlayerName()

	local ok, err = pcall(function()
		-- Nếu server của bạn cần Player object thay vì string,
		-- đổi targetName bên dưới thành getTargetPlayer()
		SetPropertieRF:InvokeServer(
			taskInfo.remoteName,
			{ taskInfo.model },
			targetName
		)
	end)

	if not ok then
		logWarn("Remote lỗi:", taskInfo.uid or "no-uid", taskInfo.blockName, taskInfo.propName, err)
	end

	return ok
end

local function processPropertiesPayload(rawPayload)
	logInfo("Nhận payload:", typeof(rawPayload), type(rawPayload))

	local payloadBlocks = normalizePayload(rawPayload)
	if type(payloadBlocks) ~= "table" then
		logWarn("Payload không hợp lệ")
		_G.PropertiesBlock = false
		return
	end

	logInfo("Số entry trong payload:", #payloadBlocks)

	local tasks, normalizedBlocks, resolvedCount, missingRemoteCount, missingModelCount = buildPendingTasks(payloadBlocks)

	if resolvedCount == 0 then
		logWarn("Không resolve được block nào từ payload")
		_G.PropertiesBlock = false
		return
	end

	if #tasks == 0 then
		if missingModelCount > 0 then
			logWarn("Có block nhưng thiếu model hợp lệ để xử lý")
		elseif missingRemoteCount > 0 then
			logWarn("Có block, nhưng remote name chưa map được cho một số property")
		else
			logInfo("Có block, và tất cả property đã khớp sẵn")
		end

		_G.PropertiesBlock = false
		return
	end

	logInfo(("Bắt đầu xử lý %d property cần sửa"):format(#tasks))

	local batchIndex = 0
	local totalSent = 0

	while true do
		if _G.PropertiesBlock == false then
			return
		end

		local pendingTasks = {}
		for _, item in ipairs(normalizedBlocks) do
			local model = item.model
			if model and model.Parent then
				for propName, desiredValue in pairs(item.desired) do
					local remoteName = getRemoteName(item.blockName, propName)
					if remoteName then
						local currentValue = getCurrentPropertyValue(model, propName)
						if not valuesEqual(currentValue, desiredValue) then
							pendingTasks[#pendingTasks + 1] = {
								uid = item.entry and item.entry.uid,
								model = model,
								blockName = item.blockName,
								propName = propName,
								remoteName = remoteName,
								desiredValue = desiredValue,
							}
						end
					end
				end
			end
		end

		logInfo(("LOOP CHECK | pending=%d"):format(#pendingTasks))

		if #pendingTasks == 0 then
			break
		end

		table.sort(pendingTasks, function(a, b)
			if a.blockName == b.blockName then
				if a.propName == b.propName then
					return tostring(a.uid or a.model) < tostring(b.uid or b.model)
				end
				return a.propName < b.propName
			end
			return a.blockName < b.blockName
		end)

		local batchCount = math.min(BATCH_SIZE, #pendingTasks)
		batchIndex += 1

		local blockCounter = {}
		local currentBlockName = pendingTasks[1] and pendingTasks[1].blockName or "Unknown"

		logInfo(("BATCH %d | BLOCK=%s | sending=%d | remaining=%d"):format(
			batchIndex,
			currentBlockName,
			batchCount,
			#pendingTasks
		))

		for i = 1, batchCount do
			local task = pendingTasks[i]
			blockCounter[task.blockName] = (blockCounter[task.blockName] or 0) + 1

			local ok = invokePropertyRemote(task)
			if ok then
				totalSent += 1
			end
		end

		local summary = ""
		for b, c in pairs(blockCounter) do
			summary ..= (b .. ":" .. c .. " ")
		end

		logInfo(("BATCH %d DONE | totalSent=%d | blocks=[%s]"):format(
			batchIndex,
			totalSent,
			summary
		))

		if batchIndex % 5 == 0 then
			logInfo("STATUS | still running batches:", batchIndex)
		end

		task.wait(CHECK_DELAY)

		if allBlocksMatched(normalizedBlocks) then
			break
		end
	end

	_G.PropertiesBlock = false
	logInfo("Hoàn tất PropertiesBlock")
end

local function waitForPayloadLoop()
	while true do
		local payload = _G.PropertiesBlock
		if type(payload) == "table" then
			if not _G.__PropertiesBlockRunning then
				_G.__PropertiesBlockRunning = true
				task.spawn(function()
					processPropertiesPayload(payload)
					_G.__PropertiesBlockRunning = false
				end)
			end
		end
		task.wait(POLL_STEP)
	end
end

print("PropertiesBlock ready")
waitForPayloadLoop()
