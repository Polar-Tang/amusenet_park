# A brief introduction to gun shit
gun shit is a name for a big project desinged to be gun/m1 shoter framework. The main focus about all this project is the mantebillity because its planned to be reusable work with an infrastructure that allows to be forked into any new shoter game. The usability is designed to resembles fortnite gameplay
# Copilot Instructions for Gun Shit Game
These are the instruction for /gun game, a framework base for all shooter games currently in developing
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
- **Service Access**: Use `_G.ServiceBag:GetService()` and `_G.BinderProvider:Get(tag):Get(object)` for global services/binders
- **Binders**: Tag objects with CollectionService tags like "Armed", "AnimationHandler"; bind behaviors via BinderProvider
- **Combat Flow**: "Armed" tag is used for weapon binder which strongly uses inheritance behaviour and allowing weapon strategies and abilities to be data-driven from `/src/myNeverMoreS/weapon/src/Shared/CombatConfig.luau`
- **Armed binder**: Weapon binder is a context for weapons, `src/myNeverMoreS/weapon`, every weapon it's a different strategy which inherits from src/MyNevermore/Binder/Weapon/WeaponBase and they can create they own abilities via `createAbilitiesFromKey()` using `skills` and `attacks` key from the ability
- **Abilities**: Every ability must be declared in `CombatConfig.<weaponName>.attacks` or `CombatConfig.<weaponName>.skills`. CombatConfig is the ability API: each table entry is the behavior definition for that ability, and the ability key fields are the methods that implement the unique logic for that entry. The generic classes in `src/myNeverMoreS/abilities` must stay thin and only dispatch the table methods, not own ability-specific behavior. Keep the design data-driven and reuse the same class for many tables.
- **Movement abilities**: `MovementAbilityClient` and `MovementAbility` are generic parent classes used by slide, dash, zip line, and future movement abilities. The movement-specific logic belongs in `CombatConfig` movement tables through fields like `get_anim_name`, `effect`, and `endFx`. Add explicit movement types in `src/myNeverMoreS/weapon/src/Server/types/weaponTypes.luau` and keep movement params typed instead of using `any` or `self :: any`. The same movement class should work for every movement table, while each table defines its own impulse, animation, direction, VFX, and cleanup behavior.
- **Armed name**: Every weapon uses a key string to lower case which indentify it for behaviour (`CombatConfig.luau`) and animations (`src/shared/Animations/WeaponsAnims.luau`) handled by the animation handler binder


## Development Workflow
- **Setup**: `npm install` for Quenty deps, `rojo init` if needed, `rojo serve` to sync with Roblox Studio
- **Testing**: Playtest in Studio; no automated tests - use prints for debugging
- **Building**: `rojo build` to generate rbxlx/rbxm files
- **Debugging**: Add `print()` statements; check attributes/events in Studio explorer

## Conventions
- **Modules**: Require via `local module = require(path)`; use `export type` for Luau types and create a different file for types often called as `serviceTypes`
- **Events**: Define in `RS.RemoteEvents/` as model.json; Listen to this events in `serviceMediator` or main entry point (`ServiceRoot`)
- **UI**: Use Roact components in `client/UI/`; mount to PlayerGui
- **File Naming**: `.luau` for module scripts, `.rbxmx` for models

## Key Files
- `src/server/ServiceRoot.server.luau`: Service initialization, player setup
- `src/client/UI/ServiceRoot.client.luau`: Client initialization
- `src/server/Combat/CombatMediator.luau`: Combat event handling
- `src/client/UI/App.luau`: Main UI mounting
- `src/myNeverMoreS/weapon/src/Shared/CombatConfig.luau`: Data used to call ability:Execute, important for creating new weapons
- `src/myNeverMoreS/abilities/src/Server/Abilities/RangeAttack.luau` and `/src/myNeverMoreS/abilities/src/Client/Abilities/RangeAttackClient.luau`: All attack abilities are used through this classes
