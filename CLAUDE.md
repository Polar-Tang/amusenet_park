# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# A brief introduction to gun shit
gun shit is a name for a big project desinged to be gun/m1 shoter framework. The main focus about all this project is the mantebillity because its planned to be reusable work with an infrastructure that allows to be forked into any new shoter game. The usability is designed to resembles fortnite gameplay
## Architecture Overview
This is a Roblox combat game using Luau, structured as:
- `src/client/`: Client-side logic divided into 3 folders
  `src/client/Character`: Folder scripts parented to player.Character
  `src/client/StarterGui`: Assets for the UI, mainly `.rbxm` files, in-game path is gameStarterGui
  `src/client/UI`: Scripts runing at all in the client. Contains the serviceRoot.client, Roact, input handling, etc. in-game path is the singleton game.PlayerScripts
- `src/server/`: Server-side logic (combat mediation, player management)
- `src/shared/`: Shared utilities (animations, effects, Roact library)
- `src/myNeverMoreS/`: Core game systems (abilities, weapons, NPCs), every service got `shared` for replicated modules, `server`, and/or `client`
- `node_modules/@quenty` and `node_modules/@quentystudios`: Useful utilities of NeverMore engine (i encourage to read all of this folders before developing any new feature)

The folders `src/client` and `src/server` got a main entry point called ServiceRoot, this script bootstraping the game through Nevermore engine. Initialize the services using the ServiceBag. ServiceBag it's like those singleton you access via game.`serviceName`. You can retrieve services from it, and it will ensure the service exists and is initialized. This will bootstrap any other dependent dependencies. Currently the serviceBag is stored into `_G`, this allow the service game to be accesible to all the client or server via `_G.ServiceBag` just like the game singletons, however this desing is not recommended and we'll need to migrate to full DI desgin in the future.
Key frameworks:
- **Nevermore (Quenty)**: ServiceBag for DI, Binders for object behaviors, Cooldowns, and other Luau packages
- **Roact**: React-like UI library for Roblox
- **RemoteEvents**: Client-server communication via `RS.RemoteEvents/`, Remote events endpoints are located in file nameds as `*mediator*.luau` though there are some in ServiceRoot but they'll need refactorization to move the file

## Core Patterns
Services initialized in ServiceRoot are stored as a variable in `_G` once they are initialized
- **Service Access**: Use `_G.ServiceBag:GetService(<ServiceModule>)` for a service, and `_G.ServiceBag:GetService(_G.BinderProvider):Get(tag):Get(object)` for a binder. **`_G.BinderProvider` is a service KEY, not the started provider** — see *Retrieving a service / binder from inside a service* below; never call `:Get(tag)` directly on `_G.BinderProvider`.
- **Binders**: Tag objects with CollectionService tags like "Armed", "AnimationHandler"; bind behaviors via BinderProvider
- **Combat Flow**: "Armed" tag is used for weapon binder which strongly uses inheritance behaviour and allowing weapon strategies and abilities to be data-driven from `/src/myNeverMoreS/weapon/src/Shared/CombatConfig.luau`
- **Armed binder**: Weapon binder is a context for weapons, `src/myNeverMoreS/weapon`, every weapon it's a different strategy which inherits from `src/myNeverMoreS/weapon/src/Server/Binders/Weapons/WeaponBase` (server) or `WeaponBaseClient` (client). Both now extend `SharedWeaponBase` (`src/myNeverMoreS/weapon/src/Shared/Binders/Weapons/SharedWeaponBase.luau`) which owns the `_createAbilities` method. Weapons create abilities via `createAbilitiesFromKey()` using `skills` and `attacks` keys from the data table
- **Armed binder lifecycle (context vs strategy)**: The "Armed" binder class (`WeaponClient` client / `Weapon` server) is bound **once per character** and is a long-lived *context*. The actual weapon — a *strategy* (Fist/Gun/Ak_47…) — lives on `self._weapon` and is swapped on equip. Swapping a weapon does NOT re-tag the character; it calls `EquiTool(name)`, which **must destroy the previous `self._weapon` before installing the new one** (`self._weapon:Destroy()` then reassign). each `BaseAbility` registers itself into the strategy's `_maid` so a strategy's `Destroy` → `_maid:DoCleaning()` cascades into every ability's own `_maid`. 
- **Armed binder destroy contract**: Both sides expose the same surface so `characterCtxUtils` can drive equip/unequip without branching — see the shared base type `WeaponContextBase` in `src/myNeverMoreS/weapon/src/Shared/types/weaponTypes.luau` (server `WeaponContext` and `WeaponContextClient` both extend it). 
- **Abilities**: Every ability must be declared in `CombatConfig.<weaponName>.attacks` or `CombatConfig.<weaponName>.skills`. CombatConfig is the ability API: each table entry is the behavior definition for that ability, and the ability key fields are the methods that implement the unique logic for that entry. The generic classes in `src/myNeverMoreS/abilities` must stay thin and only dispatch the table methods, not own ability-specific behavior. Keep the design data-driven and reuse the same class for many tables.
- **Movement abilities**: `MovementAbilityClient` and `MovementAbility` are generic parent classes used by slide, dash, zip line, and future movement abilities. The movement-specific logic belongs in `CombatConfig` movement tables through fields like `get_anim_name`, `effect`, and `endFx`. Add explicit movement types in `src/myNeverMoreS/weapon/src/Shared/types/weaponTypes.luau` (not the server-only `Server/types/weaponTypes.luau`, which holds gun stats) and keep movement params typed using `MovementAbilityParams`/`MovementAbilitySpec` instead of `any`. The same movement class should work for every movement table, while each table defines its own impulse, animation, direction, VFX, and cleanup behavior.
- **Attack Ability**: Executed from inputManger, attckInvoker, the behavior of the hitbox should change with **`"ST"`** resolves on the **first** `AddHit` — one target, immediate, **`"AOE"`** accumulates every `AddHit` and resolves after `delay_cb_number` and should be convined with a **long-lived `TimedBox`** as HitDetectionInfo
- **Ability type field values**: `"Movement"` = client-only (skipped server-side in `SharedWeaponBase._createAbilities`), `"Defense"` = `DefenseBaseAbility`, `"Attack"` = `AttackBaseAbility`, `"Range"` = `RangeAttack`/`RangeAttackClient`, `"Reload"` = `ReloadAbility`/`ReloadAbilityClient`, `"Others"` = `MovementAbility` server-side. On client, `"Range"`, `"Movement"`, `"Attack"` and `"Reload"` are instantiated.
- **Ammo / reload**: the Tool's `_ammo` / `_reloading` attributes (`Constants.AMMO_ATTRIBUTE` / `RELOADING_ATTRIBUTE`) are the single shared ammo store — written only by the server (`RangeAttack` seeds `_ammo = magazineSize` in `new()` and decrements per validated shot; `ReloadAbility` refills after `weapon_stats.reloadTime`), replicated to clients for free. Never store ammo in `weapon_stats` at runtime: every ability holds a private clone of it. `RangeAttackClient` dry-fire-gates on the attributes and auto-reloads on empty by dispatching `self._weaponHandler:Execute(Enum.KeyCode.R)` (the same key path InputManager/MobileButtons use) — the m1 and reload abilities never reference each other. The `AmmoCounter` Roact component watches the local character's Tool and mirrors the attributes; it shows only when `_ammo` exists (guns).
- **Combat COnfig**: Every ability (server, `src/myNeverMoreS/abilities/src/Server/Abilities/*`) and `AttackBaseClient` (client, `.../Client/Abilities/*`). They
own **no** weapon-specific behavior; everything unique lives in the
`CombatConfig.<weapon>.attacks.<key>` table.
- **Armed name**: Every weapon uses a key string to lower case which indentify it for behaviour (`CombatConfig.luau`) and animations (`src/shared/Animations/WeaponsAnims.luau`) handled by the animation handler binder
- **AnimationHandler binder**: `src/myNeverMoreS/animations/src/Binder/AnimationHandler.luau` (tag `"AnimationHandler"`, constructor wrapped by `Animation.luau`). Bound once per character; `binder:Init(humanoid)` must run before any other method (every method asserts `_initialized`). It lazily builds an **AnimationDescriptor** per animation name (`{ Animation, AnimationTrack, Maid, preloaded }`); `Maid` holds the `OnSignal` marker/`Ended` connections. Key methods: `LoadAnimation(state, name)` (true=play, false=stop; lazily preloads), `OnSignal{...}` (connect a marker/Ended callback, stored in the descriptor maid). **Default vs weapon split (v_07)**: `AddAnimations(map)` registers **protected default** animations (the OtherAnims poses) — added once, tracked in `_defaultNames`, and never overwritten or torn down by a weapon swap. `registryAnims(map)` swaps only the **weapon** set *by name* (tracked in `_registryNames`): it drops the previous weapon's leftover names, rebuilds colliding names lazily, and **skips any name already owned by a default** so the default pose survives untouched. `Restart()` tears down only the weapon set (back to defaults-only).

## Binders (Quenty)

A **Binder** is a class attached to every Roblox `Instance` that carries a given `CollectionService` tag. Instead of writing per-instance `if isCharacter then ...` glue, you tag the instance and the binder constructs an OOP wrapper around it. Tag/untag is the lifecycle signal. The canonical implementation is `node_modules/@quenty/binder/src/Shared/Binder.lua` — read that before extending binder behavior.

### Mental model

- `Binder.new(tagName, ConstructorClass)` registers a tag → class mapping. `Binder:Start()` (driven by `BinderProvider` via the service bag) loops `CollectionService:GetTagged(tag)` and listens to `GetInstanceAddedSignal` / `GetInstanceRemovedSignal`.
- When a tag is added to an instance, the binder calls `ConstructorClass.new(inst, ...self._args)` and stores the result in `_instToClass[inst]`. `GetClassAddedSignal` fires.
- When a tag is removed (or the binder is destroyed), `GetClassRemovingSignal` fires, the class is dropped from the maps, and **if the class is a valid Maid task** (i.e. it has `:Destroy()` or is a callable / connection), `MaidTaskUtils.doTask(class)` is called — that's the mechanism that runs `class:Destroy()` automatically on tag removal. Then `GetClassRemovedSignal` fires.
- `binder:Get(inst)` returns the bound class for an instance. `binder:Promise(inst)` returns a Promise resolved when the class exists. `binder:ObserveBrio(inst)` gives a `Brio<class>` stream.

### How this project wires binders

Two binders matter for the combat loop, both registered in `src/client/UI/ServiceRoot.client.luau` and `src/server/ServiceRoot.server.luau` via `BinderProvider`: `"AnimationHandler"` and `"Armed"`.

Access pattern from anywhere:

```lua
local BinderProvider = _G.ServiceBag:GetService(_G.BinderProvider)
local WeaponBinder = BinderProvider:Get(Constants.ARMED_TAG)
local weaponHandler = WeaponBinder:Get(character) -- the bound class for this character
```

### Retrieving a service / binder from inside a service

A ServiceBag **service** is a module table with `ServiceName`, an `Init(self, serviceBag)` and (usually) a `Start(self)`. ServiceRoot registers it with `serviceBag:GetService(Module)` **before** `serviceBag:Init()` / `serviceBag:Start()`; the bag then calls each service's `Init(self, serviceBag)` (handing it the bag) and later `Start(self)`. So a service reaches its dependencies through the **bag it was handed at `Init`** — not through `_G` and not by `require`-ing another service directly.

```lua
function MyService.Init(self, serviceBag)
    -- Stash the bag in an UPVALUE, not a self field (see the servicebag-instance-
    -- vs-module-identity memory): the bag wraps the module in setmetatable({}, …),
    -- so a self field written here won't be visible to a direct require of the module.
    serviceBag = serviceBag
end
```

**Getting another service:** `serviceBag:GetService(OtherServiceModule)` — pass the *module* as the key; the bag returns the started, cached instance. Grab services whose runtime behavior you need in `Start`, not `Init` (an `Init`-time `GetService` returns a half-built proxy whose `Start` hasn't run — see the CameraStackService gotcha below).

**Getting a binder:** binders are reached through the BinderProvider service, and `_G.BinderProvider` is the **registration KEY** for it (it holds the raw provider object ServiceRoot built, whose binders have *not* started). The **started** provider — the one whose binders are live — only comes back from `serviceBag:GetService(_G.BinderProvider)`:

```lua
local provider = serviceBag:GetService(_G.BinderProvider) -- started instance, NOT _G.BinderProvider itself
local flagBinder = provider:Get(GameModeConstants.CTF_FLAG_TAG)
```

Calling `:Get(tag)` straight on `_G.BinderProvider` is the trap (it bit `CaptureTheFlag` — it returned binders that looked empty). Always go through `GetService` first.

**Non-service objects** that the bag never `Init`s directly (the game-mode strategies, for instance) get the bag handed *down* to them — modes receive it as `deps.serviceBag` (set in `GameModeService.Init`, passed through `BaseMode.Init`). Use that, not `_G`.

**Tags are constants, not literals:** the binder tags (`ARMED_TAG`, `ANIMATION_HANDLER_TAG`, `CD_TAG`, `NPC_TAG`) live in `src/myNeverMoreS/abilities/src/Shared/Constanst.luau`. Both ServiceRoots register the `Binders` table and `AddTag` characters using those constants — never re-hardcode the string.

### Equip / unequip workflow

Trigger: a `Tool` becomes a child of `player.Character`.

1. **Client** — `src/client/UI/ServiceRoot.client.luau`'s `onCharacterAdded` wires `character.ChildAdded`/`ChildRemoved` into a per-character maid (rebuilt on every `player.CharacterAdded`, i.e. respawn-safe). If the new child is a `Tool` it fires the server (`ReplicatedStorage.RemoteEvents.Equipment`) and initialize animationHandler as armed via `characterCtxUtils:InitChar(character, tool.Name:lower())`; `ChildRemoved` fires the remote with `has_to_equip = false` and destroys the local strategy via `characterCtxUtils:UnequipChar`.
2. **Server** — `src/server/Combat/CombatMediator.luau` `Equipment.OnServerEvent` handler does the same `characterCtxUtils:InitChar(char, r6Name)` on the server side (and `UnequipChar` when `has_to_equip = false`).

### Default weapon (fist) — a player character is never strategy-less

Two paths guarantee an alive player character always has a weapon strategy, both funneling into `characterCtxUtils:EquipDefaultWeapon(char)` (guards: skip if a Tool is present, the character is unparented, or the Humanoid is missing/dead; `DEFAULT_WEAPON = "fist"`):

- **Spawn**: a bare character never fires `ChildAdded`/`Equipment`, so each ServiceRoot's `onCharacterAdded` chains `WeaponBinder:Promise(char)` → `AnimBinder:Promise(char)` (ensuring `animHandler:Init` ran — fist is melee, its anims are required) and then equips fist. Each side equips its own strategy independently; no remote involved. NPCs are untouched (they equip via `NPCServer`/`NPCClient` `Init`, not this path).
- **Unequip**: `characterCtxUtils:UnequipChar` follows `UnequipCharWeapon` with a `task.defer`red `EquipDefaultWeapon`. The defer + Tool guard makes a hot swap (Tool A removed → Tool B added same frame) skip the fist detour, and the dead-Humanoid guard keeps corpses unarmed (death unequips the Tool to the Backpack). Both client (`ChildRemoved`) and server (`Equipment` with `has_to_equip = false`) route through this one helper.

Equipping a real Tool over the default fist needs no unequip step: `EquiTool` destroys the previous strategy before installing the new one. Fist equips with **no Tool instance present** — both `EquiTool`s tolerate that (client stores a nil `_tool`/`_aimPosition`; server skips the grip Motor6D), and fist's CombatConfig grips resolve from the character's arms.

### Common pitfalls

- **Binders are services**: always retrieve via the *started* provider — `serviceBag:GetService(_G.BinderProvider):Get(tag)` (`_G.BinderProvider` is the registration key, not the started provider; `:Get(tag)` straight on it is the trap) — never construct your own. See *Retrieving a service / binder from inside a service* above.
- **Constructor must not yield**: yielding constructors race the tag-removed signal and trigger `[Binder._add] - Failed to load instance, removed while loading!` warnings (Binder.lua:691).
- **Destroy is automatic on untag**: if your bound class has `:Destroy()`, it will be called by `MaidTaskUtils.doTask` when the tag is removed. You don't need a `ClassRemovingSignal` listener for cleanup — just implement `Destroy` correctly.
- **Instantiation is deferred — never snapshot `binder:GetAll()` at one instant**: `Binder:Start` schedules each pre-tagged instance with `task.spawn(self._add, …)` (Binder.lua:216) and binds the rest through `GetInstanceAddedSignal`, so a class can be constructed a frame (or more) *after* your consumer code runs. A one-shot `binder:GetAll()` / `provider:Get(tag):GetAll()` read at the top of some `Start` races that and silently returns `{}` even though the instances exist and bind moments later (this bit `CaptureTheFlag.Start` — flags tagged in the map came back empty). The tell: the bound class's own constructor *is* firing (prints land), but the consumer saw nothing. **Fix = react, don't snapshot**: connect `binder:GetClassAddedSignal()` (catches binds now *and* later, and re-fires on a destroy→re-tag), pair with `GetClassRemovingSignal()` to drop stale entries, and run a `GetAll()` sweep for whatever was already bound — make the per-instance handler idempotent since the sweep and the signal can both reach the same instance (same re-entry lesson as the ServiceRoot NPC sweep). `GetClassAddedSignal` fires from *inside* `_add` **after** the constructor returns (Binder.lua:722, post line-688 `constructor.new`), so anything the constructor built synchronously (a ProximityPrompt, etc.) is guaranteed to exist when your handler runs — there is no "signal fired before the object was ready" race **as long as the constructor doesn't yield** (which it must not anyway). If you genuinely need a single instance and can yield, use `binder:Promise(inst)`; to stream use `binder:ObserveBrio(inst)` / `ObserveAllBrio()`.
- **Session services must never cache `player.Character` in a field (respawn)**: both ServiceRoots and every ServiceBag service survive death; only the character Model is replaced. Anything character-scoped is (re)applied per spawn: the server re-tags + re-applies combat attributes in `onCharacterAdded` (`ServiceRoot.server.luau`, calls `CombatMediator.CharacterAdded(char)`), the client rebuilds the tool `ChildAdded`/`ChildRemoved` wiring in its own `onCharacterAdded` (per-character maid), `shiftLockController` re-acquires the rig on `LocalPlayer.CharacterAdded` (and drops its cached `_weaponClient`), `handHeadCamera` re-resolves its Motor6D rig lazily when `LocalPlayer.Character` changes, and `MainApp` re-injects the new character's WeaponClient into the Roact tree on every "Armed" rebind. New code should either read the character live each use or hook `CharacterAdded` with per-character cleanup — never capture it once at module/service init.

## Death / respawn flow (manual respawn + killer cam)

`Players.CharacterAutoLoads = false` (set at the top of `ServiceRoot.server.luau`): the engine never spawns characters. The server issues the **first** spawn itself in `PlayerAdded` (after wiring `CharacterAdded`, so the per-character setup is never missed); every later spawn only happens when the dead client fires `RemoteEvents.RespawnRequest` — handled in `ServiceRoot.server.luau`, which calls `player:LoadCharacter()` **only if the player is actually dead** (alive requests are ignored: free teleport-to-spawn otherwise).

- **Kill confirmation is EffectService's job**: `EffectService:Apply`'s `context.damage` block is the only place lethal damage lands, so it owns the authoritative "X killed Y" signal — when `wasAlive and Health <= 0` and the defender is a real Player, it fires `RemoteEvents.PlayerDied` to that client with `{ killer = attacker_char }`. The killer is a **character Model**, never a Player: it may be an NPC rig (`getCharacterActor` fake players carry the rig in `.Character` too).
- **`DeathScreen` (Roact, `src/client/UI/RoactUI/components/DeathScreen.luau`)** is the client driver, mounted from `App` with `cameraMediator` as prop. Two idempotent show-triggers: the `PlayerDied` remote (combat kills → also `cameraMediator:EnterDeathCam(killer)`) and the local `Humanoid.Died` (falls/reset/anything EffectService never sees → button only, no killer cam) — the second one guarantees the player can never be stuck dead without a respawn button. `CharacterAdded` hides it and calls `ExitDeathCam`. While dead it frees/shows the mouse (`MouseIconEnabled`, `MouseBehavior.Default`, `Modal = true` on the button); the respawn button just fires `RespawnRequest` (safe to spam, server validates).
- **Killer cam = fabricated CFrame, not the killer's Camera**: a remote player's `Camera` never replicates, and the NPC brain's eye is an unparented `Instance.new("Camera")` that exists only on the brain-owner client. But `AttackController.Shoot` builds that eye **from the NPC's Head** (`CFrame.lookAt(head.Position, target)`), so reconstructing the view from the killer Model's replicated Head is exactly as faithful and unifies player/NPC killers with zero extra remotes. `KillerCam.luau` (`cameraHandlers/camerasStates/`) is a mode strategy shaped like ThirdPerson/FirstPerson: render step at `Camera.Value` writing an over-shoulder CFrame (head rotation + offset) into the mediator's shared `_cameraState`, exponentially smoothed so the death cut glides; if the killer despawns (nil killer, Parent nil, no Head) it freezes on the last frame. Effects/combos on the stack keep working during the death cam.
- **CameraMediator integration**: `EnterDeathCam(killer?)` / `ExitDeathCam()` swap `_activeMode` like the FP/TP toggle does, plus a `_isDead` gate on the `_isFirstPerson` observer so a mid-death toggle can't evict the KillerCam (the wanted mode is re-applied from `_isFirstPerson.Value` on exit, via the factored `_applyMode`). Entering also drops `CameraMode.LockFirstPerson` (it would fight a camera far from the dead subject) and exiting restores it.
- **App's ScreenGui is `ResetOnSpawn = false`**: Roact owns it for the whole session; engine deletion on spawn would orphan the tree, and the death screen must live across death → respawn.

## NPC binder (tag "NPC")

NPCs are rigs tagged `Constants.NPC_TAG` ("NPC") in Studio, with a `Tool` child naming their weapon. The package is `src/myNeverMoreS/npc/`, registered as `["NPC"]` in both ServiceRoots. The split is deliberate:

- **`Server/Binder/NPCServer.luau`** makes the rig a *valid combatant*: in `new()` it tags `AnimationHandler`/`CD`/`Armed` (the same set players get in ServiceRoot's per-character `onCharacterAdded`) and mirrors `CombatMediator.CharacterAdded`'s combat attributes (`Combo`, `Stunned`, `Iframes`, …) so the server hit pipeline treats it exactly like a player character. `Init()` equips the first Tool child through `characterCtxUtils` so the server Weapon strategy exists. `Start()` runs **brain-owner election**.
- **`Client/Binder/NPCClient.luau`** is the *brain*: a RobloxStateMachine (`src/shared/StateMachine`, → `ReplicatedStorage.Shared.StateMachine`) with states Patrol/Idle/Attacking under `Client/States`, transitions under `Client/Transitions`, driven by four controllers built in `Client/Binder/helpers/setCtx.luau`. The machine runs on the client for performance.

### Brain ownership: exactly one client per NPC

Every client binds every NPC (tags replicate), so without election every connected client would run the machine and fire the weapon — the server would apply duplicated damage. `NPCServer` elects one client by writing its UserId to the `NpcConstants.BRAIN_OWNER_ATTRIBUTE` attribute (random pick, spreading many NPCs across clients) and re-elects on PlayerAdded/PlayerRemoving. `NPCClient:Start()` watches that attribute and boots/tears down the machine in a **brain-scoped maid** (`self._maid._brain`) holding the controllers and the machine, so a handoff cleans everything without touching the equip/watch connections. Trust level is the same as the rest of combat: the owning client is authoritative over the NPC's shots (see `npcChar` routing below).

### Network ownership MUST follow the elected brain (or the NPC never moves)

The brain runs on the owner client, and `MovementController:_moveToWaypoint` drives the rig with `Humanoid:MoveTo`. A client-issued `MoveTo` is **only simulated if that client owns the rig's assembly** — otherwise the server keeps simulating the NPC standing still, replicates that back, and the rig never moves. The tell is precise: `Humanoid.MoveToFinished` never fires on the client, so the move always falls through to `MovementController`'s 1s `WAYPOINT_TIMEOUT` and the NPC sits at the same point. This is **not** a `HipHeight`/pathfinding/geometry bug — it's an authority bug.

Fix lives in `NPCServer._setNetworkOwner(player?)`, called from `_electBrainOwner` at every election point (`Start` + PlayerAdded/Removing): `HumanoidRootPart:SetNetworkOwner(elected)` when an owner exists, `SetNetworkOwner(nil)` (revert to server) when there are no candidates. It guards against an anchored/despawning HRP (early-returns on `Anchored`, `pcall`s the call). **Requires every assembly part to be unanchored** — an anchored HRP silently keeps the standstill.

Why this is the *right* model for MMO scale, not a perf/replication compromise:

- **Code-folder location ≠ execution location.** A module under `src/shared/StateMachine` (or `nevermore/binder/src/Shared`) runs on whichever side `require`s it; there is no "shared, replicated" execution context. Moving the machine into a `Shared` folder does **not** grant replication — you still pick a machine to run it on, and network ownership is what determines `Humanoid` replication.
- **Network ownership IS the perf + replication win.** Owner client simulates the Humanoid → replicates to the server (which does *not* simulate it) → server relays to all other clients. So you get the "no server humanoid simulation" perf benefit **and** full replication to everyone at once. Animator animations also replicate from the owner, which is what makes the client-side `AnimationHandler` playback visible to other players. (The "client changes don't replicate to the server" docs caveat is about *generic property writes*, not network-owned physics — that's the one channel the engine *does* replicate back through the server.)
- **The real MMO tradeoff is trust + load**, not replication: the owner is authoritative over that NPC's movement/shots (shots are already validated server-side via `npcChar` `HasTag` + server-applied damage), and concentrating many NPCs on one laggy client hurts everyone (mitigated by the random election spreading ownership). Full server authority is the only alternative, and it costs server-side humanoid simulation — you can't dodge that tradeoff by relocating code.

### How the NPC reuses the player combat pipeline

- **`getCharacterActor` (abilities/src/Shared/utils)**: the whole hit pipeline (`castRays`, `canPlayerDamageHumanoid`, `validateTag`, `findAimAssistTarget`) only reads `.Character`, `.Team`, `.Neutral` (+ `.UserId` for attack IDs) off a Player. This util returns the real Player for player characters, else a cached fake-player table `{ Character = char, Neutral = true, UserId = char.Name }`. Server `RangeAttack` uses it instead of `GetPlayerFromCharacter`.
- **`RangeAttackClient`** gained `self._isLocalOwner` (`self.player == Players.LocalPlayer`): when false, every input/recoil/camera-handler/continuous-fire wire-up is skipped — the ability is execute-only. `SetCustomCamera(camera)` lets `_shot` read aim from a supplied Camera instead of `workspace.CurrentCamera`.
- **Unparented `Instance.new("Camera")` as CFrame holder**: both `TargetController` (vision eye for `findAimAssistTarget`, which takes a Camera) and `AttackController` (shooting eye for `SetCustomCamera`) use one. It's just a world-space CFrame container; never parented.
- **`AttckInvoker` `npcChar` routing**: the brain-owner client's Swing payload carries `npcChar = self.character` when there is no real player. The server only honors it if `CollectionService:HasTag(npcChar, Constants.NPC_TAG)` — otherwise a client could execute arbitrary characters' weapons.
- **`findAimAssistTarget`** gained an optional `filter(character) -> boolean` 5th param; `TargetController` passes "is a real player character" so NPCs never hunt each other (the candidate pool is everything tagged Armed, which now includes NPCs).

### State machine specifics (src/shared/StateMachine)

- `StateMachine.new(initial, StateMachine:LoadDirectory(folder), ctx)` **deep-copies the states, NOT the data table** — `self.Data = initialData` is by reference, so live controller instances in the ctx are safe.
- Transitions' `OnDataChanged(data)` runs **every Heartbeat** for the current state. Anything expensive a transition polls (the vision scan) must throttle *inside the controller* (`TargetController.Scan` gates on `VISION_SCAN_INTERVAL`), not in the transition.
- Only the **current** state's `OnHeartbeat` runs, so the shared clock is `data.timer += deltaTime` in *every* state's heartbeat.
- **Resumability lives in controllers, not states**: states are stateless dispatchers. The patrol goal survives an Attacking detour because `GoalController:EnsureGoal()` keeps a non-reached goal; only a reached/removed goal is re-rolled. Same idea as the Armed context/strategy split — long-lived domain objects, thin behavior on top.

### Lessons learned building this (general, will bite again)

- **ServiceRoot connection ordering differs per side**: the client registers `GetClassAddedSignal` connections **before** `serviceBag:Start()` (catches everything), the server registers them **after** — so classes bound *during* Start (pre-placed tagged rigs) never fire the server connections. Fix: a `binder:GetAll()` sweep after connecting, and make the methods the sweep calls **re-entry-guarded** (set the `_initialized`/`_started` flag at the top, since the signal and the sweep can overlap).
- **`_G.ServiceBag` is nil during server `serviceBag:Start()`** (set only after Start returns). Anything that runs during binding — like NPCServer's equip — must receive binders/services explicitly (the `characterCtxUtils:InitChar*(…, binder)` third param exists for this) instead of relying on the `_G` fallback.
- **Binder ctor signatures differ per side** (an accident of how each ServiceRoot wires `Binder.new`): server classes get `(inst, serviceBag, binderProvider)`, client classes get `(inst, serviceBag)`. Check the ServiceRoot before assuming.
- **Server AnimationHandler auto-`Init` also misses Start-time binds** (same ordering gap), so a consumer can't assume `animHandler._initialized` — check it and call `animHandler:Init(humanoid)` yourself.
- **Guns work without an AnimationHandler; melee doesn't.** Server `Weapon.new`'s anim lookup and `BaseAbility.new`'s anim binder access are nil-safe, and the gun m1 ships `animNames = {}`. Fist (melee) animations are required.
- **Don't `setmetatable(self, nil)` in `Destroy` when async callbacks can still land**: `MovementController:Destroy` rejects the in-flight move promise, whose `:Catch` calls `self:Stop()` possibly a tick later — stripping the metatable turns that into a method-not-found error.
- **Maid layering**: binder maid owns controllers; a controller that runs multi-frame work (MovementController) needs its *own* private maids (move scratch + per-waypoint race) cleaned per-operation. Never clean a binder-level maid from inside an operation — it tears down sibling controllers mid-move.
- **`Humanoid:MoveTo` has an 8s built-in timeout** — far too slow to notice a stuck combat NPC. Race `MoveToFinished` against your own `task.delay` (1s here) and recover (ballistic jump to the waypoint with `v0 = (p1 - p0 - 0.5*g*T²)/T`).
- **Free-standing `.server.luau` Scripts must not require (even transitively) any Quenty module**: Quenty modules start with `require(script.Parent.loader)`, and those `loader` links only exist after ServiceRoot's `bootstrapGame` — sibling Scripts schedule in arbitrary order, so the require races it (`loader is not a valid member` at boot, e.g. MatchListener → GameModeService → EffectService → Ragdoll). ServiceRoot is the **only** server entry point: new top-level server logic becomes a ServiceBag service it registers (MatchListener is the precedent).

### Key files

- `src/myNeverMoreS/npc/src/Shared/NpcConstants.luau`: all tuning (goal-reached distance, idle dwell, vision range/FOV/scan interval, loss grace, `BRAIN_OWNER_ATTRIBUTE`). Goal parts are tagged `Constants.NPC_GOALS_TAG` ("NPC_goals").
- `src/myNeverMoreS/npc/src/Client/Controllers/`: `GoalController` (goal pick + Promise-wrapped `ComputeAsync`), `MovementController` (waypoint chain, stuck recovery, `LookTo` tween), `TargetController` (vision), `AttackController` (simulated camera + `Weapon:Execute(m1)`; the ability cooldown stays the real fire-rate gate — `GetShootInterval` only keeps Attacking from hammering Execute).
- `src/myNeverMoreS/npc/src/Client/States/` + `Transitions/`: thin; behavior changes belong in controllers or NpcConstants.

## Animation
### Module + stub split
- `src/client/UI/Animate.luau` — the **real logic**, a ModuleScript that returns `function(animationHandler, character)`. It wraps all the original Animate state (pose machine, connections, the `wait(0.1)` move loop) in one per-character closure. ServiceRoot requires it once and `task.spawn`s it per character.
- `src/client/Character/Animate/init.client.luau` — an **empty LocalScript stub** in StarterCharacterScripts. Its only jobs: (1) exist so Roblox doesn't insert its built-in Animate (engine skips the default when a script named `Animate` is already present), and (2) host the `PlayEmote` BindableFunction child so external emote invokers still reach `character.Animate.PlayEmote`.


### Gotchas

- **`Idle` key collision (resolved in v_07)**: `OtherAnims.Idle` and the weapon `Idle` in `WeaponsAnims` (fist) share a key. The default is now *protected* — `registryAnims` skips any name already in `_defaultNames`, so the OtherAnims idle always wins and the weapon's own `Idle` entry is silently ignored on equip. If a weapon genuinely needs its own idle, give it a different key (e.g. lowercase `idle`) so it isn't shadowed by the protected default.
- **No fade transitions**: the handler's `LoadAnimation` has no transition-time param, so `transitionTime` is ignored and pose blends are instant. (Walk speed-scaling still works because `OtherAnims.Walk` keeps the exact `http://...id=180426354` url that `onRunning` checks against.)
- **`AddAnimations(OtherAnims)` at spawn**: the module calls this on init so the poses resolve before the first weapon equip (the handler starts empty). This is now the **only** place OtherAnims is registered (`InitCharAnim` no longer re-adds it), and these names become the protected defaults. A spawn-race where the first equip beats this call is self-correcting: `AddAnimations` clears any stale weapon descriptor when the id differs, and `registryAnims`' leftover-drop loop also skips `_defaultNames`.


## Camera Handling

Camera flows through Quenty's `CameraStackService`. Several non-obvious things matter when writing or reading camera code; read this section before touching `src/client/UI/cameraHandlers/`.

### The stack is "sample the top," not a composition pipeline

`CameraStackService:Start` (`node_modules/@quenty/camera/src/Client/CameraStackService.lua:67-77`) binds at `Enum.RenderPriority.Camera.Value + 75` and each frame does:

```lua
local state = self:GetTopState()
state:Set(Workspace.CurrentCamera)
```

Only the topmost effect is sampled. Effects below the top are dormant — they contribute nothing unless the topmost effect explicitly reads them through a `_getBaseState`-style closure it was constructed with. The "stack" is a list of candidates; composition is built **by your constructor code**, not by stack position.

Consequence: if you `:Add(newEffect)` expecting it to layer on top of what's already there, it won't. It replaces the previous top as the candidate. To compose, sum effects together (see below) or wire one's `_getBaseState` to read another.

### Two flavors of CameraEffect: absolute vs delta

- **Absolute** effects produce a full world-space `CameraState` with a real CFrame. They typically need a `_getBaseState` callback to know what to build on top of (`result.CFrame = base.CFrame * mine`), or they build from scratch like `DefaultCamera` reading `CameraSubject`.
- **Delta** effects produce only their contribution — usually a `CFrame.Angles(...)` rotation or a small translation. No `_getBaseState`. They return identity-ish CFrames when idle. `ImpulseCamera` is the canonical example: its `__index "CameraState"` returns `CFrame.Angles(...)` only, never a base position.

Compose them with `SummedCamera`:

```lua
local combo = SummedCamera.new(absoluteEffect, deltaEffect):SetMode("Relative")
-- result.CFrame = absoluteEffect.CFrame * deltaEffect.CFrame  (delta applied in local space)
```

`"World"` mode is unimplemented and errors. Always `:SetMode("Relative")`.

CameraStateService's built-in base entry is `(rawDefaultCamera + impulseCamera):SetMode("Relative")` (`CameraStackService.lua:57`) — exactly this pattern. `SummedCamera` accepts raw `CameraState` values too: it reads `self._cameraA.CameraState or self._cameraA`, so passing a bare `CameraState` (a value object) works as the absolute side. Useful when the subclass keeps a mutable `CameraState` and you want it to feed into the combo live.

### The `__add` Relative-mode trap (3+ effects)

`(a + b + c):SetMode("Relative")` fails. The first `+` calls the LHS effect's `__add`, which for custom effects usually does `return SummedCamera.new(self, other)` *without* `:SetMode`. The inner SummedCamera stays in default `"World"` mode. The outer `:SetMode("Relative")` only sets the outermost; when reads chain inward, the inner SummedCamera errors with `"not implemented"`.

Fix once, in every custom CameraEffect you write:

```lua
function MyEffect.__add(self, other)
    return SummedCamera.new(self, other):SetMode("Relative")
end
```

Then `a + b + c` propagates Relative mode through the whole chain. (Workaround at the call site: `((a + b):SetMode("Relative") + c):SetMode("Relative")`.)

### This project's CameraHandler design (persistent mediator + mode strategies)

The persistent camera handler is `CameraMediator` (which inherits `CameraHandlerBase`). It owns the shared `_cameraState`, the effects (`_recoilCamera`, `_lerpCamera`), and their combos for the lifetime of the session, and it is what `_G.CurrentCameraHandler` points at. The per-mode classes (`FirstPerson`, `ThirdPerson`) are thin strategies that only own a render step writing into the mediator's `_cameraState` — they no longer inherit from `CameraHandlerBase` nor call `_initEffects`. This split is what lets an in-flight lerp or recoil **survive a FirstPerson ↔ ThirdPerson toggle**: only the strategy is destroyed/reconstructed on toggle, while the effect instances (and their internal timers/springs) keep running.

`CameraHandlerBase:_initEffects(cameraStackService, cameraState)` wires (called once, by the mediator in `:Start`):

- `_recoilCamera = RecoilCamera.new()` — pure rotation delta (`CFrame.Angles(deltaPitch, deltaYaw, 0)`) backed by a single `Spring<Vector3>` whose `Target.X` is cumulative yaw and `Target.Y` is cumulative pitch (both in radians). The effect tracks its own `_appliedPitch` / `_appliedYaw` so each frame's emission is `(spring.Position - applied)` — a *delta vs. last frame*, not the absolute position. This is what makes `:Reset()` cleanly invertible: `Reset()` only sets `spring.Target = Vector3.zero`, and the spring's natural decay then emits negative deltas summing to exactly `-_applied`, returning workspace.CurrentCamera's rotation to where the player's mouse alone would have put it. The player's manual rotation never flows through this effect, so the wind-back is safe regardless of whether the player aimed during the burst. No `_getBaseState`.
- `_lerpCamera = LerpCamera.new()` — **rotation-only delta**. `:StartLerp(goal, dur)` strips translation from `goal` (only `goal - goal.Position` is kept) and from the current camera at start time; each frame it returns `inv(currentRotation) * targetRotation` so that the composed `cameraState * delta` rotates toward target while **position keeps coming from the live `_cameraState`**. This is why the lerp goal stays valid across FP↔TP: per-mode camera geometry only affects position, not aim. **Currently unused at runtime** — `_restoreRecoil` was switched to `:resetRecoil()` once RecoilCamera became invertible, since the lerp existed only to undo the recoil's accumulated pitch. The file, `CameraHandlerBase:LerpCamera` / `:StopLerpCamera`, and the recoil/lerp swap helpers are intentionally kept around so the path can be brought back without redesign.
- `_recoilCombo = SummedCamera.new(cameraState, _recoilCamera):SetMode("Relative")` — sits as the default stack top. When recoil is idle the delta is identity, so the combo visually equals `_cameraState`.
- `_lerpCombo = SummedCamera.new(cameraState, _lerpCamera):SetMode("Relative")` — built up-front but only attached to the stack while actively lerping. `swapToLerp()` removes the recoil combo and adds the lerp combo; `swapToRecoil()` reverses it (on lerp completion or `:StopLerpCamera`).

Recoil and lerp are **mutually exclusive in time** (only one combo is on the stack at once): shot fires → `RangeAttackClient._shot` calls `:StopLerpCamera` then `:recoil`; mouse moves → `InputChanged` (MouseMovement branch only) calls `:StopLerpCamera`. The swap helpers are idempotent so repeated calls are safe — which is why those `StopLerpCamera` calls are harmless no-ops while `LerpCamera` is currently unused.

**Recoil restore path** (the actual flow today): each shot's first frame snapshots `workspace.CurrentCamera.CFrame` into `_recoilRestoreCFrame` (kept for the LerpCamera-based future restore but no longer read), and the recoil cooldown's `Done` signal calls `_restoreRecoil` → `cameraHandler:resetRecoil()` → `RecoilCamera:Reset()`. The recoiler then winds its own pitch/yaw back to zero via the mechanism described above; the player's manual rotation is untouched, so the `_playerMoved` gate that used to guard the lerp call is no longer needed (the flag/connections are kept so a future return to LerpCamera doesn't need to re-add them). Note that the recoil values in `CombatConfig` (`recoilMin` / `recoilMax` / `recoilRise`) are still calibrated against the pre-refactor behavior, where the per-frame `_recoil.Y * dt` decay applied roughly 1/10 of the input as cumulative kick and `riseY` was buggily added every frame — so the same numbers will feel ~10× stronger now (and `recoilRise` will dominate). Retune downward when you touch those weapons.

Mode strategies (`ThirdPerson.luau`, `FirstPerson.luau`) take the mediator's `_cameraState` as a constructor arg, hold an own `Maid`, and bind a render step at `Enum.RenderPriority.Camera.Value` (200) that writes `CameraSubject` position + per-mode offset into that shared state. `CameraMediator:_isFirstPerson:Observe()` swaps `self._activeMode`: on each emission it `:Destroy()`s the old strategy (unbinding its render step) and constructs the new one against the same `_cameraState`. The effect combos are untouched.

### Rotation accumulates, position doesn't — by feedback loop

In `ThirdPerson.luau`'s render step: `local baseCFrame = currentCamera.CFrame; local rotationOnly = baseCFrame - baseCFrame.Position; local desired = CFrame.new(subjectPosition + offset) * rotationOnly`. Rotation is **read back from workspace.CurrentCamera**, so any per-frame rotation delta the stack wrote last frame is carried forward — that's how recoil pitch compounds across frames during a burst.

Position is recomputed from `CameraSubject` every frame and **not** read back from workspace. So position-based effects (a cumulative Y rise from sustained fire, for instance) cannot compound through the mode strategy's render step — they must maintain their own accumulator inside the CameraEffect. `RecoilCamera` does this with one spring whose Target carries cumulative yaw (`X`) and pitch (`Y`) in radians: `:Recoil(amount, rise)` adds `Vector3.new(amount.X, amount.Y + math.rad(rise or 0), 0)` to the target; `:Reset()` zeros the target. Crucially the effect emits **per-frame deltas** (`spring.Position - _applied`) rather than the absolute spring position, which keeps the spring from re-integrating itself through the workspace-rotation feedback loop. (The previous implementation added `math.rad(spring.Position.Y)` as a delta every frame, which is what made sustained-fire pitch blow up.)

### Service-lifecycle gotcha

`serviceBag:GetService(CameraStackService)` during a service's `:Init` returns a half-built proxy whose `:Start` hasn't run — the RenderStepped binding doesn't exist yet, so any effects you push during `:Init` are pushed onto a stack nothing samples. Always grab `CameraStackService` (and any service whose behavior you intend to use) in `:Start`, not `:Init`. See `SKILLS.md` §5 for the full pattern.

### Avoid post-multiplying `workspace.CurrentCamera.CFrame` in your own render step

It's tempting to `BindToRenderStep(..., Camera+75, fn)` after `CameraStackService.Start` and post-multiply the camera CFrame (same-priority bindings run in registration order, so your callback runs after the stack's write). It works — but it bypasses the stack abstraction, can't be reasoned about from inside camera effects, and produces "where did this offset come from" mysteries. Compose via effects instead; only reach for the bound render-step pattern when an effect genuinely cannot express what you need.

### Key files

- `src/client/UI/cameraHandlers/camerasStates/CameraMediator.luau`: persistent handler. Owns `_cameraState` and the effects; swaps `_activeMode` (FirstPerson/ThirdPerson strategy) on toggle. `_G.CurrentCameraHandler` points at it.
- `src/client/UI/cameraHandlers/camerasStates/CameraHandlerBase.luau`: `_initEffects` + lerp/recoil compose/swap orchestration. Inherited by the mediator; no longer inherited by mode strategies.
- `src/client/UI/cameraHandlers/camerasStates/ThirdPerson.luau` / `FirstPerson.luau`: mode strategies. Receive the mediator's `_cameraState`, bind a render step writing per-mode CFrame into it, and `:Destroy` to unbind. No effects, no combos.
- `src/client/UI/cameraHandlers/cameraEffects/RecoilCamera.luau`: rotation delta. One spring carries cumulative (yaw, pitch) in radians; effect tracks `_applied*` and emits per-frame `(spring.Position - applied)` deltas so `:Reset()` (target → 0) winds its own contribution back to zero without disturbing player aim.
- `src/client/UI/cameraHandlers/cameraEffects/LerpCamera.luau`: rotation-only delta used to restore camera aim after a recoil burst. Goal is stripped of translation so it survives FP↔TP mode swaps. **Currently unused at runtime** (recoil restore now uses `RecoilCamera:Reset` directly); kept for potential future use.
- `node_modules/@quenty/camera/src/Client/CameraStackService.lua`: the stack itself. Read `Init` and `Start`.
- `node_modules/@quenty/camera/src/Client/Effects/SummedCamera.lua`: `Relative` vs `World` modes, `__add` chaining.
- `node_modules/@quenty/camera/src/Client/Effects/ImpulseCamera.lua`: canonical delta-effect example.


## Development Workflow
- **Setup**: `npm install` for Quenty deps, then `rojo serve` to sync with Roblox Studio
- **Testing**: Playtest in Studio; no automated tests — use prints for debugging
- **Building**: `rojo build` to generate rbxlx/rbxm files
- **Debugging**: Add `print()` statements; check attributes/events in Studio explorer
- **Type/format checks**: not runnable in this environment (no stylua/luau-lsp, no
  npm scripts) — see **Tooling & Commands** below. Don't claim a lint passed when
  the toolchain isn't installed; say what you actually ran (`rojo sourcemap`) instead.

## Conventions
- **Modules**: Require via `local module = require(path)`; use `export type` for Luau types and create a different file for types often called as `serviceTypes`
- **Events**: Define in `RS.RemoteEvents/` as model.json; Listen to this events in `serviceMediator` or main entry point (`ServiceRoot`)
- **UI**: Use Roact components in `client/UI/`; mount to PlayerGui
- **File Naming**: `.luau` for module scripts, `.rbxmx` for models
- **Assert constant-keyed lookups**: whenever you fetch a tag, attribute, child, or binder **by a value from a constants module** (`Constanst.luau`, `GameModeConstants`, `NpcConstants`, …) and the thing it names is supposed to be there by construction — a binder registered in a `Binders` table, an attribute the server always seeds, a child the rig always ships — `assert` the result is non-nil with a message naming the constant. A nil there is a wiring bug (typo'd constant, missing registration), not a runtime state, so it must fail loud at the lookup instead of NPE-ing three frames later in an unrelated method. The message should quote the tag/key so the failure points straight at the missing registration, e.g. `assert(binder, \`ServiceRoot: no binder registered for tag "{Constants.ARMED_TAG}"\`)`. **Do NOT assert things that legitimately may be absent** — a Tool the player hasn't equipped, a map-authored part an artist may not have placed (CTF tolerates an unflagged map with a `warn`, not an `assert`), an attribute that is genuinely optional. Reserve `assert` for "this is always wired; if it isn't, the build is broken" (matches the style guide's *throw only to validate correct usage*); use an early-return guard or `warn` for "this might not be here yet / might be off."

## Key Files
- `src/server/ServiceRoot.server.luau`: Service initialization, player setup
- `src/client/UI/ServiceRoot.client.luau`: Client initialization
- `src/server/Combat/CombatMediator.luau`: Combat event handling
- `src/client/UI/App.luau`: Main UI mounting
- `src/myNeverMoreS/weapon/src/Shared/CombatConfig.luau`: Data used to call ability:Execute, important for creating new weapons
- `src/myNeverMoreS/abilities/src/Server/Abilities/AttackBaseAbility.luau` and `/src/myNeverMoreS/abilities/src/Client/Abilities/AttackBaseClient.luau`: melee + AOE attacks (`type = "Attack"`) — see **Attack Abilities (melee ST & AOE)**
- `src/myNeverMoreS/abilities/src/Server/Abilities/RangeAttack.luau` and `/src/myNeverMoreS/abilities/src/Client/Abilities/RangeAttackClient.luau`: ranged attacks (`type = "Range"`, guns)
- `src/myNeverMoreS/abilities/src/Client/Utils/TrajectoryAimer.luau`: client kinematic aim preview, driven by the grenade's `onEquipCBClient`

# Lua Style Guide Summary

## General
- All `require` calls must be at the top of the file.
Group `require` blocks in this order:
1. Common ancestor definition
2. Imported packages
3. Definitions derived from packages (can be broken down by subfolder)
4. Same-project modules (can be broken down by subfolder)

## Metatables
Used only for:
- **Prototype‑based classes** (with `__index` trick and explicit typing)
- **Guarding against typos** (e.g., enums that throw on missing keys)

## Classes
- Dot syntax with explicit self: function MyClass.Method(self: MyClass). Required for strict typing.
- Private fields and methods use a leading underscore.
- Use :: any casts sparingly, only at boundaries (constructors, binder registration). Fix upstream types when you can.

## Functions
- Keep arguments small (1–2)

## Comments
- Block comments for file/function documentation
- Moonwave docstrings: --[=[ @class ClassName ]=] at the top of the method/file.

## Naming
- Spell out words fully
- `PascalCase` for classes/enums and Roblox APIs
- `camelCase` for locals, members, functions
- `LOUD_SNAKE_CASE` for local constants
- File name matches the object it exports

## Yielding
- Do not call yielding functions on the main task – use `coroutine.wrap`/`delay` or Promises

## Error Handling
- Throw only to validate correct usage, with `assert` when it MUST and close guard early return when it should

## General Roblox Best Practices
- All services via `game:GetService` at top of file
- Imported module variable name = module name

## Tooling & Commands

**Reality of this environment (verify before relying on a command):** the only
Luau/Roblox tool installed on PATH is **`rojo`**. There is **no** `stylua`,
`selene`, `luau-lsp`, or `luau-analyze` available, and the root `package.json`
has **no `scripts` block** and there is **no `tools/` directory**. So the
`npm run lint:* / build:sourcemap / format` commands and the `tools/nevermore-cli`
build referenced in older notes **do not run here** — don't promise a clean lint
you can't actually produce. Type-checking and formatting happen inside Roblox
Studio (or after you install the toolchain yourself).

What actually works from the repo root:

```shell
npm install                                            # pull the Quenty deps into node_modules/
rojo serve                                             # live-sync into Studio (primary dev loop)
rojo build                                             # produce an rbxlx/rbxm
rojo sourcemap default.project.json -o sourcemap.json  # regenerate the sourcemap
```

- `rojo sourcemap` validates the **project tree and require paths** (a new file
  showing up in the map confirms it's wired in) but it does **not** parse or
  type-check Luau — it won't catch a syntax or type error.
- Runtime verification is a **Studio playtest**; debug with `print()` and inspect
  attributes/events in the Studio explorer. There are no automated tests.
- If you genuinely need type/format gating, install `stylua` and
  `luau-lsp`/`luau-analyze` yourself (cargo/rokit) — they are not provisioned here.
