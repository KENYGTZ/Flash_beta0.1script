-- =====================================================================
--  REMOTE SPY + REPLAYER  (universal)
--  Descubre remotes hookeando __namecall, te muestra los args,
--  te deja editarlos y re-dispararlos. Ruta a efecto GLOBAL real.
--
--  K = mostrar / ocultar el panel
-- =====================================================================
local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")

local CFG = {
    NEWC    = true,    -- false si tu executor rompe el yield de InvokeServer
    MAX_LOG = 120,
    MAX_UNI = 400,
}

local Spy = {
    activo = true, spam = false, seguir = true, hookOn = false,
    unicos = {}, orden = {}, registros = {}, conns = {}, ui = {},
    sucio = false, sel = nil,
}
local function conn(c) table.insert(Spy.conns, c) return c end

-- ===================== serializacion =====================
local function ser(v, prof)
    prof = prof or 0
    if prof > 3 then return "..." end
    local t = typeof(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "number" then
        if v ~= v then return "(0/0)" end
        if v == math.huge then return "math.huge" end
        if v == -math.huge then return "-math.huge" end
        return tostring(v)
    elseif t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Vector3" then return ("Vector3.new(%g,%g,%g)"):format(v.X, v.Y, v.Z)
    elseif t == "Vector2" then return ("Vector2.new(%g,%g)"):format(v.X, v.Y)
    elseif t == "CFrame" then
        local x, y, z = v:GetComponents()
        return ("CFrame.new(%g,%g,%g)"):format(x, y, z)
    elseif t == "Color3" then
        return ("Color3.fromRGB(%d,%d,%d)"):format(math.floor(v.R*255), math.floor(v.G*255), math.floor(v.B*255))
    elseif t == "EnumItem" then
        return ("Enum.%s.%s"):format(tostring(v.EnumType), v.Name)
    elseif t == "Instance" then
        return ("_I(%q)"):format(v:GetFullName())
    elseif t == "BrickColor" then
        return ("BrickColor.new(%q)"):format(v.Name)
    elseif t == "UDim2" then
        return ("UDim2.new(%g,%g,%g,%g)"):format(v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "table" then
        local out = {}
        for k, val in pairs(v) do
            table.insert(out, ("[%s]=%s"):format(ser(k, prof+1), ser(val, prof+1)))
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return ("<%s>"):format(t)
end

local function resolver(path)
    local cur = game
    for parte in string.gmatch(path, "[^%.]+") do
        local sig = cur:FindFirstChild(parte)
        if not sig then
            local ok, svc = pcall(game.GetService, game, parte)
            if ok then sig = svc end
        end
        if not sig then return nil end
        cur = sig
    end
    return cur
end

local function parseArgs(texto)
    texto = (texto or ""):gsub("^%s*(.-)%s*$", "%1")
    if texto == "" then return {} end
    local f, err = loadstring("return " .. texto)
    if not f then return nil, err end
    local env = setmetatable({_I = resolver}, {__index = getfenv()})
    pcall(setfenv, f, env)
    local r = table.pack(pcall(f))
    if not r[1] then return nil, tostring(r[2]) end
    return table.pack(table.unpack(r, 2, r.n))
end

-- ===================== registro =====================
local function registrar(inst, metodo, args, n, entrante)
    local path = entrante and inst:GetFullName() or inst:GetFullName()
    local clave = (entrante and "<- " or "-> ") .. path .. "|" .. metodo
    local u = Spy.unicos[clave]
    if not u then
        if #Spy.orden >= CFG.MAX_UNI then return end
        u = {inst = inst, metodo = metodo, path = path, entrante = entrante, cuenta = 0, texto = ""}
        Spy.unicos[clave] = u
        table.insert(Spy.orden, u)
    end
    u.cuenta += 1
    u.texto = ""
    for i = 1, n do
        if i > 1 then u.texto ..= ", " end
        u.texto ..= ser(args[i])
    end
    u.n = n
    u.args = args
    if entrante or not Spy.sel or Spy.sel ~= u or Spy.seguir then
        if Spy.sel == u and Spy.seguir and Spy.ui.args then
            Spy.ui.args.Text = u.texto
        end
    end
    table.insert(Spy.registros, {path = path, metodo = metodo, texto = u.texto, entrante = entrante})
    while #Spy.registros > CFG.MAX_LOG do table.remove(Spy.registros, 1) end
    Spy.sucio = true
end

-- ===================== hook =====================
local function instalarHook()
    if Spy.hookOn then return end
    local mt = getrawmetatable(game)
    Spy.mt, Spy.orig = mt, mt.__namecall
    local fn = function(self, ...)
        local m = getnamecallmethod()
        if Spy.activo and (m == "FireServer" or m == "InvokeServer")
        and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent")) then
            registrar(self, m, {...}, select("#", ...), false)
        end
        return Spy.orig(self, ...)     -- tail call: conserva el yield
    end
    setreadonly(mt, false)
    mt.__namecall = CFG.NEWC and newcclosure(fn) or fn
    setreadonly(mt, true)
    Spy.hookOn = true
end

local function quitarHook()
    if not Spy.hookOn then return end
    setreadonly(Spy.mt, false)
    Spy.mt.__namecall = Spy.orig
    setreadonly(Spy.mt, true)
    Spy.hookOn = false
end

-- escaneo de remotes entrantes (server -> cliente)
local function escanearEntrantes()
    local cuenta = 0
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") then
            conn(d.OnClientEvent:Connect(function(...)
                if Spy.activo then registrar(d, "OnClientEvent", {...}, select("#", ...), true) end
            end))
            cuenta += 1
        elseif d:IsA("RemoteFunction") then
            conn(d.OnClientInvoke:Connect(function(...)
                if Spy.activo then registrar(d, "OnClientInvoke", {...}, select("#", ...), true) end
                return d.OnClientInvoke(...)
            end))
            cuenta += 1
        end
    end
    return cuenta
end

-- ===================== disparo =====================
local function disparar(u)
    if not u then return false, "nada seleccionado" end
    if u.entrante then return false, "es entrante, no se puede re-disparar" end
    local args, err = parseArgs(Spy.ui.args.Text)
    if not args then return false, err end
    local inst = u.inst
    if not inst or not inst.Parent then
        inst = resolver(u.path)
        if not inst then return false, "el remote ya no existe" end
        u.inst = inst
    end
    local ok, err2 = pcall(function()
        inst[u.metodo](inst, table.unpack(args, 1, args.n))
    end)
    if not ok then return false, tostring(err2) end
    return true
end

-- ===================== UI =====================
local function nuevo(clase, props, padre)
    local o = Instance.new(clase)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = padre
    return o
end

local function construir()
    local gui = Instance.new("ScreenGui")
    gui.ResetOnSpawn = false
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local main = nuevo("Frame", {
        Size = UDim2.new(0, 440, 0, 316),
        Position = UDim2.new(0, 20, 0, 150),
        BackgroundColor3 = Color3.fromRGB(20,20,24),
        BorderSizePixel = 0,
    }, gui)
    nuevo("UICorner", {CornerRadius = UDim.new(0,10)}, main)
    Spy.ui.main = main

    local barra = nuevo("Frame", {
        Size = UDim2.new(1,0,0,24), BackgroundColor3 = Color3.fromRGB(30,30,36),
        BorderSizePixel = 0,
    }, main)
    nuevo("UICorner", {CornerRadius = UDim.new(0,10)}, barra)
    nuevo("TextLabel", {
        Size = UDim2.new(1,-60,1,0), Position = UDim2.new(0,10,0,0),
        BackgroundTransparency = 1, Text = "REMOTE SPY", TextColor3 = Color3.fromRGB(0,220,255),
        Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, barra)
    local cerrar = nuevo("TextButton", {
        Size = UDim2.new(0,24,0,24), Position = UDim2.new(1,-26,0,0),
        BackgroundColor3 = Color3.fromRGB(180,40,40), Text = "X", TextColor3 = Color3.fromRGB(255,255,255),
        Font = Enum.Font.GothamBold, TextSize = 12,
    }, barra)
    nuevo("UICorner", {CornerRadius = UDim.new(0,8)}, cerrar)

    local fila = nuevo("Frame", {Size = UDim2.new(1,-8,0,24), Position = UDim2.new(0,4,0,28),
        BackgroundTransparency = 1}, main)
    nuevo("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,4)}, fila)

    local function mini(txt, ancho, color)
        local b = nuevo("TextButton", {
            Size = UDim2.new(0, ancho, 0, 24), BackgroundColor3 = color,
            TextColor3 = Color3.fromRGB(230,230,230), Font = Enum.Font.GothamBold,
            TextSize = 11, Text = txt,
        }, fila)
        nuevo("UICorner", {CornerRadius = UDim.new(0,7)}, b)
        return b
    end

    local bCap   = mini("CAPTURA", 68, Color3.fromRGB(0,150,90))
    local bSeguir= mini("SEGUIR", 62, Color3.fromRGB(0,150,90))
    local bSpam  = mini("SPAM", 52, Color3.fromRGB(40,40,48))
    local bEsc   = mini("ESCANEAR", 74, Color3.fromRGB(45,60,110))
    local bLimp  = mini("LIMPIAR", 62, Color3.fromRGB(60,50,30))
    local bHook  = mini("UNHOOK", 64, Color3.fromRGB(60,30,60))

    local lista = nuevo("ScrollingFrame", {
        Size = UDim2.new(0,214,0,158), Position = UDim2.new(0,4,0,56),
        BackgroundColor3 = Color3.fromRGB(15,15,18), BorderSizePixel = 0,
        CanvasSize = UDim2.new(0,0,0,0), ScrollBarThickness = 4,
    }, main)
    nuevo("UIListLayout", {Padding = UDim.new(0,2)}, lista)
    Spy.ui.lista = lista

    local log = nuevo("ScrollingFrame", {
        Size = UDim2.new(0,214,0,158), Position = UDim2.new(0,222,0,56),
        BackgroundColor3 = Color3.fromRGB(15,15,18), BorderSizePixel = 0,
        CanvasSize = UDim2.new(0,0,0,0), ScrollBarThickness = 4,
    }, main)
    nuevo("UIListLayout", {Padding = UDim.new(0,1)}, log)
    Spy.ui.log = log

    nuevo("TextLabel", {
        Size = UDim2.new(1,-8,0,14), Position = UDim2.new(0,4,0,216),
        BackgroundTransparency = 1, Text = "args (editables)", TextColor3 = Color3.fromRGB(140,140,150),
        Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local args = nuevo("TextBox", {
        Size = UDim2.new(1,-8,0,24), Position = UDim2.new(0,4,0,232),
        BackgroundColor3 = Color3.fromRGB(28,28,34), TextColor3 = Color3.fromRGB(0,230,180),
        Font = Enum.Font.Code, TextSize = 12, Text = "", ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, PlaceholderText = "selecciona un remote...",
    }, main)
    nuevo("UICorner", {CornerRadius = UDim.new(0,6)}, args)
    Spy.ui.args = args

    local acc = nuevo("Frame", {Size = UDim2.new(1,-8,0,24), Position = UDim2.new(0,4,0,260),
        BackgroundTransparency = 1}, main)
    nuevo("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,4)}, acc)
    local function acc2(txt, ancho, color)
        local b = nuevo("TextButton", {Size = UDim2.new(0,ancho,0,24), BackgroundColor3 = color,
            TextColor3 = Color3.fromRGB(230,230,230), Font = Enum.Font.GothamBold, TextSize = 11, Text = txt}, acc)
        nuevo("UICorner", {CornerRadius = UDim.new(0,7)}, b)
        return b
    end
    local bFire  = acc2("RE-DISPARAR", 100, Color3.fromRGB(0,120,200))
    local bCopiar= acc2("COPIAR PATH", 92, Color3.fromRGB(50,50,60))
    local bAuto  = acc2("AUTO-OFF", 80, Color3.fromRGB(50,50,60))

    Spy.ui.estado = nuevo("TextLabel", {
        Size = UDim2.new(1,-8,0,14), Position = UDim2.new(0,4,0,288),
        BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(150,150,160),
        Font = Enum.Font.Code, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    -- arrastrar
    local drag, ini, posIni
    barra.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag, ini, posIni = true, i.Position, main.Position
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = false
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ini
            main.Position = UDim2.new(posIni.X.Scale, posIni.X.Offset + d.X, posIni.Y.Scale, posIni.Y.Offset + d.Y)
        end
    end)

    -- handlers
    cerrar.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)

    bCap.MouseButton1Click:Connect(function()
        Spy.activo = not Spy.activo
        bCap.BackgroundColor3 = Spy.activo and Color3.fromRGB(0,150,90) or Color3.fromRGB(60,40,40)
        bCap.Text = Spy.activo and "CAPTURA" or "PAUSADO"
    end)

    bSeguir.MouseButton1Click:Connect(function()
        Spy.seguir = not Spy.seguir
        bSeguir.BackgroundColor3 = Spy.seguir and Color3.fromRGB(0,150,90) or Color3.fromRGB(60,40,40)
        bSeguir.Text = Spy.seguir and "SEGUIR" or "FIJO"
    end)

    bSpam.MouseButton1Click:Connect(function()
        Spy.spam = not Spy.spam
        bSpam.BackgroundColor3 = Spy.spam and Color3.fromRGB(0,120,200) or Color3.fromRGB(40,40,48)
    end)

    bHook.MouseButton1Click:Connect(function()
        if Spy.hookOn then quitarHook() else instalarHook() end
        bHook.Text = Spy.hookOn and "UNHOOK" or "HOOK"
        bHook.BackgroundColor3 = Spy.hookOn and Color3.fromRGB(60,30,60) or Color3.fromRGB(30,70,60)
    end)

    bEsc.MouseButton1Click:Connect(function()
        local n = escanearEntrantes()
        Spy.ui.estado.Text = ("escaneados %d remotes entrantes"):format(n)
    end)

    bLimp.MouseButton1Click:Connect(function()
        Spy.unicos, Spy.orden, Spy.registros, Spy.sel = {}, {}, {}, nil
        args.Text = ""
        refrescar()
    end)

    bFire.MouseButton1Click:Connect(function()
        local ok, err = disparar(Spy.sel)
        Spy.ui.estado.Text = ok and "disparado" or ("error: " .. tostring(err))
    end)

    bCopiar.MouseButton1Click:Connect(function()
        if Spy.sel then
            pcall(setclipboard, Spy.sel.path)
            Spy.ui.estado.Text = "copiado: " .. Spy.sel.path
        end
    end)

    bAuto.MouseButton1Click:Connect(function()
        if not Spy.sel or Spy.sel.entrante then Spy.ui.estado.Text = "selecciona un remote saliente" return end
        local u = Spy.sel
        local ok, err = disparar(u)
        Spy.ui.estado.Text = ok and ("auto-remoto: " .. u.path) or tostring(err)
    end)

    return gui
end

-- ===================== refresco =====================
local function refrescar()
    local lista = Spy.ui.lista
    for _, ch in ipairs(lista:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    for _, u in ipairs(Spy.orden) do
        local b = nuevo("TextButton", {
            Size = UDim2.new(1,-6,0,20),
            BackgroundColor3 = (Spy.sel == u) and Color3.fromRGB(40,90,140) or Color3.fromRGB(30,30,36),
            TextColor3 = u.entrante and Color3.fromRGB(255,190,80) or Color3.fromRGB(210,210,215),
            Font = Enum.Font.Code, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
            Text = ("%s:%s [%d]"):format(u.entrante and "<<" or ">>", u.path, u.cuenta),
        }, lista)
        b.MouseButton1Click:Connect(function()
            Spy.sel = u
            Spy.ui.args.Text = u.texto
            Spy.ui.estado.Text = ("%s :%s   (%d llamadas)"):format(u.path, u.metodo, u.cuenta)
            refrescar()
        end)
    end
    lista.CanvasSize = UDim2.new(0, 0, 0, #Spy.orden * 22 + 4)

    local log = Spy.ui.log
    for _, ch in ipairs(log:GetChildren()) do
        if ch:IsA("TextLabel") then ch:Destroy() end
    end
    for i = #Spy.registros, 1, -1 do
        local r = Spy.registros[i]
        nuevo("TextLabel", {
            Size = UDim2.new(1,-6,0,14), BackgroundTransparency = 1,
            TextColor3 = r.entrante and Color3.fromRGB(255,190,80) or Color3.fromRGB(160,220,160),
            Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = ("%s%s  %s"):format(r.entrante and "<<" or ">>", r.path, r.texto),
        }, log)
    end
    log.CanvasSize = UDim2.new(0, 0, 0, #Spy.registros * 15 + 4)
end

-- ===================== arranque =====================
construir()
instalarHook()
refrescar()

task.spawn(function()
    while Spy.ui.main and Spy.ui.main.Parent do
        if Spy.sucio then Spy.sucio = false; refrescar() end
        task.wait(0.25)
    end
end)

conn(game:GetService("RunService").Heartbeat:Connect(function()
    if Spy.spam and Spy.sel and not Spy.sel.entrante then
        pcall(function()
            local args = parseArgs(Spy.ui.args.Text)
            local u = Spy.sel
            u.inst[u.metodo](u.inst, table.unpack(args, 1, args.n))
        end)
    end
end))

conn(UIS.InputBegan:Connect(function(i, gp)
    if gp or i.UserInputState ~= Enum.UserInputState.Begin then return end
    if UIS:GetFocusedTextBox() then return end
    if i.KeyCode == Enum.KeyCode.K then
        Spy.ui.main.Visible = not Spy.ui.main.Visible
    end
end))

-- ===================== unload =====================
local function unload()
    quitarHook()
    for _, c in ipairs(Spy.conns) do pcall(function() c:Disconnect() end) end
    Spy.conns = {}
    if Spy.ui.main and Spy.ui.main.Parent then Spy.ui.main.Parent:Destroy() end
    getgenv().RSPY = nil
end
getgenv().RSPY = {unload = unload, spy = Spy, hook = instalarHook, unhook = quitarHook}
