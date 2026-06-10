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
### Quests
- tres quests te garantiza subir 1 y medio
- cada kill te da una experience, si es doble kill, triple kill es más
[] pool the quests, hay una tabla con tittle, description and cb la cb puede usar distintas apis para checkear el su progreso
- quest diarias (cada 24 horas) y quests semanales (should make it long live in per server and store them in DS)
### distintos modos
- Deadmatch por equipos
- EL último en pie gana
- battle royale
### Battle pass 
[] subir de nivel te va dando recompensa
[] si sos jugador premium lo tenés desbloqueado
### Leveling
- Existen rangos para el jugador bronce plata oro platino diamante y MAESTRO (match making)
### Kill cam
- cambia la camara del player a quien lo asesino
- se muestra un cartelito 
- el cartelito es personalizable con las skins 
### HACER BOTS
NPCs que tienen un patrol y utilizan la misma api que aim asistant para saber a que player disparar, los bots tienen un binder en el client que simula llamar shot desde una camara donde el raycast da perfecto al player aunque en realidad no muevan la camara
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