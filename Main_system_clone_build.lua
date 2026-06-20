-- Main system

_G.HasPaint = true
_G.HasProperties = true
_G.ChangeData = false

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==================================================
-- TEAM ZONES
--==================================================
local Blue = workspace:WaitForChild("Really blueZone")
local Red = workspace:WaitForChild("Really redZone")
local Yellow = workspace:WaitForChild("New YellerZone")
local Green = workspace:WaitForChild("CamoZone")
local Purple = workspace:WaitForChild("MagentaZone")
local Black = workspace:WaitForChild("BlackZone")
local White = workspace:WaitForChild("WhiteZone")

local TEAM_ZONES_BY_NAME = {
	blue = Blue,
	red = Red,
	yellow = Yellow,
	green = Green,
	magenta = Purple,
	black = Black,
	white = White,
}

local ZONE_TO_TEAM_NAME = {
	[Blue] = "blue",
	[Red] = "red",
	[Yellow] = "yellow",
	[Green] = "green",
	[Purple] = "magenta",
	[Black] = "black",
	[White] = "white",
}

--==================================================
-- BLOCK ID MAP
--==================================================
local BLOCK_IDS = {}

local function getDataFolder()
	return LocalPlayer:FindFirstChild("Data")
end

local function buildBlockIds()
	local dataFolder = getDataFolder()
	if not dataFolder then
		return {}
	end

	local map = {}

	for _, obj in ipairs(dataFolder:GetChildren()) do
		if obj:IsA("IntValue") then
			local id = obj.Value
			if type(id) == "number" and id > 0 then
				map[obj.Name] = id
			end
		end
	end

	return map
end

local function refreshBlockIds()
	BLOCK_IDS = buildBlockIds()
end

--==================================================
-- SETTINGS
--==================================================
local BATCH_SIZE = 100
local PLACE_SETTLE_SECONDS = 1.0
local SHOW_SKIP_AFTER_SECONDS = 3.0
local LATE_POLL_STEP = 0.08
local SCALE_BATCH_PAUSE = 1.0

--==================================================
-- STATE
--==================================================
local skippedBlockNames = {}
local skipRequested = false
local skipPickedRequested = false
local replaceRequested = false
local activeSkipPanelNames = {}
local selectedPendingTypes = {}

local scalingLockRunning = false

local lastPendingSignature = nil
local lastPendingElapsedShown = -1

local pendingBillboards = {}

local pendingMarkerFolder = workspace:FindFirstChild("CloneBlockPendingMarkers")
if not pendingMarkerFolder then
	pendingMarkerFolder = Instance.new("Folder")
	pendingMarkerFolder.Name = "CloneBlockPendingMarkers"
	pendingMarkerFolder.Parent = workspace
end
--==================================================
-- GUI
--==================================================
local oldGui = PlayerGui:FindFirstChild("CloneBlockSkipGui")
if oldGui then
	oldGui:Destroy()
end

local SkipGui = Instance.new("ScreenGui")
SkipGui.Name = "CloneBlockSkipGui"
SkipGui.ResetOnSpawn = false
SkipGui.IgnoreGuiInset = true
SkipGui.DisplayOrder = 99999
SkipGui.Parent = PlayerGui

local Panel = Instance.new("Frame")
Panel.Name = "Panel"
Panel.AnchorPoint = Vector2.new(1, 1)
Panel.Position = UDim2.new(1, -16, 1, -16)
Panel.Size = UDim2.fromOffset(420, 360)
Panel.BackgroundTransparency = 0.12
Panel.Visible = false
Panel.Parent = SkipGui

local PanelCorner = Instance.new("UICorner")
PanelCorner.CornerRadius = UDim.new(0, 10)
PanelCorner.Parent = Panel

local PanelStroke = Instance.new("UIStroke")
PanelStroke.Thickness = 1
PanelStroke.Transparency = 0.35
PanelStroke.Parent = Panel

local PanelTitle = Instance.new("TextLabel")
PanelTitle.BackgroundTransparency = 1
PanelTitle.Position = UDim2.fromOffset(12, 10)
PanelTitle.Size = UDim2.new(1, -24, 0, 24)
PanelTitle.Font = Enum.Font.GothamBold
PanelTitle.TextSize = 16
PanelTitle.TextXAlignment = Enum.TextXAlignment.Left
PanelTitle.Text = "Late block monitor"
PanelTitle.Parent = Panel

local PanelBody = Instance.new("TextLabel")
PanelBody.BackgroundTransparency = 1
PanelBody.Position = UDim2.fromOffset(12, 38)
PanelBody.Size = UDim2.new(1, -24, 0, 62)
PanelBody.Font = Enum.Font.Gotham
PanelBody.TextSize = 13
PanelBody.TextXAlignment = Enum.TextXAlignment.Left
PanelBody.TextYAlignment = Enum.TextYAlignment.Top
PanelBody.TextWrapped = true
PanelBody.Text = ""
PanelBody.Parent = Panel

local PendingList = Instance.new("ScrollingFrame")
PendingList.Name = "PendingList"
PendingList.Position = UDim2.fromOffset(12, 104)
PendingList.Size = UDim2.new(1, -24, 1, -154)
PendingList.BackgroundTransparency = 0.18
PendingList.BorderSizePixel = 0
PendingList.ScrollBarThickness = 6
PendingList.CanvasSize = UDim2.new(0, 0, 0, 0)
PendingList.AutomaticCanvasSize = Enum.AutomaticSize.Y
PendingList.Parent = Panel

local PendingListCorner = Instance.new("UICorner")
PendingListCorner.CornerRadius = UDim.new(0, 8)
PendingListCorner.Parent = PendingList

local PendingListPadding = Instance.new("UIPadding")
PendingListPadding.PaddingTop = UDim.new(0, 6)
PendingListPadding.PaddingBottom = UDim.new(0, 6)
PendingListPadding.PaddingLeft = UDim.new(0, 6)
PendingListPadding.PaddingRight = UDim.new(0, 6)
PendingListPadding.Parent = PendingList

local PendingListLayout = Instance.new("UIListLayout")
PendingListLayout.Padding = UDim.new(0, 6)
PendingListLayout.SortOrder = Enum.SortOrder.LayoutOrder
PendingListLayout.Parent = PendingList

local ReplaceButton = Instance.new("TextButton")
ReplaceButton.Name = "ReplaceButton"
ReplaceButton.AnchorPoint = Vector2.new(1, 1)
ReplaceButton.Position = UDim2.new(1, -244, 1, -12)
ReplaceButton.Size = UDim2.fromOffset(110, 34)
ReplaceButton.Font = Enum.Font.GothamBold
ReplaceButton.TextSize = 14
ReplaceButton.Text = "Replace"
ReplaceButton.Visible = false
ReplaceButton.Parent = Panel

local ReplaceButtonCorner = Instance.new("UICorner")
ReplaceButtonCorner.CornerRadius = UDim.new(0, 8)
ReplaceButtonCorner.Parent = ReplaceButton

local SkipButton = Instance.new("TextButton")
SkipButton.Name = "SkipButton"
SkipButton.AnchorPoint = Vector2.new(1, 1)
SkipButton.Position = UDim2.new(1, -128, 1, -12)
SkipButton.Size = UDim2.fromOffset(110, 34)
SkipButton.Font = Enum.Font.GothamBold
SkipButton.TextSize = 14
SkipButton.Text = "Skip"
SkipButton.Visible = false
SkipButton.Parent = Panel

local SkipButtonCorner = Instance.new("UICorner")
SkipButtonCorner.CornerRadius = UDim.new(0, 8)
SkipButtonCorner.Parent = SkipButton

local SkipPickedButton = Instance.new("TextButton")
SkipPickedButton.Name = "SkipPickedButton"
SkipPickedButton.AnchorPoint = Vector2.new(1, 1)
SkipPickedButton.Position = UDim2.new(1, -12, 1, -12)
SkipPickedButton.Size = UDim2.fromOffset(110, 34)
SkipPickedButton.Font = Enum.Font.GothamBold
SkipPickedButton.TextSize = 14
SkipPickedButton.Text = "Skip picked"
SkipPickedButton.Visible = false
SkipPickedButton.Parent = Panel

local SkipPickedButtonCorner = Instance.new("UICorner")
SkipPickedButtonCorner.CornerRadius = UDim.new(0, 8)
SkipPickedButtonCorner.Parent = SkipPickedButton

-- khai báo trước
local buildCountMap
local formatCountLines
local getUniqueBlockNames

local function clearPendingSelection()
	table.clear(selectedPendingTypes)
end

local function clearPendingBillboards()
	for record, marker in pairs(pendingBillboards) do
		if marker.gui then
			marker.gui:Destroy()
		end
		if marker.part then
			marker.part:Destroy()
		end
		pendingBillboards[record] = nil
	end
end

local function createPendingBillboard(record, targetZone)
	local expectedCF = targetZone.CFrame:ToWorldSpace(record.sourceRelative)

	local part = Instance.new("Part")
	part.Name = "PendingMarker_" .. record.blockName
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = expectedCF
	part.Parent = pendingMarkerFolder

	local gui = Instance.new("BillboardGui")
	gui.Name = "PendingBillboard"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(180, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextScaled = false
	label.Text = "Pending | " .. record.blockName
	label.Parent = gui

	pendingBillboards[record] = {
		part = part,
		gui = gui,
	}
end

local function syncPendingBillboards(unresolvedRecords, targetZone)
	local alive = {}

	for _, record in ipairs(unresolvedRecords) do
		alive[record] = true
		if not pendingBillboards[record] then
			createPendingBillboard(record, targetZone)
		end
	end

	for record, marker in pairs(pendingBillboards) do
		if not alive[record] then
			if marker.gui then marker.gui:Destroy() end
			if marker.part then marker.part:Destroy() end
			pendingBillboards[record] = nil
		end
	end
end

local function hideSkipPanel()
	lastPendingSignature = nil
	lastPendingElapsedShown = -1
	Panel.Visible = false
	SkipButton.Visible = false
	SkipPickedButton.Visible = false
	ReplaceButton.Visible = false
	PanelTitle.Text = "Late block monitor"
	PanelBody.Text = ""
	for _, child in ipairs(PendingList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	clearPendingBillboards()
	table.clear(activeSkipPanelNames)
	clearPendingSelection()
	skipRequested = false
	skipPickedRequested = false
	replaceRequested = false
end

local function makePendingSignature(unresolvedRecords)
	local counts = {}

	for _, record in ipairs(unresolvedRecords) do
		counts[record.blockName] = (counts[record.blockName] or 0) + 1
	end

	local names = {}
	for name in pairs(counts) do
		names[#names + 1] = name
	end
	table.sort(names)

	local parts = {}
	for _, name in ipairs(names) do
		parts[#parts + 1] = name .. ":" .. counts[name] .. ":" .. tostring(selectedPendingTypes[name] == true)
	end

	return table.concat(parts, "|"), counts, names
end

local function refreshPendingUI(unresolvedRecords, elapsed, batchIndex, targetZone, force)
	local signature, counts, names = makePendingSignature(unresolvedRecords)

	if elapsed < SHOW_SKIP_AFTER_SECONDS then
		hideSkipPanel()
		return
	end

	syncPendingBillboards(unresolvedRecords, targetZone)

	if not force and signature == lastPendingSignature then
		PanelBody.Text = table.concat({
			("BATCH %d | pending after %.1fs"):format(batchIndex, elapsed or 0),
			("Total pending: %d"):format(#unresolvedRecords),
			("Picked types: %d"):format((function()
				local n = 0
				for _ in pairs(selectedPendingTypes) do
					n += 1
				end
				return n
			end)()),
			"Click a row to toggle pick",
		}, "\n")
		return
	end

	lastPendingSignature = signature

	for _, child in ipairs(PendingList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for selectedName in pairs(selectedPendingTypes) do
		if not counts[selectedName] then
			selectedPendingTypes[selectedName] = nil
		end
	end

	local selectedCount = 0
	for _ in pairs(selectedPendingTypes) do
		selectedCount += 1
	end

	PanelTitle.Text = "Unplaced blocks still pending"
	PanelBody.Text = table.concat({
		("BATCH %d | pending after %.1fs"):format(batchIndex, elapsed or 0),
		("Total pending: %d"):format(#unresolvedRecords),
		("Picked types: %d"):format(selectedCount),
		"Click a row to toggle pick",
	}, "\n")

	for _, name in ipairs(names) do
		local count = counts[name]
		local picked = selectedPendingTypes[name] == true

		local row = Instance.new("TextButton")
		row.Name = "Pending_" .. name
		row.Size = UDim2.new(1, 0, 0, 30)
		row.AutoButtonColor = true
		row.Font = Enum.Font.GothamBold
		row.TextSize = 14
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = (picked and "✓ " or "  ") .. name .. " x" .. count
		row.BackgroundTransparency = picked and 0.05 or 0.18
		row.Parent = PendingList

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		row.Activated:Connect(function()
			selectedPendingTypes[name] = not selectedPendingTypes[name] or nil
			refreshPendingUI(unresolvedRecords, elapsed, batchIndex, true)
		end)
	end

	Panel.Visible = true
	SkipButton.Visible = true
	SkipPickedButton.Visible = true
	ReplaceButton.Visible = true
	table.clear(activeSkipPanelNames)
	for _, name in ipairs(names) do
		activeSkipPanelNames[#activeSkipPanelNames + 1] = name
	end
end

local function getActionRecordsFromPending(unresolvedRecords)
	local selected = {}

	for _, record in ipairs(unresolvedRecords) do
		if selectedPendingTypes[record.blockName] then
			selected[#selected + 1] = record
		end
	end

	-- không chọn gì thì dùng toàn bộ như cũ
	if #selected == 0 then
		return unresolvedRecords, false
	end

	return selected, true
end

ReplaceButton.Activated:Connect(function()
	replaceRequested = true
end)

SkipButton.Activated:Connect(function()
	skipRequested = true
end)

SkipPickedButton.Activated:Connect(function()
	skipPickedRequested = true
end)

--==================================================
-- STABLE RECORD / MATCH HELPERS
--==================================================
local function roundTo(n, step)
	step = step or 0.001
	return math.floor((n / step) + 0.5) * step
end

local function vecKey(v, step)
	step = step or 0.01
	return table.concat({
		tostring(roundTo(v.X, step)),
		tostring(roundTo(v.Y, step)),
		tostring(roundTo(v.Z, step)),
	}, ",")
end

local function cfKey(cf, step)
	step = step or 0.001
	local comps = { cf:GetComponents() }
	for i = 1, 12 do
		comps[i] = tostring(roundTo(comps[i], step))
	end
	return table.concat(comps, ",")
end

local MATCH_MAX_POS = 2.25
local MATCH_MAX_REL = 0.45

local function buildMatchKey(blockName, blockId, relativeCF)
	return table.concat({
		blockName or "",
		tostring(blockId or ""),
		cfKey(relativeCF or CFrame.new(), 0.001),
	}, "|")
end

local function getInstancePath(inst, root)
	local parts = {}
	local current = inst

	while current and current ~= root do
		parts[#parts + 1] = current.Name
		current = current.Parent
	end

	if current ~= root then
		return inst.Name
	end

	local out = {}
	for i = #parts, 1, -1 do
		out[#out + 1] = parts[i]
	end

	return table.concat(out, "/")
end

local function makeBlockRecord(base)
	base.matchKey = buildMatchKey(base.blockName, base.blockId, base.sourceRelative)
	return base
end

local function cfDistance(a, b)
	local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = a:GetComponents()
	local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = b:GetComponents()

	return math.abs(ax - bx)
		+ math.abs(ay - by)
		+ math.abs(az - bz)
		+ math.abs(a00 - b00)
		+ math.abs(a01 - b01)
		+ math.abs(a02 - b02)
		+ math.abs(a10 - b10)
		+ math.abs(a11 - b11)
		+ math.abs(a12 - b12)
		+ math.abs(a20 - b20)
		+ math.abs(a21 - b21)
		+ math.abs(a22 - b22)
end

--==================================================
-- HELPERS
--==================================================
local function normalizeUploadBool(v)
	if type(v) == "boolean" then
		return v
	end
	return nil
end

local function firstBoolean(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "boolean" then
			return v
		end
	end
	return nil
end

local function extractUploadProperties(item)
	local props = {}

	props.Anchored = firstBoolean(item.Anchored, item.Anchor)
	props.CanCollide = firstBoolean(item.CanCollide, item.Cancollide, item.Collision)

	if type(item.Transparency) == "number" then
		props.Transparency = math.clamp(item.Transparency, 0, 1)
	end

	props.CastShadow = firstBoolean(item.CastShadow)

	if next(props) == nil then
		return nil
	end

	return props
end

local function color3ToRGBTable(c3)
	return {
		R = math.floor(c3.R * 255 + 0.5),
		G = math.floor(c3.G * 255 + 0.5),
		B = math.floor(c3.B * 255 + 0.5),
	}
end

local function normalizeColorInput(v)
	if typeof(v) == "Color3" then
		return color3ToRGBTable(v)
	end

	if type(v) ~= "table" then
		return nil
	end

	local r = v.R or v.r or v[1]
	local g = v.G or v.g or v[2]
	local b = v.B or v.b or v[3]

	if r == nil or g == nil or b == nil then
		return nil
	end

	return {
		R = math.floor(tonumber(r) + 0.5),
		G = math.floor(tonumber(g) + 0.5),
		B = math.floor(tonumber(b) + 0.5),
	}
end

local function colorTableToColor3(t)
	if type(t) ~= "table" then
		return Color3.new(1, 1, 1)
	end

	local r = tonumber(t.R or t.r or t[1]) or 255
	local g = tonumber(t.G or t.g or t[2]) or 255
	local b = tonumber(t.B or t.b or t[3]) or 255

	if r > 1 or g > 1 or b > 1 then
		return Color3.fromRGB(
			math.clamp(math.floor(r + 0.5), 0, 255),
			math.clamp(math.floor(g + 0.5), 0, 255),
			math.clamp(math.floor(b + 0.5), 0, 255)
		)
	end

	return Color3.new(r, g, b)
end

local function getModelPaintColor(model)
	local ppart = model:FindFirstChild("PPart", true)
	if ppart and ppart:IsA("BasePart") then
		return color3ToRGBTable(ppart.Color)
	end
	return { R = 255, G = 255, B = 255 }
end

local getPaintOwnerName
local rewriteSourcePathForOwner

local function getPPartColor(model)
	local ppart = model:FindFirstChild("PPart", true)
	if ppart and ppart:IsA("BasePart") then
		return ppart.Color
	end
	return Color3.new(1, 1, 1)
end

local function buildUnifiedPaintPayload(placedRecords, origin)
	local payload = {
		origin = origin or "CloneBlock",
		blocks = {},
	}

	local paintOwner = getPaintOwnerName()

	for _, item in ipairs(placedRecords) do
		local model = item.placedBlock
		if model and model.Parent then
			local record = item.record
			local paintColor = record.paintColor or getPPartColor(model)

			payload.blocks[#payload.blocks + 1] = {
				uid = record.uid,
				blockName = record.blockName,
				blockId = record.blockId,
				model = model,
				placedBlock = model,
				sourcePath = record.sourcePath,
				isClone = true,

				-- chỉ khác PropertiesBlock ở đây
				color = paintColor,

				-- giữ thêm để tương thích/fallback nếu cần
				sourceOwner = paintOwner,
				expectedColor = record.paintColor,
			}
		end
	end

	return payload
end

local PROPERTY_VALUE_NAMES = {
	Aim = true,
	MaxSpeed = true,
	MaxForce = true,
	FuseTime = true,
	FlightDistance = true,
	ShowCrosshairs = true,
	WaitDuration = true,
	SemitoneOffset = true,
	ReverseRotation = true,
	TargetAngle = true,
	ExtendLength = true,
	Speed = true,
	ReverseSpin = true,
	DepthScale = true,
	HeadScale = true,
	HeightScale = true,
	WidthScale = true,
}

local function readValueFromInstance(inst)
	if not inst then
		return nil
	end

	if inst:IsA("ValueBase") then
		return inst.Value
	end

	local directValue = inst:FindFirstChildWhichIsA("ValueBase")
	if directValue then
		return directValue.Value
	end

	return nil
end

local function findDescendantByName(root, name)
	if not root then
		return nil
	end

	for _, inst in ipairs(root:GetDescendants()) do
		if inst.Name == name then
			return inst
		end
	end

	return nil
end

local function collectPropertiesFromModel(model)
	local ppart = model:FindFirstChild("PPart", true)
	if not (ppart and ppart:IsA("BasePart")) then
		return nil
	end

	local props = {}

	-- 4 thuộc tính chính
	props.Anchored = ppart.Anchored
	props.CanCollide = ppart.CanCollide
	props.Transparency = ppart.Transparency
	props.CastShadow = ppart.CastShadow

	-- các Value cùng parent với PPart
	local parent = ppart.Parent
	if parent then
		for _, child in ipairs(parent:GetChildren()) do
			if PROPERTY_VALUE_NAMES[child.Name] and child:IsA("ValueBase") then
				props[child.Name] = child.Value
			end
		end
	end

	-- đặc biệt: SemitoneOffset -> ServoMaxTorque / AngularSpeed
	do
		local semitoneNode = findDescendantByName(ppart, "SemitoneOffset")
			or (parent and findDescendantByName(parent, "SemitoneOffset"))

		if semitoneNode then
			local semitoneValue = readValueFromInstance(semitoneNode)
			if semitoneValue ~= nil then
				props.SemitoneOffset = semitoneValue
			end

			local servoNode = findDescendantByName(semitoneNode, "ServoMaxTorque")
			local angularNode = findDescendantByName(semitoneNode, "AngularSpeed")

			local servoValue = readValueFromInstance(servoNode)
			local angularValue = readValueFromInstance(angularNode)

			if servoValue ~= nil then
				props.ServoMaxTorque = servoValue
			end
			if angularValue ~= nil then
				props.AngularSpeed = angularValue
			end
		end
	end

	-- đặc biệt: HingeConstraint -> MotorMaxTorque
	do
		local hingeNode = findDescendantByName(ppart, "HingeConstraint")
			or (parent and findDescendantByName(parent, "HingeConstraint"))

		if hingeNode then
			local motorNode = findDescendantByName(hingeNode, "MotorMaxTorque")
			local motorValue = readValueFromInstance(motorNode)

			if motorValue ~= nil then
				props.MotorMaxTorque = motorValue
			end
		end
	end

	if next(props) == nil then
		return nil
	end

	return props
end

local function buildUnifiedPropertiesPayload(placedRecords, origin)
	local payload = {
		origin = origin or "CloneBlock",
		blocks = {},
	}

	for _, item in ipairs(placedRecords) do
		local model = item.placedBlock
		if model and model.Parent then
			local props = item.record.sourceProperties or collectPropertiesFromModel(model)

			if props then
				payload.blocks[#payload.blocks + 1] = {
					uid = item.record.uid,
					blockName = item.record.blockName,
					blockId = item.record.blockId,
					model = model,
					placedBlock = model,
					sourcePath = item.record.sourcePath,
					isClone = true,

					-- giữ schema cũ
					properties = props,

					-- thêm field trực tiếp để tương thích receiver cũ
					Anchored = props.Anchored,
					CanCollide = props.CanCollide,
					Transparency = props.Transparency,
					CastShadow = props.CastShadow,

					expectedProperties = item.record.sourceProperties,
				}
			end
		end
	end

	return payload
end

local function pushPropertiesPayload(placedRecords, origin)
	if _G.HasProperties ~= true then
		return
	end

	_G.PropertiesBlock = buildUnifiedPropertiesPayload(placedRecords, origin)

	repeat
		task.wait(0.1)
	until _G.PropertiesBlock == false
end

local function pushPaintPayload(placedRecords, origin)
	if _G.HasPaint ~= true then
		return
	end

	_G.PaintBlock = buildUnifiedPaintPayload(placedRecords, origin)

	repeat
		task.wait(0.1)
	until _G.PaintBlock == false
end

local function report(statusFn, kind, message)
	if type(statusFn) == "function" then
		statusFn(kind, message)
	else
		local text = ("[CloneBlock] %s"):format(message)
		if kind == "error" then
			warn(text)
		else
			print(text)
		end
	end
end

local function makeStatusFn(customFn)
	if type(customFn) == "function" then
		return customFn
	end

	return function(kind, message)
		local text = ("[CloneBlock] %s"):format(message)
		if kind == "error" then
			warn(text)
		else
			print(text)
		end
	end
end

local function resolvePath(path)
	if typeof(path) == "Instance" then
		return path
	end

	if type(path) ~= "string" then
		return nil
	end

	local current = game
	for segment in path:gmatch("[^%.]+") do
		if segment == "game" then
			current = game
		elseif segment == "workspace" or segment == "Workspace" then
			current = workspace
		else
			current = current:WaitForChild(segment)
		end
	end

	return current
end

local function getTeamNameFromZone(zone)
	return ZONE_TO_TEAM_NAME[zone]
end

local function getOwnZone()
	local team = LocalPlayer.Team
	if not team then
		return nil
	end
	return TEAM_ZONES_BY_NAME[team.Name]
end

local function isAllMode(mode)
	return mode == true or mode == "all"
end

local function getLeaderNameForSourceTeam(sourceTeamName)
	local teamObj = Teams:FindFirstChild(sourceTeamName)
	if not teamObj then
		return nil
	end

	local leader = teamObj:FindFirstChild("TeamLeader")
	if not leader or not leader:IsA("StringValue") then
		return nil
	end

	local leaderName = leader.Value
	if not leaderName or leaderName == "" then
		return nil
	end

	return leaderName
end

local function getBlocksRoot()
	return workspace:WaitForChild("Blocks")
end

local function getBlocksOwnerName()
	if _G.ChangeData ~= true then
		return LocalPlayer.Name
	end

	local team = LocalPlayer.Team
	if not team then
		return LocalPlayer.Name
	end

	local teamObj = Teams:FindFirstChild(team.Name)
	if not teamObj then
		return LocalPlayer.Name
	end

	local leader = teamObj:FindFirstChild("TeamLeader")
	if not (leader and leader:IsA("StringValue")) then
		return LocalPlayer.Name
	end

	local leaderName = leader.Value
	if type(leaderName) ~= "string" or leaderName == "" then
		return LocalPlayer.Name
	end

	return leaderName
end

getPaintOwnerName = function()
	if _G.ChangeData ~= true then
		return LocalPlayer.Name
	end

	local team = LocalPlayer.Team
	if not team then
		return LocalPlayer.Name
	end

	local teamObj = Teams:FindFirstChild(team.Name) or team
	local leader = teamObj and teamObj:FindFirstChild("TeamLeader")
	if not leader then
		return LocalPlayer.Name
	end

	if leader:IsA("StringValue") then
		return (leader.Value ~= "" and leader.Value) or LocalPlayer.Name
	end

	if leader:IsA("ObjectValue") and leader.Value then
		return leader.Value.Name
	end

	return LocalPlayer.Name
end

rewriteSourcePathForOwner = function(sourcePath, ownerName)
	if type(sourcePath) ~= "string" or sourcePath == "" then
		return sourcePath
	end

	local rest = sourcePath:match("^[^/]+/(.+)$")
	if rest then
		return ownerName .. "/" .. rest
	end

	return ownerName .. "/" .. sourcePath
end

local function getLocalBlocksFolder()
	return getBlocksRoot():WaitForChild(getBlocksOwnerName())
end

local function getPlaceRF()
	return LocalPlayer:WaitForChild("Backpack")
		:WaitForChild("BuildingTool")
		:WaitForChild("RF")
end

local getScalingTool
local equipScalingTool

getScalingTool = function()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	return (backpack and backpack:FindFirstChild("ScalingTool"))
		or char:FindFirstChild("ScalingTool")
end

equipScalingTool = function()
	local tool = getScalingTool()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local hum = char:FindFirstChildOfClass("Humanoid")

	if tool and hum then
		pcall(function()
			hum:EquipTool(tool)
		end)
	end
end

--==================================================
-- TOOL HOLD SYSTEM
--==================================================
local heldToolName = nil
local heldToolLocked = false
local holdToolLoopRunning = false

local function getToolByName(toolName)
	local char = LocalPlayer.Character
	local backpack = LocalPlayer:FindFirstChild("Backpack")

	if char then
		local t = char:FindFirstChild(toolName)
		if t and t:IsA("Tool") then
			return t
		end
	end

	if backpack then
		local t = backpack:FindFirstChild(toolName)
		if t and t:IsA("Tool") then
			return t
		end
	end

	return nil
end

local function equipToolByName(toolName)
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end

	local tool = getToolByName(toolName)
	if not tool then
		return false
	end

	return pcall(function()
		hum:EquipTool(tool)
	end)
end

local function releaseAnyHeldTool()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum:UnequipTools()
		end)
	end
end

local function startHoldToolMonitor()
	if holdToolLoopRunning then
		return
	end

	holdToolLoopRunning = true

	task.spawn(function()
		while holdToolLoopRunning do
			if heldToolLocked and heldToolName then
				local char = LocalPlayer.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local tool = getToolByName(heldToolName)

				if tool and hum and (not char:FindFirstChild(heldToolName)) then
					pcall(function()
						hum:EquipTool(tool)
					end)
				end
			end

			if not heldToolLocked then
				holdToolLoopRunning = false
				break
			end

			task.wait(0.15)
		end
	end)
end

local function holdTool(toolName, shouldHold)
	-- holdTool(false) -> nhả tool đang giữ
	if toolName == false and shouldHold == nil then
		heldToolName = nil
		heldToolLocked = false
		releaseAnyHeldTool()
		return true
	end

	-- chỉ release đúng tool đang được giữ
	if type(toolName) == "string" and shouldHold == false then
		if heldToolName == toolName then
			heldToolName = nil
			heldToolLocked = false
			releaseAnyHeldTool()
			return true
		end
		return false
	end

	-- holdTool("ToolA", true)
	if type(toolName) == "string" and shouldHold == true then
		-- nếu đang giữ tool khác thì thả tool cũ trước
		if heldToolLocked and heldToolName and heldToolName ~= toolName then
			releaseAnyHeldTool()
		end

		heldToolName = toolName
		heldToolLocked = true
		startHoldToolMonitor()

		local ok = equipToolByName(toolName)
		return ok
	end

	return false
end
---------------------------------------------------------------------

local function getScalingRF()
	local backpack = LocalPlayer:WaitForChild("Backpack")
	local tool = backpack:FindFirstChild("ScalingTool") or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("ScalingTool"))

	if not tool then
		equipScalingTool()
		local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
		tool = char:WaitForChild("ScalingTool", 5)
	end

	assert(tool, "ScalingTool not found")
	return tool:WaitForChild("RF")
end

local function getModelPivotData(model)
	local okPivot, pivot = pcall(function()
		return model:GetPivot()
	end)
	if not okPivot then
		return nil, nil, nil
	end

	local okSize, size = pcall(function()
		return model:GetExtentsSize()
	end)
	if not okSize then
		return nil, nil, nil
	end

	local rotationOnly = pivot - pivot.Position
	return pivot, size, rotationOnly
end

local function isPointInsideZoneXZ(worldPos, zone)
	local p = zone.CFrame:PointToObjectSpace(worldPos)
	local half = zone.Size * 0.5

	return math.abs(p.X) <= half.X
		and math.abs(p.Z) <= half.Z
end

local function isModelInsideZoneXZ(model, zone)
	local boxCF, boxSize = model:GetBoundingBox()
	local half = boxSize * 0.5

	local corners = {
		Vector3.new(-half.X, -half.Y, -half.Z),
		Vector3.new(-half.X, -half.Y,  half.Z),
		Vector3.new(-half.X,  half.Y, -half.Z),
		Vector3.new(-half.X,  half.Y,  half.Z),
		Vector3.new( half.X, -half.Y, -half.Z),
		Vector3.new( half.X, -half.Y,  half.Z),
		Vector3.new( half.X,  half.Y, -half.Z),
		Vector3.new( half.X,  half.Y,  half.Z),
	}

	for i = 1, 8 do
		local worldCorner = (boxCF * CFrame.new(corners[i])).Position

		if not isPointInsideZoneXZ(worldCorner, zone) then
			return false
		end
	end

	return true
end

local function getSourceZoneFromInput(zoneOrPath)
	if typeof(zoneOrPath) == "Instance" then
		if zoneOrPath:IsA("BasePart") then
			return zoneOrPath
		end
		return nil
	end

	if type(zoneOrPath) == "string" then
		local plr = Players:FindFirstChild(zoneOrPath)
		if plr and plr.Team then
			return TEAM_ZONES_BY_NAME[plr.Team.Name]
		end

		local zone = resolvePath(zoneOrPath)
		if zone and zone:IsA("BasePart") then
			return zone
		end
	end

	return nil
end

local function getSourceFolders(sourceTeamName, mode)
	local blocksRoot = getBlocksRoot()

	if not isAllMode(mode) then
		local leaderName = getLeaderNameForSourceTeam(sourceTeamName)
		if not leaderName then
			return nil, "không tìm thấy TeamLeader của team nguồn"
		end

		local sourceFolder = blocksRoot:FindFirstChild(leaderName)
		if not sourceFolder then
			return nil, "không tìm thấy folder Blocks của leader: " .. leaderName
		end

		return { sourceFolder }
	end

	local sourceFolders = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == sourceTeamName then
			local folder = blocksRoot:FindFirstChild(plr.Name)
			if folder then
				sourceFolders[#sourceFolders + 1] = folder
			end
		end
	end

	if #sourceFolders == 0 then
		return nil, "không tìm thấy folder Blocks nào của người chơi thuộc team nguồn"
	end

	return sourceFolders
end

buildCountMap = function(records)
	local counts = {}

	for _, record in ipairs(records) do
		counts[record.blockName] = (counts[record.blockName] or 0) + 1
	end

	local names = {}
	for name in pairs(counts) do
		names[#names + 1] = name
	end

	table.sort(names, function(a, b)
		local ca, cb = counts[a], counts[b]
		if ca == cb then
			return a < b
		end
		return ca > cb
	end)

	return counts, names
end

formatCountLines = function(records, headerPrefix)
	local counts, names = buildCountMap(records)
	local lines = {}

	if headerPrefix then
		lines[#lines + 1] = headerPrefix
	end

	lines[#lines + 1] = ("Total: %d"):format(#records)

	for _, name in ipairs(names) do
		lines[#lines + 1] = ("- %s x%d"):format(name, counts[name])
	end

	return table.concat(lines, "\n"), counts, names
end

local function printPlannedBlocks(records, statusFn)
	local text = formatCountLines(records, "CHECK SUMMARY")
	for line in text:gmatch("[^\n]+") do
		report(statusFn, "info", line)
	end

	for i, record in ipairs(records) do
		report(
			statusFn,
			"info",
			("[%03d] %s | id=%s | path=%s | key=%s"):format(
				i,
				tostring(record.blockName),
				tostring(record.blockId),
				tostring(record.sourcePath),
				tostring(record.matchKey)
			)
		)
	end
end

getUniqueBlockNames = function(records)
	local seen = {}
	local names = {}

	for _, record in ipairs(records) do
		local blockName = record.blockName
		if blockName and not seen[blockName] then
			seen[blockName] = true
			names[#names + 1] = blockName
		end
	end

	table.sort(names)
	return names
end

local function isPriorityBlockName(blockName)
	return type(blockName) == "string" and string.find(blockName, "Block", 1, true) ~= nil
end

local function splitPriorityRecords(records)
	local priority = {}
	local normal = {}

	for _, record in ipairs(records) do
		if isPriorityBlockName(record.blockName) then
			priority[#priority + 1] = record
		else
			normal[#normal + 1] = record
		end
	end

	return priority, normal
end

local function collectBlockRecords(sourceFolders, sourceZone)
	local records = {}
	local skippedOutside = 0
	local seq = 0

	for _, sourceFolder in ipairs(sourceFolders) do
		for _, inst in ipairs(sourceFolder:GetDescendants()) do
			if inst:IsA("Model") and inst:FindFirstChildWhichIsA("BasePart", true) then
				local blockName = inst.Name
				local blockId = BLOCK_IDS[blockName]

				if blockId then
					local pivot, size, rotationOnly = getModelPivotData(inst)

					if pivot and size and rotationOnly then
						if isModelInsideZoneXZ(inst, sourceZone) then
							seq += 1

							local sourceRelative = sourceZone.CFrame:ToObjectSpace(pivot)

                            records[#records + 1] = makeBlockRecord({
                                uid = ("%s#%05d"):format(sourceFolder.Name, seq),
                                sourceOwner = sourceFolder.Name,
                                sourcePath = getInstancePath(inst, sourceFolder),

                                blockName = blockName,
                                blockId = blockId,

                                sourcePivot = pivot,
                                sourceSize = size,
                                sourceRotationOnly = rotationOnly,
                                sourceRelative = sourceRelative,

                                paintColor = getModelPaintColor(inst),
                                sourceProperties = collectPropertiesFromModel(inst),
                            })
						else
							skippedOutside += 1
						end
					end
				end
			end
		end
	end

	return records, skippedOutside
end

local function collectNewModels(destFolder, knownModels)
	local models = {}

	for _, child in ipairs(destFolder:GetChildren()) do
		if child:IsA("Model") and not knownModels[child] then
			models[#models + 1] = child
		end
	end

	return models
end

local function dist2(a, b)
	local d = a - b
	return d.X * d.X + d.Y * d.Y + d.Z * d.Z
end

local function getCandidateInfo(model, targetZone)
	local pivot, size, rotationOnly = getModelPivotData(model)
	if not pivot or not size or not rotationOnly then
		return nil
	end

	local relative = targetZone.CFrame:ToObjectSpace(pivot)

	return {
		model = model,
		pivot = pivot,
		size = size,
		rotationOnly = rotationOnly,
		relative = relative,

		blockName = model.Name,
		blockId = BLOCK_IDS[model.Name],
		matchKey = buildMatchKey(model.Name, BLOCK_IDS[model.Name], relative),
	}
end

local function candidateScore(record, item, expectedPivot)
	if item.blockName ~= record.blockName then
		return nil
	end

	if item.blockId ~= record.blockId then
		return nil
	end

	local posDist = (item.pivot.Position - expectedPivot.Position).Magnitude
	local relDist = cfDistance(item.relative, record.sourceRelative)

	if posDist > MATCH_MAX_POS then
		return nil
	end
	if relDist > MATCH_MAX_REL then
		return nil
	end

	return (posDist * 100) + (relDist * 10)
end

local function claimBestModel(candidates, used, record, expectedPivot)
	for i, item in ipairs(candidates) do
		if not used[i]
			and item.matchKey == record.matchKey
			and item.blockName == record.blockName
			and item.blockId == record.blockId then
			return i
		end
	end

	local bestIndex = nil
	local bestScore = nil

	for i, item in ipairs(candidates) do
		if not used[i] then
			local score = candidateScore(record, item, expectedPivot)
			if score and (not bestScore or score < bestScore) then
				bestScore = score
				bestIndex = i
			end
		end
	end

	return bestIndex
end

local function matchBatchToModels(batchRecords, newModels, targetZone, knownModels)
	local candidates = {}

	for _, model in ipairs(newModels) do
		local info = getCandidateInfo(model, targetZone)
		if info then
			candidates[#candidates + 1] = info
		end
	end

	local used = {}
	local placedRecords = {}

	for _, record in ipairs(batchRecords) do
		local expectedPivot = targetZone.CFrame:ToWorldSpace(record.sourceRelative)
		local index = claimBestModel(candidates, used, record, expectedPivot)

		if index then
			used[index] = true
			local model = candidates[index].model
			knownModels[model] = true

			placedRecords[#placedRecords + 1] = {
				record = record,
				placedBlock = model,
			}
		end
	end

	return placedRecords
end

local function dispatchBatchPlace(batchRecords, targetZone, placeRF)
	for _, record in ipairs(batchRecords) do
		task.spawn(function()
			pcall(function()
				placeRF:InvokeServer(
					record.blockName,
					record.blockId,
					targetZone,
					record.sourceRelative,
					true
				)
			end)
		end)
	end
end

local function dispatchBatchScale(placedRecords, targetZone, scalingRF)
	local done = 0
	local total = #placedRecords

	for _, item in ipairs(placedRecords) do
		task.spawn(function()
			if item.placedBlock and item.placedBlock.Parent then
				pcall(function()
					scalingRF:InvokeServer(
						item.placedBlock,
						item.record.sourceSize,
						targetZone.CFrame:ToWorldSpace(item.record.sourceRelative)
					)
				end)
			end
			done += 1
		end)
	end

	while done < total do
		task.wait()
	end
end

local function applyCurrentBatchSkip(unresolvedRecords, statusFn, batchIndex)
	local names = getUniqueBlockNames(unresolvedRecords)
	if #names == 0 then
		return
	end

	for _, name in ipairs(names) do
		skippedBlockNames[name] = true
	end

	report(
		statusFn,
		"error",
		("PLACE %d | SKIP applied | skipped types = %s"):format(
			batchIndex,
			table.concat(names, ", ")
		)
	)
end

local function waitForLatePlacementsOrSkip(batchRecords, placedRecords, targetZone, destFolder, knownModels, placeRF, statusFn, batchIndex)
	local placedSet = {}
	local skippedOnceSet = {}

	for _, item in ipairs(placedRecords) do
		placedSet[item.record] = true
	end

	local startedAt = os.clock()

	local function getCurrentUnresolved()
		local unresolved = {}

		for _, record in ipairs(batchRecords) do
			if not placedSet[record] and not skippedOnceSet[record] and not skippedBlockNames[record.blockName] then
				unresolved[#unresolved + 1] = record
			end
		end

		return unresolved
	end

	while true do
		local unresolved = getCurrentUnresolved()

		if #unresolved == 0 then
			hideSkipPanel()
			return placedRecords
		end

		local elapsed = os.clock() - startedAt

		if elapsed >= SHOW_SKIP_AFTER_SECONDS then
			refreshPendingUI(unresolved, elapsed, batchIndex, targetZone, false)
		else
			hideSkipPanel()
			lastPendingSignature = nil
		end

		local actionRecords, hasSelection = getActionRecordsFromPending(unresolved)

		if replaceRequested then
			replaceRequested = false

			report(
				statusFn,
				"info",
				("PLACE %d | Replace clicked | retrying %d block(s)"):format(batchIndex, #actionRecords)
			)

			dispatchBatchPlace(actionRecords, targetZone, placeRF)
			task.wait(PLACE_SETTLE_SECONDS)

			local newModels = collectNewModels(destFolder, knownModels)
			if #newModels > 0 then
				local extraPlaced = matchBatchToModels(actionRecords, newModels, targetZone, knownModels)
				for _, item in ipairs(extraPlaced) do
					if not placedSet[item.record] then
						placedSet[item.record] = true
						placedRecords[#placedRecords + 1] = item
					end
				end
			end

			startedAt = os.clock()
			task.wait(LATE_POLL_STEP)
			continue
		end

		if skipPickedRequested then
			skipPickedRequested = false

			for _, record in ipairs(actionRecords) do
				skippedOnceSet[record] = true
			end

			report(
				statusFn,
				"info",
				("PLACE %d | Skip picked clicked | skipped once = %d"):format(batchIndex, #actionRecords)
			)

			task.wait(LATE_POLL_STEP)
			continue
		end

		if skipRequested then
			skipRequested = false

			applyCurrentBatchSkip(actionRecords, statusFn, batchIndex)
			hideSkipPanel()

			task.wait(LATE_POLL_STEP)
			continue
		end

		local newModels = collectNewModels(destFolder, knownModels)
		if #newModels > 0 then
			local extraPlaced = matchBatchToModels(unresolved, newModels, targetZone, knownModels)
			for _, item in ipairs(extraPlaced) do
				if not placedSet[item.record] then
					placedSet[item.record] = true
					placedRecords[#placedRecords + 1] = item
				end
			end
		end

		task.wait(LATE_POLL_STEP)
	end
end

local function processPlaceBatches(records, targetZone, destFolder, knownModels, placeRF, statusFn)
	local allPlacedRecords = {}
	local batchIndex = 0

	for startIndex = 1, #records, BATCH_SIZE do
		batchIndex += 1

		local batchRecords = {}
		local endIndex = math.min(startIndex + BATCH_SIZE - 1, #records)

		for i = startIndex, endIndex do
			local record = records[i]
			if not skippedBlockNames[record.blockName] then
				batchRecords[#batchRecords + 1] = record
			else
				report(statusFn, "info", ("PLACE %d | already skipped type | %s"):format(batchIndex, record.blockName))
			end
		end

		if #batchRecords > 0 then
			report(statusFn, "info", ("PLACE %d | sending %d block(s)"):format(batchIndex, #batchRecords))

			dispatchBatchPlace(batchRecords, targetZone, placeRF)

			task.wait(PLACE_SETTLE_SECONDS)

			local newModels = collectNewModels(destFolder, knownModels)
			local placedRecords = matchBatchToModels(batchRecords, newModels, targetZone, knownModels)

			if #placedRecords > 0 then
				report(statusFn, "info", ("PLACE %d | matched immediately = %d/%d"):format(batchIndex, #placedRecords, #batchRecords))
			end

			local placedSet = {}
			for _, item in ipairs(placedRecords) do
				placedSet[item.record] = true
			end

			local unresolved = {}
			for _, record in ipairs(batchRecords) do
				if not placedSet[record] then
					unresolved[#unresolved + 1] = record
				end
			end

			if #unresolved > 0 then
				report(
					statusFn,
					"error",
					("PLACE %d | waiting late place | matched=%d/%d | pending=%s"):format(
						batchIndex,
						#placedRecords,
						#batchRecords,
						table.concat(getUniqueBlockNames(unresolved), ", ")
					)
				)

                placedRecords = waitForLatePlacementsOrSkip(
                    batchRecords,
                    placedRecords,
                    targetZone,
                    destFolder,
                    knownModels,
                    placeRF,
                    statusFn,
                    batchIndex
                )
			end

			for _, item in ipairs(placedRecords) do
				allPlacedRecords[#allPlacedRecords + 1] = item
			end
		end
	end

	return allPlacedRecords
end

local function processScaleBatches(placedRecords, targetZone, scalingRF, statusFn)
	local batchIndex = 0
	local scaledTotal = 0

	for startIndex = 1, #placedRecords, BATCH_SIZE do
		batchIndex += 1

		local batchRecords = {}
		local endIndex = math.min(startIndex + BATCH_SIZE - 1, #placedRecords)

		for i = startIndex, endIndex do
			batchRecords[#batchRecords + 1] = placedRecords[i]
		end

		if #batchRecords > 0 then
			report(statusFn, "info", ("SCALE %d | scaling %d block(s)"):format(batchIndex, #batchRecords))

			equipScalingTool()
			dispatchBatchScale(batchRecords, targetZone, scalingRF)

			scaledTotal += #batchRecords

			report(statusFn, "info", ("SCALE %d | done | %d/%d"):format(batchIndex, #batchRecords, #batchRecords))
			task.wait(SCALE_BATCH_PAUSE)
		end
	end

	return scaledTotal
end

--==================================================
-- MAIN
--==================================================
local HttpService = game:GetService("HttpService")

local function toVector3(v)
	if typeof(v) == "Vector3" then
		return v
	end

	if type(v) == "table" then
		if #v >= 3 then
			return Vector3.new(v[1], v[2], v[3])
		end

		if v.X and v.Y and v.Z then
			return Vector3.new(v.X, v.Y, v.Z)
		end
	end

	return nil
end

local function toCFrame(v)
	if typeof(v) == "CFrame" then
		return v
	end

	if type(v) == "table" then
		if #v == 12 then
			return CFrame.new(table.unpack(v))
		end

		if v.CFrame ~= nil then
			return toCFrame(v.CFrame)
		end
	end

	return nil
end

local function normalizeUploadBuild(raw)
	if type(raw) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok then
			return nil, "UploadBuild JSON không hợp lệ"
		end
		raw = decoded
	end

	if type(raw) ~= "table" then
		return nil, "UploadBuild phải là table hoặc JSON string"
	end

	return raw
end

local function BuildUploadToRecords(upload)
	local normalized, err = normalizeUploadBuild(upload)
	if not normalized then
		return nil, err
	end

	upload = normalized

	local defaultBlockName = upload.BlockType
	local defaultBlockId = BLOCK_IDS[defaultBlockName]
	if not defaultBlockId then
		return nil, "BlockType không hợp lệ hoặc không có trong BLOCK_IDS: " .. tostring(defaultBlockName)
	end

	local rootPos = toVector3(upload.RootPos)
	if not rootPos then
		return nil, "RootPos không hợp lệ"
	end

	local build = upload.Build
	if type(build) ~= "table" or #build == 0 then
		return nil, "Build trống"
	end

	local rootItem = build[1]
	if type(rootItem) ~= "table" then
		return nil, "Build[1] không hợp lệ"
	end

	local rootCF = toCFrame(rootItem.CFrame)
	if not rootCF then
		return nil, "Build[1].CFrame không hợp lệ"
	end

	local rootRotationOnly = rootCF - rootCF.Position
	local records = {}

	for index, item in ipairs(build) do
		if type(item) == "table" then
			local itemCF = toCFrame(item.CFrame)
			local itemSize = toVector3(item.Size)

			local itemBlockName = defaultBlockName
			if type(item.Type) == "string" and item.Type ~= "" then
				itemBlockName = item.Type
			end

			local itemBlockId = BLOCK_IDS[itemBlockName]

			if itemCF and itemSize and itemBlockId then
				local relativeToRoot = rootCF:ToObjectSpace(itemCF)
				local finalRelative = CFrame.new(rootPos) * rootRotationOnly * relativeToRoot

                records[#records + 1] = makeBlockRecord({
                    uid = ("upload#%05d"):format(index),
                    sourcePath = ("Build[%d]"):format(index),

                    blockName = itemBlockName,
                    blockId = itemBlockId,

                    sourceSize = itemSize,
                    sourcePivot = itemCF,
                    sourceRelative = finalRelative,
                    sourceRotationOnly = finalRelative - finalRelative.Position,

                    paintColor = normalizeColorInput(item.Color),
                    sourceProperties = extractUploadProperties(item),
                })
			end
		end
	end

	return records
end

local function CloneBlockUpload(upload, customStatusFn)
	refreshBlockIds()
	for k in pairs(skippedBlockNames) do
		skippedBlockNames[k] = nil
	end

	hideSkipPanel()
	skipRequested = false
	replaceRequested = false

	local statusFn = makeStatusFn(customStatusFn)
	report(statusFn, "info", "START | Bắt đầu CloneBlockUpload")

	local targetZone = getOwnZone()
	if not targetZone then
		report(statusFn, "error", "không tìm thấy zone của team hiện tại")
		return
	end

	local records, err = BuildUploadToRecords(upload)
	if not records then
		report(statusFn, "error", err)
		return
	end

	if #records == 0 then
		report(statusFn, "error", "không có record hợp lệ trong UploadBuild")
		return
	end

	report(statusFn, "info", ("UPLOAD | records=%d | BlockType=%s"):format(#records, tostring(upload.BlockType)))

	local priorityRecords, normalRecords = splitPriorityRecords(records)

	report(statusFn, "info", ("PRIORITY | contains 'Block' = %d"):format(#priorityRecords))
	printPlannedBlocks(priorityRecords, statusFn)

	report(statusFn, "info", ("NORMAL | without 'Block' = %d"):format(#normalRecords))
	printPlannedBlocks(normalRecords, statusFn)

	local destFolder = getLocalBlocksFolder()
	local placeRF = getPlaceRF()

	local knownModels = {}
	for _, obj in ipairs(destFolder:GetChildren()) do
		if obj:IsA("Model") then
			knownModels[obj] = true
		end
	end

	report(statusFn, "info", ("STEP 2/3 | PLACE phase | batchSize=%d"):format(BATCH_SIZE))

	local placedPriority = processPlaceBatches(priorityRecords, targetZone, destFolder, knownModels, placeRF, statusFn)
	local placedNormal = processPlaceBatches(normalRecords, targetZone, destFolder, knownModels, placeRF, statusFn)

	local placedRecords = {}
	for _, item in ipairs(placedPriority) do
		placedRecords[#placedRecords + 1] = item
	end
	for _, item in ipairs(placedNormal) do
		placedRecords[#placedRecords + 1] = item
	end

	report(statusFn, "info", ("STEP 3/3 | SCALE phase | placed=%d"):format(#placedRecords))
	holdTool("ScalingTool", true)

	local scalingRF = getScalingRF()
	local scaledCount = processScaleBatches(placedRecords, targetZone, scalingRF, statusFn)

	holdTool(false)
	hideSkipPanel()

    pushPaintPayload(placedRecords, "CloneBlockUpload")
    if _G.HasProperties == true then
        holdTool("PropertiesTool", true)
        pushPropertiesPayload(placedRecords, "CloneBlockUpload")
        holdTool(false)
    end

	report(statusFn, "info", ("Completed | upload=%d | placed=%d | scaled=%d"):format(#records, #placedRecords, scaledCount))
end

local function CloneBlock(sourceZoneOrPath, mode, customStatusFn)
	refreshBlockIds()
	for k in pairs(skippedBlockNames) do
		skippedBlockNames[k] = nil
	end

	hideSkipPanel()
	skipRequested = false

	local statusFn = makeStatusFn(customStatusFn)
	report(statusFn, "info", "START | Bắt đầu CloneBlock")

	local sourceZone = getSourceZoneFromInput(sourceZoneOrPath)
	if not sourceZone then
		report(statusFn, "error", "source zone không hợp lệ")
		return
	end

	local sourceTeamName = getTeamNameFromZone(sourceZone)
	if not sourceTeamName then
		report(statusFn, "error", "không tìm thấy team tương ứng với zone này")
		return
	end

	local myTeam = LocalPlayer.Team
	local myTeamName = myTeam and myTeam.Name or "None"

	report(statusFn, "info", ("INFO | My Team = %s"):format(myTeamName))
	report(statusFn, "info", ("INFO | Copy Team = %s"):format(sourceTeamName))

	local targetZone = getOwnZone()
	if not targetZone then
		report(statusFn, "error", "không tìm thấy zone của team hiện tại")
		return
	end

	report(statusFn, "info", "STEP 1/3 | collecting source folders...")
	local sourceFolders, err = getSourceFolders(sourceTeamName, mode)
	if not sourceFolders then
		report(statusFn, "error", err)
		return
	end

	report(statusFn, "info", "STEP 1/3 | scanning snapshot...")
	local snapshot, skippedOutside = collectBlockRecords(sourceFolders, sourceZone)

	if #snapshot == 0 then
		report(statusFn, "error", "không có model hợp lệ để clone")
		return
	end

    report(statusFn, "info", ("STEP 1/3 | snapshot done | inside=%d | skippedOutsideXZ=%d"):format(#snapshot, skippedOutside))

    local prioritySnapshot, normalSnapshot = splitPriorityRecords(snapshot)

    report(statusFn, "info", ("PRIORITY | contains 'Block' = %d"):format(#prioritySnapshot))
    printPlannedBlocks(prioritySnapshot, statusFn)

    report(statusFn, "info", ("NORMAL | without 'Block' = %d"):format(#normalSnapshot))
    printPlannedBlocks(normalSnapshot, statusFn)

	local destFolder = getLocalBlocksFolder()
	local placeRF = getPlaceRF()

	local knownModels = {}
	for _, obj in ipairs(destFolder:GetChildren()) do
		if obj:IsA("Model") then
			knownModels[obj] = true
		end
	end

    report(statusFn, "info", ("STEP 2/3 | PLACE phase | batchSize=%d"):format(BATCH_SIZE))

    local placedPriority = processPlaceBatches(prioritySnapshot, targetZone, destFolder, knownModels, placeRF, statusFn)
    local placedNormal = processPlaceBatches(normalSnapshot, targetZone, destFolder, knownModels, placeRF, statusFn)

    local placedRecords = {}
    for _, item in ipairs(placedPriority) do
        placedRecords[#placedRecords + 1] = item
    end
    for _, item in ipairs(placedNormal) do
        placedRecords[#placedRecords + 1] = item
    end

	report(statusFn, "info", ("STEP 3/3 | SCALE phase | placed=%d"):format(#placedRecords))
	holdTool("ScalingTool", true)

	local scalingRF = getScalingRF()
	local scaledCount = processScaleBatches(placedRecords, targetZone, scalingRF, statusFn)

	holdTool(false)
	hideSkipPanel()

    pushPaintPayload(placedRecords, "CloneBlock")
    if _G.HasProperties == true then
        holdTool("PropertiesTool", true)
        pushPropertiesPayload(placedRecords, "CloneBlock")
        holdTool(false)
    end

	report(statusFn, "info", ("Completed | snapshot=%d | placed=%d | scaled=%d"):format(#snapshot, #placedRecords, scaledCount))

	local notify = _G.HAPPYnotification
	if type(notify) == "function" then
		notify({
			title = "Complete",
			text = "All block cloned",
			color = { 0, 255, 0 },
			time = 5,
		})
	else
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Complete",
				Text = "All block cloned",
				Duration = 5,
			})
		end)
	end
end

--==================================================
-- RUN
--==================================================
--CloneBlock("trong10072012")
--CloneBlock(Green, "all")

_G.UploadBuild = {
	BlockType = "WoodBlock",
	RootPos = { 0, 10, 0 },
	Build = {
		{
			Type = "WoodBlock",
			CFrame = { 0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
			Size = { 2, 2, 2 },
            Color = {255, 0, 0},
            Transparency = 0.75,
            Anchor = false,
            Cancollide = true,
            CastShadow = false,
		},
		{
			Type = "WoodBlock",
			CFrame = { 5, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
			Size = { 2, 2, 2 },
		},
		{
			CFrame = { 10, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
			Size = { 2, 2, 2 },
            Color = {255, 0, 0},
		},
	}
}

CloneBlockUpload(_G.UploadBuild)
