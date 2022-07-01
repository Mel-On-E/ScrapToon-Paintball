Spawn = class()

if not g_spawns then
    g_spawns = {}
end

function Spawn:server_onCreate()
    if self:sv_validateSpawn() then
        self.color = self.shape.color
        self.key = #g_spawns+1
        g_spawns[self.key] = self.shape
        self.network:sendToClients("cl_create")
    end
end

function Spawn:server_onFixedUpdate()
    if self.color ~= self.shape.color then
        if self.key and self:sv_validateSpawn(true) then
            g_spawns[self.key] = nil
            self.key = #g_spawns+1
            g_spawns[self.key] = self.shape
        end
    end
end

function Spawn:server_onDestroy()
    if self.key then
        g_spawns[self.key] = nil
    end
end

function Spawn:sv_validateSpawn(noDestroy)
    for k, shape in pairs(g_spawns) do
        if shape.color == self.shape.color then
            if not noDestroy then
                self.network:sendToClients("cl_msg", "You can only have one spawn per color")
                self.shape:destroyPart(0)
            end
            return false
        end
    end
    return true
end

function Spawn:cl_msg(msg)
    sm.gui.chatMessage(msg)
end

function Spawn:cl_create()
    self.client_glowEffect = sm.effect.createEffect( "PlayerStart - Glow", self.interactable )
	self.client_glowEffect:start()
end