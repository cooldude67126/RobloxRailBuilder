--!strict
-- Cart Kit Builder v2 — Roblox Studio Plugin
-- Chains together pieces from an existing cart-ride kit folder (e.g. "Ultimatecartridekit")
-- placed in workspace. Adds a translucent preview ("ghost") before committing a piece,
-- collision checking against the floor/other geometry, and click-to-reposition for the cursor.
--
-- Install: copy into your Roblox "Plugins" folder (Plugins tab > Plugins Folder in Studio),
--          then File > Reload Plugins.
--
-- Workflow:
--   1. Scan Kit -> pick a category -> click a piece. This stages a translucent GHOST
--      preview at the current cursor instead of placing anything for real.
--   2. Adjust the ghost with Rotate / Flip / Nudge, or turn on "Click to Move Cursor"
--      and click a spot in the 3D viewport to reposition it.
--   3. Click "Confirm Placement". If the ghost's actual part geometry overlaps anything
--      in the world (like the floor), placement is BLOCKED and you'll see what it hit —
--      adjust and try again. If clear, the real piece is placed and the cursor advances.
--   4. If a placed piece needs hand-correction afterward (drag it, let the kit's own Snap
--      system true it up), select it and click "Sync Cursor to Selection" to keep building
--      accurately from wherever it actually landed — this matters most for turn pieces,
--      since their exit angle isn't a simple straight-line extension.
--   5. "Undo Last Piece" removes the last placed piece and rewinds the cursor.

local Selection = game:GetService("Selection")

local toolbar = plugin:CreateToolbar("Cart Kit Builder")
local toggleButton = toolbar:CreateButton(
	"Kit Builder",
	"Open the cart kit builder panel",
	"rbxassetid://4458901886"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	true, false,
	340, 680,
	300, 480
)
local widget = plugin:CreateDockWidgetPluginGui("CartKitBuilderWidget", widgetInfo)
widget.Title = "Cart Kit Builder"

----------------------------------------------------------------
-- UI scaffolding
----------------------------------------------------------------

local root = Instance.new("Frame")
root.Size = UDim2.new(1, 0, 1, 0)
root.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
root.BorderSizePixel = 0
root.Parent = widget

local topLayout = Instance.new("UIListLayout")
topLayout.Padding = UDim.new(0, 6)
topLayout.Parent = root

local topPad = Instance.new("UIPadding")
topPad.PaddingTop = UDim.new(0, 8)
topPad.PaddingLeft = UDim.new(0, 8)
topPad.PaddingRight = UDim.new(0, 8)
topPad.Parent = root

local function makeLabel(text: string, height: number?)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, height or 18)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(200, 200, 200)
	l.Font = Enum.Font.SourceSans
	l.TextSize = 14
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = root
	return l
end

local function makeButton(text: string, height: number?)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, height or 30)
	b.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 15
	b.Text = text
	b.Parent = root
	return b
end

local function smallBtn(parent: Instance, text: string, width: number)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, width, 1, 0)
	b.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.SourceSans
	b.TextSize = 13
	b.Text = text
	b.Parent = parent
	return b
end

-- Kit folder path row
makeLabel("Kit folder name (in workspace)")
local folderBox = Instance.new("TextBox")
folderBox.Size = UDim2.new(1, 0, 0, 28)
folderBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
folderBox.TextColor3 = Color3.new(1, 1, 1)
folderBox.Font = Enum.Font.SourceSans
folderBox.TextSize = 15
folderBox.Text = "Ultimatecartridekit"
folderBox.Parent = root

local scanBtn = makeButton("Scan Kit")
local statusLabel = makeLabel("Not scanned yet.", 32)

-- Category selector row
makeLabel("Category")
local categoryRow = Instance.new("Frame")
categoryRow.Size = UDim2.new(1, 0, 0, 28)
categoryRow.BackgroundTransparency = 1
categoryRow.Parent = root
local categoryLayout = Instance.new("UIListLayout")
categoryLayout.FillDirection = Enum.FillDirection.Horizontal
categoryLayout.Padding = UDim.new(0, 4)
categoryLayout.Parent = categoryRow

local CATEGORY_NAMES = {
	"Generic parts",
	"Supported parts",
	"Track changers",
	"Obsticles",
	"Power ups",
}
local categoryButtons: { [string]: TextButton } = {}
for _, name in ipairs(CATEGORY_NAMES) do
	local cb = Instance.new("TextButton")
	cb.Size = UDim2.new(0, 60, 1, 0)
	cb.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	cb.TextColor3 = Color3.new(1, 1, 1)
	cb.Font = Enum.Font.SourceSans
	cb.TextSize = 11
	cb.TextWrapped = true
	cb.Text = name
	cb.Parent = categoryRow
	categoryButtons[name] = cb
end

-- Scrollable piece list
local pieceScroll = Instance.new("ScrollingFrame")
pieceScroll.Size = UDim2.new(1, 0, 0, 140)
pieceScroll.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
pieceScroll.BorderSizePixel = 0
pieceScroll.ScrollBarThickness = 6
pieceScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
pieceScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
pieceScroll.Parent = root

local pieceLayout = Instance.new("UIListLayout")
pieceLayout.Padding = UDim.new(0, 3)
pieceLayout.Parent = pieceScroll

local piecePad = Instance.new("UIPadding")
piecePad.PaddingTop = UDim.new(0, 4)
piecePad.PaddingLeft = UDim.new(0, 4)
piecePad.PaddingRight = UDim.new(0, 4)
piecePad.Parent = pieceScroll

local instantPlaceBtn = makeButton("Instant Place (OFF) — click a piece to place it directly")

-- Preview status + confirm/cancel
local previewStatus = makeLabel("No piece staged.", 36)

local confirmCancelRow = Instance.new("Frame")
confirmCancelRow.Size = UDim2.new(1, 0, 0, 32)
confirmCancelRow.BackgroundTransparency = 1
confirmCancelRow.Parent = root
local ccLayout = Instance.new("UIListLayout")
ccLayout.FillDirection = Enum.FillDirection.Horizontal
ccLayout.Padding = UDim.new(0, 6)
ccLayout.Parent = confirmCancelRow

local confirmBtn = Instance.new("TextButton")
confirmBtn.Size = UDim2.new(0.65, 0, 1, 0)
confirmBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 90)
confirmBtn.TextColor3 = Color3.new(1, 1, 1)
confirmBtn.Font = Enum.Font.SourceSansBold
confirmBtn.TextSize = 15
confirmBtn.Text = "Confirm Placement"
confirmBtn.Parent = confirmCancelRow

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.new(0.3, 0, 1, 0)
cancelBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
cancelBtn.TextColor3 = Color3.new(1, 1, 1)
cancelBtn.Font = Enum.Font.SourceSansBold
cancelBtn.TextSize = 15
cancelBtn.Text = "Cancel"
cancelBtn.Parent = confirmCancelRow

-- Cursor controls
makeLabel("Cursor Controls")

local rotRow = Instance.new("Frame")
rotRow.Size = UDim2.new(1, 0, 0, 30)
rotRow.BackgroundTransparency = 1
rotRow.Parent = root
local rotLayout = Instance.new("UIListLayout")
rotLayout.FillDirection = Enum.FillDirection.Horizontal
rotLayout.Padding = UDim.new(0, 4)
rotLayout.Parent = rotRow

local rotLeft45 = smallBtn(rotRow, "↺45°", 50)
local rotRight45 = smallBtn(rotRow, "↻45°", 50)
local rotLeft90 = smallBtn(rotRow, "↺90°", 50)
local rotRight90 = smallBtn(rotRow, "↻90°", 50)
local flip180 = smallBtn(rotRow, "Flip 180°", 65)

local nudgeRow = Instance.new("Frame")
nudgeRow.Size = UDim2.new(1, 0, 0, 30)
nudgeRow.BackgroundTransparency = 1
nudgeRow.Parent = root
local nudgeLayout = Instance.new("UIListLayout")
nudgeLayout.FillDirection = Enum.FillDirection.Horizontal
nudgeLayout.Padding = UDim.new(0, 4)
nudgeLayout.Parent = nudgeRow

local nudgeFwd = smallBtn(nudgeRow, "Fwd +2", 55)
local nudgeBack = smallBtn(nudgeRow, "Back -2", 60)
local nudgeUp = smallBtn(nudgeRow, "Up +2", 55)
local nudgeDown = smallBtn(nudgeRow, "Down -2", 60)

local reverseBtn = makeButton("Reverse Piece (OFF) — swap entry/exit (e.g. flips Ramp to climb)")
local swapEntryBtn = makeButton("Swap Entry Point (no multi-entry piece staged)")

local clickMoveBtn = makeButton("Click to Move Cursor (OFF)")
local axisToggleBtn = makeButton("Forward Axis: -Z (default)")
local syncBtn = makeButton("Sync Cursor to Selection")
local undoBtn = makeButton("Undo Last Piece")
local resetBtn = makeButton("Reset Cursor to Origin")
local levelBtn = makeButton("Level Cursor (Zero Rotation)")
local cursorLabel = makeLabel("Cursor: (0, 0, 0)")

----------------------------------------------------------------
-- State
----------------------------------------------------------------

local kitFolder: Folder? = nil
local pieceButtons: { Instance } = {}
local currentCategory: string = CATEGORY_NAMES[1]

local cursorCFrame = CFrame.new(0, 5, 0) -- start a little above origin to avoid an instant floor collision

local trackOutFolder = workspace:FindFirstChild("MyCartTrack")
if not (trackOutFolder and trackOutFolder:IsA("Folder")) then
	trackOutFolder = Instance.new("Folder")
	trackOutFolder.Name = "MyCartTrack"
	trackOutFolder.Parent = workspace
end

-- history of {model = Instance, previousCursor = CFrame} for undo
local history: { { model: Model, previousCursor: CFrame, previousLastPieceName: string? } } = {}

-- Forward-declared here (assigned later, once collision-checking is defined)
-- so the piece-button click handlers, wired up earlier in the file, can call it.
local attemptConfirm: (() -> boolean)? = nil
local instantPlaceEnabled = false
local reverseConnector = false
local entryPointIndex = 1
local cachedAutoConnector: any = nil -- auto-detected connector data for the currently staged piece

-- active ghost preview state
local ghostModel: Model? = nil
local ghostSourceModel: Instance? = nil
local ghostSize: Vector3? = nil
local ghostPlacementCFrame: CFrame? = nil
local ghostAdvanceOffset: CFrame? = nil

local mouse = plugin:GetMouse()
local clickMoveActive = false
local clickMoveConn: RBXScriptConnection? = nil

-- Which local axis of a piece is treated as "forward" (the direction the track
-- travels). The kit's actual authoring axis can't be verified without running
-- Studio directly, so this is user-adjustable: cycle it with the toggle button
-- until pieces line up front-to-back instead of side-to-side.
local FORWARD_OPTIONS = {
	{ label = "+X (default — confirmed from kit data)", axis = "X", sign = 1 },
	{ label = "-X", axis = "X", sign = -1 },
	{ label = "+Z", axis = "Z", sign = 1 },
	{ label = "-Z", axis = "Z", sign = -1 },
}
local forwardIndex = 1

local function forwardVector(): Vector3
	local opt = FORWARD_OPTIONS[forwardIndex]
	if opt.axis == "Z" then
		return Vector3.new(0, 0, opt.sign)
	else
		return Vector3.new(opt.sign, 0, 0)
	end
end

local function sizeAlongForward(size: Vector3): number
	local opt = FORWARD_OPTIONS[forwardIndex]
	return (opt.axis == "Z") and size.Z or size.X
end

local function updateAxisButtonLabel()
	axisToggleBtn.Text = "Forward Axis: " .. FORWARD_OPTIONS[forwardIndex].label
end
updateAxisButtonLabel()

local function updateCursorLabel()
	local p = cursorCFrame.Position
	local _rx, ry, _rz = cursorCFrame:ToEulerAnglesXYZ()
	cursorLabel.Text = string.format("Cursor: (%.1f, %.1f, %.1f)  Yaw: %.1f°", p.X, p.Y, p.Z, math.deg(ry))
end
updateCursorLabel()

local function highlightCategoryButtons()
	for name, btn in pairs(categoryButtons) do
		btn.BackgroundColor3 = (name == currentCategory) and Color3.fromRGB(0, 120, 90)
			or Color3.fromRGB(64, 64, 64)
	end
end
highlightCategoryButtons()

----------------------------------------------------------------
-- Ghost preview helpers
----------------------------------------------------------------

local function destroyGhost()
	if ghostModel then
		ghostModel:Destroy()
	end
	ghostModel = nil
	ghostSourceModel = nil
	ghostSize = nil
	ghostPlacementCFrame = nil
	ghostAdvanceOffset = nil
	previewStatus.Text = "No piece staged."
	previewStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
end

-- Strip anything from a preview clone that could run, make noise, or otherwise
-- misbehave while it's just a translucent hologram.
local function sanitizeGhost(model: Model)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("Sound")
			or inst:IsA("ClickDetector") or inst:IsA("ParticleEmitter")
			or inst:IsA("Fire") or inst:IsA("Smoke") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Anchored = true
			inst.Transparency = math.clamp(inst.Transparency + 0.5, 0.55, 0.9)
		end
	end
end

-- ============================================================
-- Auto-detected connectors (primary system)
-- ============================================================
-- Rather than hand-deriving trig for every piece (slow and error-prone, as the
-- last several pieces proved), this scans a piece for parts explicitly named
-- EntryRail / EntryTie / ExitRail / ExitTie and builds connector data directly
-- from them. A Rail's orientation is unambiguous (a Tie is symmetric and can
-- read as 0° or 180° for the same physical placement), so Rail is preferred
-- for rotation when both are present; Tie is preferred for position since
-- ties mark the exact cross-section in this kit's convention. Multiple parts
-- sharing the same name (e.g. two EntryRail parts on a merge piece) are
-- clustered by proximity into separate connector candidates.

local CLUSTER_THRESHOLD = 10 -- studs; wide enough to cover a normal two-rail gauge as one connector, but narrower than the distance between genuinely separate entry points

-- A Rail is just a symmetric beam along its own length, same as a Tie across
-- its width — there's no geometric way to tell "front" from "back" purely from
-- the part itself, so its stored rotation can come out 180° backward with no
-- visual difference in the source model. When that happens for a specific
-- piece, the fix goes here rather than re-deriving anything.
local ENTRY_FACING_QUIRKS: { [string]: number } = {
	["Big Spiral"] = 180,
	["Short Track"] = 180,
	["Bump"] = 180,
}

-- Same idea as ENTRY_FACING_QUIRKS, but for the exit connector specifically —
-- a piece can have one, both, or neither depending on what its tagged parts
-- actually reveal. cart ride loop visually turns 90° to the right (clockwise
-- from above), which in Roblox's Y-up right-handed system is a NEGATIVE yaw.
local EXIT_FACING_QUIRKS: { [string]: number } = {
	["cart ride loop"] = -180,
	["Short Track"] = 180,
	["Bump"] = 180,
}

-- Some facing issues only show up for a specific PAIR of pieces (e.g. Short
-- Track's exit and Track turn's entry individually read fine against most
-- other pieces, but the combination is off) — rather than a piece being
-- backward universally. Keyed as PAIRWISE_ENTRY_QUIRKS[previousPieceName][thisPieceName].
local PAIRWISE_ENTRY_QUIRKS: { [string]: { [string]: number } } = {
	["Short Track"] = {
		["Track turn"] = 180,
	},
	["Big Spiral"] = {
		["Track turn"] = 180,
	},
	["Bump"] = {
		["*"] = 180, -- Bump followed by most pieces needs this; Track turn is fine as-is (see below)
		["Track turn"] = 0,
	},
}

-- Tracks what was placed most recently, so pairwise quirks above can apply.
local lastPlacedPieceName: string? = nil

local function findNamedParts(model: Model, name: string): { BasePart }
	local found = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == name then
			table.insert(found, inst)
		end
	end
	return found
end

local function clusterParts(parts: { BasePart }): { { BasePart } }
	local clusters: { { BasePart } } = {}
	for _, part in ipairs(parts) do
		local placed = false
		for _, cluster in ipairs(clusters) do
			if (cluster[1].Position - part.Position).Magnitude < CLUSTER_THRESHOLD then
				table.insert(cluster, part)
				placed = true
				break
			end
		end
		if not placed then
			table.insert(clusters, { part })
		end
	end
	return clusters
end

-- Builds a world CFrame for one connector cluster. A normal straight piece has
-- TWO parallel rails (left/right) both tagged the same name for one entrance —
-- those get averaged together into a single midpoint, not treated as separate
-- connectors. Position comes from Tie(s) if present (else averaged Rail(s));
-- rotation comes from a Rail if present (else a Tie), since a Tie is symmetric
-- and its own rotation reading can be ambiguous.
local function clusterToWorldCFrame(cluster: { BasePart }): CFrame
	local rails: { BasePart } = {}
	local ties: { BasePart } = {}
	for _, p in ipairs(cluster) do
		if p.Name == "EntryRail" or p.Name == "ExitRail" then
			table.insert(rails, p)
		elseif p.Name == "EntryTie" or p.Name == "ExitTie" then
			table.insert(ties, p)
		end
	end

	local function averagePosition(parts: { BasePart }): Vector3
		local sum = Vector3.new(0, 0, 0)
		for _, p in ipairs(parts) do
			sum += p.Position
		end
		return sum / #parts
	end

	local position: Vector3
	if #ties > 0 then
		position = averagePosition(ties)
	else
		position = averagePosition(rails)
	end

	local rotationSource: BasePart = (#rails > 0 and rails[1]) or ties[1]
	local rotOnly = rotationSource.CFrame - rotationSource.CFrame.Position
	return rotOnly + position
end

type AutoConnectorData = {
	pivot: CFrame,
	entryWorldCFrames: { CFrame },
	exitWorldCFrames: { CFrame },
}

-- Returns nil if the piece has no tagged parts at all (not yet renamed, or
-- doesn't need special handling — falls through to older/generic systems).
local function getAutoConnectors(model: Model): AutoConnectorData?
	local entryParts = {}
	for _, p in ipairs(findNamedParts(model, "EntryRail")) do table.insert(entryParts, p) end
	for _, p in ipairs(findNamedParts(model, "EntryTie")) do table.insert(entryParts, p) end

	local exitParts = {}
	for _, p in ipairs(findNamedParts(model, "ExitRail")) do table.insert(exitParts, p) end
	for _, p in ipairs(findNamedParts(model, "ExitTie")) do table.insert(exitParts, p) end

	if #entryParts == 0 and #exitParts == 0 then
		return nil
	end

	local entryCFrames = {}
	for _, cluster in ipairs(clusterParts(entryParts)) do
		table.insert(entryCFrames, clusterToWorldCFrame(cluster))
	end

	local exitCFrames = {}
	for _, cluster in ipairs(clusterParts(exitParts)) do
		table.insert(exitCFrames, clusterToWorldCFrame(cluster))
	end

	return {
		pivot = model:GetPivot(),
		entryWorldCFrames = entryCFrames,
		exitWorldCFrames = exitCFrames,
	}
end

-- ============================================================
-- Hardcoded fallback connectors (legacy — kept only for pieces not yet tagged)
-- ============================================================
local PIECE_CONNECTORS: { [string]: { entryFromPivot: CFrame, exitFromEntry: CFrame } } = {}

local REVERSE_ROTATION_QUIRKS: { [string]: number } = {}

-- Computes where a piece would land given the current cursor, and how far the
-- cursor should advance afterward, plus (for multi-entry pieces) how many
-- entry candidates exist. Priority: auto-detected named parts > hardcoded
-- fallback table > generic straight-line bounding-box assumption.
local function computePlacement(sourceModel: Model)
	local auto = getAutoConnectors(sourceModel)
	if auto then
		local pivot = auto.pivot
		local entryList = auto.entryWorldCFrames
		local exitList = auto.exitWorldCFrames
		cachedAutoConnector = { entryCount = #entryList, exitCount = #exitList }

		local clampedIndex = math.clamp(entryPointIndex, 1, math.max(#entryList, 1))
		local entryWorld = entryList[clampedIndex]
		local exitWorld = exitList[1]

		if reverseConnector and entryWorld and exitWorld then
			entryWorld, exitWorld = exitWorld, entryWorld
		end

		local facingQuirk = ENTRY_FACING_QUIRKS[sourceModel.Name]
		if facingQuirk and entryWorld then
			local rotOnly = entryWorld - entryWorld.Position
			entryWorld = (rotOnly * CFrame.Angles(0, math.rad(facingQuirk), 0)) + entryWorld.Position
		end

		if lastPlacedPieceName and entryWorld then
			local pairTable = PAIRWISE_ENTRY_QUIRKS[lastPlacedPieceName]
			local pairQuirk = pairTable and (pairTable[sourceModel.Name] or pairTable["*"])
			if pairQuirk then
				local rotOnly = entryWorld - entryWorld.Position
				entryWorld = (rotOnly * CFrame.Angles(0, math.rad(pairQuirk), 0)) + entryWorld.Position
			end
		end

		local exitFacingQuirk = EXIT_FACING_QUIRKS[sourceModel.Name]
		if exitFacingQuirk and exitWorld then
			local exitRotOnly = exitWorld - exitWorld.Position
			exitWorld = (exitRotOnly * CFrame.Angles(0, math.rad(exitFacingQuirk), 0)) + exitWorld.Position
		end

		local ok, _cf, size = pcall(function()
			return sourceModel:GetBoundingBox()
		end)
		size = ok and size or Vector3.new(1, 1, 1)

		if entryWorld then
			local entryFromPivot = pivot:ToObjectSpace(entryWorld)
			local placementCFrame = cursorCFrame * entryFromPivot:Inverse()
			local advanceOffset
			if exitWorld then
				advanceOffset = entryWorld:ToObjectSpace(exitWorld)
			else
				-- Dead-end piece (e.g. Broken track end): nothing to advance to.
				advanceOffset = CFrame.new(0, 0, 0)
			end
			return placementCFrame, size, advanceOffset, (not exitWorld)
		else
			-- Spawn-type piece (no entry — e.g. cart spawners): drop it directly
			-- at the cursor, then continue building from its exit.
			local placementCFrame = cursorCFrame
			local advanceOffset = CFrame.new(0, 0, 0)
			if exitWorld then
				local exitFromPivot = pivot:ToObjectSpace(exitWorld)
				advanceOffset = exitFromPivot
			end
			return placementCFrame, size, advanceOffset, false
		end
	end

	local connector = PIECE_CONNECTORS[sourceModel.Name]
	if connector then
		local entryFromPivot = connector.entryFromPivot
		local exitFromEntry = connector.exitFromEntry

		if reverseConnector then
			local exitFromPivot = entryFromPivot * exitFromEntry
			entryFromPivot = exitFromPivot
			exitFromEntry = exitFromEntry:Inverse()

			local quirk = REVERSE_ROTATION_QUIRKS[sourceModel.Name]
			if quirk then
				entryFromPivot = entryFromPivot * CFrame.Angles(0, math.rad(quirk), 0)
			end
		end

		local placementCFrame = cursorCFrame * entryFromPivot:Inverse()
		local advanceOffset = exitFromEntry
		local ok, _cf, size = pcall(function()
			return sourceModel:GetBoundingBox()
		end)
		return placementCFrame, (ok and size or Vector3.new(1, 1, 1)), advanceOffset, false
	end

	local ok, cframe, size = pcall(function()
		return sourceModel:GetBoundingBox()
	end)
	if not ok then
		return nil
	end
	local localOffset = cframe:ToObjectSpace(sourceModel:GetPivot())
	local halfDepth = sizeAlongForward(size) / 2
	local placementCFrame = cursorCFrame * CFrame.new(forwardVector() * halfDepth) * localOffset
	local advanceOffset = CFrame.new(forwardVector() * sizeAlongForward(size))
	return placementCFrame, size, advanceOffset, false
end

local function updateSwapEntryButton()
	if cachedAutoConnector and cachedAutoConnector.entryCount > 1 then
		swapEntryBtn.Text = string.format(
			"Swap Entry Point (%d of %d)",
			math.clamp(entryPointIndex, 1, cachedAutoConnector.entryCount),
			cachedAutoConnector.entryCount
		)
	else
		swapEntryBtn.Text = "Swap Entry Point (no multi-entry piece staged)"
	end
end

local function refreshGhostPosition()
	if not (ghostModel and ghostSourceModel) then
		return
	end
	local placementCFrame, size, advanceOffset, isDeadEnd = computePlacement(ghostSourceModel :: Model)
	if not placementCFrame then
		return
	end
	ghostPlacementCFrame = placementCFrame
	ghostSize = size
	ghostAdvanceOffset = advanceOffset
	local gm: Model = ghostModel :: Model
	gm:PivotTo(placementCFrame)
	updateSwapEntryButton()
	return isDeadEnd
end

local function stagePreview(sourceModel: Instance)
	if not sourceModel:IsA("Model") then
		warn("[Cart Kit Builder] '" .. sourceModel.Name .. "' isn't a Model, skipping.")
		return
	end
	destroyGhost()
	entryPointIndex = 1

	local clone = (sourceModel :: Model):Clone()
	clone.Name = "GHOST_" .. sourceModel.Name
	sanitizeGhost(clone)
	clone.Parent = workspace

	ghostModel = clone
	ghostSourceModel = sourceModel
	local isDeadEnd = refreshGhostPosition()

	if isDeadEnd then
		previewStatus.Text = "Staged: " .. sourceModel.Name .. " — dead end (no exit), Confirm still places it."
	else
		previewStatus.Text = "Staged: " .. sourceModel.Name .. " — adjust, then Confirm."
	end
	previewStatus.TextColor3 = Color3.fromRGB(255, 200, 100)
end

----------------------------------------------------------------
-- Collision checking
----------------------------------------------------------------

-- Checks each real BasePart of the ghost (in its current, already-placed position)
-- against everything in the world except the track folder and the ghost itself.
-- Returns true + nil if clear, or false + a short description of what it hit.
local function checkGhostCollision(): (boolean, string?)
	if not ghostModel then
		return false, "no piece staged"
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { ghostModel :: Instance, trackOutFolder :: Instance }

	for _, part in ipairs((ghostModel :: Model):GetDescendants()) do
		if part:IsA("BasePart") then
			-- Shrink slightly so pieces that are meant to sit flush (touching, not
			-- overlapping) don't false-positive against the floor or neighbors.
			local shrink = Vector3.new(0.3, 0.3, 0.3)
			local testSize = Vector3.new(
				math.max(part.Size.X - shrink.X, 0.1),
				math.max(part.Size.Y - shrink.Y, 0.1),
				math.max(part.Size.Z - shrink.Z, 0.1)
			)
			local hits = workspace:GetPartBoundsInBox(part.CFrame, testSize, overlapParams)
			if #hits > 0 then
				return false, hits[1].Name .. " (" .. hits[1]:GetFullName() .. ")"
			end
		end
	end

	return true, nil
end

----------------------------------------------------------------
-- Kit scanning
----------------------------------------------------------------

local function clearPieceButtons()
	for _, b in ipairs(pieceButtons) do
		b:Destroy()
	end
	pieceButtons = {}
end

local function populatePieceList()
	clearPieceButtons()
	if not kitFolder then
		return
	end
	local category = (kitFolder :: Folder):FindFirstChild(currentCategory)
	if not category then
		local warnLabel = Instance.new("TextLabel")
		warnLabel.Size = UDim2.new(1, 0, 0, 24)
		warnLabel.BackgroundTransparency = 1
		warnLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		warnLabel.Font = Enum.Font.SourceSans
		warnLabel.TextSize = 13
		warnLabel.Text = "No '" .. currentCategory .. "' folder found in kit."
		warnLabel.Parent = pieceScroll
		table.insert(pieceButtons, warnLabel)
		return
	end

	for _, child in ipairs(category:GetChildren()) do
		if child:IsA("Model") then
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 0, 26)
			btn.BackgroundColor3 = Color3.fromRGB(58, 58, 58)
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Font = Enum.Font.SourceSans
			btn.TextSize = 13
			btn.Text = child.Name
			btn.Parent = pieceScroll
			btn.MouseButton1Click:Connect(function()
				stagePreview(child)
				if instantPlaceEnabled and attemptConfirm then
					attemptConfirm()
				end
			end)
			table.insert(pieceButtons, btn)
		end
	end
end

instantPlaceBtn.MouseButton1Click:Connect(function()
	instantPlaceEnabled = not instantPlaceEnabled
	instantPlaceBtn.Text = instantPlaceEnabled
		and "Instant Place (ON) — click a piece to place it directly"
		or "Instant Place (OFF) — click a piece to place it directly"
	instantPlaceBtn.BackgroundColor3 = instantPlaceEnabled and Color3.fromRGB(0, 120, 90) or Color3.fromRGB(64, 64, 64)
end)

scanBtn.MouseButton1Click:Connect(function()
	local name = folderBox.Text
	local found = workspace:FindFirstChild(name)
	if found and found:IsA("Folder") then
		kitFolder = found
		statusLabel.Text = "Scanned '" .. name .. "' successfully."
		populatePieceList()
	else
		kitFolder = nil
		statusLabel.Text = "Couldn't find a Folder named '" .. name .. "' in workspace."
		clearPieceButtons()
	end
end)

for name, btn in pairs(categoryButtons) do
	btn.MouseButton1Click:Connect(function()
		currentCategory = name
		highlightCategoryButtons()
		populatePieceList()
	end)
end

----------------------------------------------------------------
-- Confirm / Cancel
----------------------------------------------------------------

-- Returns true if the staged ghost was successfully placed for real.
attemptConfirm = function(): boolean
	if not (ghostModel and ghostSourceModel and ghostPlacementCFrame) then
		previewStatus.Text = "Nothing staged — click a piece first."
		previewStatus.TextColor3 = Color3.fromRGB(255, 150, 150)
		return false
	end

	local clear, hitDescription = checkGhostCollision()
	if not clear then
		previewStatus.Text = "Blocked — intersects " .. (hitDescription or "something") .. ". Adjust and retry."
		previewStatus.TextColor3 = Color3.fromRGB(255, 110, 110)
		return false
	end

	local realClone = (ghostSourceModel :: Model):Clone()
	realClone.Parent = trackOutFolder
	realClone:PivotTo(ghostPlacementCFrame :: CFrame)

	table.insert(history, { model = realClone, previousCursor = cursorCFrame, previousLastPieceName = lastPlacedPieceName })
	lastPlacedPieceName = (ghostSourceModel :: Model).Name

	local advanceOffset = ghostAdvanceOffset :: CFrame
	cursorCFrame = cursorCFrame * advanceOffset
	updateCursorLabel()

	print(("[Cart Kit Builder] Placed '%s'."):format((ghostSourceModel :: Model).Name))
	destroyGhost()
	return true
end

confirmBtn.MouseButton1Click:Connect(function()
	if attemptConfirm then
		attemptConfirm()
	end
end)

cancelBtn.MouseButton1Click:Connect(function()
	destroyGhost()
end)

----------------------------------------------------------------
-- Cursor manipulation (also live-updates the ghost, if any)
----------------------------------------------------------------

local function adjustCursor(fn: () -> ())
	fn()
	updateCursorLabel()
	if ghostModel then
		refreshGhostPosition()
		local clear, hitDescription = checkGhostCollision()
		if clear then
			previewStatus.Text = "Staged: " .. (ghostSourceModel :: Model).Name .. " — looks clear. Confirm?"
			previewStatus.TextColor3 = Color3.fromRGB(140, 220, 140)
		else
			previewStatus.Text = "Would intersect " .. (hitDescription or "something") .. " — keep adjusting."
			previewStatus.TextColor3 = Color3.fromRGB(255, 180, 120)
		end
	end
end

rotLeft45.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.Angles(0, math.rad(45), 0)
	end)
end)
rotRight45.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.Angles(0, math.rad(-45), 0)
	end)
end)
rotLeft90.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.Angles(0, math.rad(90), 0)
	end)
end)
rotRight90.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.Angles(0, math.rad(-90), 0)
	end)
end)
flip180.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.Angles(0, math.rad(180), 0)
	end)
end)

nudgeFwd.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.new(forwardVector() * 2)
	end)
end)
nudgeBack.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame * CFrame.new(forwardVector() * -2)
	end)
end)
nudgeUp.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame + Vector3.new(0, 2, 0)
	end)
end)
nudgeDown.MouseButton1Click:Connect(function()
	adjustCursor(function()
		cursorCFrame = cursorCFrame - Vector3.new(0, 2, 0)
	end)
end)

----------------------------------------------------------------
-- Click-to-move-cursor (the "hologram" positioning tool)
----------------------------------------------------------------

clickMoveBtn.MouseButton1Click:Connect(function()
	clickMoveActive = not clickMoveActive
	clickMoveBtn.Text = clickMoveActive and "Click to Move Cursor (ON — click viewport)" or "Click to Move Cursor (OFF)"
	clickMoveBtn.BackgroundColor3 = clickMoveActive and Color3.fromRGB(150, 110, 30) or Color3.fromRGB(64, 64, 64)

	if clickMoveActive then
		clickMoveConn = mouse.Button1Down:Connect(function()
			if not mouse.Hit then
				return
			end
			-- Keep current facing, just move position to the clicked point.
			local hitPos = mouse.Hit.Position
			adjustCursor(function()
				cursorCFrame = CFrame.new(hitPos) * (cursorCFrame - cursorCFrame.Position)
			end)
		end)
	elseif clickMoveConn then
		clickMoveConn:Disconnect()
		clickMoveConn = nil
	end
end)

----------------------------------------------------------------
-- Sync / Undo / Reset
----------------------------------------------------------------

local function refreshGhostAndStatus()
	if not ghostModel then
		return
	end
	refreshGhostPosition()
	local clear, hitDescription = checkGhostCollision()
	if clear then
		previewStatus.Text = "Staged: " .. (ghostSourceModel :: Model).Name .. " — looks clear. Confirm?"
		previewStatus.TextColor3 = Color3.fromRGB(140, 220, 140)
	else
		previewStatus.Text = "Would intersect " .. (hitDescription or "something") .. " — keep adjusting."
		previewStatus.TextColor3 = Color3.fromRGB(255, 180, 120)
	end
end

axisToggleBtn.MouseButton1Click:Connect(function()
	forwardIndex = (forwardIndex % #FORWARD_OPTIONS) + 1
	updateAxisButtonLabel()
	refreshGhostAndStatus()
end)

reverseBtn.MouseButton1Click:Connect(function()
	reverseConnector = not reverseConnector
	reverseBtn.Text = reverseConnector
		and "Reverse Piece (ON) — swap entry/exit (e.g. flips Ramp to climb)"
		or "Reverse Piece (OFF) — swap entry/exit (e.g. flips Ramp to climb)"
	reverseBtn.BackgroundColor3 = reverseConnector and Color3.fromRGB(0, 120, 90) or Color3.fromRGB(64, 64, 64)
	refreshGhostAndStatus()
end)

swapEntryBtn.MouseButton1Click:Connect(function()
	if cachedAutoConnector and cachedAutoConnector.entryCount > 1 then
		entryPointIndex = (entryPointIndex % cachedAutoConnector.entryCount) + 1
		refreshGhostAndStatus()
	end
end)

syncBtn.MouseButton1Click:Connect(function()
	local selected = Selection:Get()
	if #selected == 0 then
		warn("[Cart Kit Builder] Select the piece you want to sync to first.")
		return
	end
	local inst = selected[1]
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then
		warn("[Cart Kit Builder] Selection must be a Model or Part.")
		return
	end

	if inst:IsA("Model") then
		local auto = getAutoConnectors(inst :: Model)
		if auto and #auto.exitWorldCFrames > 0 then
			-- Use the tagged exit connector directly instead of guessing from
			-- the bounding box — matches exactly what computePlacement uses
			-- when this piece is placed normally, including facing corrections.
			local exitWorld = auto.exitWorldCFrames[1]
			local quirk = EXIT_FACING_QUIRKS[inst.Name]
			if quirk then
				local rotOnly = exitWorld - exitWorld.Position
				exitWorld = (rotOnly * CFrame.Angles(0, math.rad(quirk), 0)) + exitWorld.Position
			end
			cursorCFrame = exitWorld
			lastPlacedPieceName = inst.Name
			updateCursorLabel()
			print("[Cart Kit Builder] Cursor synced to tagged exit of: " .. inst.Name)
			return
		end
	end

	-- Fallback: no tagged exit found (piece not yet renamed), use the old
	-- bounding-box estimate.
	local pivot: CFrame
	local depth = 0
	if inst:IsA("Model") then
		local ok, _cf, size = pcall(function()
			return (inst :: Model):GetBoundingBox()
		end)
		pivot = (inst :: Model):GetPivot()
		if ok then
			depth = sizeAlongForward(size)
		end
	else
		local part = inst :: BasePart
		pivot = part.CFrame
		depth = sizeAlongForward(part.Size)
	end

	cursorCFrame = pivot * CFrame.new(forwardVector() * (depth / 2))
	lastPlacedPieceName = inst.Name
	updateCursorLabel()
	print("[Cart Kit Builder] Cursor synced to selection (bounding-box estimate): " .. inst.Name)
end)

undoBtn.MouseButton1Click:Connect(function()
	local last = table.remove(history)
	if not last then
		warn("[Cart Kit Builder] Nothing to undo.")
		return
	end
	last.model:Destroy()
	cursorCFrame = last.previousCursor
	lastPlacedPieceName = last.previousLastPieceName
	updateCursorLabel()
end)

resetBtn.MouseButton1Click:Connect(function()
	cursorCFrame = CFrame.new(0, 5, 0)
	lastPlacedPieceName = nil
	updateCursorLabel()
end)

levelBtn.MouseButton1Click:Connect(function()
	cursorCFrame = CFrame.new(cursorCFrame.Position)
	updateCursorLabel()
	if ghostModel then
		refreshGhostPosition()
	end
end)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget.Enabled = true
