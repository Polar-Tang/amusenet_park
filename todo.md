[] Migrate all the remotes events to blink
#### Be aware of what's hit
[.] Tag the part which is hit and send it to the backend
[.] Figure out how to validate, we can do something like use the raycastPosition from the backend and check its position is not too far of the tagged part position
[] Using tag for the important parts, if the object can be destroyed HasTa("destroyable") if its head HasTa("player_hear") then do more damage end

### Ensure system is right
[] put some dummies which moves and test wheter the damage, raycats, etc are accurate

### Start movement system
###### Slide


your goal is to have a new movement type ability that works using the real design for abilities
- The slide file you found is an old implementation for dashes, it was meant to tell which's dash direction and roll vfx, this file needs to be removed and all the ability logic must be up to Weapon/WeaponClient context. Input manager will not have any file like InputManager.Bindings.
- Please create a new type for movement abilities, src/myNeverMoreS/weapon/src/Shared/types/weaponTypes.luau this will be the methods you use in the fields like effect: (self: Movementbility) -> (), these are methods called by parent class, function at combat config is why they are data-driven (read instructions.md, abilities section for more info)
- The slides on the other hand is different logic from dashes, they should applyImpulse instead of alignPosition because we need cancellable acelaration instead of a position prediction. Please program the slide ability as a new table for CombatConfig.lua

[Movement skill Slide] 
Make WeaponBase and WeaponBaseClient to inherit by the same asbtract class, this new file src/myNeverMoreS/weapon/src/Shared/Binders/Weapons/SharedWeaponBase.luau _createAbilities will hold the _createAbilities method which do sliglthy the same, but the main difference is it detects whether is server or not to not create Movement type abilities. Then you can remove _createAbilities from WeaponBase and WeaponBaseClient as they are now the abstract class method

# Syrup village
[.] melee
[.] hold shift (correr)
[.] hold right click
[.] animations loader refactorization
[.] ver no usar viewmodels (parte 1) 
[,] ver no usar viewmodels (parte 2) 
### finnish todo's
[.] Lerp camera firing on movement
[.] Lerp camera firing between camera mode changes
[.] callin restore cframe during m1 movement, 
[.] Check the current animation Equip play 
#### Explore strange lags + hand camera bugs
[] Strange call of PivotTO during a :recoil call
### Last steps
### Ver que funcione el aka y su animación
[.] Fix c0 and c1
[.] Using a different condition to rotate the shit
[] Align weapons like AK-47 to be harmonized with the camera

### Idle anim problem
Las animaciones de idle hacen que el character se mueva, hay varios procesos que hacen que el crosshair del arma quede en el centro de la cámara, pero el character se mueve todo el tiempo de arriba a bajo por la animación idle. 
soluciones
- ~Crear un cameraSubject, la camera se mueve junto con el player~ (mala idea porque tendría el mismo efecto que un cirujano con parkinson)
- usar otra animación para idle que no mueva el character en ningún eje

Update CLAUDE.md clearifying what tools are avaible. If there's anything important in any sections about the attack workflow you wanna add go ahead, for example an AttackAbility section (melee and AOE)
### task left
[.] agregar granadas
### VERSIÓN MOBILE
[.] Create the UI elements
[] Connect UI elements
### search the las peephole with mobile support
[.] On fist mode there's a point that have the same player's height, this point is obstucting the view from the camera, please edit drawTrajectory to don't create point too close to the player humanoid rootpart Y. Secondly i disables dragging boolean flag because i noticed is doing likely nothing and the modible version works better without that closeguard return. Third, when i aim too close to the player the peephole aims to player's back, i think it's due some kind of collision with player character, as this grenade is meant to be throw to other's players i think the click position shouldn't collide with them. 
[.] Dragging shit, weird collide
[.] There's a task left behind for mobile version, we already made the ui buttons and the drawTrajectory previsualizer, the only think we lack is that mobile users got only two thumbs and meanwhile a thumb is holding shot button it cannot move the screen to aim the target. What we need is auto-aim for our mobile users. I've never built this before but i guess we can do it as so:
- Do a wide raycast in order to catch the most humanoids as posible (isValid(target)) 
- Once a target is found we use LerpCamera to Cframe.lookAt(cameraPos, targetPos)
I'm not sure in regards how to get a target but i'm sure the LerpCamera has a perfect use case here

This works great however this new feature give us more bugs, i think there's
  some point when the target is facing the player's back, in such case
  the aim locked should become false and start tracking the target, also the 
  third person camera offset do fight with the rotation of lerp camera, i'm 
  not sure why this happens

where the camera offset is derived from workspace.CurrentCamera's rotation (rotationOnly:VectorToWorldSpace(CAMERA_OFFSET)). When the player drags on
  mobile, Roblox's default touch control still rotates the base camera. The lerp
  snaps the angle back onto the target, but the per-frame base rotation that
  drives the offset keeps changing — so the camera orbits the character's
  position even though the aim looks locked. That's the "position moves, angle
  doesn't" you saw. 
[] Enable first person mode in grenade


# Arlong Park
(lógica específica del juego)

## gameplaymap
### adding mmo
Range attack client has an ammo but it does not much, use an ammo in combatConfig weapon (fist hasn't an ammo) discount in server, i don't rembember if it's an attribute but if it's you can directly render it in the client. If ammo in backend is cero do early return, 
recharges de weapon is a brand new ability of the weapon and it's keycode is r. It's called from src/client/UI/RoactUI/components/MobileButtons.luau, inoutManager and directly from RangeAttack client, calling the weapon from the ability, not sure if registering this in create abilities as a callback or how could we do it. The ability actually is pretty dependant of m1, it only sets an atribute like swing that doesn't allow _shot to execute, and unset it after a harcoded value (we will change that in the future) and reset the _ammo that uses to be an internal value of M1 range attack client
How we could update this and add this feature in cleanest way? we will need some special fiels and methods at RangeAttackClient?

### Quests
- tres quests te garantiza subir 1 y medio
- cada kill te da una experience, si es doble kill, triple kill es más
[] pool the quests, hay una tabla con tittle, description and cb la cb puede usar distintas apis para checkear el su progreso
- quest diarias (cada 24 horas) y quests semanales (should make it long live in per server and store them in DS)
- Adding new quest to test, also create a component in src/client/UI/RoactUI that connects to QuestProgressRemote and share the quests list and update with its progession. If each quests require a different text you can consider move the quests pool to replicated storage so client and server can read it. 


### HACER BOTS
NPCs que tienen un patrol y utilizan la misma api que aim asistant para saber a que player disparar, los bots tienen un binder en el client que simula llamar shot desde una camara donde el raycast da perfecto al player aunque en realidad no muevan la camara
We need to create a new really complex binder, their tag is NPC. And it will go at src/myNeverMoreS/npc/src/Client/Binder, the npc state machine should be in client and not server for better perfomance. But we may need a Server binder for npc in order of tagging the Armed server version
- new method
  - Tagged the NPC with armed, creates maid and the needed fields
- Their Init method:
  It finds first child of class Tool and equip it, they should do the necesary to init Weapon, confirm if we can use weapon without animationHandler
- The start method
We should create a state machine, here's a real example of a binder using the state machine
```
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local StateMachine = require(ReplicatedStorage.StateMachine)
local setCTX = require(script.Parent.helpers.setCtx)
local StatesFolder = ReplicatedStorage.NPC.States
local StateMachineBinder = {}
StateMachineBinder.ServiceName = "StateMachine"
StateMachineBinder.__index = StateMachineBinder

function StateMachineBinder.new(char: Model, serviceBag)
	local self = setmetatable({}, StateMachineBinder)

	self.char = char
	self.state = nil
	self._initialized = false
	self._players = {}
	self.serviceBag = serviceBag
	self.maid = Maid.new()

	return self
end

-- this method is called on nearby players
function StateMachineBinder:Init(player)
	-- the state machine is like the npc's brain

	local state = StateMachine.new(
		"Idle",
		StateMachine:LoadDirectory(StatesFolder),
		setCTX(self.char, self.serviceBag, player, self.maid)
	)
	self.state = state
	self._initialized = true
	return self
end

function StateMachineBinder:Destroy()
	-- TODO: test this
	self.maid:DoCleaning()
	if self.state then
		self.state:Destroy()
	end
end
return StateMachineBinder
```
We use ReplicatedStorage.StateMachine, it loads a table with the context used throguh the state machines and string matching the state where it should start
In our example the directore shared.NPC looks like this:
```
.
├── Controllers
│   ├── 1
│   ├── EatController
│   │   └── EatController.luau
│   ├── MovementController
│   │   └── MovementController.luau
│   ├── PetAnimatorController
│   │   └── PetAnimatorController.luau
│   ├── SoundController
│   │   └── SoundController.luau
│   └── TargetController
│       └── TargetController.luau
├── Overhead.rbxm
├── Servicies
│   ├── BillboardService
│   │   └── BillboardService.luau
│   └── PlotService
│       ├── FenceBounds.luau
│       └── init.luau
├── States
│   ├── Eat.luau
│   ├── Idle.luau
│   └── Patrol.luau
└── Transitions
    ├── FinnishEating.luau
    ├── FinnishPatrol.luau
    ├── StartEating.luau
    └── StartPatrol.luau
```
The state are classes that longs as well as some transition to another state returns true and controllers are logic used along the state meachin to split responsability and keep the code clean. Here's the movementController:
```
local RS = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local packages = RS.Nevermore.Quenty
local NpcFighterTypes = require(ReplicatedStorage.Nevermore.Custom.NPCFighter.src.Shared.utils.NpcFighterTypes)
local petData = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.Binder.helpers.petData)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local Promise = require(ReplicatedStorage.Nevermore.Quenty.promise.Shared.Promise)
local BaseObject = require(packages.baseobject.Shared.BaseObject)

local MovementController = setmetatable({}, BaseObject)
MovementController.__index = MovementController

function MovementController.new(data: NpcFighterTypes.controllerdataInint, serviceBag: any, player)
	local self = setmetatable(data, MovementController)
	self._currentMovePromise = nil
	local petName = self.pet:GetAttribute("petName")
	self.speed = assert(petData[petName], "invalid petName").walkSpeed
	self._maid = Maid.new()

	-- IMPORTANT: `data.maid` (inherited onto this table) is the *binder* maid -- it
	-- owns every controller plus the pet's AncestryChanged teardown. This controller
	-- treats `self.maid` as its own move-scratch maid and DoCleaning()s it (see
	-- MoveTo's :Finally and _jumpToWaypoint), which would tear down its sibling
	-- controllers -> pet:Destroy() -> the pet vanishes mid-move. Own a private maid
	-- so move cleanup never reaches the binder maid.
	self.maid = Maid.new()

	-- Assume the pet has a Humanoid
	local humanoid = self.pet:WaitForChild("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = self.speed
	end
	self.humanoid = humanoid
	self.maid_waypoints = Maid.new()
	self.maid:GiveTask(self.maid_waypoints)
	return self
end

-- constsants
local GRAVITY = Vector3.new(0, -workspace.Gravity, 0)
local T = 0.5 -- use a fixed time for the ball to reach the target

function MovementController._jumpToWaypoint(
	self: NpcFighterTypes.MovementController,
	targetPosition: Vector3,
	onComplete
)
	self.maid_waypoints:DoCleaning()

	local startPosition = self.hrp.Position

	--V1 = P1 - P0 - 0.5*G*T^2/T
	local initialVelocity = (targetPosition - startPosition - 0.5 * GRAVITY * T ^ 2) / T
	local t = 0
	local moveConn
	moveConn = RunService.Heartbeat:Connect(function(deltaTime)
		t += deltaTime

		if t > T then
			onComplete(true)
			moveConn:Disconnect()
			return
		end

		--// s = s0 + v0*t + 0.5*a*t^2
		local newPos = startPosition + (initialVelocity * t) + 0.5 * GRAVITY * (t ^ 2)

		self.pet:MoveTo(newPos)
	end)
	self.maid:GiveTask(moveConn)
end

function MovementController.Stop(self: NpcFighterTypes.MovementController)
	self._maid:DoCleaning()
	self.isMoving = false
	if self.animationHandler then
		self.animationHandler:LoadAnimation(false, "walk")
	end
end

function MovementController.getAnimHandler(self: NpcFighterTypes.MovementController)
	local animHandler = self.animationHandler
	if animHandler then
		return animHandler
	end
	local BinderProvider = _G.ServiceBag:GetService(_G.BinderProvider)
	local AnimationBinder = BinderProvider:Get("AnimationHandler")
	self.animationHandler = AnimationBinder:Get(self.pet)
	return self.animationHandler
end

function MovementController.ForgotPath(self: NpcFighterTypes.MovementController)
	if self._currentMovePromise then
		self._currentMovePromise:Destroy()
	end
end

function MovementController.MoveTo(self: NpcFighterTypes.MovementController, path: Path)
	self._maid:DoCleaning()
	self._currentMovePromise = Promise.new(function(resolve, reject)
		local waypoints = path:GetWaypoints()

		if #waypoints == 0 then
			resolve()
			return
		end

		local animHandler = self:getAnimHandler()
		-- Not very sure why Promise defer does run after maid:DoCleaning but this fix it
		local status = pcall(function()
			animHandler:LoadAnimation(true, "walk")
		end)
		if not status then
			reject()
			self:Destroy()
			return
		end

		self.isMoving = true

		local currentIndex = 1
		local function moveNext()
			-- clean previous move connections and promises
			if not self.isMoving then
				resolve()
				return
			end
			if currentIndex > #waypoints then
				animHandler:LoadAnimation(false, "walk")
				self.isMoving = false
				resolve()
				self.maid_waypoints:DoCleaning()
				return
			end

			local waypoint = waypoints[currentIndex]

			self:_moveToWaypoint(waypoint.Position, function(reached)
				if reached then
					currentIndex += 1
					moveNext()
				else
					self:_jumpToWaypoint(waypoint.Position, function(reached)
						if reached then
							currentIndex += 1
							moveNext()
						else
							reject("Failed to reach waypoint")
						end
					end)
				end
			end)
		end
		moveNext()
	end):Finally(function(...): ...any
		self.maid:DoCleaning()
	end)
	return self._currentMovePromise
end

function MovementController._moveToWaypoint(
	self: NpcFighterTypes.MovementController,
	targetPosition: Vector3,
	onComplete: (boolean) -> ()
)
	self.maid_waypoints:DoCleaning()

	task.defer(function()
		local timer
		local time_out = Promise.new(function(resolve, reject)
			local t = 0

			timer = RunService.Heartbeat:Connect(function(dt)
				t += dt
				if t >= 1 then
					resolve()
				end
			end)
		end)
			:Then(function()
				onComplete(false)
				timer:Disconnect()
			end)
			:Finally(function(...): ...any
				timer:Disconnect()
			end)
			:Catch(function(...): ...any
				print("rejeccted")
				timer:Disconnect()
			end)

		self.maid_waypoints:GiveTask(timer)
		local conn = self.humanoid.MoveToFinished:Once(function(reach)
			onComplete(reach)
		end)
		self.maid_waypoints:GivePromise(time_out)
		self.maid_waypoints:GiveTask(conn)

		self.humanoid:MoveTo(targetPosition)
	end)
end

function MovementController.DestroyNPC(self: NpcFighterTypes.MovementController)
	self._maid:DoCleaning()
	self.pet:Destroy()
	self.isMoving = false
end

function MovementController.Destroy(self: NpcFighterTypes.MovementController)
	self._maid:DoCleaning()
	self.maid:DoCleaning()
	self.pet:Destroy()
	self.isMoving = false
end

local TweenService = game:GetService("TweenService")

local LOOK_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function MovementController.LookTo(self: NpcFighterTypes.MovementController, to: Vector3)
	local currentCFrame = self.hrp.CFrame
	local targetCFrame = CFrame.lookAt(currentCFrame.Position, to)

	local tween = TweenService:Create(self.hrp, LOOK_TWEEN_INFO, {
		CFrame = targetCFrame,
	})

	self._maid:GiveTask(tween)

	tween:Play()

	return tween
end

return MovementController
```
setCtx do create the tables for the controlles and give them to a gobal maid src/myNeverMoreS/npc/src/Shared/Binder/helpers/setCtx.luau. An state looks like this:
```
local ReplicatedSorage = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateMachine = require(ReplicatedSorage.StateMachine)
local utils = require(ReplicatedStorage.utils.utils)

local State = StateMachine.State

local Idle = State.new("Idle")

Idle.Transitions = {
	require(script.Parent.Parent.Transitions.StartPatrol),
	require(ReplicatedSorage.NPC.Transitions.StartEating),
}

function Idle:OnInit(data)
	-- runs once the state is created
end

function Idle:OnEnter(data)
-- runs once we enter the state
	data.lastIdleTime = data.timer
end

function Idle:OnHeartbeat(data, deltatime)
	data.timer += deltatime
end

return Idle

```
and transitions looks like this:
```
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxStateMachine = require(ReplicatedStorage.StateMachine)

local Transition = RobloxStateMachine.Transition

local StartPatrol = Transition.new("Patrol")

function StartPatrol:OnDataChanged(data)
	local timeSinceLastPatrol = data.timer - data.lastPatrolTime
	if timeSinceLastPatrol >= data.patrol_interval then
		return true
	end
	return false
end

return StartPatrol
```
On data changed runs onHearbeat because we are changing data.timer. As StartPatrol is a transition at Idle.Transition it will transition to the Patrol state.
So our bots will be have Patrol, Attacking and Idle. they start in patrol, do patrol to a part (workspace.goal_*), these pats are also tagged as NPC_goals, add this tag to constants. On patrol enter it checks whether there's already a goal in the context, and if its already closer enough pick a new random goal and create a path with pathFinder to reach its goal (the object domain for this is goalController), returns this goal and give it to movementController
```
local ReplicatedSorage = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedSorage.StateMachine)
local NpcFighterTypes = require(ReplicatedStorage.Nevermore.Custom.NPCFighter.src.Shared.utils.NpcFighterTypes)

local State = StateMachine.State
local Following = State.new("Following")

function Following:OnEnter(data) end

function Following:OnHeartbeat(data: NpcFighterTypes.petStateCtx, deltaTime)
	data.timer += deltaTime
	if data.timer - data.lastTriggerTime >= 1 then
		local timerPhto = data.timer
		data.lastTriggerTime = timerPhto

		local goalPos = data.TargetController:GetGoal()
		if goalPos then
			data.TargetController:CalculatePath(goalPos):Then(function(path: Path): ...any
				data.MovementController:ForgotPath()
				data.MovementController:MoveTo(path)
			end)
		end
	end
end

return Following
```
Once it reachs its goal start idle (the transtion is the position reached to the current goal) and idle transition uses a timer of 20 seconds to return to Patrol. All states variables may be resumed if there are interrumpted, how they are interrumpted? There's the transition to attacking, We should use a controller to find a target to shoot, it uses src/myNeverMoreS/abilities/src/Shared/utils/findAimAssistTarget.luau to find a target, once it finds it we tansition to attacking state should have another controller that simulates a camera to shoot the player, we may need to change rangeAttackClient maybe, because they read workspace.CurrentCamera but there should a field for custom camera or something, once you finnish the controller that simulates the armed in the client, the attacking state calls it, there's delay between Weapon:Execute(m1) so call controller shoot between intervals

### HacerBots 2
The lobby will sent an image to this game version when it start, it creates a number of bots in random goal workspace.goal_*, init them from the server, uses ServerStorage.NPC_models pick a random one and added, position and adding the needed tags. Create a test that initialize them with 4 npcs to see if it works

The server recive a message like 
MessagingService:PublishAsync(Config.MATCH_FOUND_TOPIC, {
		matchId = HttpService:GenerateGUID(false),
		accessCode = accessCode,
		userIds = userIds,
		botCount = botCount,
	})
  from the lobby place to start the bots, how could we recive that message and fill the place with the needed bots through MessagingService api?
## Once in lobby

### quests
We got a pool of quests at src/shared/Quests/QuestsData.luau we 

#### Loby version
We are using a quest handler version like the one from the shooter place. The deal is that shooter and lobby will syncronize through using the same datastore, but only the lobby will accept quests. It uses a pool of quests, they should be sorted by weekly and daily, we can store the last connection of the player and check if a day have passed to aceppt the 3 new random quest from the pool, the same for weekly and we can accept them. Follow the same quest pattern to align to the new quests shape and create new ones for daily and weekly by adding more quests to src/shared/Quests/QuestsData.luau.allQuests

#### Lobby, arrange with bots after time out
We are using a queu, if it doesn't find any player fills the missing players with bots, we need to sent an image to the gameServer to create a quantity of bots.

### distintos modos
Define an architecture for using the same source file and different game mods
King of the Hill (koh)
Capture the Flag (ctf)
Last Man Standing (lms)
Team Deathmatch (tdm)
### Battle pass 
[] subir de nivel te va dando recompensa
[] si sos jugador premium lo tenés desbloqueado
### Leveling
- Existen rangos para el jugador bronce plata oro platino diamante y MAESTRO (match making)
### Kill cam
- cambia la camara del player a quien lo asesino
- se muestra un cartelito 
- el cartelito es personalizable con las skins
### FULL GAME UI
estilizado como wonkeland
[] Slots para las skins como 10 
[] RNG spin roulete (recompensas skin)
[] hay slots para las recompensas 2 de límite o 3 si pagás
[] recompensa para los jugadores premium 
[] AMO ui, echa con imágenes de ia
[] Radar (usando un "pie slice" una fracción del perimetro del círculo rotada inteligentemente)

### loby
- misiones
- shop
- ajustes
- invnetario/personalizar
- leaderboard
### Modos de juego
The lobby needs to be changed a little bit to send game modes to the other place
### Lobby quests mode
We should change the PlayButton interaction, it nows should pop up a sign.
It has a close button which is a red frame with an x for textlabel and close functionallity, you can use a context if you want to, There are some providers and context in the context folder, a context consumer use the useContextUtility like this:
```
```
function Crosshair:render()
	local withCtx = useContext({ CrosshairContext = CrosshairContext })

	return withCtx(function(ctx)
		local crosshairCtx = ctx.CrosshairContext
```
```
So the sign design, it occupies most the screen and it shows different 'game modes' which are columns, every column is a component so we DRY and it takes description, title, image and button cb as props, the titles are the folowings
King of the Hill (koh)
Capture the Flag (ctf)
Last Man Standing (lms)
Team Deathmatch (tdm)
The callbacks do fire the server with the game mode: koh ctf lms tdm
Get creative with description and use placeholder as images
#### Backend
joinQueue(player: Player) of Queu manager needs to craft a payload for the reserved server
The payload type goes like:
export type MatchPayload = {
	mode: string?,
	botCount: number?,
	matchId: string?,
}

### What happens to quests?
Currently i'm trying to access the quests 


### Create a tutorial handler
We need a tutorial handler for a ui. It should be built in roact 
This handler expose a start method which goes like:
Highlight a location: It's like you covering the entire UI with a frame opacity, only leaving a frame full of borders radious with no index, as result the only that can be clicked is the part with the border frame that has no this opaciti zindex covering it. Param: A position and size
Animated hand pointing: There's an image that can tween its position, rotation, Optionally the size. Param: Start position and an end position, the same for rotataion
We should manually call the Destroy method which set back everything to normal and cleanups connection via maid:DoCleaning if any


[] Find out different aim position and all the weapons should have the posibility to enable this camera mode

-- NEEDED ANIMATIONS:
Recargar
Apuntar
Equipar
Desequipar
Okay, handHeadCamera is working well, however the aimPosition isn't still at the camera center

I want you to design a GUI for my roblox game, specifically the lobby screen. The player charater is at the lobby and got some buttons for:
### loby

- misiones

- shop

- ajustes

- invnetario/personalizar

- leaderboard
 Important things to know: The header buttons are reserved by roblox and always be there, the right side always have the leaderboard there left side and the bottom center probably will have the weapons list and bottom left will be probably reserve too. the first two image are roblox UI and the third one is a fortnite
misiones, novedades, ajustes, hitos, códigos
si sos jugador free to play tenés que pasarte 3 seasons
bronze plata oro platino diamante maestro
cuando recipen arrancas ranked sos bronze tres 
una victoria te da 30
una derrota resta 25
100 puts bronce 3, 100 pts bronze 2 
inventory
skins de armas
skins de kill card

 I updated default.project.json, later src/client was everythin in
  StarterPlayerScripts, the same with src/shared to ReplicatedStorage, and
  src/server ServerScriptService, the problem with this is that any instance
  added to ReplicatedStorage, StarterPlayerScripts or ServerScriptStorage was
  overwrited by rojo compiling, now i fixed this error by overwriting a single
  folder in each of them, the problem is that now every file path needs to be
  updated. Please update all the requires

### Create a spin roulette 

1. Create the template
Given a spin roulete, create a Roact component  image label which's a square but the image is the spin roulete wheel. The other component is a button its activated callback function you send a remote event for creating an angle for this wheel. 
2. Create items and a remote event
Connect to the server this remote event at ServiceRoot.server.luau.
In replicated storage create src/shared/items/roulleteItems.luau You will a list of reward and every one got a "rarety" field besides an angle in radians, this angle should be related with the rewards quantity, for example 6 would be 60 degrees or pi / 3 rad so the angles will go like:
0, π​/3, 2π/3​, π, 4π/3​, 5π​/3, 2π
there are 6 rewards 3 are common, 2 are uncommon and one is epic. We pick a reward and fire back the client to this angle
Then server connection does
local rarety = WeightedRandom.Pick({
  {value = "Common",    weight = 200},
  {value = "Uncommon",  weight = 80},
  {value = "Epic",      weight = 12},
})
3. Rotate the image
Given the second law of newton, calculate the angular force needed to do full rotations and desacelarates the wheel until reach the angle told by the server

### Using treasures 
We need to create chest that can be detected by a radar. First create a binder (see claude.md there should be a section for binder) this binder lives in shared folder. The tag used is at src/myNeverMoreS/abilities/src/Shared/Constanst.luau. It does create a proximity prompt parented to the object (instance of the tag).
The proximity prompt fires a remote event the server event create two weapons and uses

Now check if we are already using promptShown connection of a proximity promt, because we need to detect if the parent of proximity prompt has this tag, then you need to render a radar component.
Radar component is a png of a slice of a circle, but you need to calculate the its angle between the camera and the chest position so the slice point the camera rotation needed to reach the chest
