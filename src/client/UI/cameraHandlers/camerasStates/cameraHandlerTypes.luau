-- cameraHandlerTypes.luau

export type CameraHandlerBase = {
	SetCframe: (self: CameraHandlerBase, cf: CFrame?) -> (),
	GetCurrentCFrame: (self: CameraHandlerBase) -> CFrame,
	Destroy: (self: CameraHandlerBase) -> (),
}

export type ThirdPersonCamera = CameraHandlerBase & {
	_recoil: Vector2,
	_zoom: number,
	_hasToRecoil: boolean,
	recoil: (self: ThirdPersonCamera, recoilAmount: Vector2) -> (),
	_recoiling: (self: ThirdPersonCamera, dt: number, currentCFrame: CFrame) -> (),
}

return {}
