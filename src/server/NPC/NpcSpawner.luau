--[=[
	@class NpcSpawner

	Server-side bot spawner. The lobby tells this game version how many bots to
	create when the round starts; this module does the actual work:

	  * picks a random rig from `ServerStorage.NPC_models`,
	  * pivots it onto a random `workspace.goal_*` part (the same parts the brain
	    patrols between, tagged `NPC_goals`),
	  * unanchors the assembly — `NPCServer._setNetworkOwner` can only hand the
	    rig to the elected brain client if every assembly part is unanchored, and
	    an anchored HumanoidRootPart silently keeps the NPC standing still,
	  * tags it `NPC_TAG`, which is the lifecycle signal that constructs the
	    server/client NPC binders (combat mirroring + brain election).

	Each rig must ship a `Tool` child naming its weapon (NPCServer.Init equips
	the first Tool child); models in `NPC_models` are authored that way.
]=]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)

local NpcSpawner = {}

-- Lifts the rig so it drops onto the goal instead of spawning embedded in it.
local SPAWN_HEIGHT_OFFSET = 5
-- Horizontal scatter so several bots sharing one goal don't stack on the same
-- stud and shove each other on spawn.
local SPAWN_SCATTER_RADIUS = 6

local random = Random.new()

--[=[
	Every authored rig under ServerStorage.NPC_models. Errors loudly if the
	folder is missing or empty — a silent no-op would just look like the lobby
	signal never arrived.
]=]
local function getModelTemplates(): { Model }
	local folder = ServerStorage:FindFirstChild("NPC_models")
	assert(folder, "[NpcSpawner] ServerStorage.NPC_models folder is missing")

	local templates = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(templates, child)
		end
	end

	assert(#templates > 0, "[NpcSpawner] ServerStorage.NPC_models has no Model children")
	return templates
end

--[=[
	The goal parts NPCs both spawn on and patrol between. Primary source is the
	`NPC_goals` tag (what GoalController reads); falls back to a `goal_*` name
	scan of the workspace so a map that only named its goals still works.
]=]
local function getGoals(): { BasePart }
	local seen = {}
	local goals = {}

	for _, goal in CollectionService:GetTagged(Constants.NPC_GOALS_TAG) do
		if goal:IsA("BasePart") and not seen[goal] then
			seen[goal] = true
			table.insert(goals, goal)
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name:match("^goal_") and not seen[descendant] then
			seen[descendant] = true
			table.insert(goals, descendant)
		end
	end

	return goals
end

-- Network ownership can only follow the brain if nothing in the assembly is
-- anchored (see NPCServer._setNetworkOwner / the CLAUDE.md authority note).
local function unanchor(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
end

local function spawnPositionFor(goal: BasePart): Vector3
	local angle = random:NextNumber(0, 2 * math.pi)
	local radius = random:NextNumber(0, SPAWN_SCATTER_RADIUS)
	local scatter = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return goal.Position + scatter + Vector3.new(0, SPAWN_HEIGHT_OFFSET, 0)
end

--[=[
	Spawns one bot: clones a random template onto a random goal, unanchors it,
	and tags it `NPC` (which boots the binders). Returns the spawned Model.

	@param templates { Model } -- pre-fetched once by Spawn to avoid re-scanning
	@param goals { BasePart }
]=]
function NpcSpawner.SpawnOne(templates: { Model }, goals: { BasePart }): Model
	local template = templates[random:NextInteger(1, #templates)]
	local goal = goals[random:NextInteger(1, #goals)]

	local npc = template:Clone()
	unanchor(npc)
	npc:PivotTo(CFrame.new(spawnPositionFor(goal)))
	npc.Parent = Workspace

	-- Tag last: the binder constructor runs the moment the tag lands, and it
	-- expects the rig already positioned and parented in the world.
	CollectionService:AddTag(npc, Constants.NPC_TAG)

	return npc
end

--[=[
	Spawns `count` bots from ServerStorage.NPC_models onto random goals. This is
	the entry point the lobby signal drives.

	@param count number
	@return { Model } -- the spawned rigs
]=]
function NpcSpawner.Spawn(count: number): { Model }
	assert(type(count) == "number" and count > 0, "[NpcSpawner] count must be a positive number")

	local templates = getModelTemplates()
	local goals = getGoals()
	assert(#goals > 0, "[NpcSpawner] no goal parts found (tag a part `NPC_goals` or name one `goal_*`)")

	local spawned = {}
	for _ = 1, count do
		table.insert(spawned, NpcSpawner.SpawnOne(templates, goals))
	end

	return spawned
end

return NpcSpawner
