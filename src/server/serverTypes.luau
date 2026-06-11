--[=[
	@class serverTypes
	Server-wide shared types.
]=]

export type PlayerBinder<handler> = {
	_players: { [number]: any },
	_handler: handler,
	new: (handler: handler) -> any,
	InitPlayer: (self: PlayerBinder<handler>, player: Player, ...any) -> (),
	GetHandler: (self: PlayerBinder<handler>, player: Player) -> handler,
	RemovePlayer: (self: PlayerBinder<handler>, player: Player) -> (),
}

return {}
