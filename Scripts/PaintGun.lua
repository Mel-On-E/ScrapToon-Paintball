dofile("$SURVIVAL_DATA/Scripts/game/survival_items.lua")

PaintGun = class()

local ballSize = sm.vec3.one()*0.25
local colors = {
	"#eeeeee", "#f5f071", "#cbf66f", "#68ff88", "#7eeded", "#4c6fe3", "#ae79f0", "#ee7bf0", "#f06767", "#eeaf5c",
	"#7f7f7f", "#e2db13", "#a0ea00", "#19e753", "#2ce6e6", "#0a3ee2", "#7514ed", "#cf11d2", "#d02525", "#df7f00",
	"#4a4a4a", "#817c00", "#577d07", "#0e8031", "#118787", "#0f2e91", "#500aa6", "#720a74", "#7c0000", "#673b00",
	"#222222", "#323000", "#375000", "#064023", "#0a4444", "#0a1d5a", "#35086c", "#520653", "#560202", "#472800"
}
local unpaintableParts = {sm.uuid.new("92587d7f-0d69-4e42-8936-d53cf26002bb")}
local unpaintableBlocks = {blk_glass, blk_glasstile, blk_armoredglass}
local swimSpeedFactor = 3
local paintSlowFactor = 1/3
local paintDamage = 2.5
local paintDamageTicks = 10

function PaintGun:server_onCreate()
	self.sv = {}
	self.sv.balls = {}
	g_sv_players = {}
	self.ballID = 2
end

function PaintGun:server_onFixedUpdate(timeStep)
    if self.tool then
        local owner = self.tool:getOwner()
		local char = owner:getCharacter()
		local climb = false
		
		if g_sv_players[owner.id] and g_sv_players[owner.id].equipped then
			local pos = char:getWorldPosition() - sm.vec3.new(0,0,char:getHeight())
			local valid, result = sm.physics.spherecast(pos + sm.vec3.new(0,0,0.25), pos + sm.vec3.new(0,0,1.1), 0.5, nil, sm.physics.filter.staticBody + sm.physics.filter.dynamicBody)
			
			local oldSpeed = g_sv_players[owner.id].speed
			local newSpeed = 1

			if valid then
				local shape = result:getShape()

				if shape.color == g_sv_players[owner.id].color then
					if char:isCrouching() then
						climb = true
						newSpeed = swimSpeedFactor
					end
				elseif sm.item.getShapeDefaultColor(shape.uuid) ~= shape.color then
					newSpeed = paintSlowFactor

					if g_sv_players[owner.id].paintDamageCooldown + paintDamageTicks < sm.game.getCurrentTick() then
						sm.event.sendToInteractable(g_gameManager.interactable, "sv_dmg", {id = owner.id, dmg = paintDamage, respawnColor = g_sv_players[owner.id].color})
						g_sv_players[owner.id].paintDamageCooldown = sm.game.getCurrentTick()
					end
				end
			end

			if newSpeed ~= oldSpeed then
				g_sv_players[owner.id].speed = newSpeed
				self.network:sendToClient(owner, "cl_set_speed", newSpeed)
			end
		end
		
		if climb then
			char:setClimbing(true)
		elseif char:isClimbing() then
			char:setClimbing(false)
		end
    end

	for id, ball in pairs(self.sv.balls) do
		local pos, dir = self:calculate_trajectory(ball.pos, ball.dir, timeStep)
		local valid, result = sm.physics.raycast(ball.pos, pos)
		ball.pos = pos
		ball.dir = dir

		if valid then
			local effectParams = {
				Size = 0.08, Velocity_max_50 = 50.0, Material = 2, Color = ball.color
			} 
			sm.effect.playEffect("PaintBall", result.pointWorld, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), effectParams)
			self:sv_delete_ball(id)

            local char = result:getCharacter()
            if char then
                char:setColor(ball.color)

				if g_gameManager and char:isPlayer() then
					local player = char:getPlayer()
					if ball.color ~= g_sv_players[player.id].color then
						local attacker
						if ball.player then
							attacker = "#" .. string.sub(g_sv_players[ball.player.id].color:getHexStr(), 1, 6) .. ball.player.name
						end
						sm.event.sendToInteractable(g_gameManager.interactable, "sv_dmg", {id = player.id, dmg = ball.dmg, respawnColor = g_sv_players[player.id].color, attacker = attacker})
					end
				end
            end
			
			local blocksToPaint = {}
			for _, body in pairs(sm.physics.getSphereContacts(result.pointWorld, self.data.paintRadius).bodies) do	
				for _, shape in pairs(body:getShapes()) do
					if shape.color ~= ball.color then
						if not shape.isBlock then
							for _, uuid in ipairs(unpaintableParts) do
								if shape.uuid == uuid then
									goto nextShape
								end
							end

							--TODO get chance for painting pig parts
							local distance = (shape.worldPosition - result.pointWorld):length()
							if distance <= self.data.paintRadius + math.random()*self.data.paintRadius + math.random()*self.data.paintRadius + math.random()*self.data.paintRadius then
								shape:setColor(ball.color)
							end
							--TODO check if single block?
							--TODO avoid joints getting disconnected?
						else
							for _, uuid in ipairs(unpaintableBlocks) do
								if shape.uuid == uuid then
									goto nextShape
								end
							end

							local blockPos = shape:getClosestBlockLocalPosition(result.pointWorld)
							local distance = (blockPos/4 - result.pointLocal):length()
							if distance <= self.data.paintRadius*2 then
								blocksToPaint[#blocksToPaint+1] = {pos = blockPos, shape = shape, d = distance }
							end
						end
					end
					::nextShape::
				end
			end


			if #blocksToPaint > 0 then
				local foundBlocks = {}
				foundBlocks[#foundBlocks+1] = blocksToPaint[1].pos

				local painted = {}
				local ticks = 0

				while #blocksToPaint > 0 do
					ticks = ticks + 1
					local closestDistance = nil
					
					for _, block in pairs(blocksToPaint) do
						if not closestDistance or block.d < closestDistance then
							closestDistance = block.d
						end
					end

					if ticks > 1000 then
						break
					end

					for k, block in pairs(blocksToPaint) do
						for _, pos in pairs(painted) do
							if pos == block.pos then
								blocksToPaint[k] = nil
								goto next
							end
						end

						if block.d == closestDistance then
							local pointWorld = block.shape.body:transformPoint(block.pos/4)

							local blockSize = 0.25
							for x = -1, 2, 1 do
								for y = -1, 2, 1 do
									for z = -1, 2, 1 do
										local offset = sm.vec3.new(blockSize*x, blockSize*y, blockSize*z)
										local blockPos = block.shape:getClosestBlockLocalPosition(pointWorld + offset)
										if blockPos ~= block.pos then
											local distance = (blockPos/4 - result.pointLocal):length()
										 	if distance <= self.data.paintRadius*2 + math.random()*self.data.paintRadius + math.random()*self.data.paintRadius/2 then
												local found = false
												for _, pos in pairs(foundBlocks) do
													if pos == blockPos then
														found = true
													end
												end

												if not found then
													blocksToPaint[#blocksToPaint+1] = {pos = blockPos, shape = block.shape, d = distance}
													foundBlocks[#foundBlocks+1] = blockPos
												end
											end
										end
									end
								end
							end

							blocksToPaint[k] = nil

							if block.d <= self.data.paintRadius + math.random()*self.data.paintRadius + math.random()*self.data.paintRadius + math.random()*self.data.paintRadius then
								painted[#painted+1] = block.pos
								
								block.shape:destroyBlock(block.pos)
								local newShape = block.shape.body:createBlock(block.shape.uuid, sm.vec3.one(), block.pos, true)
								newShape:setColor(ball.color)
							end
						end
						::next::
					end
				end
				--print("DONE")
				--print(ticks)
			end
		end
	end
end


function PaintGun:sv_fire_ball(params, player)
	local color = params.color or g_sv_players[player.id].color
	self.sv.balls[self.ballID] = { player = player, pos = params.pos, dir = params.dir, color = color, id = self.ballID, dmg = params.dmg }
	self.network:sendToClients("cl_create_ball", {pos = params.pos, dir = params.dir, color = color, id = self.ballID})
	
	self.ballID = self.ballID + 1
end

function PaintGun:sv_delete_ball(id)
	self.sv.balls[id] = nil
	self.network:sendToClients("cl_delete_ball", id)
end

function PaintGun:sv_player_joined(params, player)
	g_sv_players[player.id] = {
		color = sm.color.new(string.sub(params.color, 1) .. "ff"),
		player = player,
		speed = 1,
		paintDamageCooldown = sm.game.getCurrentTick()
	}
	self.network:sendToClients("cl_set_name_tags", g_sv_players)
end

function PaintGun:sv_set_color(color, player)
	g_sv_players[player.id].color = sm.color.new(string.sub(color, 1) .. "ff")
	self.network:sendToClients("cl_set_name_tags", g_sv_players)
end

function PaintGun:sv_equip(status, player)
	g_sv_players[player.id].equipped = status
end

function PaintGun:cl_onCreate()
	self.cl = {}
	self.cl.balls = {}
	if not g_cl_PaintGun then
		g_cl_PaintGun = self
		g_cl_PaintGun.color = "#eeeeee"
		g_cl_PaintGun.speed = 1
	end
	self.network:sendToServer("sv_player_joined", {color = g_cl_PaintGun.color})
end

function PaintGun:cl_onUpdate(dt)
	for id, ball in pairs(self.cl.balls) do
		local pos, dir = self:calculate_trajectory(ball.pos, ball.dir, dt)
		ball.effect:setPosition(pos)
		ball.pos = pos
		ball.dir = dir
	end

	if self == g_cl_PaintGun then
		sm.localPlayer.getPlayer().character.movementSpeedFraction = g_cl_PaintGun.speed
	end
end

function PaintGun:cl_create_ball(params)
	local ballEffect = sm.effect.createEffect("ShapeRenderable")
	ballEffect:setParameter("uuid", sm.uuid.new( "36335664-6e61-4d44-9876-54f9660a8565" ))
	ballEffect:setParameter("color", params.color)
	ballEffect:setScale(ballSize)
	ballEffect:start()

	self.cl.balls[params.id] = {effect = ballEffect, pos = params.pos, dir = params.dir, id = params.id}
end

function PaintGun:cl_delete_ball(id)
	if self.cl.balls[id] then
		self.cl.balls[id].effect:destroy()
		self.cl.balls[id] = nil
	end
end

function PaintGun:client_onToggle()
	if not self.gui then
		self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/PaintGun.layout")
		for i=0, 40 do
			self.gui:setButtonCallback("ColorButton" .. tostring(i), "cl_onColorButton")
		end
	end
	self.gui:open()
	return false
end

function PaintGun:cl_onColorButton(name)
	local index = tonumber(string.sub(name, 12))
	g_cl_PaintGun.color = colors[index+1]
	self.gui:close()
	sm.gui.displayAlertText(g_cl_PaintGun.color .. "New Color")
	if self.tool then
		self.network:sendToServer("sv_set_color", g_cl_PaintGun.color)
	end
end

function PaintGun:cl_set_name_tags(players)
	for id, player in pairs(players) do
		local color = "#" .. string.sub(player.color:getHexStr(), 1, 6)
		local name = ""
		local char = player.player:getCharacter()
		if (not g_cl_gameManager or color == g_cl_PaintGun.color) and not char:isDowned() and sm.localPlayer.getPlayer() ~= player.player then
			name = color .. player.player.name
		end
		char:setNameTag(name)
	end
end

function PaintGun:cl_set_speed(newSpeed)
	g_cl_PaintGun.speed = newSpeed
end





function PaintGun:calculate_trajectory(pos, dir, dt)
	dir = (dir:normalize() - sm.vec3.new(0,0,1)*dt*0.1):normalize() * dir:length()
	pos = pos + dir*dt*0.5
	return pos, dir
end