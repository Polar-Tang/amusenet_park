### Idle anim problem
Las animaciones de idle hacen que el character se mueva, hay varios procesos que hacen que el crosshair del arma quede en el centro de la cámara, pero el character se mueve todo el tiempo de arriba a bajo por la animación idle. 
soluciones
- ~Crear un cameraSubject, la camera se mueve junto con el player~ (mala idea porque tendría el mismo efecto que un cirujano con parkinson)
- usar otra animación para idle que no mueva el character en ningún eje


# Arlong Park
(lógica específica del juego)



### Quests
- tres quests te garantiza subir 1 y medio
- cada kill te da una experience, si es doble kill, triple kill es más
[] pool the quests, hay una tabla con tittle, description and cb la cb puede usar distintas apis para checkear el su progreso
- quest diarias (cada 24 horas) y quests semanales (should make it long live in per server and store them in DS)
- Adding new quest to test, also create a component in src/client/UI/RoactUI that connects to QuestProgressRemote and share the quests list and update with its progession. If each quests require a different text you can consider move the quests pool to replicated storage so client and server can read it. 

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


### distintos modos
Define an architecture for using the same source file and different game mods
King of the Hill (koht)
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

###  para pensar
Base mode has a win method, when its called it should teleport back to the server, how could we do that?

### Id for ban player in for a detected exploit
There's an exploit found in the bots when we set networkownership to client. I will not remove the exploit but i got an id: Add a registry ban system, it's a custom nevermore service that writes a player user id in a cloud storage. 
Note: i'm not sure if i should write it to datastorage service because i don't know how to query it later for do the ban, maybe we should kick the player instantly but i don't know how to leave a registry for its ban or ban him instantly
We asume a player is cheating by counting the npc shots, if he's not shooting in the cooldown interal it should we get the player owner and asume it's cheating.
What do you think?

### Adding a player to active games
-> implementation plan: TODO_midjoin.md (this repo, shooter side) + amusenet_lobby/TODO_midjoin.md (lobby side)
How could we consider active server with a game already running? The game modes in shooter have:
```
matchMaid:GiveTask(Players.PlayerAdded:Connect(onPlayerAdded))
```
How we could consider the servers that are running a game mode? 
note: we shouldn't consider game modes as LastManStanding, even we can increase its time fro finding a match later

### Keep the lobby connected
The data sent from the lobby to the shooter has this shape:
```
{
			matchId = HttpService:GenerateGUID(false),
			accessCode = accessCode,
			userIds = userIds,
			botCount = botCount,
			mode = mode,
		})
```
Are utilizing each field? we use it in fill MatchListener, please make this shape a type

### Keep game modes in shooter
### Last man standing
Okay, i removed 
if GameModeService:ShouldEquipDefaultWeapon() then
				characterCtxUtils:EquipDefaultWeapon(char)
			end
because default weapon will be always a desired thing. What i meant to "no start with weapons" it's actually a backpack seeding

### Making a car framework
I never complete this Car framework, i've got all the binders done but i get problems in creating other Cars, i were working in a class to do match <CAR WORKING> setting, if it have the same constraints and the same attachment properties i asume it would work. How could we set up <CART> in order to work with the vinder? (<Cart working> already does ).
Use the mcp connection and find out the needed configuration to properly match <CAR WORKING>, then finnish <SET UP CLASS> in order to make them work.
Note: <SET UP CLASS> needs to run in the command bar, if it's done in runtime the phisics constraints will cause some parts to fly away

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

We are loading from lobby some payload for teleport data:
type MatchPayload = {
	matchId: string,
	botCount: number,
	mode: string,
	questsByUserId: { [string]: questTypes.QuestsSaveData },
}


### Adding a time out 


### Check if 
we are including the member team into the  exlude list of the ray cast