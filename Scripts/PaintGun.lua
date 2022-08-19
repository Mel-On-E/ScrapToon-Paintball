dofile("$SURVIVAL_DATA/Scripts/game/survival_items.lua")

PaintGun = class()

local ballSize = sm.vec3.one() * 0.25
local colors = {
	"#eeeeee",
	"#f5f071",
	"#cbf66f",
	"#68ff88",
	"#7eeded",
	"#4c6fe3",
	"#ae79f0",
	"#ee7bf0",
	"#f06767",
	"#eeaf5c",
	"#7f7f7f",
	"#e2db13",
	"#a0ea00",
	"#19e753",
	"#2ce6e6",
	"#0a3ee2",
	"#7514ed",
	"#cf11d2",
	"#d02525",
	"#df7f00",
	"#4a4a4a",
	"#817c00",
	"#577d07",
	"#0e8031",
	"#118787",
	"#0f2e91",
	"#500aa6",
	"#720a74",
	"#7c0000",
	"#673b00",
	"#222222",
	"#323000",
	"#375000",
	"#064023",
	"#0a4444",
	"#0a1d5a",
	"#35086c",
	"#520653",
	"#560202",
	"#472800"
}
local effect_positions = {
	sm.vec3.new(0, 0, 0.1),
	sm.vec3.new(0, 0.25, 0.1),
	sm.vec3.new(0.25, 0, 0.1),
	sm.vec3.new(0.25, 0.25, 0.1),
	sm.vec3.new(0, -0.25, 0.1),
	sm.vec3.new(-0.25, 0, 0.1),
	sm.vec3.new(-0.25, -0.25, 0.1),
	sm.vec3.new(0.25, -0.25, 0.1),
	sm.vec3.new(-0.25, 0.25, 0.1)
}
local unpaintableParts = {sm.uuid.new("92587d7f-0d69-4e42-8936-d53cf26002bb")}
local unpaintableBlocks = {blk_glass, blk_glasstile, blk_armoredglass}
local swimSpeedFactor = 3
local paintSlowFactor = 1 / 3
local paintDamage = 2.5
local paintDamageTicks = 10

function PaintGun:server_onCreate()
	self.sv = {}
	self.swimming = false
	self.swim_shape = nil
	self.swim_start_pos = nil
	self.swim_timeout = 40
	self.swim_timer = 0
	g_sv_players = {}
	self.ballID = 2
	self.false_in_a_row = 0
	self.is_equiped = false
	self.camera_reset = false
	self.swim_shape_last_pos = nil
	self.last_swim_shape = nil
	self.deleted_balls = {}
end

function PaintGun:client_onFixedUpdate(timeStep)
	if self.tool then
		self.is_equiped = self.tool:isEquipped()
		if sm.camera.getCameraState() ~= 1 then
			if self.area_trigger == nil or not sm.exists(self.area_trigger) then
				self.area_trigger =
					sm.areaTrigger.createSphere(
					0.5,
					sm.camera.getPosition() + sm.vec3.new(0,0,-0.75),
					sm.quat.identity(),
					34319,
					{player = sm.localPlayer.getPlayer()}
				)
			end
			self.area_trigger:setWorldPosition(sm.camera.getPosition() + sm.vec3.new(0,0,-0.75))
		elseif self.area_trigger ~= nil or sm.exists(self.area_trigger) then
			sm.areaTrigger.destroy(self.area_trigger)
			self.area_trigger = nil
		end
	end
end


function PaintGun:server_onFixedUpdate(timeStep)
	if self.tool then
		local owner = self.tool:getOwner()
		local char = owner:getCharacter()
		if self.is_equiped == true and self.swim_timer == 0 then
			if g_sv_players[owner.id] and g_sv_players[owner.id].equipped and self.reference_pos ~= nil then
				local pos = self.reference_pos
				local valid, result =
					sm.physics.spherecast(
					pos + sm.vec3.new(0, 0, 0.5),
					pos + sm.vec3.new(0, 0, -0.75),
					0.3,
					nil,
					3
				)

				if valid then
					self.false_in_a_row = 0
					local shape = result:getShape()
					if shape.color == g_sv_players[owner.id].color then
						if char:isCrouching() and self.swim_timer == 0 then
							self.swim_shape = shape
							self.swim_start_pos = char:getWorldPosition()
							if self.swimming == false then
								char:setWorldPosition(sm.vec3.new(0, 0, 1))
								self.swimming = true
							end
						elseif self.swimming == true then
							self.swimming = false
							self.swim_timer = self.swim_timeout
						end
					elseif sm.item.getShapeDefaultColor(shape.uuid) ~= shape.color then
						self.swimming = false
						self.swim_timer = self.swim_timeout
						newSpeed = paintSlowFactor
						if g_gameManager and g_sv_players[owner.id].paintDamageCooldown + paintDamageTicks < sm.game.getCurrentTick() then
							sm.event.sendToInteractable(
								g_gameManager.interactable,
								"sv_dmg",
								{id = owner.id, dmg = paintDamage, respawnColor = g_sv_players[owner.id].color}
							)
							g_sv_players[owner.id].paintDamageCooldown = sm.game.getCurrentTick()
						end
					elseif self.swimming == true then
						self.swim_timer = self.swim_timeout
						self.swimming = false
					end
				elseif self.false_in_a_row < 3 then
					self.false_in_a_row = self.false_in_a_row + 1
				elseif self.swimming == true then
					self.swim_timer = self.swim_timeout
					self.swimming = false
				end
			end
		end

		if self.swim_timer > 0 then
			self.swim_timer = self.swim_timer - 1
		end
	end

	last_projectile_pos = nil

	if #self.deleted_balls > 0 then
		local item = table.remove(self.deleted_balls, 1)
		local result = item[1]
		local ball = item[2]
		local id = item[3]
		local blocksToPaint = {}
		area = sm.physics.getSphereContacts(result.pointWorld, self.data.paintRadius / 2)
		expanded_once = false
		for _, body in pairs(area.bodies) do
			radius = self.data.paintRadius
			::getShapes::
			other_color_found = false
			closest_shape = nil
			joint_list = {}
			for _, shape in pairs(body:getShapes()) do
				jointList = {}
				for _, joint in pairs(shape:getJoints(false, false)) do
					if
						(joint:getShapeB() ~= nil and joint:getShapeB().id == shape.id) or
							(joint:getShapeA() ~= nil and joint:getShapeA().id == shape.id)
					 then
						jointList[shape.id] = joint
					end
				end
				if shape.color ~= ball.color then
					found_blocks = {}
					--                              \/ check if single block?
					if not shape.isBlock or shape:getBoundingBox():length() < 0.5 then
						--TODO avoid joints getting disconnected?
						for _, uuid in ipairs(unpaintableParts) do
							if shape.uuid == uuid then
								goto nextshape
							end
						end
						--TODO get chance for painting pig parts
						local distance = (shape.worldPosition - result.pointWorld):length()
						if distance <= radius * 10 then
							if closest_shape == nil then
								closest_shape = {offset = distance, pos = shape:getLocalPosition(), shape = shape}
							end
							if closest_shape.offset > distance then
								closest_shape = {offset = distance, pos = shape:getLocalPosition(), shape = shape}
							end
						end
						if distance <= radius + math.random(-1, 1) then
							if (GAME_SCRIPT_INIT == true) then
								ReplacePaintCount(shape:getColor():getHexStr(), ball.color:getHexStr(), 1)
							end
							other_color_found = true
							shape:setColor(ball.color)
						end
					else
						for _, uuid in ipairs(unpaintableBlocks) do
							if shape.uuid == uuid then
								goto nextshape
							end
						end
						local start = shape:getClosestBlockLocalPosition(result.pointWorld)
						local pointWorld = body:transformPoint(start / 4)
						local offset_distance = (pointWorld - result.pointWorld):length()
						local blockSize = 0.25
						-- this is for growing paint
						if offset_distance <= radius * 10 then
							if closest_shape == nil then
								closest_shape = {offset = offset_distance, pos = start, shape = shape}
							end
							if closest_shape.offset > offset_distance then
								closest_shape = {offset = offset_distance, pos = start, shape = shape}
							end
						end
						if offset_distance <= radius * 2 and not self.data.singleBlock then
							for x = -1, 2, 1 do
								for y = -1, 2, 1 do
									for z = -1, 2, 1 do
										local offset = sm.vec3.new(x, y, z)
										local blockPos = shape:getClosestBlockLocalPosition(body:transformPoint((start + offset) / 4))
										local distance = (offset_distance + offset:length()) / 4
										local random_length = radius + math.random(-1, 1)
										if distance <= random_length then
											found = false
											for _, pos in pairs(found_blocks) do
												if pos == blockPos then
													found = true
												end
											end
											if found == false then
												found_blocks[#found_blocks + 1] = blockPos
												other_color_found = true
												if jointList[shape.id] == nil or (jointList[shape.id]:getLocalPosition() - blockPos):length() > 1 then
													shape:destroyBlock(blockPos)
													local newShape = shape.body:createBlock(shape.uuid, sm.vec3.one(), blockPos, true)
													newShape:setColor(ball.color)
												else
													joint_list[#joint_list + 1] = {shape = shape, joint = jointList[shape.id], color = ball.color}
												end
											end
										end
									end
								end
							end
						elseif offset_distance <= 0.3 and self.data.singleBlock then
							if jointList[shape.id] == nil or (jointList[shape.id]:getLocalPosition() - start):length() > 1 then
								shape:destroyBlock(start)
								local newShape = shape.body:createBlock(shape.uuid, sm.vec3.one(), start, true)
								newShape:setColor(ball.color)
							else
								joint_list[#joint_list + 1] = {shape = shape, joint = jointList[shape.id], color = ball.color}
							end
							goto exit_all
						end
					end
				end
				::nextshape::
			end
			-- joint things here
			for _, data in pairs(joint_list) do
				data.shape:setColor(data.color)
			end
			-- this grows the paint
			if other_color_found == false and closest_shape ~= nil and expanded_once == false and self.data.singleBlock == false then
				radius = ((closest_shape.shape.body:transformPoint(closest_shape.pos / 4) - result.pointWorld):length() / 2)
				expanded_once = true
				goto getShapes
			end
		end
		::exit_all::
	end

	for id, ball in pairs(self.cl.balls) do
		local pos, dir = self:calculate_trajectory(ball.pos, ball.dir, timeStep)
		local valid, result = sm.physics.raycast(ball.pos, pos, nil, -1)
		ball.pos = pos
		ball.dir = dir

		if valid then
			local effectParams = {
				Size = 0.08,
				Velocity_max_50 = 50.0,
				Material = 2,
				Color = ball.color
			}
			sm.effect.playEffect("PaintBall", result.pointWorld, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), effectParams)
			self:sv_delete_ball(id)
			local char = result:getCharacter()
			if result.type == "areaTrigger" then
				char = result:getAreaTrigger():getUserData().player:getCharacter()
			end
			if char then
				char:setColor(ball.color)
				if g_gameManager and char:isPlayer() then
					local player = char:getPlayer()
					if ball.color ~= g_sv_players[player.id].color then
						local attacker
						if ball.player then
							attacker = "#" .. string.sub(g_sv_players[ball.player.id].color:getHexStr(), 1, 6) .. ball.player.name
						end
						sm.event.sendToInteractable(
							g_gameManager.interactable,
							"sv_dmg",
							{id = player.id, swimming = result.type == "areaTrigger", dmg = ball.dmg, respawnColor = g_sv_players[player.id].color, attacker = attacker}
						)
					end
				end
			end
			self.deleted_balls[#self.deleted_balls + 1] = {result, ball, id}
		end
	end
end

function PaintGun:cl_debug(params)
	if self.debug == nil then
		self.debug = {}
	end
	if self.debug.effect == nil then
		self.debug.effect = {}
	end
	if self.debug.effect[params[1]] == nil then
		self.debug.effect[params[1]] = sm.effect.createEffect("ShapeRenderable")
		self.debug.effect[params[1]]:setParameter("uuid", sm.uuid.new("0603b36e-0bdb-4828-b90c-ff19abcdfe34"))
		self.debug.effect[params[1]]:setParameter("color", sm.color.new(math.random(), math.random(), math.random(), 1))
		self.debug.effect[params[1]]:start()
	end
	self.debug.effect[params[1]]:setScale(sm.vec3.new(0.3, 0.3, 0.3))
	self.debug.effect[params[1]]:setPosition(params[2])
	self.debug.effect[params[1]]:setRotation(params[3])
end

function PaintGun:sv_fire_ball(params, player)
	local rot = sm.vec3.new(math.random(-90, 90), math.random(-90, 90), math.random(-90, 90))
	local factor = sm.vec3.new(math.random(-1.5, 1.5), math.random(-1.5, 1.5), math.random(-1.5, 1.5))
	local color = params.color or g_sv_players[player.id].color
	self.cl.balls[self.ballID] = {
		player = player,
		rotation = rot,
		rot_factor = factor,
		pos = params.pos,
		dir = params.dir,
		color = color,
		id = self.ballID,
		dmg = params.dmg
	}
	self.network:sendToClients(
		"cl_create_ball",
		self.cl.balls[self.ballID]
	)

	self.ballID = self.ballID + 1
end

function PaintGun:sv_delete_ball(id)
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

function PaintGun:sv_equip(params)
	g_sv_players[params.player.id].equipped = params.status
end

function PaintGun:cl_onCreate()
	self.cl = {}
	self.cl.balls = {}
	self.camera_reset = false
	if not g_cl_PaintGun or g_cl_PaintGun ~= {} then
		g_cl_PaintGun = self
		g_cl_PaintGun.color = "#eeeeee"
		g_cl_PaintGun.speed = 1
	end
	self.effect_size = 1
	self.network:sendToServer("sv_player_joined", {color = g_cl_PaintGun.color})
end

local HAS_SWIM_INIT

function PaintGun:sv_paint_shape(params)
	params.shape:setColor(params.color)
end

function PaintGun:cl_onUpdate(dt)
	if self.tool then
		local owner = self.tool:getOwner()
		local char = owner:getCharacter()
		CameraPosition = sm.camera.getPosition()
		if self.swimming == true and self.swim_shape ~= nil then
			if HAS_SWIM_INIT ~= true then
				HAS_SWIM_INIT = true
				fov = sm.camera.getFov()
				if sm.camera.getCameraState() == 1 then
					sm.camera.setCameraState(3)
				else
					sm.camera.setCameraState(6)
				end
				local move_to = self.swim_start_pos
				local valid, result = sm.physics.raycast(move_to + sm.vec3.new(0, 0, 20), move_to + sm.vec3.new(0, 0, -5))
				if valid and result:getShape() ~= nil then
					if result.pointWorld:length() > 0 then
						target = math.max(result.pointWorld.z - move_to.z + 0.75, -0.03)
						if target < 1.2 then
							target = math.min(target, 0.075)
						elseif target < 2 then
							target = math.min(target, 0.2)
						end
						move_to.z = move_to.z + target
					end
				end
				sm.camera.setPosition(move_to)
				sm.camera.setFov(fov)
				if self.move_effect == nil or self.move_effect:isDone() then
					self.move_effect = sm.effect.createEffect("WaterProjectile - Hit")
					self.move_effect:setParameter("color", sm.color.new(0, 0, 0, 1))
					self.move_effect:setScale(sm.vec3.new(1, 1, 1))
					self.move_effect:setPosition(move_to + sm.vec3.new(0, 0, -0.5))
					self.move_effect:setRotation(sm.quat.fromEuler(sm.camera.getDirection()))
					self.move_effect:setAutoPlay(false)
					self.move_effect:start()
				end
				self.swim_start_pos = nil
				goto continue
			end

			sm.camera.setDirection(char:getDirection())
			-- moving
			m_dir = self.tool:getRelativeMoveDirection()
			move_dir = sm.vec3.new(0, 0, 0)
			cam_dir = sm.camera.getDirection() * sm.vec3.new(1, 1, 0) * 0.05
			base_shape_rotation = self.swim_shape:getWorldRotation()

			if m_dir:length() > 0 then
				m_dir = m_dir:normalize()
				self.reference_pos = CameraPosition
				front_move = sm.vec3.new(0, 0, 0)
				-- move dir
				move_dir = cam_dir
				if m_dir.y < -0.5 then
					front_move = -cam_dir
				elseif m_dir.y > 0.5 then
					front_move = cam_dir
				end
				if m_dir.x > 0.5 then
					move_dir = (sm.vec3.getRotation(sm.vec3.new(1, 0, 0), sm.vec3.new(0, -1, 0)) * move_dir) + front_move
				elseif m_dir.x < -0.5 then
					move_factor = 0.5
					move_dir = (sm.vec3.getRotation(sm.vec3.new(1, 0, 0), sm.vec3.new(0, 1, 0)) * move_dir) + front_move
				else
					move_dir = front_move
				end
				if self.visual == nil then
					self.visual = {}
				end
				-- MoveEffect
				for i = 1, math.floor(self.effect_size) do
					self.visual[i] =
						sm.particle.createParticle(
						"paint_smoke",
						self.reference_pos + sm.vec3.new(0, 0, -0.5) + effect_positions[i],
						base_shape_rotation,
						g_sv_players[char:getPlayer().id].color
					)
				end
				if self.audio == nil or sm.game.getCurrentTick() % 20 == 0 then
					self.audio = sm.effect.createEffect("Mechanic - StatusUnderwater")
					self.audio:setScale(sm.vec3.new(1, 1, 1))
					self.audio:setAutoPlay(false)
					self.audio:start()
				end
				self.audio:setRotation(base_shape_rotation)
				self.audio:setPosition(self.reference_pos)
				if self.effect_size < 9 then
					self.effect_size = self.effect_size + 0.05
				end
			else
				self.effect_size = 1
			end
			move_dir = sm.vec3.new(math.floor(move_dir.x * 100), math.floor(move_dir.y * 100), math.floor(move_dir.z * 100)) / 100
			local move_to = self.reference_pos + move_dir + self.swim_shape.body:getVelocity() * dt
			local valid, result = sm.physics.raycast(move_to + sm.vec3.new(0, 0, 20), move_to + sm.vec3.new(0, 0, -5))
			if valid and result:getShape() ~= nil then
				if result.pointWorld:length() > 0 then
					target = math.max(result.pointWorld.z - move_to.z + 0.75, -0.03)
					if target < 1.2 then
						target = math.min(target, 0.075)
					elseif target < 2 then
						target = math.min(target, 0.2)
					end
					move_to.z = move_to.z + target
				end
			end
			sm.camera.setPosition(move_to)
			self.camera_reset = false
			self.reference_pos = move_to
			self.last_reference_pos = self.reference_pos
		elseif self.camera_reset == false and self.last_reference_pos ~= nil then
			HAS_SWIM_INIT = false
			self.swim_shape = nil
			self.audio = nil
			eff = sm.effect.createEffect("WaterProjectile - Hit")
			eff:setParameter("color", sm.color.new(1, 0, 0, 1))
			eff:setScale(sm.vec3.new(1, 1, 1))
			eff:setPosition(self.last_reference_pos - sm.vec3.new(0, 0, 0.75))
			eff:setRotation(sm.quat.fromEuler(sm.camera.getDirection()))
			eff:setAutoPlay(false)
			eff:start()
			self.network:sendToServer("sv_relocate_char", {character = char, reference_pos = self.last_reference_pos})
			self.camera_reset = true
		else
			self.reference_pos = char:getWorldPosition()
		end
	end

	::continue::
	for id, ball in pairs(self.cl.balls) do
		if ball.effect ~= nil then
			ball.effect:setPosition(ball.pos)
			ball.rotation = ball.rotation + ball.rot_factor
			ball.effect:setRotation(sm.quat.fromEuler(ball.rotation))
		end
	end

	if self == g_cl_PaintGun and char then
		if sm.isHost then
			char.movementSpeedFraction = g_cl_PaintGun.speed
		else
			char.clientPublicData.waterMovementSpeedFraction = g_cl_PaintGun.speed
		end
	end
end

function PaintGun:cl_set_default_cam()
	sm.camera.setCameraState(1)
end

function PaintGun:sv_relocate_char(params)
	if params.reference_pos ~= nil then
		params.character:setWorldPosition(params.reference_pos)
	end
	self.network:sendToClient(params.character:getPlayer(), "cl_set_default_cam")
end

function PaintGun:cl_create_ball(params)
	local ballEffect = sm.effect.createEffect("ShapeRenderable")
	ballEffect:setParameter("uuid", sm.uuid.new("36335664-6e61-4d44-9876-54f9660a8565"))
	ballEffect:setParameter("color", params.color)
	ballEffect:setScale(ballSize)
	ballEffect:setRotation(sm.quat.fromEuler(params.rotation))
	ballEffect:start()

	self.cl.balls[params.id] = params
	self.cl.balls[params.id].effect = ballEffect
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
		for i = 0, 40 do
			self.gui:setButtonCallback("ColorButton" .. tostring(i), "cl_onColorButton")
		end
	end
	self.gui:open()
	return false
end

function PaintGun:cl_onColorButton(name)
	local index = tonumber(string.sub(name, 12))
	g_cl_PaintGun.color = colors[index + 1]
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
		if
			(not g_cl_gameManager or color == g_cl_PaintGun.color) and not char:isDowned() and
				sm.localPlayer.getPlayer() ~= player.player
		 then
			name = color .. player.player.name
		end
		char:setNameTag(name)
	end
end

function PaintGun:cl_set_speed(newSpeed)
	g_cl_PaintGun.speed = newSpeed
end

function PaintGun:calculate_trajectory(pos, dir, dt)
	dt = dt / 2
	dir = (dir:normalize() - sm.vec3.new(0, 0, 1) * dt * 0.01):normalize() * dir:length()
	if dir.z > 90 then
		dir.z = dir.z - math.pow(math.abs(dir.z), 0.3)
	elseif dir.z > 20 then
		dir.z = dir.z - math.pow(math.abs(dir.z), 0.1)
	else
		dir.z = dir.z - math.pow(math.abs(dir.z), 0.01)
	end
	pos = pos + dir * dt * 0.5
	return pos, dir
end
