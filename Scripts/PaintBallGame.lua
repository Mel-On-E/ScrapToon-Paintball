dofile("$CONTENT_DATA/Scripts/PaintGun.lua")

PaintBallGame = class()

local maxHealth = 100
local inkPerTick = 0.1
local climbInkRegenMultiplier = 7.5
local healthPerTenTicks = 0.5
local healthRegenInkMultiplier = 4.0
local respawnTime = 10

function PaintBallGame:server_onCreate()
    if not g_gameManager then
        g_gameManager = self
        g_gameManager.players = {}
        g_gameManager.respawns = {}
        g_gameManager.game = {
            mode = "Turf Wars",
            start = false,
            settings = { time = 5 }
        }
        self.network:sendToClients("cl_init", g_gameManager.game)
    else
        self.network:sendToClients("cl_msg", "You can only have one game manager")
        self.shape:destroyPart(0)
    end
end

function PaintBallGame:server_onFixedUpdate()
    if self ~= g_gameManager then return end

    if sm.game.getCurrentTick() % 10 == 0 then
        for id, player in pairs(g_gameManager.players) do
            if player.health > 0 then
                local multiplier = player.player:getCharacter():isClimbing() and healthRegenInkMultiplier or 1
                player.health = math.min(player.health + healthPerTenTicks*multiplier, maxHealth)
                g_gameManager.network:sendToClient(player.player, "cl_dmg", {health = player.health})
            end
        end
    end

    for k, respawn in pairs(self.respawns) do
        if respawn.time < sm.game.getCurrentTick() then
            local spawnPosition = sm.vec3.one()
            local yaw = 0
            local pitch = 0       

            for _, spawn in pairs(g_spawns) do
                if spawn.color == respawn.color then
                    spawnPosition = spawn.worldPosition + spawn:getAt() * 0.825
                    local spawnDirection = -spawn:getUp()
                    pitch = math.asin( spawnDirection.z )
                    yaw = math.atan2( spawnDirection.x, -spawnDirection.y )
                end
            end

            local newChar = sm.character.createCharacter( respawn.player, respawn.player:getCharacter():getWorld(), spawnPosition, yaw, pitch )

            respawn.player:setCharacter(newChar)
            g_gameManager.players[respawn.player.id].health = maxHealth
            self.network:sendToClient(respawn.player, "cl_init", g_gameManager.game)
            self.network:sendToClients("cl_set_name_tags", g_sv_players)
            sm.effect.playEffect( "Characterspawner - Activate", spawnPosition )

            self.respawns[k] = nil
        end
    end
end

function PaintBallGame:server_onDestroy()
    if self == g_gameManager then
        g_gameManager = nil
    end
end

function PaintBallGame:sv_join_game(params, player)
    g_gameManager.players[player.id] = {health = maxHealth, player = player}
    self.network:sendToClient(player, "cl_init", g_gameManager.game)
end

function PaintBallGame:sv_dmg(params)
    if g_gameManager.players[params.id].health > 0 then
        g_gameManager.players[params.id].health = math.max(g_gameManager.players[params.id].health - params.dmg, 0)
        g_gameManager.network:sendToClient(g_gameManager.players[params.id].player, "cl_dmg", {health = g_gameManager.players[params.id].health, damage = params.dmg})
        if g_gameManager.players[params.id].health == 0 then
            g_gameManager:sv_death({player = g_gameManager.players[params.id].player, respawnColor = params.respawnColor, attacker = params.attacker})
        end
    end
end

function PaintBallGame:sv_death(params)
    params.player:getCharacter():setTumbling(true)
    params.player:getCharacter():setDowned(true)

    local name = "#" .. string.sub(params.respawnColor:getHexStr(), 1, 6) .. params.player.name
    if params.attacker then
        self.network:sendToClients("cl_msg", name .. "#ffffff was inked by " .. params.attacker)
    else
        self.network:sendToClients("cl_msg", name .. "#ffffff was inked")
    end
    

    self.respawns[#self.respawns+1] = {player = params.player, time = sm.game.getCurrentTick() + respawnTime*40, color = params.respawnColor}
    self.network:sendToClient(params.player, "cl_death")
    self.network:sendToClients("cl_set_name_tags", g_sv_players)
end

function PaintBallGame:sv_change_settings(params)
    g_gameManager.game.settings.time = math.max(3, math.min(params.time, 20))
    self.network:sendToClients("cl_update_game", g_gameManager.game)
end

function PaintBallGame:client_onCreate()
    if not g_paintHud then
		g_paintHud = sm.gui.createSurvivalHudGui()
		g_paintHud:setVisible("WaterBar", false)
		g_paintHud:setVisible("BindingPanel", false)
		g_paintHud:setImage("FoodIcon", "gui_icon_hud_water.png")
		g_paintHud:open()

        self.network:sendToServer("sv_join_game")
	end
end

function PaintBallGame:cl_init(game)
    self.cl = {}
    self.cl.health = 100
    g_cl_gameManager = self
    g_cl_gameManager.cl_game = g_gameManager.game
    g_paint = 100
    g_paintHud:setSliderData( "Food", maxHealth+1, g_paint )
    self.death = nil
end

function PaintBallGame:client_onDestroy()
    if g_cl_gameManager == self then
        if g_paintHud then
            g_paintHud:destroy()
            g_paintHud = nil
        end
        if g_paint then
            g_paint = nil
            g_cl_gameManager = nil
        end
        if self.gui then
            self.gui:destroy()
        end
    end
end

function PaintBallGame:client_onFixedUpdate()
    if g_paint then
        local multiplier = sm.localPlayer.getPlayer():getCharacter():isClimbing() and climbInkRegenMultiplier or 1
        g_paint = math.min(g_paint + inkPerTick*multiplier, 100)
        g_paintHud:setSliderData( "Food", 101, g_paint )
    end

    if self.death and sm.game.getCurrentTick()%40 == 0 then
        self.death = math.max(self.death-1, 0)
    end
end

function PaintBallGame:client_onUpdate()
    if self.death then
        sm.gui.setInteractionText("Respawn in " .. tostring(self.death))
    end

    if g_paint < 99 then
        sm.gui.setProgressFraction(math.max(g_paint-2, 0)/100)
    end
end

function PaintBallGame:client_onInteract(character, state)
    if state then
        self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/PaintGameMaster.layout")

        self:cl_update_gui()

        self.gui:setButtonCallback("TimeUp", "cl_time_up")
        self.gui:setButtonCallback("TimeDown", "cl_time_down")
        self.gui:setButtonCallback("Start", "cl_start_game")

        self.gui:open()
    end
end

function PaintBallGame:cl_spendPaint(cost)
    if g_paint < cost then
        sm.gui.displayAlertText(g_cl_PaintGun.color .. "No Ink")
        return false
    end

    g_paint = g_paint - cost
    g_paintHud:setSliderData( "Food", 101, g_paint )
    return true
end

function PaintBallGame:cl_dmg(params)  
    g_paintHud:setSliderData( "Health", maxHealth*10+1, params.health*10 )
    if params.damage then
        local effectParams = {
            ["char"] = sm.localPlayer.getPlayer():isMale() and 1 or 2,
            ["damage"] = params.damage
        }
        sm.effect.playEffect("Mechanic - HurtDrown", sm.localPlayer.getPlayer().character.worldPosition, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), effectParams )
    end
end

function PaintBallGame:cl_msg(msg)
    sm.gui.chatMessage(msg)
end

function PaintBallGame:cl_death()
    self.death = respawnTime
    sm.gui.setInteractionText("Respawn in " .. tostring(self.death))
end

function PaintBallGame:cl_set_name_tags(players)
    PaintGun.cl_set_name_tags(self, players)
end

function PaintBallGame:cl_update_game(game)
    g_cl_gameManager.cl_game = game
    if self.gui:isActive() then
        self:cl_update_gui()
    end
end

function PaintBallGame:cl_update_gui()
    self.gui:setText("Time", tostring(g_cl_gameManager.cl_game.settings.time) .. "min")
    self.gui:setText("Start", g_cl_gameManager.cl_game.start and "End Game" or "Start Game")
end

function PaintBallGame:cl_time_up()
    self.network:sendToServer("sv_change_settings", {time = g_cl_gameManager.cl_game.settings.time + 1})
end

function PaintBallGame:cl_time_down()
    self.network:sendToServer("sv_change_settings", {time = g_cl_gameManager.cl_game.settings.time - 1})
end



--TODO Turf wars game mode
--add time back
--make settings work
--why am I writing this down? I think I know what to do


--TODO Delete projectiles after timelimit
--TODO Add some crouch shoot cooldown



--TODO Find someone to do 2D paint splash effects
--TODO Find someone to rewrite the algo for coloring blocks
--better splash effects?
--sphere instead of glue bottle? water effect?