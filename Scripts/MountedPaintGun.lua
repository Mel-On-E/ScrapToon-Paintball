dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile("$CONTENT_DATA/Scripts/PaintGun.lua") --Paintball

MountedPaintGun = class(PaintGun)
MountedPaintGun.maxParentCount = 1
MountedPaintGun.maxChildCount = 0
MountedPaintGun.connectionInput = bit.bor( sm.interactable.connectionType.logic )
MountedPaintGun.connectionOutput = sm.interactable.connectionType.none
MountedPaintGun.colorNormal = sm.color.new( 0xcb0a00ff )
MountedPaintGun.colorHighlight = sm.color.new( 0xee0a00ff )
MountedPaintGun.poseWeightCount = 1

local FireDelay = 8 --ticks
local MinForce = 125.0
local MaxForce = 135.0
local SpreadDeg = 1.0
local Damage = 28/2


--[[ Server ]]

-- (Event) Called upon creation on server
function MountedPaintGun.server_onCreate( self )
	PaintGun.server_onCreate(self)

	self.sv.fireDelayProgress = 0
	self.sv.canFire = true
	self.sv.parentActive = false
end


-- (Event) Called upon game tick. (40 times a second)
function MountedPaintGun.server_onFixedUpdate( self, timeStep )
	if not self.sv.canFire then
		self.sv.fireDelayProgress = self.sv.fireDelayProgress + 1
		if self.sv.fireDelayProgress >= FireDelay then
			self.sv.fireDelayProgress = 0
			self.sv.canFire = true
		end
	end
	self:sv_tryFire()
	local logicInteractable = self.interactable:getSingleParent()
	if logicInteractable then
		self.sv.parentActive = logicInteractable:isActive()
	end

	PaintGun.server_onFixedUpdate(self, timeStep)
end

-- Attempt to fire a projectile
function MountedPaintGun.sv_tryFire( self )
	local logicInteractable = self.interactable:getSingleParent()
	local active = logicInteractable and logicInteractable:isActive() or false
	local freeFire = true

	if freeFire then
		if active and not self.sv.parentActive and self.sv.canFire then
			self:sv_fire()
		end
	end
end

function MountedPaintGun.sv_fire( self )
	self.sv.canFire = false
	local firePos = sm.vec3.new( 0.0, 0.0, 0.375 )
	local fireForce = math.random( MinForce, MaxForce )

	-- Add random spread
	local dir = sm.noise.gunSpread( self.shape.up, SpreadDeg )

	-- Fire projectile from the shape
	--sm.projectile.shapeProjectileAttack( projectile_potato, Damage, firePos, dir * fireForce, self.shape )
	self:sv_fire_ball({pos = self.shape.worldPosition, dir = dir * fireForce, color = self.shape.color, dmg = Damage})--PaintBall


	self.network:sendToClients( "cl_onShoot" )
end


--[[ Client ]]

-- (Event) Called upon creation on client
function MountedPaintGun.client_onCreate( self )
	PaintGun.cl_onCreate(self)

	self.cl.boltValue = 0.0
	self.cl.shootEffect = sm.effect.createEffect( "MountedPotatoRifle - Shoot", self.interactable )
end

-- (Event) Called upon every frame. (Same as fps)
function MountedPaintGun.client_onUpdate( self, dt )
	if self.cl.boltValue > 0.0 then
		self.cl.boltValue = self.cl.boltValue - dt * 10
	end
	if self.cl.boltValue ~= self.cl.prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl.boltValue ) --Clamping inside
		self.cl.prevBoltValue = self.cl.boltValue
	end

	PaintGun.cl_onUpdate(self, dt)
end

-- Called from server upon the gun shooting
function MountedPaintGun.cl_onShoot( self )
	self.cl.boltValue = 1.0
	self.cl.shootEffect:start()
	local impulse = sm.vec3.new( 0, 0, -1 ) * 500
	sm.physics.applyImpulse( self.shape, impulse )
end
