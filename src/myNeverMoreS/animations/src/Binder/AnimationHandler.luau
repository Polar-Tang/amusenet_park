--[[
Animation handler @v_04
	The .new accepts an object as a parameter, it tolerates the model player or the player object
	Check the animation priority before stop it
	Got bindable events for animations
Animation handler @v_03
	implements Lazy load on registered animations
Animation handler @v_04
	Added Init method for animationContainer, supports AnimationController and Humanoid.Animator
	Requires Init to be called before using other methods
Animation handler @v_05
	bug fixed
Animation handler @v_06
	Per-descriptor Maid + AnimationTrack + Animation instances are now registered
	into the global `_maid` under keyed slots ("desc_<name>" / "track_<name>" /
	"anim_<name>"). This means:
	  * `_maid:DoCleaning()` actually tears every descriptor's connections and
	    tracks down — previously the per-descriptor maids were orphaned.
	  * `_ClearAnimation(name)` is a single-line maid wipe.
	  * `registryAnims` is self-contained: it tears the previous set down before
	    declaring the new descriptors, so callers don't need to call `Restart`
	    first.
	  * Added `StopAll` for "interrupt every playing track but keep descriptors
	    preloaded" (cheaper than a full teardown).
Animation handler @v_07
	Default vs weapon animation split. `AddAnimations` now marks its names as
	*defaults* (`_defaultNames`) that are added once and protected. `registryAnims`
	swaps only the *weapon* set by name (tracked in `_registryNames`): it drops the
	previous weapon's leftovers, rebuilds colliding names, and never overwrites a
	default. `ClearAllTheAnims` (full wipe) is now reserved for `Destroy`; `Restart`
	clears only the weapon set. This keeps default poses (OtherAnims) playing
	uninterrupted across weapon swaps and removes the Idle-collision glitch.
]]
local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
--local NeverMore = require(RS.Packages.neverMore.loader).load(script.Parent.Parent.Parent.Packages.neverMore)
--local Binder = NeverMore("Binder")
--print("binder ", Binder)
local AnimationHandler = {}
AnimationHandler.__index = AnimationHandler
type MaidType = typeof(Maid.new(...))

export type AnimationsData = {
	animationId: string,
	AnimationTrack: AnimationTrack,
	--AnimationPriorityNumber: number -- i'm not sure if this is useful
}

export type AnimationMap = {
	[string]: { Animation },
}

export type Options = {
	player: Player?,
	char: Model?,
	animations: AnimationMap?,
	armName: string?,
}

--[[
local PRIORITY_LIST = {
	Enum.AnimationPriority.Core,
	Enum.AnimationPriority.Idle,
	Enum.AnimationPriority.Movement,
	Enum.AnimationPriority.Action,
	Enum.AnimationPriority.Action2,
	Enum.AnimationPriority.Action3,
	Enum.AnimationPriority.Action4,
}
]]
type AnimationDescriptor = {
	Animation: Animation,
	AnimationTrack: AnimationTrack,
	Maid: MaidType,
	preloaded: boolean,
}

type AnimationDescriptors = {
	[string]: AnimationDescriptor,
}

export type AnimationHandlerType = {
	Char: Model,
	animations: AnimationMap,
	animationDescriptors: AnimationDescriptors,
	armName: string,
	_maid: MaidType,
	_initialized: boolean,
	animator: Animator,
	Init: (self: AnimationHandlerType, animationContainer: Instance) -> (),
	LoadAnimation: (
		self: AnimationHandlerType,
		state: boolean,
		animaName: string,
		isPreload: boolean?
	) -> AnimationTrack?,
	AddAnimations: (self: AnimationHandlerType, newAnims: AnimationMap) -> (),
	Restart: (self: AnimationHandlerType) -> (),
	Destroy: (self: AnimationHandlerType) -> (),
	registryAnims: (self: AnimationHandlerType, anims: AnimationMap) -> (),
	preloadAll: (self: AnimationHandlerType) -> (),
	OnSignal: (self: AnimationHandlerType, info: connArgs) -> (),
	PreloadAnims: (self: AnimationHandlerType, animsName: { string }) -> (),
	ClearAllTheAnims: (self: AnimationHandlerType) -> (),
	StopAll: (self: AnimationHandlerType) -> (),
}

function AnimationHandler.new(char, serviceBag): Options
	local self = setmetatable({}, AnimationHandler)
	self.Char = char
	self.animations = {}
	self.animationDescriptors = {}
	self.armName = ""
	self._maid = Maid.new()
	self._initialized = false
	-- Names added via `AddAnimations` (default poses, OtherAnims). Protected:
	-- `registryAnims` never overwrites or tears these down.
	self._defaultNames = {}
	-- Names declared by the last `registryAnims` call (the current weapon set).
	-- Used to drop the previous weapon's leftovers on the next swap.
	self._registryNames = {}
	return self
end

function AnimationHandler:Init(animationContainer: Instance)
	assert(not self._initialized, "Already initialized")
	if animationContainer:IsA("AnimationController") then
		self.animator = (animationContainer :: any):WaitForChild("Animator")
	elseif animationContainer:IsA("Humanoid") then
		self.animator = (animationContainer :: any):WaitForChild("Animator")
	else
		error("animationContainer must be AnimationController or Humanoid")
	end
	self._initialized = true
end

function AnimationHandler:IsInitialized()
	return self._initialized 
	
end

--[[
If takes state false does nothing, returns nil
If takes state false and animation name, stop it, returns nil
If takes state true and animation name, play it, returns AnimationTrack
If takes state true and animation name and preload true, playr and stop it inmediatly, returns nil
]]
function AnimationHandler:LoadAnimation(state: boolean, animaName: string, isPreload: boolean)
	assert(self._initialized, "Must call Init first")
	if isPreload then
		warn("Do you meant to use Preload() " .. debug.traceback())
	end
	-- Ensure the descriptor exists *before* dereferencing it. After a
	-- `_ClearAnimation` the descriptor entry is fully gone; this re-creates it.
	self:_ensurePreload(animaName)
	-- Unregistered name: `_ensurePreload` -> `_initDescriptior` bails when
	-- `self.animations[animaName]` is nil and leaves no descriptor. No-op here
	-- instead of asserting through `_getDescriptor`, so a caller asking for an
	-- animation this rig's set never declared (e.g. EffectService's "stuned" on
	-- a server NPC handler) degrades to "no animation" rather than throwing and
	-- aborting the caller's pipeline mid-apply (the stun WalkSpeed never got set).
	if not self.animationDescriptors[animaName] then
		warn(`AnimationHandler:LoadAnimation -- "{animaName}" is not a registered animation; skipping`)
		return nil
	end
	local current_desc = self:_getDescriptor(animaName)
	local animaTionTrack: AnimationTrack = current_desc.AnimationTrack

	if state and not animaTionTrack then
		local newanimaTionTrack = self.animator:LoadAnimation(current_desc.Animation)
		newanimaTionTrack:Play()
		current_desc.AnimationTrack = newanimaTionTrack
		-- Hand ownership of the track to the global maid so it is :Destroy()'d
		-- on cleanup (and replaces any prior track stored under this key).
		self._maid["track_" .. animaName] = newanimaTionTrack
		return animaTionTrack
	elseif state and animaTionTrack then
		animaTionTrack:Play()
		return animaTionTrack
	end

	---- STOP ANIM ----
	if not state and animaTionTrack then
		animaTionTrack:Stop()
		return nil
	elseif not state then
		return nil
	end
	return nil
end

-- Check if there's an animator in case the user is ragdolled
function AnimationHandler:_Check()
	if not self.animator then
		return
	end
end

function AnimationHandler:_initDescriptior(animaName: string)
	local existing = self.animationDescriptors[animaName]
	if existing and existing.AnimationTrack then
		warn("This descriptor was already initialized " .. debug.traceback())
		return
	end

	local animId = self.animations[animaName]
	if not animId then 
		return
	end
	local descriptor: AnimationDescriptor = {} :: AnimationDescriptor
	local newAnimation = Instance.new("Animation")
	newAnimation.AnimationId = animId
	descriptor.Animation = newAnimation
	descriptor.Maid = Maid.new()
	self.animationDescriptors[animaName] = descriptor

	-- Wire this descriptor's lifecycle into the global maid. From this point
	-- on, `self._maid:DoCleaning()` (or assigning `nil` to either slot) will
	-- destroy the Animation instance and run the descriptor's own maid,
	-- which disconnects every OnSignal-registered marker/Ended connection.
	self._maid["desc_" .. animaName] = descriptor.Maid
	self._maid["anim_" .. animaName] = newAnimation
end

-- Declare the firast animation track and set ptreload to true in the descriptor
function AnimationHandler:_ensurePreload(animaName)
	if self.animationDescriptors[animaName] and self.animationDescriptors[animaName].preloaded then
		return
	end
	self:_initDescriptior(animaName)

	-- `_initDescriptior` bails (no descriptor) when the name isn't in
	-- `self.animations`. Don't dereference a nil descriptor below -- let the
	-- caller (`LoadAnimation`) see the missing descriptor and no-op.
	if not self.animationDescriptors[animaName] then
		return
	end

	-- Load the animation and declare it
	do
		local animaTionTrack: AnimationTrack =
			self.animator:LoadAnimation(self.animationDescriptors[animaName].Animation)
		animaTionTrack:Play()
		animaTionTrack:Stop()
		self.animationDescriptors[animaName].AnimationTrack = animaTionTrack
		-- Track ownership goes to the global maid; on teardown it is :Destroy()'d.
		self._maid["track_" .. animaName] = animaTionTrack
	end

	self.animationDescriptors[animaName].preloaded = true
end

-- Just a helper to getting the animation tracker by its animation name
function AnimationHandler:_getDescriptor(animaName): AnimationDescriptor
	assert(animaName, "Animation name is nil")
	assert(self.animations[animaName], animaName .. " animation name does not exists")
	return self.animationDescriptors[animaName]
end

-- Register a *default* animation set (e.g. OtherAnims locomotion / poses).
-- These names are added once and protected: a weapon equip (`registryAnims`)
-- will never overwrite or tear them down, so the default poses keep playing
-- across swaps. If a default's id actually changed, its descriptor is cleared
-- so the next `LoadAnimation` rebuilds it with the new id.
function AnimationHandler:AddAnimations(newAnims)
	assert(self._initialized, "Must call Init first")
	for k, v in pairs(newAnims) do
		if self.animations[k] ~= v then
			self:_ClearAnimation(k)
		end
		self.animations[k] = v
		self._defaultNames[k] = true
	end
end

-- Reset to the default (`AddAnimations`) set only: tear down every weapon
-- animation registered via `registryAnims`, leaving the protected default set
-- (OtherAnims) untouched. A *full* teardown — defaults included — only happens
-- in `Destroy` via `ClearAllTheAnims`.
function AnimationHandler:Restart()
	assert(self._initialized, "Must call Init first")
	for name in pairs(self._registryNames) do
		self:_ClearAnimation(name)
		self.animations[name] = nil
	end
	self._registryNames = {}
end

function AnimationHandler:Destroy()
	assert(self._initialized, "Must call Init first")
	self:ClearAllTheAnims()
	self._maid:DoCleaning()
	setmetatable(self, nil)
end

-- Swap the *weapon* animation set. Touches weapon animations by name only —
-- it never wipes everything (that is `Destroy` -> `ClearAllTheAnims`) and never
-- the protected default set added via `AddAnimations`:
--   * names from the previous `registryAnims` call that the new set drops are
--     cleared by name, so a weapon swap never leaks the old weapon's tracks;
--   * an incoming name that collides with an existing descriptor is cleared so
--     the next `LoadAnimation` rebuilds it lazily with the new id;
--   * an incoming name already owned by a default (OtherAnims) is skipped, so a
--     weapon equip can never clobber a default pose (no Idle glitch).
-- Descriptors are not eagerly declared: `_ensurePreload` lazily builds them
-- from `self.animations` on the first `LoadAnimation`.
function AnimationHandler:registryAnims(anims: AnimationMap)
	assert(self._initialized, "Must call Init first")

	for name in pairs(self._registryNames) do
		if anims[name] == nil and not self._defaultNames[name] then
			self:_ClearAnimation(name)
			self.animations[name] = nil
		end
	end

	local registered = {}
	for name, animId in pairs(anims) do
		if not self._defaultNames[name] then
			self:_ClearAnimation(name)
			self.animations[name] = animId
			registered[name] = true
		end
	end

	self._registryNames = registered
end

-- Preaload all the animation at once, better don't use it on long animations list
function AnimationHandler:preloadAll()
	assert(self._initialized, "Must call Init first")
	warn(debug.traceback())
	for name, _ in pairs(self.animations) do
		self:_ensurePreload(name)
	end
end

type connArgs = {
	callback: (Track: AnimationTrack, params: any) -> (),
	animationName: string,
	animationEventName: string,
	override: boolean?,
}

function AnimationHandler:OnSignal(info: connArgs)
	assert(self._initialized, "Must call Init first")
	local animName = info.animationName
	local animationEventName = info.animationEventName
	local override = info.override
	local descriptor: AnimationDescriptor = self.animationDescriptors[animName]

	local animationTrack = descriptor.AnimationTrack
	local signal: RBXScriptSignal
	if descriptor.Maid[animationEventName] and not override then
		return
	elseif descriptor.Maid[animationEventName] and override then
		descriptor.Maid[animationEventName]:Disconnect()
	end

	if animationEventName == "EndedCon" then
		signal = animationTrack.Ended
	else
		signal = animationTrack:GetMarkerReachedSignal(animationEventName)
	end

	local conn = signal:Connect(function(param)
		info.callback(animationTrack, param)
	end)
	-- Note: this connection lives inside the descriptor's own maid, which
	-- is registered into the global maid under `desc_<name>`. When the
	-- descriptor is torn down (`_ClearAnimation` / `Restart` / `Destroy`)
	-- this connection is disconnected automatically.
	descriptor.Maid[animationEventName] = conn
end

function AnimationHandler:PreloadAnims(animsName: { string })
	assert(self._initialized, "Must call Init first")
	for _, name in ipairs(animsName) do
		self:_ensurePreload(name)
	end
end

-- Stop every currently-playing AnimationTrack without tearing descriptors
-- down. Use this when you want to interrupt all in-flight anims (e.g. ragdoll
-- transition, weapon swap pre-cleanup) but keep tracks preloaded so the next
-- `LoadAnimation(true, name)` can play instantly.
function AnimationHandler:StopAll()
	assert(self._initialized, "Must call Init first")
	for _, desc in pairs(self.animationDescriptors) do
		local track = desc.AnimationTrack
		if track and track.IsPlaying then
			track:Stop()
		end
	end
end

-- Fully tear down a single descriptor. Assigning `nil` to each maid slot
-- triggers `Destroy`/`DoCleaning` on whatever was stored there, so this
-- handles AnimationTrack:Destroy(), Animation:Destroy() and every OnSignal
-- connection that was registered into the descriptor's maid.
function AnimationHandler:_ClearAnimation(animName)
	self._maid["track_" .. animName] = nil
	self._maid["desc_" .. animName] = nil
	self._maid["anim_" .. animName] = nil
	self.animationDescriptors[animName] = nil
end

-- `_ClearAnimation` mutates `self.animationDescriptors`, so we drain the
-- table with `next()` rather than iterating with `pairs` (which is undefined
-- behavior under in-place removal). Same pattern Quenty's Binder.Destroy uses.
function AnimationHandler:ClearAllTheAnims()
	assert(self._initialized, "Must call Init first")
	local name = next(self.animationDescriptors)
	while name do
		self:_ClearAnimation(name)
		name = next(self.animationDescriptors)
	end
end
export type AnimationHandler = AnimationHandlerType

return AnimationHandler
