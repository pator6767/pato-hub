if type(_G.__AzucarHubCleanup) == "function" then pcall(_G.__AzucarHubCleanup) end

local success, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not success or not Rayfield then
    warn("[Error]: No se pudo cargar Rayfield. Revisa la consola (F9) para ver los bloqueos HTTP.")
    return
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ==========================================================
-- CONFIGURACIÓN GENERAL
-- ==========================================================
local MAX_DISTANCE = 1500
local MOUSE_HITBOX_RADIUS = 250
local ATTACH_OFFSET = 0.5
local TPKey = Enum.KeyCode.G
local FlyKey = Enum.KeyCode.P

-- ==========================================================
-- CONFIGURACIÓN DEL MAGNET DE NPCS
-- ==========================================================
local NPC_MAGNET_ENABLED = false
local NPC_SEARCH_RADIUS = 350
local NPC_MAGNET_HEIGHT = -8
local npcCache = {}
local lastCacheRefresh = 0

-- ==========================================================
-- CONFIGURACIÓN DE BARCO Y POCA VIDA
-- ==========================================================
local AUTO_BRING_ENABLED = true
local LOW_HEALTH_PERCENT = 25
local BoatCFrame = nil

-- Variables de Estado
local isHoldingKey = false
local lockedTargetChar = nil
local lockedTargetPlayer = nil

-- Variables de Misc (Auto V4 / Dash Length)
local autoV4 = false
local v4Connection = nil
local DashEnabled = false
local DashConnection = nil
local DashLenghtDistance420 = 5

-- Variables de Combate (Fast Attack)
local FastAttackEnabled = false
local AttackPlayers = true
local AttackRange = 120
local LongRangeEnabled = false
local LongRangeStand = 30   -- distancia a la que te quedas del objetivo
local FastAttackRunning = true

-- Variables de Fly
local FlyEnabled = false
local FlySpeed = 60
local flyBV = nil
local flyBG = nil
local flyConn = nil
local FlyToggle = nil
local boatBV = nil
local boatBG = nil
local boatSinkBound = false
local boatLastPos = nil
local boatStuckTime = 0
local boatCFrameMode = false
local lastBoatScan = 0
local lastManualExit = 0      -- evita que el auto-sentarse te vuelva a sentar justo al salir
local buyBoatNow = nil        -- se define en la pestaña Barcos
local toggleBoatSeat = nil    -- se define en la pestaña Barcos
local AutoSitBoats = true
local ContextActionService = game:GetService("ContextActionService")

-- Variables de ESP
local ESPPlayersEnabled = false
local ESPNPCsEnabled = false
local ESPNames = true
local ESPDistance = true
local ESPShowHealth = true
local ESPShowEnergy = true
local ESPShowKen = true
local ESPMaxDistance = math.huge -- sin límite de distancia
local ESPLineThickness = 1.5
local espObjects = {}
local espNpcList = {}
local lastEspNpcRefresh = 0
local espConn = nil

local PLAYER_COLOR = Color3.fromRGB(255, 0, 0)
local NPC_COLOR = Color3.fromRGB(0, 120, 255)

-- ==========================================================
-- VENTANA RAYFIELD
-- ==========================================================
local Window = Rayfield:CreateWindow({
    Name = "Pato Hub",
    LoadingTitle = "Pato Hub",
    LoadingSubtitle = "TP + NPCs Magnet + Fast Attack + Fly + ESP",
    ToggleUIKeybind = "K",
    ConfigurationSaving = { Enabled = false },
    Discord = { Enabled = false },
    KeySystem = false
})

local function Notify(title, content, duration)
    Rayfield:Notify({
        Title = title,
        Content = content,
        Duration = duration or 3,
        Image = "bell"
    })
end

-- ==========================================================
-- ESP (LÍNEAS: ROJO = JUGADORES, AZUL = NPCS)
-- ==========================================================
local function removeESP(key)
    local obj = espObjects[key]
    if obj then
        for _, drawing in pairs(obj) do
            pcall(function() drawing:Remove() end)
        end
        espObjects[key] = nil
    end
end

local function clearAllESP()
    for key in pairs(espObjects) do
        removeESP(key)
    end
end

local function getESP(key, color)
    local obj = espObjects[key]
    if obj then return obj end

    local line = Drawing.new("Line")
    line.Color = color
    line.Thickness = ESPLineThickness
    line.Visible = false

    local text = Drawing.new("Text")
    text.Color = color
    text.Size = 14
    text.Center = true
    text.Outline = true
    text.Visible = false

    local function newSquare(squareColor)
        local sq = Drawing.new("Square")
        sq.Color = squareColor
        sq.Filled = true
        sq.Thickness = 1
        sq.Visible = false
        return sq
    end

    local kenText = Drawing.new("Text")
    kenText.Color = Color3.fromRGB(255, 255, 255)
    kenText.Size = 13
    kenText.Center = true
    kenText.Outline = true
    kenText.Visible = false

    obj = {
        Line = line,
        Text = text,
        HealthBG = newSquare(Color3.fromRGB(0, 0, 0)),
        HealthFill = newSquare(Color3.fromRGB(0, 255, 0)),
        EnergyBG = newSquare(Color3.fromRGB(0, 0, 0)),
        EnergyFill = newSquare(Color3.fromRGB(0, 150, 255)),
        KenText = kenText,
    }
    espObjects[key] = obj
    return obj
end

local function refreshEspNpcList()
    table.clear(espNpcList)
    local folders = {
        Workspace:FindFirstChild("Enemies"),
        Workspace:FindFirstChild("NPCs"),
        Workspace:FindFirstChild("Mobs")
    }
    for _, folder in ipairs(folders) do
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
                    table.insert(espNpcList, model)
                end
            end
        end
    end
end

local function hideESP(obj)
    for _, drawing in pairs(obj) do
        pcall(function() drawing.Visible = false end)
    end
end

-- Energía: devuelve (actual, máxima). La máxima puede ser nil si el juego no la expone.
local function getEnergyInfo(model)
    local energyObj = model:FindFirstChild("Energy")
    local cur = nil
    if energyObj and energyObj:IsA("ValueBase") and type(energyObj.Value) == "number" then
        cur = energyObj.Value
    end
    if cur == nil then
        local attr = model:GetAttribute("Energy")
        if type(attr) == "number" then cur = attr end
    end

    local max = model:GetAttribute("MaxEnergy")
    if type(max) ~= "number" and energyObj then
        max = energyObj:GetAttribute("Max") or energyObj:GetAttribute("MaxValue")
        if type(max) ~= "number" then
            local child = energyObj:FindFirstChild("Max") or energyObj:FindFirstChild("MaxValue")
            max = child and child:IsA("ValueBase") and child.Value or nil
        end
    end
    if type(max) ~= "number" or max <= 0 then max = nil end

    return cur, max
end

-- Ken Haki: busca el contador de esquives en atributos o valores del personaje/jugador.
local KEN_NAMES = { "KenDodgesLeft", "KenDodges", "KenDodge", "KenCount", "KenHits", "Ken", "ObservationDodges" }

local function getKenCount(model, plr)
    for _, name in ipairs(KEN_NAMES) do
        local v = model:GetAttribute(name)
        if v == nil and plr then v = plr:GetAttribute(name) end
        if type(v) == "number" then return v end

        local inst = model:FindFirstChild(name) or (plr and plr:FindFirstChild(name))
        if inst and inst:IsA("ValueBase") and type(inst.Value) == "number" then
            return inst.Value
        end
    end
    return nil
end

local function drawTarget(key, model, color, displayName, cam, origin, myPos, seen)
    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    local dist = (hrp.Position - myPos).Magnitude
    if dist > ESPMaxDistance then return end

    seen[key] = true
    local obj = getESP(key, color)

    local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
    if not onScreen then
        hideESP(obj)
        return
    end

    local target = Vector2.new(pos.X, pos.Y)

    obj.Line.Thickness = ESPLineThickness
    obj.Line.From = origin
    obj.Line.To = target
    obj.Line.Visible = true

    if ESPNames or ESPDistance then
        local label = ""
        if ESPNames then label = displayName end
        if ESPDistance then
            label = label .. (label ~= "" and " " or "") .. "[" .. math.floor(dist) .. "]"
        end
        obj.Text.Text = label
        obj.Text.Position = Vector2.new(target.X, target.Y - 50)
        obj.Text.Visible = true
    else
        obj.Text.Visible = false
    end

    local isPlayer = typeof(key) == "Instance" and key:IsA("Player")
    local barW, barH = 60, 5
    local barX = target.X - barW / 2
    local y = target.Y - 32

    -- Barra de vida (verde)
    if ESPShowHealth and hum.MaxHealth > 0 then
        local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        obj.HealthBG.Position = Vector2.new(barX - 1, y - 1)
        obj.HealthBG.Size = Vector2.new(barW + 2, barH + 2)
        obj.HealthBG.Visible = true
        obj.HealthFill.Position = Vector2.new(barX, y)
        obj.HealthFill.Size = Vector2.new(barW * ratio, barH)
        obj.HealthFill.Visible = true
        y = y + barH + 3
    else
        obj.HealthBG.Visible = false
        obj.HealthFill.Visible = false
    end

    -- Barra de energía (azul) - solo jugadores
    local showEnergy = false
    if ESPShowEnergy and isPlayer then
        local cur, max = getEnergyInfo(model)
        if cur then
            obj.MaxEnergySeen = math.max(obj.MaxEnergySeen or 0, cur)
            max = max or obj.MaxEnergySeen
            local ratio = (max and max > 0) and math.clamp(cur / max, 0, 1) or 0
            obj.EnergyBG.Position = Vector2.new(barX - 1, y - 1)
            obj.EnergyBG.Size = Vector2.new(barW + 2, barH + 2)
            obj.EnergyBG.Visible = true
            obj.EnergyFill.Position = Vector2.new(barX, y)
            obj.EnergyFill.Size = Vector2.new(barW * ratio, barH)
            obj.EnergyFill.Visible = true
            y = y + barH + 3
            showEnergy = true
        end
    end
    if not showEnergy then
        obj.EnergyBG.Visible = false
        obj.EnergyFill.Visible = false
    end

    -- Ken Haki - solo jugadores
    if ESPShowKen and isPlayer then
        local ken = getKenCount(model, key)
        obj.KenText.Text = "Ken: " .. (ken ~= nil and tostring(ken) or "?")
        obj.KenText.Position = Vector2.new(target.X, y)
        obj.KenText.Visible = true
    else
        obj.KenText.Visible = false
    end
end

local function startESP()
    if espConn then return end

    espConn = RunService.RenderStepped:Connect(function()
        if not ESPPlayersEnabled and not ESPNPCsEnabled then
            clearAllESP()
            return
        end

        local cam = Workspace.CurrentCamera
        local myChar = LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not cam or not myHRP then return end

        local viewport = cam.ViewportSize
        local origin = Vector2.new(viewport.X / 2, viewport.Y)
        local myPos = myHRP.Position
        local seen = {}

        if ESPPlayersEnabled then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    drawTarget(plr, plr.Character, PLAYER_COLOR, plr.Name, cam, origin, myPos, seen)
                end
            end
        end

        if ESPNPCsEnabled then
            if tick() - lastEspNpcRefresh > 1 then
                lastEspNpcRefresh = tick()
                refreshEspNpcList()
            end
            for _, model in ipairs(espNpcList) do
                if model.Parent then
                    drawTarget(model, model, NPC_COLOR, model.Name, cam, origin, myPos, seen)
                end
            end
        end

        for key in pairs(espObjects) do
            if not seen[key] then
                removeESP(key)
            end
        end
    end)
end

local function stopESP()
    if espConn then
        espConn:Disconnect()
        espConn = nil
    end
    clearAllESP()
end

local function updateESPState()
    if ESPPlayersEnabled or ESPNPCsEnabled then
        startESP()
    else
        stopESP()
    end
end

-- ==========================================================
-- FLY
-- ==========================================================
local function setHumanoidStates(hum, enabled, except)
    for _, st in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
        if st ~= Enum.HumanoidStateType.None and st ~= except then
            pcall(function() hum:SetStateEnabled(st, enabled) end)
        end
    end
end

local function clearBoatMovers()
    boatLastPos = nil
    boatStuckTime = 0
    boatCFrameMode = false
    if boatBV then
        pcall(function() boatBV:Destroy() end)
        boatBV = nil
    end
    if boatBG then
        pcall(function() boatBG:Destroy() end)
        boatBG = nil
    end
    if boatSinkBound then
        boatSinkBound = false
        pcall(function() ContextActionService:UnbindAction("PatoBoatNoJump") end)
    end
end

-- Detecta si estás sentado aunque SeatPart venga vacío (algunos barcos solo ponen Sit)
local function getSeatedPart(humanoid, hrp)
    if humanoid.SeatPart then
        return humanoid.SeatPart
    end
    if humanoid.Sit then
        local ok, parts = pcall(function() return hrp:GetConnectedParts(true) end)
        if ok and parts then
            for _, part in ipairs(parts) do
                if part:IsA("Seat") or part:IsA("VehicleSeat") then
                    return part
                end
            end
        end
    end
    return nil
end

local function getFlyDir(cam)
    local dir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0) end
    if dir.Magnitude > 0 then
        dir = dir.Unit
    end
    return dir
end

local function stopFly()
    clearBoatMovers()
    if flyConn then
        flyConn:Disconnect()
        flyConn = nil
    end
    if flyBV then
        pcall(function() flyBV:Destroy() end)
        flyBV = nil
    end
    if flyBG then
        pcall(function() flyBG:Destroy() end)
        flyBG = nil
    end

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.PlatformStand = false
        setHumanoidStates(hum, true)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

-- Fly estilo Fly GUI v3: usa BodyVelocity + BodyGyro, apaga los estados del
-- humanoide y se repone solo si el juego (V4, habilidades, etc.) lo rompe.
local function startFly()
    stopFly()

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return false end

    local lastStateFix = 0

    flyConn = RunService.RenderStepped:Connect(function(dt)
        local cam = Workspace.CurrentCamera
        local c = LocalPlayer.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local humanoid = c and c:FindFirstChildOfClass("Humanoid")
        if not (cam and root and humanoid) or humanoid.Health <= 0 then return end

        -- MODO BARCO: si estás sentado, vuela el barco entero en vez del personaje
        local seat = getSeatedPart(humanoid, root)
        if seat then
            if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
            if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end

            local boatRoot = seat.AssemblyRootPart or seat
            if boatRoot.Anchored then boatRoot.Anchored = false end

            if not boatBV or boatBV.Parent ~= boatRoot then
                if boatBV then pcall(function() boatBV:Destroy() end) end
                boatBV = Instance.new("BodyVelocity")
                boatBV.Name = "PatoBoatBV"
                boatBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                boatBV.Velocity = Vector3.zero
                boatBV.Parent = boatRoot
            end

            if not boatBG or boatBG.Parent ~= boatRoot then
                if boatBG then pcall(function() boatBG:Destroy() end) end
                boatBG = Instance.new("BodyGyro")
                boatBG.Name = "PatoBoatBG"
                -- Mantiene el barco nivelado pero deja que gire (eje Y libre)
                boatBG.MaxTorque = Vector3.new(9e9, 0, 9e9)
                boatBG.P = 9e4
                boatBG.Parent = boatRoot
            end

            -- Espacio sube el barco sin sacarte del asiento
            if not boatSinkBound then
                boatSinkBound = true
                ContextActionService:BindActionAtPriority(
                    "PatoBoatNoJump",
                    function() return Enum.ContextActionResult.Sink end,
                    false,
                    Enum.ContextActionPriority.High.Value,
                    Enum.KeyCode.Space
                )
            end

            local dir = getFlyDir(cam)

            -- Si el barco no avanza con la física (el juego lo frena), pasa a mover por CFrame
            if dir.Magnitude > 0 then
                if boatLastPos and not boatCFrameMode then
                    local moved = (boatRoot.Position - boatLastPos).Magnitude
                    if moved < FlySpeed * dt * 0.3 then
                        boatStuckTime = boatStuckTime + dt
                    else
                        boatStuckTime = 0
                    end
                    if boatStuckTime > 0.4 then
                        boatCFrameMode = true
                    end
                end
                boatLastPos = boatRoot.Position
            else
                boatStuckTime = 0
                boatLastPos = nil
            end

            if boatCFrameMode then
                boatBV.Velocity = Vector3.zero
                boatRoot.AssemblyLinearVelocity = Vector3.zero
                boatRoot.AssemblyAngularVelocity = Vector3.zero
                if dir.Magnitude > 0 then
                    boatRoot.CFrame = boatRoot.CFrame + dir * FlySpeed * dt
                end
            else
                boatBV.Velocity = dir * FlySpeed
            end

            local look = boatRoot.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 0.05 then
                local right = boatRoot.CFrame.RightVector
                flat = Vector3.new(right.X, 0, right.Z)
            end
            if flat.Magnitude > 0.05 then
                boatBG.CFrame = CFrame.lookAt(boatRoot.Position, boatRoot.Position + flat.Unit)
            end
            return
        else
            clearBoatMovers()
        end

        -- Si el juego destruyó o movió los movers, se recrean al instante
        if not flyBV or flyBV.Parent ~= root then
            if flyBV then pcall(function() flyBV:Destroy() end) end
            flyBV = Instance.new("BodyVelocity")
            flyBV.Name = "PatoFlyBV"
            flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end
        if not flyBG or flyBG.Parent ~= root then
            if flyBG then pcall(function() flyBG:Destroy() end) end
            flyBG = Instance.new("BodyGyro")
            flyBG.Name = "PatoFlyBG"
            flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBG.P = 9e4
            flyBG.CFrame = cam.CFrame
            flyBG.Parent = root
        end

        -- Si algo te ancló o te sacó del estado de vuelo, se corrige
        if root.Anchored then root.Anchored = false end
        if not humanoid.PlatformStand then humanoid.PlatformStand = true end

        if tick() - lastStateFix > 0.25 then
            lastStateFix = tick()
            setHumanoidStates(humanoid, false, Enum.HumanoidStateType.Swimming)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true) end)
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
            if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
                pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Swimming) end)
            end
        end

        -- Con el fly activo, si estás junto a un asiento de barco libre, te sienta
        if AutoSitBoats and not humanoid.SeatPart and tick() - lastBoatScan > 0.5
            and tick() - lastManualExit > 3 then
            lastBoatScan = tick()
            local boats = Workspace:FindFirstChild("Boats")
            if boats then
                for _, d in ipairs(boats:GetDescendants()) do
                    if d:IsA("VehicleSeat") and d.Occupant == nil
                        and (d.Position - root.Position).Magnitude <= 12 then
                        local ok = pcall(function() d:Sit(humanoid) end)
                        if not ok then humanoid.Sit = true end
                        break
                    end
                end
            end
        end

        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0) end

        if dir.Magnitude > 0 then
            dir = dir.Unit
        end

        flyBV.Velocity = dir * FlySpeed
        flyBG.CFrame = cam.CFrame
    end)

    return true
end

local function setFly(state)
    FlyEnabled = state
    if state then
        local ok = startFly()
        if not ok then
            FlyEnabled = false
            if FlyToggle then FlyToggle:Set(false) end
        end
    else
        stopFly()
    end
end

-- Si reapareces con el fly activado, se vuelve a activar
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    if FlyEnabled then
        task.wait(1)
        if FlyEnabled then
            startFly()
        end
    end
end)

-- ==========================================================
-- MAGNET DE NPCS (DEBAJO DE TI)
-- ==========================================================
local function refreshNPCCache()
    local localChar = LocalPlayer.Character
    table.clear(npcCache)

    -- Solo carpetas de enemigos hostiles (nada de Workspace general ni NPCs de interacción)
    local searchFolders = {
        Workspace:FindFirstChild("Enemies"),
        Workspace:FindFirstChild("Mobs")
    }

    for _, folder in ipairs(searchFolders) do
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and model ~= localChar and model ~= lockedTargetChar
                    and not Players:GetPlayerFromCharacter(model) then
                    local humanoid = model:FindFirstChildOfClass("Humanoid")
                    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
                    local interactable = model:FindFirstChildWhichIsA("ProximityPrompt", true)
                        or model:FindFirstChildWhichIsA("ClickDetector", true)
                    if humanoid and hrp and not interactable then
                        table.insert(npcCache, {humanoid = humanoid, hrp = hrp})
                    end
                end
            end
        end
    end
end

local function runNPCMagnet()
    if not NPC_MAGNET_ENABLED then return end

    local localChar = LocalPlayer.Character
    local myHRP = localChar and localChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    if tick() - lastCacheRefresh > 0.5 then
        lastCacheRefresh = tick()
        refreshNPCCache()
    end

    local myPos = myHRP.Position
    local magnetPos = myPos + Vector3.new(0, NPC_MAGNET_HEIGHT, 0)

    for _, npc in ipairs(npcCache) do
        local hrp = npc.hrp
        if hrp and hrp.Parent and npc.humanoid.Health > 0 then
            if (hrp.Position - myPos).Magnitude <= NPC_SEARCH_RADIUS then
                pcall(function()
                    hrp.CFrame = CFrame.new(magnetPos)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end
end

-- ==========================================================
-- DETECCIÓN CON HITBOX AMPLIADA DEL MOUSE
-- ==========================================================
local function getTargetWithHitbox()
    local localChar = LocalPlayer.Character
    local myHRP = localChar and localChar:FindFirstChild("HumanoidRootPart")

    local directTarget = Mouse.Target
    if directTarget then
        local char = directTarget:FindFirstAncestorOfClass("Model")
        if char then
            local player = Players:GetPlayerFromCharacter(char)
            if player and player ~= LocalPlayer and char:FindFirstChild("HumanoidRootPart") then
                return player, char
            end
        end
    end

    local mousePos = UserInputService:GetMouseLocation()
    local closestPlayer = nil
    local closestChar = nil
    local shortestScreenDistance = MOUSE_HITBOX_RADIUS

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local char = player.Character
            local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
            local humanoid = char:FindFirstChildOfClass("Humanoid")

            if hrp and (not humanoid or humanoid.Health > 0) then
                local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local screenDist = (mousePos - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
                    if screenDist < shortestScreenDistance then
                        if myHRP then
                            local worldDist = (myHRP.Position - hrp.Position).Magnitude
                            if worldDist <= MAX_DISTANCE then
                                shortestScreenDistance = screenDist
                                closestPlayer = player
                                closestChar = char
                            end
                        else
                            shortestScreenDistance = screenDist
                            closestPlayer = player
                            closestChar = char
                        end
                    end
                end
            end
        end
    end

    return closestPlayer, closestChar
end

-- ==========================================================
-- LÓGICA PRINCIPAL DE TP & SPAM
-- ==========================================================
local function performInstantTP()
    local localChar = LocalPlayer.Character
    if not (localChar and localChar:FindFirstChild("HumanoidRootPart")) then return end
    local myHRP = localChar.HumanoidRootPart

    if not (lockedTargetChar and lockedTargetChar:FindFirstChild("HumanoidRootPart")) then
        local targetPlayer, targetChar = getTargetWithHitbox()
        if targetPlayer and targetChar then
            lockedTargetPlayer = targetPlayer
            lockedTargetChar = targetChar
        else
            return
        end
    end

    local targetHRP = lockedTargetChar:FindFirstChild("HumanoidRootPart") or lockedTargetChar:FindFirstChild("Torso") or lockedTargetChar:FindFirstChild("UpperTorso")
    local targetHumanoid = lockedTargetChar:FindFirstChildOfClass("Humanoid")
    if not targetHRP then return end

    -- POCA VIDA -> LLEVAR AL BARCO
    if AUTO_BRING_ENABLED and BoatCFrame and targetHumanoid and targetHumanoid.MaxHealth > 0 then
        local healthPercent = (targetHumanoid.Health / targetHumanoid.MaxHealth) * 100
        if healthPercent <= LOW_HEALTH_PERCENT and targetHumanoid.Health > 0 then
            myHRP.CFrame = BoatCFrame
            myHRP.AssemblyLinearVelocity = Vector3.zero
            pcall(function()
                targetHRP.CFrame = BoatCFrame * CFrame.new(0, 0, -2)
                targetHRP.AssemblyLinearVelocity = Vector3.zero
            end)
            return
        end
    end

    -- PEGADO NORMAL AL ENEMIGO
    local distance = (myHRP.Position - targetHRP.Position).Magnitude
    if distance <= MAX_DISTANCE then
        myHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 0, ATTACH_OFFSET)
        myHRP.AssemblyLinearVelocity = Vector3.zero
    end
end

local heartbeatConn = RunService.Heartbeat:Connect(function()
    if isHoldingKey then
        performInstantTP()
    end
    runNPCMagnet()
end)

-- ==========================================================
-- FAST ATTACK (HILO SECUNDARIO)
-- ==========================================================
task.spawn(function()
    local Modules = ReplicatedStorage:WaitForChild("Modules", 5)
    local NetModule = Modules and Modules:FindFirstChild("Net")
    local CombatUtilModule = Modules and Modules:FindFirstChild("CombatUtil")

    if not NetModule or not CombatUtilModule then
        warn("[Error]: No se encontraron los módulos de combate del juego.")
        return
    end

    local CombatUtil = require(CombatUtilModule)
    local Net = require(NetModule)

    local RegisterAttack = NetModule:FindFirstChild("RE/RegisterAttack")
    local RegisterHit = Net:RemoteEvent("RegisterHit", true)

    local ValidParts = {
        RightUpperArm = true, RightLowerArm = true, RightHand = true,
        RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
        LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
        LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
        UpperTorso = true, LowerTorso = true, Head = true
    }

    local function GetEnemiesAndPlayers(includePlayers)
        local targets = {}
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, v in pairs(enemies:GetChildren()) do table.insert(targets, v) end
        end
        if includePlayers then
            local characters = Workspace:FindFirstChild("Characters")
            if characters then
                for _, v in pairs(characters:GetChildren()) do table.insert(targets, v) end
            end
        end
        return targets
    end

    local function GetBladeHits(character, originParts, range, includePlayers)
        local hits = {}
        local targets = GetEnemiesAndPlayers(includePlayers)
        for _, target in pairs(targets) do
            if target:IsDescendantOf(Workspace) and target ~= character and target:FindFirstChild("HumanoidRootPart") then
                local hrp = target.HumanoidRootPart
                local adjustedRange = Players:GetPlayerFromCharacter(target) and (range / 1.5) or range
                if (hrp.Position - originParts[1].Position).Magnitude <= (adjustedRange + hrp.Size.X / 2) then
                    for _, childPart in pairs(target:GetChildren()) do
                        if childPart:IsA("BasePart") then table.insert(hits, childPart) end
                    end
                end
            end
        end
        return hits
    end

    local function AttackAOE(range, includePlayers)
        local targetsList = {}
        local hitCache = {}
        local character = LocalPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end

        local hits = GetBladeHits(character, { character.HumanoidRootPart }, range or 80, includePlayers)
        for _, part in pairs(hits) do
            local rig = CombatUtil:GetRigOfHitPart(part)
            if rig and not hitCache[rig] and ValidParts[part.Name] and CombatUtil:IsVulnerable(rig) then
                table.insert(targetsList, { rig, part })
                hitCache[rig] = true
            end
        end
        return #targetsList > 0 and targetsList or nil
    end

    -- Rango largo: si el objetivo más cercano está lejos, te acerca hasta LongRangeStand
    local function ApproachNearest()
        if not LongRangeEnabled then return end

        local character = LocalPlayer.Character
        local myHRP = character and character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end

        local nearest, nearestDist = nil, AttackRange
        for _, target in pairs(GetEnemiesAndPlayers(AttackPlayers)) do
            if target ~= character and target:IsDescendantOf(Workspace) then
                local hrp = target:FindFirstChild("HumanoidRootPart")
                local hum = target:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local d = (hrp.Position - myHRP.Position).Magnitude
                    if d < nearestDist then
                        nearest, nearestDist = hrp, d
                    end
                end
            end
        end

        if nearest and nearestDist > LongRangeStand then
            local dir = myHRP.Position - nearest.Position
            dir = Vector3.new(dir.X, 0, dir.Z)
            if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
            local pos = nearest.Position + dir.Unit * LongRangeStand
            myHRP.CFrame = CFrame.new(pos.X, nearest.Position.Y, pos.Z)
            myHRP.AssemblyLinearVelocity = Vector3.zero
        end
    end

    while FastAttackRunning do
        task.wait(0.05)
        if FastAttackEnabled then
            pcall(ApproachNearest)
            pcall(function()
                local targets = AttackAOE(AttackRange, AttackPlayers)
                if targets and RegisterAttack and RegisterHit then
                    RegisterAttack:FireServer(0)
                    RegisterHit:FireServer(table.remove(targets, 1)[2], targets)
                end
            end)
        end
    end
end)

-- ==========================================================
-- EVENTOS DE TECLADO
-- ==========================================================
local inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == TPKey then
        isHoldingKey = true
        local targetPlayer, targetChar = getTargetWithHitbox()
        if targetPlayer and targetChar then
            lockedTargetPlayer = targetPlayer
            lockedTargetChar = targetChar
        end
        performInstantTP()
    end

    if input.KeyCode == FlyKey then
        if FlyToggle then
            FlyToggle:Set(not FlyEnabled)
        else
            setFly(not FlyEnabled)
        end
    end

    if input.KeyCode == Enum.KeyCode.N and buyBoatNow then
        task.spawn(buyBoatNow)
    end

    if input.KeyCode == Enum.KeyCode.X and toggleBoatSeat then
        task.spawn(toggleBoatSeat)
    end
end)

local inputEndedConn = UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.KeyCode == TPKey then
        isHoldingKey = false
        lockedTargetChar = nil
        lockedTargetPlayer = nil
    end
end)

-- ==========================================================
-- GIRO VISUAL HORIZONTAL (NO AFECTA EL MOVIMIENTO)
-- ==========================================================
local SpinEnabled = true
local SPIN_SPEED = 14       -- radianes por segundo (giro horizontal)
local spinConn = nil
local spinCharConn = nil
local spinJoint = nil
local spinOriginalC0 = nil

local function stopSpinIntro()
    if spinConn then
        spinConn:Disconnect()
        spinConn = nil
    end
    if spinJoint and spinJoint.Parent and spinOriginalC0 then
        spinJoint.C0 = spinOriginalC0
    end
    spinJoint = nil
    spinOriginalC0 = nil
end

local function spinIntro()
    stopSpinIntro()
    if not SpinEnabled then return end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- Busca el Motor6D que une el HumanoidRootPart con el cuerpo (R6 y R15)
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("Motor6D") and v.Part0 == hrp then
            spinJoint = v
            break
        end
    end
    if not spinJoint then return end

    spinOriginalC0 = spinJoint.C0
    local angle = 0

    spinConn = RunService.RenderStepped:Connect(function(dt)
        if not SpinEnabled or not spinJoint or not spinJoint.Parent then
            stopSpinIntro()
            return
        end

        -- giro siempre horizontal (eje Y)
        angle = (angle + SPIN_SPEED * dt) % (math.pi * 2)
        spinJoint.C0 = spinOriginalC0 * CFrame.Angles(0, angle, 0)
    end)
end

-- ==========================================================
-- SUPER JUMP
-- ==========================================================
local SuperJumpEnabled = false
local SuperJumpForce = 150   -- velocidad vertical en studs/s (150 ≈ 57 studs de altura)
local jumpConn = nil

jumpConn = UserInputService.JumpRequest:Connect(function()
    if not SuperJumpEnabled or FlyEnabled then return end

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) or hum.Health <= 0 then return end

    -- Sin revisar el suelo: puedes volver a saltar en el aire, infinitas veces

    -- Espera un frame para que el salto normal no pise nuestra velocidad
    task.spawn(function()
        RunService.Heartbeat:Wait()
        if hrp.Parent then
            local v = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(v.X, SuperJumpForce, v.Z)
        end
    end)
end)

-- ==========================================================
-- FAST ATTACK DRAGONSTORM (AUTOMÁTICO, APUNTA SOLO)
-- ==========================================================
local GunFastEnabled = false
local GunFastRunning = true
local GunAttackPlayers = true
local GunAttackNPCs = true
local GunAttackRange = 1500
local GunMethod = "Mantener click (Gatling)"   -- o "Click rápido (Activate)"
local DragonAutoAim = true                     -- apunta solo al enemigo más cercano
local gunHolding = false
local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

-- Estado del auto-apuntado (lo lee el hook)
local dragonAlive = true
local dragonHooksInstalled = false
local DragonAimPos = nil
local DragonAimPart = nil
local DragonTool = nil

local dragonHookOk = type(hookmetamethod) == "function"
    and type(newcclosure) == "function"
    and type(getnamecallmethod) == "function"
    and type(checkcaller) == "function"

local function installDragonHooks()
    if dragonHooksInstalled or not dragonHookOk then return end
    dragonHooksInstalled = true

    -- Si el disparo lee Mouse.Hit / Mouse.Target, apunta al enemigo
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if dragonAlive and DragonAimPos and self == Mouse and not checkcaller() then
            if key == "Hit" then
                return CFrame.new(DragonAimPos)
            elseif key == "Target" then
                return DragonAimPart
            end
        end
        return oldIndex(self, key)
    end))

    -- Si el disparo manda una posición o dirección al servidor, también se corrige
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()

        if dragonAlive and DragonAimPos and DragonTool
            and (method == "FireServer" or method == "InvokeServer")
            and not checkcaller() then

            local fromTool = typeof(self) == "Instance" and self:IsDescendantOf(DragonTool)
            if fromTool then
                local args = table.pack(...)
                local myChar = LocalPlayer.Character
                local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
                local target = DragonAimPos
                local changed = false

                for i = 1, args.n do
                    local v = args[i]
                    if typeof(v) == "Vector3" then
                        local mag = v.Magnitude
                        if mag > 0.98 and mag < 1.02 then
                            -- vector unitario = dirección
                            if myHRP then
                                local dir = target - myHRP.Position
                                if dir.Magnitude > 0 then
                                    args[i] = dir.Unit
                                    changed = true
                                end
                            end
                        else
                            -- posición
                            args[i] = target
                            changed = true
                        end
                    end
                end

                if changed then
                    if type(setnamecallmethod) == "function" then
                        setnamecallmethod(method)
                    end
                    return oldNamecall(self, table.unpack(args, 1, args.n))
                end
            end
        end

        if type(setnamecallmethod) == "function" then
            setnamecallmethod(method)
        end
        return oldNamecall(self, ...)
    end))
end

local function gunReleaseClick()
    if gunHolding and VirtualInputManager then
        local pos = UserInputService:GetMouseLocation()
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
        end)
    end
    gunHolding = false
end

local function getNearestGunTarget(myPos)
    local bestPart = nil
    local bestDist = GunAttackRange

    local function consider(model)
        local hum = model:FindFirstChildOfClass("Humanoid")
        local part = model:FindFirstChild("HumanoidRootPart")
        if not hum or not part or hum.Health <= 0 then return end
        local d = (part.Position - myPos).Magnitude
        if d <= bestDist then
            bestDist = d
            bestPart = part
        end
    end

    if GunAttackPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                consider(plr.Character)
            end
        end
    end

    if GunAttackNPCs then
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, model in ipairs(enemies:GetChildren()) do
                if model:IsA("Model") then
                    consider(model)
                end
            end
        end
    end

    return bestPart
end

-- Dragonstorm tiene M1 mantenible (tipo Gatling): dispara solo mientras haya un enemigo en rango
task.spawn(function()
    while GunFastRunning do
        task.wait(0.01)

        local active = false

        if GunFastEnabled then
            pcall(function()
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local tool = char and char:FindFirstChildOfClass("Tool")
                if not (hrp and tool) then return end
                if not tool.Name:lower():find("dragonstorm") then return end

                local part = getNearestGunTarget(hrp.Position)
                if not part then return end

                active = true
                DragonTool = tool

                -- Apunta solo al enemigo (con un poco de predicción de movimiento)
                if DragonAutoAim and dragonHooksInstalled then
                    DragonAimPart = part
                    DragonAimPos = part.Position + (part.AssemblyLinearVelocity * 0.1)
                end

                if GunMethod == "Click rápido (Activate)" then
                    tool:Activate()
                elseif VirtualInputManager and not gunHolding then
                    local pos = UserInputService:GetMouseLocation()
                    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                    gunHolding = true
                end
            end)
        end

        if not active then
            DragonAimPos = nil
            DragonAimPart = nil
            DragonTool = nil
        end

        -- Sin objetivo (o cambiaste de método): suelta el click
        if gunHolding and (not active or GunMethod == "Click rápido (Activate)") then
            pcall(gunReleaseClick)
        end
    end

    pcall(gunReleaseClick)
end)

-- ==========================================================
-- INTERFAZ RAYFIELD - PESTAÑA PRINCIPAL
-- ==========================================================
local MainTab = Window:CreateTab("Principal", "swords")

MainTab:CreateSection("Magnet de NPCs")

MainTab:CreateToggle({
    Name = "Magnet de NPCs (debajo de mí)",
    CurrentValue = false,
    Flag = "NPCMagnetToggle",
    Callback = function(Value)
        NPC_MAGNET_ENABLED = Value
        if Value then
            lastCacheRefresh = 0
        end
    end,
})

MainTab:CreateSlider({
    Name = "Altura del Magnet (- abajo / + arriba)",
    Range = {-60, 30},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = -8,
    Flag = "NPCMagnetHeight",
    Callback = function(Value)
        NPC_MAGNET_HEIGHT = Value
    end,
})

MainTab:CreateSlider({
    Name = "Radio de Búsqueda de NPCs",
    Range = {50, 800},
    Increment = 25,
    Suffix = " studs",
    CurrentValue = 350,
    Flag = "NPCRadiusSlider",
    Callback = function(Value)
        NPC_SEARCH_RADIUS = Value
    end,
})

MainTab:CreateSection("Configuración de Barco")

MainTab:CreateButton({
    Name = "Guardar Posición del Barco",
    Callback = function()
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            BoatCFrame = char.HumanoidRootPart.CFrame
            Notify("Barco Guardado", "Posición guardada exitosamente.", 2.5)
        end
    end,
})

MainTab:CreateSlider({
    Name = "Poca Vida para Barco",
    Range = {5, 60},
    Increment = 5,
    Suffix = "%",
    CurrentValue = 25,
    Flag = "LowHealthSlider",
    Callback = function(Value)
        LOW_HEALTH_PERCENT = Value
    end,
})

MainTab:CreateSection("Opciones de TP y Mouse")

MainTab:CreateSlider({
    Name = "Hitbox del Mouse",
    Range = {50, 600},
    Increment = 25,
    Suffix = " px",
    CurrentValue = 250,
    Flag = "HitboxSlider",
    Callback = function(Value)
        MOUSE_HITBOX_RADIUS = Value
    end,
})

MainTab:CreateSlider({
    Name = "Distancia Máxima",
    Range = {50, 5000},
    Increment = 25,
    Suffix = " m",
    CurrentValue = 1500,
    Flag = "MaxDistSlider",
    Callback = function(Value)
        MAX_DISTANCE = Value
    end,
})

MainTab:CreateSection("Super Jump")

MainTab:CreateToggle({
    Name = "Super Jump",
    CurrentValue = false,
    Flag = "SuperJumpToggle",
    Callback = function(Value)
        SuperJumpEnabled = Value
    end,
})

MainTab:CreateSlider({
    Name = "Fuerza del Salto",
    Range = { 50, 600 },
    Increment = 10,
    Suffix = " studs/s",
    CurrentValue = 150,
    Flag = "SuperJumpForceSlider",
    Callback = function(Value)
        SuperJumpForce = Value
    end,
})

-- ==========================================================
-- AUTO DEFENSA (SE ALEJA CUANDO TIENES POCA VIDA)
-- ==========================================================
MainTab:CreateSection("Auto Defensa")

local AutoDefenseEnabled = false
local AutoDefenseThreshold = 35     -- % de vida para activarse
local AutoDefenseDistance = 500     -- studs que se aleja
local AutoDefenseSpeed = 300        -- studs/s (movimiento gradual, no un salto instantáneo)
local autoDefConn = nil
local autoDefEscaping = false
local autoDefTriggered = false

local function findNearestThreat(myPos)
    local bestPart, bestDist = nil, 500

    local function consider(model)
        local hum = model:FindFirstChildOfClass("Humanoid")
        local part = model:FindFirstChild("HumanoidRootPart")
        if not hum or not part or hum.Health <= 0 then return end
        local d = (part.Position - myPos).Magnitude
        if d < bestDist then
            bestDist = d
            bestPart = part
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            consider(plr.Character)
        end
    end

    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then
        for _, model in ipairs(enemies:GetChildren()) do
            if model:IsA("Model") then
                consider(model)
            end
        end
    end

    return bestPart
end

local function runEscape()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end

    -- Si estás en un barco, se mueve el barco entero
    local mover = hrp
    if hum.SeatPart then
        mover = hum.SeatPart.AssemblyRootPart or hum.SeatPart
    end

    -- Dirección: lejos del enemigo más cercano (si no hay ninguno, hacia atrás)
    local threat = findNearestThreat(hrp.Position)
    local dir
    if threat then
        dir = hrp.Position - threat.Position
    else
        dir = -hrp.CFrame.LookVector
    end
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
    dir = dir.Unit

    autoDefEscaping = true
    Notify("Auto Defensa", "Poca vida: alejándote del peligro.", 2.5)

    local travelled = 0
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        local currentChar = LocalPlayer.Character
        local currentHRP = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
        local currentHum = currentChar and currentChar:FindFirstChildOfClass("Humanoid")

        if not AutoDefenseEnabled or not currentHRP or not currentHum or currentHum.Health <= 0
            or travelled >= AutoDefenseDistance or not mover.Parent then
            conn:Disconnect()
            autoDefEscaping = false
            if mover.Parent then
                mover.AssemblyLinearVelocity = Vector3.zero
            end
            return
        end

        -- Avanza de a poco (no es un salto instantáneo) y sube un poco al inicio
        local step = math.min(AutoDefenseSpeed * dt, AutoDefenseDistance - travelled)
        local rise = (travelled < 100) and (60 * step / 100) or 0
        travelled = travelled + step

        local cf = mover.CFrame
        mover.CFrame = cf + dir * step + Vector3.new(0, rise, 0)
        mover.AssemblyLinearVelocity = Vector3.zero
    end)
end

local function setAutoDefense(state)
    AutoDefenseEnabled = state
    autoDefTriggered = false

    if autoDefConn then
        autoDefConn:Disconnect()
        autoDefConn = nil
    end

    if state then
        autoDefConn = RunService.Heartbeat:Connect(function()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 or hum.MaxHealth <= 0 then return end

            local pct = (hum.Health / hum.MaxHealth) * 100
            if pct <= AutoDefenseThreshold then
                if not autoDefTriggered and not autoDefEscaping then
                    autoDefTriggered = true
                    task.spawn(runEscape)
                end
            elseif pct > AutoDefenseThreshold + 10 then
                autoDefTriggered = false -- se vuelve a armar cuando te recuperas
            end
        end)
    end
end

MainTab:CreateToggle({
    Name = "Auto Defensa",
    CurrentValue = false,
    Flag = "AutoDefenseToggle",
    Callback = function(Value)
        setAutoDefense(Value)
    end,
})

MainTab:CreateSlider({
    Name = "Vida para activarse",
    Range = { 5, 80 },
    Increment = 1,
    Suffix = "%",
    CurrentValue = 35,
    Flag = "AutoDefenseThresholdSlider",
    Callback = function(Value)
        AutoDefenseThreshold = Value
    end,
})

MainTab:CreateSlider({
    Name = "Distancia de escape",
    Range = { 100, 2000 },
    Increment = 50,
    Suffix = " studs",
    CurrentValue = 500,
    Flag = "AutoDefenseDistanceSlider",
    Callback = function(Value)
        AutoDefenseDistance = Value
    end,
})

MainTab:CreateSlider({
    Name = "Velocidad de escape",
    Range = { 100, 600 },
    Increment = 25,
    Suffix = " studs/s",
    CurrentValue = 300,
    Flag = "AutoDefenseSpeedSlider",
    Callback = function(Value)
        AutoDefenseSpeed = Value
    end,
})

-- ==========================================================
-- INTERFAZ RAYFIELD - PESTAÑA COMBATE (FAST ATTACK)
-- ==========================================================
local CombatTab = Window:CreateTab("Combate", "zap")

CombatTab:CreateSection("Fast Attack")

CombatTab:CreateToggle({
    Name = "Activar Fast Attack",
    CurrentValue = false,
    Flag = "FastAttackToggle",
    Callback = function(Value)
        FastAttackEnabled = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Atacar Jugadores (PvP)",
    CurrentValue = true,
    Flag = "AttackPlayersToggle",
    Callback = function(Value)
        AttackPlayers = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Rango de Ataque",
    Range = {30, 1500},
    Increment = 5,
    Suffix = " studs",
    CurrentValue = 120,
    Flag = "RangeSlider",
    Callback = function(Value)
        AttackRange = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Rango largo (acercarse al objetivo)",
    CurrentValue = false,
    Flag = "LongRangeToggle",
    Callback = function(Value)
        LongRangeEnabled = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Distancia a la que me quedo del objetivo",
    Range = { 5, 100 },
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 30,
    Flag = "LongRangeStandSlider",
    Callback = function(Value)
        LongRangeStand = Value
    end,
})

CombatTab:CreateSection("Fast Attack (Dragonstorm)")

CombatTab:CreateToggle({
    Name = "Activar Fast Attack Dragonstorm",
    CurrentValue = false,
    Flag = "GunFastToggle",
    Callback = function(Value)
        if Value and DragonAutoAim then
            if dragonHookOk then
                installDragonHooks()
            else
                Notify("Dragonstorm", "Tu executor no soporta hookmetamethod: disparará hacia tu cursor.", 5)
            end
        end
        GunFastEnabled = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Apuntar solo al enemigo",
    CurrentValue = true,
    Flag = "DragonAutoAimToggle",
    Callback = function(Value)
        DragonAutoAim = Value
        if Value and GunFastEnabled and dragonHookOk then
            installDragonHooks()
        end
        if not Value then
            DragonAimPos = nil
            DragonAimPart = nil
        end
    end,
})

CombatTab:CreateDropdown({
    Name = "Método de disparo",
    Options = { "Mantener click (Gatling)", "Click rápido (Activate)" },
    CurrentOption = { "Mantener click (Gatling)" },
    MultipleOptions = false,
    Flag = "GunMethodDropdown",
    Callback = function(option)
        if type(option) == "table" then option = option[1] end
        GunMethod = option or "Mantener click (Gatling)"
    end,
})

CombatTab:CreateToggle({
    Name = "Dragonstorm: Atacar Jugadores",
    CurrentValue = true,
    Flag = "GunPlayersToggle",
    Callback = function(Value)
        GunAttackPlayers = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Dragonstorm: Atacar NPCs",
    CurrentValue = true,
    Flag = "GunNPCsToggle",
    Callback = function(Value)
        GunAttackNPCs = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Dragonstorm: Rango de Ataque",
    Range = { 50, 3000 },
    Increment = 50,
    Suffix = " studs",
    CurrentValue = 1500,
    Flag = "GunRangeSlider",
    Callback = function(Value)
        GunAttackRange = Value
    end,
})

CombatTab:CreateParagraph({
    Title = "Cómo usarlo",
    Content = "Equipa la Dragonstorm y activa el toggle. Dispara sola, muy rápido, al enemigo más cercano dentro del rango, sin que tengas que apuntar. Cierra el menú (tecla K) para que el click automático no caiga sobre la interfaz."
})

-- ==========================================================
-- HITBOX EXPANDER
-- ==========================================================
local HitboxEnabled = false
local HitboxSize = 40
local HitboxTransparency = 0.7
local HitboxPlayers = true
local HitboxNPCs = false
local hitboxOriginals = setmetatable({}, { __mode = "k" })
local hitboxConn = nil
local lastHitboxTick = 0
local HitboxShowBox = true
local HitboxBoxTransparency = 0.6
local hitboxBoxes = setmetatable({}, { __mode = "k" })

local function removeHitboxBox(part)
    local box = hitboxBoxes[part]
    if box then
        pcall(function() box:Destroy() end)
        hitboxBoxes[part] = nil
    end
end

local function restoreHitboxPart(part)
    removeHitboxBox(part)
    local orig = hitboxOriginals[part]
    if orig and part.Parent then
        pcall(function()
            part.Size = orig.Size
            part.Transparency = orig.Transparency
            part.CanCollide = orig.CanCollide
            part.CanTouch = orig.CanTouch
            part.CanQuery = orig.CanQuery
        end)
    end
    hitboxOriginals[part] = nil
end

local function restoreHitboxes()
    for part in pairs(hitboxOriginals) do
        restoreHitboxPart(part)
    end
end

local function expandHitbox(model, active, color)
    local hum = model:FindFirstChildOfClass("Humanoid")
    local part = model:FindFirstChild("HumanoidRootPart")
    if not hum or not part or hum.Health <= 0 then return end

    if not hitboxOriginals[part] then
        hitboxOriginals[part] = {
            Size = part.Size,
            Transparency = part.Transparency,
            CanCollide = part.CanCollide,
            CanTouch = part.CanTouch,
            CanQuery = part.CanQuery,
        }
    end

    part.Size = Vector3.new(HitboxSize, HitboxSize, HitboxSize)
    part.Transparency = HitboxTransparency
    part.CanCollide = false
    part.CanTouch = true
    part.CanQuery = true

    -- Caja visible del hitbox (se ve a través de paredes)
    if HitboxShowBox then
        local box = hitboxBoxes[part]
        if not box or not box.Parent then
            box = Instance.new("BoxHandleAdornment")
            box.Name = "PatoHitboxBox"
            box.Adornee = part
            box.AlwaysOnTop = true
            box.ZIndex = 5
            box.Parent = part
            hitboxBoxes[part] = box
        end
        box.Size = part.Size
        box.Color3 = color
        box.Transparency = HitboxBoxTransparency
    else
        removeHitboxBox(part)
    end

    active[part] = true
end

local function updateHitboxes()
    local active = {}

    if HitboxPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                expandHitbox(plr.Character, active, PLAYER_COLOR)
            end
        end
    end

    if HitboxNPCs then
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, model in ipairs(enemies:GetChildren()) do
                if model:IsA("Model") then
                    expandHitbox(model, active, NPC_COLOR)
                end
            end
        end
    end

    -- Lo que ya no está activo (apagaste jugadores/NPCs, murió, etc.) vuelve a la normalidad
    for part in pairs(hitboxOriginals) do
        if not active[part] then
            restoreHitboxPart(part)
        end
    end
end

local function setHitbox(state)
    HitboxEnabled = state
    if hitboxConn then
        hitboxConn:Disconnect()
        hitboxConn = nil
    end

    if state then
        hitboxConn = RunService.Heartbeat:Connect(function()
            if tick() - lastHitboxTick < 0.1 then return end
            lastHitboxTick = tick()
            pcall(updateHitboxes)
        end)
    else
        restoreHitboxes()
    end
end

local HitboxTab = Window:CreateTab("Hitbox", "box")

HitboxTab:CreateSection("Hitbox Expander")

HitboxTab:CreateToggle({
    Name = "Activar Hitbox Expander",
    CurrentValue = false,
    Flag = "HitboxToggle",
    Callback = function(Value)
        setHitbox(Value)
    end,
})

HitboxTab:CreateSlider({
    Name = "Tamaño del Hitbox",
    Range = { 3, 500 },
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 40,
    Flag = "HitboxSizeSlider",
    Callback = function(Value)
        HitboxSize = Value
    end,
})

HitboxTab:CreateSlider({
    Name = "Transparencia del Hitbox",
    Range = { 0, 1 },
    Increment = 0.05,
    CurrentValue = 0.7,
    Flag = "HitboxTransparencySlider",
    Callback = function(Value)
        HitboxTransparency = Value
    end,
})

HitboxTab:CreateToggle({
    Name = "Mostrar caja del Hitbox (ESP)",
    CurrentValue = true,
    Flag = "HitboxBoxToggle",
    Callback = function(Value)
        HitboxShowBox = Value
    end,
})

HitboxTab:CreateSlider({
    Name = "Transparencia de la caja",
    Range = { 0, 1 },
    Increment = 0.05,
    CurrentValue = 0.6,
    Flag = "HitboxBoxTransparencySlider",
    Callback = function(Value)
        HitboxBoxTransparency = Value
    end,
})

HitboxTab:CreateToggle({
    Name = "Hitbox: Todos los jugadores",
    CurrentValue = true,
    Flag = "HitboxPlayersToggle",
    Callback = function(Value)
        HitboxPlayers = Value
    end,
})

HitboxTab:CreateToggle({
    Name = "Hitbox: NPCs",
    CurrentValue = false,
    Flag = "HitboxNPCsToggle",
    Callback = function(Value)
        HitboxNPCs = Value
    end,
})

HitboxTab:CreateParagraph({
    Title = "Con el Fast Attack",
    Content = "El Fast Attack suma la mitad del tamaño del hitbox a su rango de golpe. Con un hitbox de 100, alcanza 50 studs más lejos. Sube el tamaño de a poco y combínalo con el slider \"Rango de Ataque\" de la pestaña Combate."
})

-- ==========================================================
-- INTERFAZ RAYFIELD - PESTAÑA ESP
-- ==========================================================
local ESPTab = Window:CreateTab("ESP", "eye")

ESPTab:CreateSection("Líneas de ESP (sin límite de distancia)")

ESPTab:CreateToggle({
    Name = "ESP Jugadores (línea roja)",
    CurrentValue = false,
    Flag = "ESPPlayersToggle",
    Callback = function(Value)
        if Value and not Drawing then
            Notify("ESP", "Tu executor no soporta la librería Drawing.", 4)
            return
        end
        ESPPlayersEnabled = Value
        updateESPState()
    end,
})

ESPTab:CreateToggle({
    Name = "ESP NPCs (línea azul)",
    CurrentValue = false,
    Flag = "ESPNPCsToggle",
    Callback = function(Value)
        if Value and not Drawing then
            Notify("ESP", "Tu executor no soporta la librería Drawing.", 4)
            return
        end
        ESPNPCsEnabled = Value
        lastEspNpcRefresh = 0
        updateESPState()
    end,
})

ESPTab:CreateSection("Opciones")

ESPTab:CreateToggle({
    Name = "Mostrar Nombres",
    CurrentValue = true,
    Flag = "ESPNamesToggle",
    Callback = function(Value)
        ESPNames = Value
    end,
})

ESPTab:CreateToggle({
    Name = "Mostrar Distancia",
    CurrentValue = true,
    Flag = "ESPDistanceToggle",
    Callback = function(Value)
        ESPDistance = Value
    end,
})

ESPTab:CreateToggle({
    Name = "Mostrar Vida (barra verde)",
    CurrentValue = true,
    Flag = "ESPHealthToggle",
    Callback = function(Value)
        ESPShowHealth = Value
    end,
})

ESPTab:CreateToggle({
    Name = "Mostrar Energía (barra azul)",
    CurrentValue = true,
    Flag = "ESPEnergyToggle",
    Callback = function(Value)
        ESPShowEnergy = Value
    end,
})

ESPTab:CreateToggle({
    Name = "Mostrar Ken Haki",
    CurrentValue = true,
    Flag = "ESPKenToggle",
    Callback = function(Value)
        ESPShowKen = Value
    end,
})

ESPTab:CreateSlider({
    Name = "Grosor de la Línea",
    Range = {1, 5},
    Increment = 0.5,
    Suffix = " px",
    CurrentValue = 1.5,
    Flag = "ESPThicknessSlider",
    Callback = function(Value)
        ESPLineThickness = Value
    end,
})

-- ==========================================================
-- INTERFAZ RAYFIELD - PESTAÑA JUGADORES (LISTA DEL SERVIDOR)
-- ==========================================================
local PlayersTab = Window:CreateTab("Jugadores", "users")

local PlayerListParagraph = nil
local PlayerInfoParagraph = nil
local PlayerListDropdown = nil
local SelectedListPlayer = nil

local function getPlayerLevel(plr)
    local data = plr:FindFirstChild("Data")
    local lvl = data and data:FindFirstChild("Level")
    return lvl and lvl.Value or nil
end

local function buildPlayerListText()
    local list = Players:GetPlayers()
    table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)

    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local lines = {}

    for i, plr in ipairs(list) do
        local line = i .. ". " .. plr.DisplayName .. " (@" .. plr.Name .. ")"

        local lvl = getPlayerLevel(plr)
        if lvl then line = line .. " | Lvl " .. tostring(lvl) end

        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hum then
            line = line .. " | Vida " .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth)
        else
            line = line .. " | sin personaje"
        end

        if plr == LocalPlayer then
            line = line .. " | (tú)"
        elseif hrp and myHRP then
            line = line .. " | " .. math.floor((hrp.Position - myHRP.Position).Magnitude) .. " studs"
        end

        lines[#lines + 1] = line
    end

    return #list, table.concat(lines, "\n")
end

local function buildPlayerInfo(plr)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add("Nombre: " .. plr.DisplayName .. " (@" .. plr.Name .. ")")
    local lvl = getPlayerLevel(plr)
    add("Nivel: " .. (lvl and tostring(lvl) or "?"))

    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (char and hum) then
        add("Estado: sin personaje cargado")
        return table.concat(lines, "\n")
    end

    add("Vida: " .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth))

    local cur, max = getEnergyInfo(char)
    if cur then
        add("Energía: " .. math.floor(cur) .. "/" .. (max and tostring(math.floor(max)) or "?"))
    else
        add("Energía: ?")
    end

    local ken = getKenCount(char, plr)
    add("Ken Haki: " .. (ken ~= nil and tostring(ken) or "?"))

    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if hrp and myHRP and plr ~= LocalPlayer then
        add("Distancia: " .. math.floor((hrp.Position - myHRP.Position).Magnitude) .. " studs")
    end

    -- Datos crudos: sirven para saber cómo se llaman realmente la energía y el ken
    add("--- Datos crudos del personaje ---")
    local n = 0
    for k, v in pairs(char:GetAttributes()) do
        if n < 25 then
            add(tostring(k) .. " = " .. tostring(v))
            n = n + 1
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("ValueBase") and n < 25 then
            add(child.Name .. " = " .. tostring(child.Value))
            n = n + 1
        end
    end

    return table.concat(lines, "\n")
end

local function refreshPlayerList()
    local count, text = buildPlayerListText()
    if PlayerListParagraph then
        PlayerListParagraph:Set({
            Title = "Jugadores en el servidor: " .. count,
            Content = text
        })
    end

    if PlayerListDropdown then
        local names = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then table.insert(names, plr.Name) end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        if #names == 0 then names = { "Ninguno" } end
        PlayerListDropdown:Refresh(names)
        SelectedListPlayer = nil
    end
end

PlayersTab:CreateSection("Lista del servidor")

PlayersTab:CreateButton({
    Name = "Actualizar Lista",
    Callback = function()
        refreshPlayerList()
        Notify("Jugadores", "Lista actualizada.", 2)
    end,
})

PlayerListParagraph = PlayersTab:CreateParagraph({
    Title = "Jugadores en el servidor",
    Content = "Cargando..."
})

PlayersTab:CreateSection("Info de un jugador")

PlayerListDropdown = PlayersTab:CreateDropdown({
    Name = "Elegir Jugador",
    Options = { "Ninguno" },
    CurrentOption = { "Ninguno" },
    MultipleOptions = false,
    Flag = "PlayerListDropdown",
    Callback = function(option)
        if type(option) == "table" then option = option[1] end
        SelectedListPlayer = (option and option ~= "Ninguno") and option or nil
    end,
})

PlayersTab:CreateButton({
    Name = "Ver Info del Jugador",
    Callback = function()
        if not SelectedListPlayer then
            Notify("Jugadores", "Elige un jugador primero (y actualiza la lista si no aparece).", 3)
            return
        end
        local plr = Players:FindFirstChild(SelectedListPlayer)
        if not plr then
            Notify("Jugadores", "Ese jugador ya no está en el servidor. Actualiza la lista.", 3)
            return
        end
        if PlayerInfoParagraph then
            PlayerInfoParagraph:Set({
                Title = "Info de " .. plr.Name,
                Content = buildPlayerInfo(plr)
            })
        end
    end,
})

PlayerInfoParagraph = PlayersTab:CreateParagraph({
    Title = "Info del jugador",
    Content = "Elige un jugador y presiona \"Ver Info del Jugador\"."
})

refreshPlayerList()

-- ==========================================================
-- INTERFAZ RAYFIELD - PESTAÑA FLY
-- ==========================================================
local FlyTab = Window:CreateTab("Fly", "plane")

FlyTab:CreateSection("Volar (tecla P)")

FlyToggle = FlyTab:CreateToggle({
    Name = "Activar Fly",
    CurrentValue = false,
    Flag = "FlyToggle",
    Callback = function(Value)
        setFly(Value)
    end,
})

FlyTab:CreateSlider({
    Name = "Velocidad de Vuelo",
    Range = {10, 300},
    Increment = 5,
    Suffix = " studs/s",
    CurrentValue = 60,
    Flag = "FlySpeedSlider",
    Callback = function(Value)
        FlySpeed = Value
    end,
})

FlyTab:CreateToggle({
    Name = "Sentarse solo en barcos cercanos",
    CurrentValue = true,
    Flag = "AutoSitBoatsToggle",
    Callback = function(Value)
        AutoSitBoats = Value
    end,
})

FlyTab:CreateParagraph({
    Title = "Controles",
    Content = "W/A/S/D: moverte hacia donde mira la cámara. Espacio: subir. Ctrl izquierdo: bajar. P: activar/desactivar. Sentado en un barco, el fly mueve el barco entero (Espacio sube sin bajarte)."
})

-- ==========================================================
-- INTERFAZ RAYFIELD - PESTAÑA MISC (AUTO V4 + DASH LENGTH)
-- ==========================================================
local MiscTab = Window:CreateTab("Misc", "gem")

MiscTab:CreateSection("Auto V4")

MiscTab:CreateToggle({
    Name = "Auto V4",
    CurrentValue = false,
    Flag = "AutoV4Toggle",
    Callback = function(state)
        autoV4 = state
        if v4Connection then
            task.cancel(v4Connection)
            v4Connection = nil
        end

        if state then
            v4Connection = task.spawn(function()
                while autoV4 do
                    task.wait(0.5)
                    pcall(function()
                        local awakening = LocalPlayer.Backpack:FindFirstChild("Awakening")
                            or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Awakening"))
                        if awakening then
                            awakening:WaitForChild("RemoteFunction"):InvokeServer(true)
                        end
                    end)
                end
            end)
        end
    end,
})

MiscTab:CreateSection("Unbreakable")

local unbreakable = false
local unbreakableLoop = nil

MiscTab:CreateToggle({
    Name = "Unbreakable (no cancelan tus habilidades)",
    CurrentValue = false,
    Flag = "UnbreakableToggle",
    Callback = function(state)
        unbreakable = state
        if unbreakableLoop then
            task.cancel(unbreakableLoop)
            unbreakableLoop = nil
        end

        if state then
            unbreakableLoop = task.spawn(function()
                while unbreakable do
                    local char = LocalPlayer.Character
                    if char and char:GetAttribute("UnbreakableAll") ~= true then
                        char:SetAttribute("UnbreakableAll", true)
                    end
                    task.wait(0.1)
                end
            end)
        else
            local char = LocalPlayer.Character
            if char then
                char:SetAttribute("UnbreakableAll", false)
            end
        end
    end,
})

MiscTab:CreateSection("Auto Ken")

local autoKen = false
local kenLoop = nil
local KenInterval = 2

MiscTab:CreateToggle({
    Name = "Auto Ken (esquiva habilidades)",
    CurrentValue = false,
    Flag = "AutoKenToggle",
    Callback = function(state)
        autoKen = state
        if kenLoop then
            task.cancel(kenLoop)
            kenLoop = nil
        end

        if state then
            kenLoop = task.spawn(function()
                while autoKen do
                    pcall(function()
                        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                        local commE = remotes and remotes:FindFirstChild("CommE")
                        local char = LocalPlayer.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if commE and hum and hum.Health > 0 then
                            commE:FireServer("Ken", true)
                        end
                    end)
                    task.wait(KenInterval)
                end
            end)
        end
    end,
})

MiscTab:CreateSlider({
    Name = "Cada cuánto reactivar el Ken",
    Range = { 0.5, 10 },
    Increment = 0.5,
    Suffix = " s",
    CurrentValue = 2,
    Flag = "AutoKenInterval",
    Callback = function(Value)
        KenInterval = Value
    end,
})

MiscTab:CreateSection("Dash Length")

MiscTab:CreateToggle({
    Name = "Dash Length",
    CurrentValue = false,
    Flag = "DashLengthToggle",
    Callback = function(state)
        DashEnabled = state
        if DashConnection then
            task.cancel(DashConnection)
            DashConnection = nil
        end

        if state then
            DashConnection = task.spawn(function()
                while DashEnabled do
                    task.wait(0.1)
                    local character = LocalPlayer.Character
                    if character and character:GetAttribute("DashLength") ~= DashLenghtDistance420 then
                        character:SetAttribute("DashLength", DashLenghtDistance420)
                        character:SetAttribute("DashLengthAir", DashLenghtDistance420)
                    end
                end
            end)
        else
            local character = LocalPlayer.Character
            if character then
                character:SetAttribute("DashLength", 1)
                character:SetAttribute("DashLengthAir", 1)
            end
        end
    end,
})

MiscTab:CreateDropdown({
    Name = "Dash Length Value",
    Options = {"180", "120", "90", "60", "35", "5"},
    CurrentOption = {"5"},
    MultipleOptions = false,
    Flag = "DashLenght12",
    Callback = function(option)
        if type(option) == "table" then option = option[1] end
        DashLenghtDistance420 = tonumber(option) or 120
    end,
})

MiscTab:CreateSection("Velocidad (moverte más rápido)")

local WalkSpeedEnabled = false
local WalkSpeedValue = 16
local WalkMethod = "WalkSpeed"
local walkConn = nil

local function setWalkSpeed(state)
    WalkSpeedEnabled = state
    if walkConn then
        walkConn:Disconnect()
        walkConn = nil
    end

    if state then
        walkConn = RunService.Heartbeat:Connect(function(dt)
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not (hum and hrp) then return end

            if WalkMethod == "WalkSpeed" then
                if hum.WalkSpeed ~= WalkSpeedValue then
                    hum.WalkSpeed = WalkSpeedValue
                end
            else
                -- CFrame: suma movimiento extra hacia donde caminas (sirve si el juego resetea WalkSpeed)
                if not FlyEnabled and not hum.SeatPart and hum.MoveDirection.Magnitude > 0 then
                    local extra = math.max(WalkSpeedValue - 16, 0)
                    hrp.CFrame = hrp.CFrame + hum.MoveDirection * extra * dt
                end
            end
        end)
    else
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end

MiscTab:CreateToggle({
    Name = "Velocidad",
    CurrentValue = false,
    Flag = "WalkSpeedToggle",
    Callback = function(state)
        setWalkSpeed(state)
    end,
})

MiscTab:CreateSlider({
    Name = "Velocidad (16 = normal)",
    Range = { 16, 300 },
    Increment = 2,
    Suffix = " studs/s",
    CurrentValue = 16,
    Flag = "WalkSpeedSlider",
    Callback = function(Value)
        WalkSpeedValue = Value
    end,
})

MiscTab:CreateDropdown({
    Name = "Método de velocidad",
    Options = { "WalkSpeed", "CFrame (más compatible)" },
    CurrentOption = { "WalkSpeed" },
    MultipleOptions = false,
    Flag = "WalkMethodDropdown",
    Callback = function(option)
        if type(option) == "table" then option = option[1] end
        WalkMethod = (option and option:find("CFrame")) and "CFrame" or "WalkSpeed"

        -- Al pasar a CFrame, devuelve el WalkSpeed a lo normal para no sumar las dos velocidades
        if WalkMethod == "CFrame" then
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = 16 end
        end
    end,
})

MiscTab:CreateSection("Giro del personaje (visual)")

MiscTab:CreateToggle({
    Name = "Girar siempre (horizontal)",
    CurrentValue = true,
    Flag = "SpinToggle",
    Callback = function(Value)
        SpinEnabled = Value
        if Value then
            spinIntro()
        else
            stopSpinIntro()
        end
    end,
})

MiscTab:CreateSlider({
    Name = "Velocidad de giro",
    Range = { 1, 60 },
    Increment = 1,
    Suffix = " rad/s",
    CurrentValue = 14,
    Flag = "SpinSpeedSlider",
    Callback = function(Value)
        SPIN_SPEED = Value
    end,
})

MiscTab:CreateSection("Avisos del servidor")

local JoinLeaveNotify = true

MiscTab:CreateToggle({
    Name = "Avisar cuando un jugador entra o sale",
    CurrentValue = true,
    Flag = "JoinLeaveToggle",
    Callback = function(Value)
        JoinLeaveNotify = Value
    end,
})

local joinConn = Players.PlayerAdded:Connect(function(plr)
    if JoinLeaveNotify and plr ~= LocalPlayer then
        Rayfield:Notify({
            Title = "Jugador entró",
            Content = plr.DisplayName .. " (@" .. plr.Name .. ")",
            Duration = 4,
            Image = "user-plus"
        })
    end
end)

local leaveConn = Players.PlayerRemoving:Connect(function(plr)
    if JoinLeaveNotify and plr ~= LocalPlayer then
        Rayfield:Notify({
            Title = "Jugador salió",
            Content = plr.DisplayName .. " (@" .. plr.Name .. ")",
            Duration = 4,
            Image = "user-minus"
        })
    end
end)

-- ==========================================================
-- PESTAÑA BARCOS (COMPRAR DESDE CUALQUIER LUGAR + ENTRAR/SALIR)
-- ==========================================================
local BOAT_LIST = {
    "Dinghy",
    "PirateSloop",
    "PirateBrigade",
    "PirateGrandBrigade",
    "MarineSloop",
    "MarineBrigade",
    "MarineGrandBrigade",
    "BeastHunter",
}

local SelectedBoat = "PirateBrigade"
local CustomBoatName = nil
local AutoFlyBoat = true
local BuyingBoat = false
local lastBoat = nil
local BoatSpawnHeight = 8   -- altura sobre ti a la que aparece el barco

local function boatOwnerOk(model)
    local owner = model:FindFirstChild("Owner")
    if not owner then return true end -- si el juego no marca dueño, no podemos filtrar
    if owner:IsA("ValueBase") then
        local v = owner.Value
        return v == LocalPlayer or tostring(v) == LocalPlayer.Name
    end
    return true
end

local function findMyBoatSeat()
    -- 1) El último barco que compraste o usaste
    if lastBoat and lastBoat.Parent then
        local seat = lastBoat:FindFirstChildWhichIsA("VehicleSeat", true)
        if seat then return seat end
    end

    local boats = Workspace:FindFirstChild("Boats")
    if not boats then return nil end

    -- 2) Un barco con tu nombre como dueño
    for _, b in ipairs(boats:GetChildren()) do
        local owner = b:FindFirstChild("Owner")
        if owner and owner:IsA("ValueBase") and boatOwnerOk(b) then
            local seat = b:FindFirstChildWhichIsA("VehicleSeat", true)
            if seat then return seat end
        end
    end

    -- 3) Si no hay dueño marcado, el asiento libre más cercano
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local best, bestDist = nil, math.huge
    for _, d in ipairs(boats:GetDescendants()) do
        if d:IsA("VehicleSeat") and d.Occupant == nil then
            local dist = (d.Position - hrp.Position).Magnitude
            if dist < bestDist then
                best, bestDist = d, dist
            end
        end
    end
    return best
end

local function sitIn(seat, hum)
    local ok = pcall(function() seat:Sit(hum) end)
    if not ok then hum.Sit = true end
end

-- Tecla X: salir del barco si estás sentado, o volver a entrar a tu barco
toggleBoatSeat = function()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) or hum.Health <= 0 then return end

    local seat = hum.SeatPart or (hum.Sit and getSeatedPart(hum, hrp)) or nil
    if seat then
        -- SALIR
        lastManualExit = tick()
        lastBoat = seat:FindFirstAncestorOfClass("Model") or lastBoat
        local weld = seat:FindFirstChild("SeatWeld") or hrp:FindFirstChild("SeatWeld")
        if weld then
            pcall(function() weld:Destroy() end)
        end
        hum.Sit = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        return
    end

    -- ENTRAR
    local boatSeat = findMyBoatSeat()
    if not boatSeat then
        Notify("Barcos", "No encontré un barco tuyo. Compra uno con la tecla N.", 3)
        return
    end

    lastManualExit = 0
    hrp.CFrame = boatSeat.CFrame * CFrame.new(0, 2, 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    sitIn(boatSeat, hum)
    lastBoat = boatSeat:FindFirstAncestorOfClass("Model") or lastBoat
end

-- Busca al vendedor de barcos del mar actual
local function findBoatDealer()
    local function isDealer(model)
        local name = model.Name:lower()
        return model:IsA("Model") and (name:find("boat dealer") or name:find("luxury"))
    end

    local npcs = Workspace:FindFirstChild("NPCs")
    if npcs then
        for _, d in ipairs(npcs:GetDescendants()) do
            if isDealer(d) then return d end
        end
    end

    for _, d in ipairs(Workspace:GetDescendants()) do
        if isDealer(d) then return d end
    end
    return nil
end

-- Tecla N: compra el barco elegido desde donde estés, lo trae a ti y te sienta
buyBoatNow = function()
    if BuyingBoat then return end
    BuyingBoat = true

    pcall(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp) or hum.Health <= 0 then return end

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if not commF then
            Notify("Barcos", "No encontré el remote de compra (CommF_).", 4)
            return
        end

        local boatName = CustomBoatName or SelectedBoat
        local origin = hrp.CFrame

        -- Guardamos los barcos que ya existen para detectar el nuevo
        local before = {}
        local boats = Workspace:FindFirstChild("Boats")
        if boats then
            for _, b in ipairs(boats:GetChildren()) do
                before[b] = true
            end
        end

        local function tryBuy()
            return pcall(function()
                return commF:InvokeServer("BuyBoat", boatName)
            end)
        end

        local function waitForNewBoat(timeout)
            local t0 = tick()
            while tick() - t0 < timeout do
                local folder = Workspace:FindFirstChild("Boats")
                if folder then
                    for _, b in ipairs(folder:GetChildren()) do
                        if not before[b] and boatOwnerOk(b) and b:FindFirstChildWhichIsA("VehicleSeat", true) then
                            return b
                        end
                    end
                end
                task.wait(0.2)
            end
            return nil
        end

        -- Intento 1: comprar directo desde donde estás
        local ok, result = tryBuy()
        if not ok then
            Notify("Barcos", "Error al comprar: " .. tostring(result), 4)
            return
        end

        local newBoat = waitForNewBoat(3)
        local movedToDealer = false

        -- Intento 2: si desde lejos no apareció, va al vendedor, compra y se lleva el barco de vuelta
        if not newBoat then
            local dealer = findBoatDealer()
            if dealer then
                Notify("Barcos", "Comprando en el vendedor y trayendo el barco a ti...", 3)
                movedToDealer = true
                hrp.CFrame = dealer:GetPivot() * CFrame.new(0, 3, 6)
                hrp.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.4)
                tryBuy()
                newBoat = waitForNewBoat(4)
            end
        end

        if not newBoat then
            if movedToDealer then
                hrp.CFrame = origin -- vuelve a donde estabas
            end
            Notify("Barcos", "No apareció el barco. Puede que no tengas Beli o el nombre sea otro.", 5)
            return
        end

        local seat = newBoat:FindFirstChildWhichIsA("VehicleSeat", true)
        if not seat then return end

        -- Te lleva al asiento y te sienta
        hrp.CFrame = seat.CFrame * CFrame.new(0, 2, 0)
        hrp.AssemblyLinearVelocity = Vector3.zero
        sitIn(seat, hum)

        local t1 = tick()
        while tick() - t1 < 2 and not hum.SeatPart do
            task.wait(0.1)
        end

        -- Ya sentado, trae el barco (contigo dentro) al lugar donde estabas
        if hum.SeatPart then
            pcall(function() newBoat:PivotTo(origin * CFrame.new(0, BoatSpawnHeight, 0)) end)
        end

        lastBoat = newBoat
        lastManualExit = 0

        if AutoFlyBoat and not FlyEnabled and FlyToggle then
            FlyToggle:Set(true)
        end

        Notify("Barcos", "Barco comprado: " .. boatName, 3)
    end)

    BuyingBoat = false
end

local BoatTab = Window:CreateTab("Barcos", "ship")

BoatTab:CreateSection("Comprar barco desde cualquier lugar")

BoatTab:CreateDropdown({
    Name = "Barco a comprar",
    Options = BOAT_LIST,
    CurrentOption = { SelectedBoat },
    MultipleOptions = false,
    Flag = "BoatSelectDropdown",
    Callback = function(option)
        if type(option) == "table" then option = option[1] end
        SelectedBoat = option or SelectedBoat
    end,
})

BoatTab:CreateInput({
    Name = "Nombre personalizado del barco (opcional)",
    CurrentValue = "",
    PlaceholderText = "Si el nombre de la lista no funciona",
    RemoveTextAfterFocusLost = false,
    Flag = "BoatCustomName",
    Callback = function(Text)
        Text = tostring(Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        CustomBoatName = (Text ~= "") and Text or nil
    end,
})

BoatTab:CreateToggle({
    Name = "Activar el fly al comprar",
    CurrentValue = true,
    Flag = "AutoFlyBoatToggle",
    Callback = function(Value)
        AutoFlyBoat = Value
    end,
})

BoatTab:CreateSlider({
    Name = "Altura a la que aparece el barco",
    Range = { 0, 100 },
    Increment = 2,
    Suffix = " studs",
    CurrentValue = 8,
    Flag = "BoatSpawnHeightSlider",
    Callback = function(Value)
        BoatSpawnHeight = Value
    end,
})

BoatTab:CreateButton({
    Name = "Comprar y sentarme ahora",
    Callback = function()
        task.spawn(buyBoatNow)
    end,
})

BoatTab:CreateSection("Entrar y salir del barco")

BoatTab:CreateButton({
    Name = "Salir / Entrar al barco",
    Callback = function()
        task.spawn(toggleBoatSeat)
    end,
})

BoatTab:CreateParagraph({
    Title = "Teclas",
    Content = "N: compra el barco elegido, lo trae a ti y te sienta. X: sales del barco si estás sentado, o vuelves a entrar a tu barco desde donde estés. Con el fly activo vuelas el barco entero."
})

-- ==========================================================
-- PESTAÑA TELEPORTS
-- ==========================================================
local HttpService = game:GetService("HttpService")

-- Coordenadas que ya venían en tu script original.
local TP_PLACES = {
    { name = "Barco Embrujado", pos = Vector3.new(-6500, 129, -123) },
    { name = "Mansion",         pos = Vector3.new(-12463, 376, -7567) },
}

local TP_FILE = "pato_hub_tps.json"
local TPGradual = true
local TPSpeed = 1200
local tpConn = nil
local SelectedTPPlace = TP_PLACES[1].name

local function findPlace(name)
    for _, place in ipairs(TP_PLACES) do
        if place.name == name then return place end
    end
    return nil
end

local function saveTPPlaces()
    if type(writefile) ~= "function" then return end
    local data = {}
    for _, place in ipairs(TP_PLACES) do
        if place.pos and not place.fromGame then
            data[place.name] = { place.pos.X, place.pos.Y, place.pos.Z }
        end
    end
    pcall(function()
        writefile(TP_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadTPPlaces()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
    pcall(function()
        if not isfile(TP_FILE) then return end
        local data = HttpService:JSONDecode(readfile(TP_FILE))
        for name, v in pairs(data) do
            local place = findPlace(name)
            if place and type(v) == "table" and #v == 3 then
                place.pos = Vector3.new(v[1], v[2], v[3])
            end
        end
    end)
end

loadTPPlaces()


-- Teletransporte: gradual (más seguro contra anti-cheat) o instantáneo
local function teleportTo(pos)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) or hum.Health <= 0 then return end

    -- Si estás en un barco, se mueve el barco entero
    local mover = hrp
    if hum.SeatPart then
        mover = hum.SeatPart.AssemblyRootPart or hum.SeatPart
    end

    local target = pos + Vector3.new(0, 3, 0)

    if tpConn then
        tpConn:Disconnect()
        tpConn = nil
    end

    if not TPGradual then
        mover.CFrame = CFrame.new(target) * (mover.CFrame - mover.CFrame.Position)
        mover.AssemblyLinearVelocity = Vector3.zero
        return
    end

    tpConn = RunService.Heartbeat:Connect(function(dt)
        if not mover.Parent then
            tpConn:Disconnect()
            tpConn = nil
            return
        end

        local delta = target - mover.Position
        local dist = delta.Magnitude
        if dist < 1 then
            mover.AssemblyLinearVelocity = Vector3.zero
            tpConn:Disconnect()
            tpConn = nil
            return
        end

        local step = math.min(TPSpeed * dt, dist)
        mover.CFrame = mover.CFrame + delta.Unit * step
        mover.AssemblyLinearVelocity = Vector3.zero
    end)
end

local function goToPlace(place)
    if not place.pos then
        Notify("Teleports", place.name .. " aún no tiene coordenadas. Ve ahí y usa \"Guardar mi posición aquí\".", 5)
        return
    end
    Notify("Teleports", "Yendo a " .. place.name, 2)
    teleportTo(place.pos)
end

local TPTab = Window:CreateTab("Teleports", "map-pin")

TPTab:CreateSection("Ir a un lugar")

for _, place in ipairs(TP_PLACES) do
    TPTab:CreateButton({
        Name = "Ir a " .. place.name,
        Callback = function()
            goToPlace(place)
        end,
    })
end

TPTab:CreateSection("Guardar coordenadas")

TPTab:CreateDropdown({
    Name = "Lugar a configurar",
    Options = (function()
        local names = {}
        for _, place in ipairs(TP_PLACES) do table.insert(names, place.name) end
        return names
    end)(),
    CurrentOption = { SelectedTPPlace },
    MultipleOptions = false,
    Flag = "TPPlaceDropdown",
    Callback = function(option)
        if type(option) == "table" then option = option[1] end
        SelectedTPPlace = option or SelectedTPPlace
    end,
})

TPTab:CreateButton({
    Name = "Guardar mi posición aquí",
    Callback = function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local place = findPlace(SelectedTPPlace)
        if not (hrp and place) then return end

        place.pos = hrp.Position
        place.fromGame = false
        saveTPPlaces()
        Notify("Teleports", string.format("%s guardado: %d, %d, %d", place.name,
            math.floor(hrp.Position.X), math.floor(hrp.Position.Y), math.floor(hrp.Position.Z)), 4)
    end,
})

TPTab:CreateInput({
    Name = "Pegar coordenadas (x, y, z)",
    CurrentValue = "",
    PlaceholderText = "ej: -12463, 376, -7567",
    RemoveTextAfterFocusLost = false,
    Flag = "TPCoordsInput",
    Callback = function(Text)
        local x, y, z = tostring(Text or ""):match("(-?[%d%.]+)[,%s]+(-?[%d%.]+)[,%s]+(-?[%d%.]+)")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        local place = findPlace(SelectedTPPlace)
        if x and y and z and place then
            place.pos = Vector3.new(x, y, z)
            place.fromGame = false
            saveTPPlaces()
            Notify("Teleports", place.name .. " guardado con esas coordenadas.", 3)
        elseif tostring(Text or "") ~= "" then
            Notify("Teleports", "Formato inválido. Usa: x, y, z", 3)
        end
    end,
})

TPTab:CreateButton({
    Name = "Ver mis coordenadas actuales",
    Callback = function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local p = hrp.Position
            local txt = string.format("%d, %d, %d", math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
            print("[Pato Hub] Mis coordenadas: " .. txt)
            Notify("Mis coordenadas", txt, 6)
        end
    end,
})

TPTab:CreateSection("Opciones")

TPTab:CreateToggle({
    Name = "Teletransporte gradual (más seguro)",
    CurrentValue = true,
    Flag = "TPGradualToggle",
    Callback = function(Value)
        TPGradual = Value
    end,
})

TPTab:CreateSlider({
    Name = "Velocidad del teletransporte",
    Range = { 100, 5000 },
    Increment = 50,
    Suffix = " studs/s",
    CurrentValue = 1200,
    Flag = "TPSpeedSlider",
    Callback = function(Value)
        TPSpeed = Value
    end,
})

TPTab:CreateParagraph({
    Title = "Cómo agregar lugares",
    Content = "Ve al lugar, elígelo en \"Lugar a configurar\" y presiona \"Guardar mi posición aquí\". También puedes pegar coordenadas. Se guardan en un archivo y se recuerdan la próxima vez que ejecutes el script."
})

-- ==========================================================
-- LIMPIEZA AL VOLVER A EJECUTAR EL SCRIPT
-- ==========================================================
_G.__AzucarHubCleanup = function()
    isHoldingKey = false
    NPC_MAGNET_ENABLED = false
    FastAttackEnabled = false
    FastAttackRunning = false
    FlyEnabled = false
    ESPPlayersEnabled = false
    ESPNPCsEnabled = false
    autoV4 = false
    DashEnabled = false
    pcall(stopFly)
    pcall(stopESP)
    SpinEnabled = false
    LongRangeEnabled = false
    WalkSpeedEnabled = false
    JoinLeaveNotify = false
    pcall(stopSpinIntro)
    pcall(function() if tpConn then tpConn:Disconnect() end end)
    AutoDefenseEnabled = false
    pcall(function() if autoDefConn then autoDefConn:Disconnect() end end)
    HitboxEnabled = false
    pcall(function() if hitboxConn then hitboxConn:Disconnect() end end)
    pcall(restoreHitboxes)
    pcall(function() if walkConn then walkConn:Disconnect() end end)
    pcall(function() joinConn:Disconnect() end)
    pcall(function() leaveConn:Disconnect() end)
    pcall(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end)
    unbreakable = false
    pcall(function() if unbreakableLoop then task.cancel(unbreakableLoop) end end)
    pcall(function()
        local char = LocalPlayer.Character
        if char then char:SetAttribute("UnbreakableAll", false) end
    end)
    autoKen = false
    pcall(function() if kenLoop then task.cancel(kenLoop) end end)
    GunFastEnabled = false
    GunFastRunning = false
    dragonAlive = false
    DragonAimPos = nil
    pcall(gunReleaseClick)
    SuperJumpEnabled = false
    pcall(function() if jumpConn then jumpConn:Disconnect() end end)
    pcall(function() if spinCharConn then spinCharConn:Disconnect() end end)
    pcall(function() if v4Connection then task.cancel(v4Connection) end end)
    pcall(function() if DashConnection then task.cancel(DashConnection) end end)
    pcall(function() heartbeatConn:Disconnect() end)
    pcall(function() inputBeganConn:Disconnect() end)
    pcall(function() inputEndedConn:Disconnect() end)
    pcall(function() charAddedConn:Disconnect() end)
    pcall(function() Rayfield:Destroy() end)
end

Notify("Pato Hub", "[ G ] pegado al enemigo, [ P ] fly, [ N ] comprar barco, [ X ] salir/entrar al barco, [ K ] oculta la UI.", 6)

-- Al terminar de cargar todo, el personaje gira para siempre (solo visual)
task.delay(0.5, spinIntro)

-- Si reapareces, el giro se vuelve a poner solo
spinCharConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if SpinEnabled then
        spinIntro()
    end
end)