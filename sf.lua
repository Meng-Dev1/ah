local FIREBASE_URL = "https://aselolejoss-73512-default-rtdb.firebaseio.com/"
local gameJobId    = game.JobId
local gamePlaceId  = tostring(game.PlaceId)

local TeleportService  = game:GetService("TeleportService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local SF_IsRefreshing  = false

local eventList = {
    "Dreadfin Hunt", "Baby Bloop Fish", "Bloop Fish", "Whales Pool", "Orcas Pool",
    "The Kraken Pool", "Ancient Depth Serpent", "Animal Pool", "Plesiosaur Hunt", "Goldwraith Hunt",
    "Reef Titan Hunt", "Sunken Reliquary", "Omnithal Hunt",
    "Animal Pool - Second Sea", "Octophant Pool Without Elephant",
    "Sea Leviathan Pool", "Isonade", "Forsaken Veil - Scylla",
    "Blue Moon - Second Sea", "Blue Moon - First Sea", "Great White Shark", "LEGO",
    "LEGO - Studolodon", "Mosslurker", "Narwhal", "Whale Shark",
    "Birthday Megalodon", "Colossal Blue Dragon", "Colossal Ancient Dragon",
    "Colossal Ethereal Dragon", "Megalodon Ancient", "Megalodon Default",
    "Megalodon Phantom", "Skeletal Leviathan Hunt", "Pliosaur Hunt",
    "Toxic Boil", "Flower Guardian Hunt", "Rotbloom Hunt", "Megamouth Hunt", "Humpback Whale Pool"
}
local workspaceNameOverrides = {
    ["Ancient Depth Serpent"] = "The Depths - Serpent"
}

-- ============================================================
-- CUACA
-- ============================================================
local function getWeather()
    local ok, val = pcall(function()
        return game:GetService("ReplicatedStorage"):WaitForChild("world", 3):WaitForChild("cycle", 3).Value
    end)
    return (ok and val) and val or "Unknown"
end

local function getWeatherTotem()
    local RS = game:GetService("ReplicatedStorage")
    local parts = {}

    -- Weather aktif (sovereign/meteorological/main)
    pcall(function()
        local SharedWeather = require(RS.shared.modules.SharedWeather)
        local groups = { "sovereign", "meteorological", "main" }
        local weathers = require(RS.shared.modules.library.weathers)
        for _, g in ipairs(groups) do
            local w = SharedWeather.GetActiveGroupWeather(g)
            if w and w ~= "None" then
                local wd = weathers[w]
                table.insert(parts, (wd and (wd.DisplayName or wd.Name)) or w)
            end
        end
    end)

    -- Season
    pcall(function()
        local s = RS:WaitForChild("world", 3):WaitForChild("season", 3).Value
        if s and s ~= "" then table.insert(parts, s) end
    end)

    -- Server Event
    pcall(function()
        local e = RS:WaitForChild("world", 3):WaitForChild("event", 3).Value
        if e and e ~= "" and e ~= "None" then table.insert(parts, e) end
    end)

    return table.concat(parts, " / ")
end

local function SF_GetStarfall()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj.Name == "StarCrater" and obj:IsA("Model") then
            return true
        end
    end
    return false
end

local function getNextSunkenIn(uptimeSec)
    if not uptimeSec or uptimeSec == 0 then return nil, 999999 end
    local uptimeMin = uptimeSec / 60
    local n = 0
    local nextSpawnMin
    repeat
        nextSpawnMin = 60 + 70 * n
        n = n + 1
    until nextSpawnMin > uptimeMin
    local diffSec = math.floor(nextSpawnMin * 60 - uptimeSec)
    local m = math.floor(diffSec / 60)
    return string.format("%dM", m), diffSec
end

-- ============================================================
-- ACTIVE EVENTS
-- ============================================================
local function SF_GetActiveEvents()
    local activeEvents = {}
    local ok, fishingZones = pcall(function()
        return workspace:WaitForChild("zones", 3):WaitForChild("fishing", 3)
    end)
    if not ok or not fishingZones then return activeEvents end
    for _, eventName in ipairs(eventList) do
        local lookupName = workspaceNameOverrides[eventName] or eventName
        local eventZone = fishingZones:FindFirstChild(lookupName)
        if eventZone and eventZone:IsA("BasePart") then
            table.insert(activeEvents, eventName)
        end
    end
    return activeEvents
end

-- ============================================================
-- REQUEST HELPER
-- ============================================================
local function doRequest(opt)
    if type(request) == "function" then return request(opt)
    elseif type(syn) == "table" and syn.request then return syn.request(opt)
    elseif type(http) == "table" and http.request then return http.request(opt)
    end
end

-- ============================================================
-- FIREBASE
-- ============================================================
local function SF_Register()
    if gameJobId == "" then return end

    local currentEvents      = SF_GetActiveEvents()
    local currentWeather     = getWeather()
    local currentWorldStatus = getWeatherTotem()
    local currentStarfall    = SF_GetStarfall()
    local currentPlayers     = #game:GetService("Players"):GetPlayers()

    local uptimeSec = 0
    pcall(function()
        local uptimeLabel = game:GetService("Players").LocalPlayer.PlayerGui.serverInfo.serverInfo.uptime
        local function parseUptimeText(text)
            local d = tonumber(text:match("(%d+)D")) or 0
            local h = tonumber(text:match("(%d+)H")) or 0
            local m = tonumber(text:match("(%d+)M")) or 0
            local s = tonumber(text:match("(%d+)S")) or 0
            return d*86400 + h*3600 + m*60 + s
        end
        uptimeSec = parseUptimeText(uptimeLabel.Text)
    end)

    pcall(function()
        doRequest({
            Url     = FIREBASE_URL .. "/servers/" .. gameJobId .. ".json",
            Method  = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({
                jobId         = gameJobId,
                placeId       = gamePlaceId,
                playerCount   = currentPlayers,
                maxPlayers    = game.Players.MaxPlayers,
                events        = currentEvents,
                starfall      = currentStarfall,
                weather       = currentWeather,
                worldStatus   = currentWorldStatus,
                uptimeSeconds = uptimeSec,
                lastSeen      = { [".sv"] = "timestamp" }
            })
        })
    end)
end

local function SF_Fetch()
    local ok, res = pcall(function()
        return doRequest({ Url = FIREBASE_URL .. "/servers.json", Method = "GET" })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok2 or type(data) ~= "table" then return {} end

    local nowMs = os.time() * 1000
    local list  = {}
    for _, s in pairs(data) do
        if type(s) == "table" and s.lastSeen then
            local age = nowMs - (tonumber(s.lastSeen) or 0)
            if age < 12000 and s.jobId ~= gameJobId then
                table.insert(list, s)
            end
        end
    end
    table.sort(list, function(a, b)
        local _, aSec = getNextSunkenIn(a.uptimeSeconds)
        local _, bSec = getNextSunkenIn(b.uptimeSeconds)
        return (aSec or 999999) < (bSec or 999999)
    end)
    return list
end

local function SF_Unregister()
    pcall(function()
        doRequest({
            Url    = FIREBASE_URL .. "/servers/" .. gameJobId .. ".json",
            Method = "DELETE"
        })
    end)
end

-- ============================================================
-- PALET WARNA � Mengikuti referensi screenshot
-- ============================================================
local C = {
    BG      = Color3.fromRGB(18, 18, 22),      -- panel background
    BG2     = Color3.fromRGB(26, 26, 32),      -- card / header bg
    BG3     = Color3.fromRGB(36, 36, 46),      -- hover / button bg
    Text    = Color3.fromRGB(235, 235, 238),   -- primary text
    TextDim = Color3.fromRGB(100, 100, 118),   -- secondary/muted text
    Accent  = Color3.fromRGB(100, 170, 255),   -- blue accent (JOIN btn)
    AccentH = Color3.fromRGB(130, 190, 255),   -- hover blue
    Border  = Color3.fromRGB(38, 38, 52),      -- subtle border
    Green   = Color3.fromRGB(72, 200, 110),    -- online dot
    PillBG  = Color3.fromRGB(24, 24, 30),      -- top pill
    PillBdr = Color3.fromRGB(55, 55, 70),      -- pill border
    Gold    = Color3.fromRGB(255, 205, 90),    -- starfall gold
    Purple  = Color3.fromRGB(175, 135, 255),   -- world status purple
    Cyan    = Color3.fromRGB(90, 195, 255),    -- next sunken cyan
}

-- ============================================================
-- HELPERS
-- ============================================================
local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local function stroke(p, col, t)
    local s = Instance.new("UIStroke")
    s.Color     = col or C.Border
    s.Thickness = t or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent    = p
end

local function hover(btn, n, h)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = h }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = n }):Play()
    end)
end

-- ============================================================
-- SCREEN GUI
-- ============================================================
if game:GetService("CoreGui"):FindFirstChild("SF_MengHub") then
    game:GetService("CoreGui"):FindFirstChild("SF_MengHub"):Destroy()
end

local SG = Instance.new("ScreenGui")
SG.Name           = "SF_MengHub"
SG.ResetOnSpawn   = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.DisplayOrder   = 999
SG.IgnoreGuiInset = true
SG.Parent         = game:GetService("CoreGui")

-- ============================================================
-- PILL BUTTON � tengah atas (mirip screenshot: "Servers")
-- ============================================================
local TopBtn = Instance.new("TextButton")
TopBtn.Size             = UDim2.new(0, 130, 0, 36)
TopBtn.AnchorPoint      = Vector2.new(0.5, 0)
TopBtn.Position         = UDim2.new(0.5, 0, 0, 44)
TopBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
TopBtn.Text             = ""
TopBtn.AutoButtonColor  = false
TopBtn.ZIndex           = 50
TopBtn.Parent           = SG
corner(TopBtn, 99)
stroke(TopBtn, C.PillBdr, 1)
hover(TopBtn, Color3.fromRGB(22, 22, 28), C.BG3)

-- Dot hijau kiri
local Dot = Instance.new("Frame")
Dot.Size             = UDim2.new(0, 7, 0, 7)
Dot.Position         = UDim2.new(0, 14, 0.5, 0)
Dot.AnchorPoint      = Vector2.new(0, 0.5)
Dot.BackgroundColor3 = C.Green
Dot.ZIndex           = 51
Dot.Parent           = TopBtn
corner(Dot, 99)

-- Label "Servers"
local TopLbl = Instance.new("TextLabel")
TopLbl.Size                   = UDim2.new(1, -28, 1, 0)
TopLbl.Position               = UDim2.new(0, 28, 0, 0)
TopLbl.BackgroundTransparency = 1
TopLbl.Text                   = "Servers"
TopLbl.TextColor3             = C.Text
TopLbl.TextSize               = 13
TopLbl.Font                   = Enum.Font.GothamBold
TopLbl.TextXAlignment         = Enum.TextXAlignment.Center
TopLbl.ZIndex                 = 51
TopLbl.Parent                 = TopBtn

-- ============================================================
-- PANEL UTAMA � lebar, pendek per card
-- Panel width: 600, tinggi disesuaikan konten
-- ============================================================
local PANEL_W = 600
-- Panel height: header(58) + searchbar(50) + 2.5 cards * 82px + padding = ~320
local PANEL_H = 360

local Panel = Instance.new("Frame")
Panel.Size             = UDim2.new(0, PANEL_W, 0, PANEL_H)
Panel.AnchorPoint      = Vector2.new(0.5, 0)
Panel.Position         = UDim2.new(0.5, 0, 0, 88)
Panel.BackgroundColor3 = C.BG
Panel.Visible          = false
Panel.ZIndex           = 40
Panel.ClipsDescendants = true
Panel.Parent           = SG
corner(Panel, 24)
stroke(Panel, C.Border, 1)

-- ============================================================
-- HEADER � "Available Servers" + tombol kanan
-- ============================================================
local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1, 0, 0, 54)
Header.BackgroundColor3 = C.BG
Header.ZIndex           = 41
Header.Parent           = Panel

-- Garis bawah header
local HeaderLine = Instance.new("Frame")
HeaderLine.Size             = UDim2.new(1, -24, 0, 1)
HeaderLine.Position         = UDim2.new(0, 12, 1, -1)
HeaderLine.BackgroundColor3 = C.Border
HeaderLine.ZIndex           = 42
HeaderLine.Parent           = Header

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size                   = UDim2.new(1, -120, 1, 0)
TitleLbl.Position               = UDim2.new(0, 20, 0, 0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text                   = "Available Servers"
TitleLbl.TextColor3             = C.Text
TitleLbl.TextSize               = 15
TitleLbl.Font                   = Enum.Font.GothamBold
TitleLbl.TextXAlignment         = Enum.TextXAlignment.Left
TitleLbl.ZIndex                 = 42
TitleLbl.Parent                 = Header

-- Refresh button � unicode aman dari obfuscation
local RefBtn = Instance.new("TextButton")
RefBtn.Size             = UDim2.new(0, 32, 0, 32)
RefBtn.Position         = UDim2.new(1, -16, 0.5, 0)
RefBtn.AnchorPoint      = Vector2.new(1, 0.5)
RefBtn.BackgroundColor3 = C.BG3
RefBtn.Text             = "R"
RefBtn.TextColor3       = C.Accent
RefBtn.TextSize         = 17
RefBtn.Font             = Enum.Font.GothamBold
RefBtn.AutoButtonColor  = false
RefBtn.ZIndex           = 42
RefBtn.Parent           = Header
corner(RefBtn, 10)
hover(RefBtn, C.BG3, C.Border)

-- Close button � unicode aman
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size             = UDim2.new(0, 32, 0, 32)
CloseBtn.Position         = UDim2.new(1, -54, 0.5, 0)
CloseBtn.AnchorPoint      = Vector2.new(1, 0.5)
CloseBtn.BackgroundColor3 = C.BG3
CloseBtn.Text             = "X"
CloseBtn.TextColor3       = C.TextDim
CloseBtn.TextSize         = 18
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.AutoButtonColor  = false
CloseBtn.ZIndex           = 42
CloseBtn.Parent           = Header
corner(CloseBtn, 10)
hover(CloseBtn, C.BG3, C.Border)

-- ============================================================
-- SEARCH BAR � full rounded, mirip screenshot
-- ============================================================
local SearchWrap = Instance.new("Frame")
SearchWrap.Size             = UDim2.new(1, -24, 0, 36)
SearchWrap.Position         = UDim2.new(0, 12, 0, 62)
SearchWrap.BackgroundColor3 = C.BG2
SearchWrap.ZIndex           = 41
SearchWrap.Parent           = Panel
corner(SearchWrap, 99)
stroke(SearchWrap, C.Border, 1)

-- Search icon � teks biasa, 100% aman dari obfuscation
local SearchIco = Instance.new("TextLabel")
SearchIco.Size                   = UDim2.new(0, 34, 1, 0)
SearchIco.BackgroundTransparency = 1
SearchIco.Text                   = "/"
SearchIco.TextColor3             = C.TextDim
SearchIco.TextSize               = 14
SearchIco.Font                   = Enum.Font.GothamBold
SearchIco.ZIndex                 = 42
SearchIco.Parent                 = SearchWrap

local SearchBox = Instance.new("TextBox")
SearchBox.Size                   = UDim2.new(1, -40, 1, 0)
SearchBox.Position               = UDim2.new(0, 34, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.PlaceholderText        = "Search by event..."
SearchBox.PlaceholderColor3      = Color3.fromRGB(65, 65, 85)
SearchBox.Text                   = ""
SearchBox.TextColor3             = C.Text
SearchBox.TextSize               = 12
SearchBox.Font                   = Enum.Font.Gotham
SearchBox.TextXAlignment         = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus       = false
SearchBox.ZIndex                 = 42
SearchBox.Parent                 = SearchWrap

-- ============================================================
-- SCROLL LIST
-- ============================================================
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size                   = UDim2.new(1, -24, 1, -114)
Scroll.Position               = UDim2.new(0, 12, 0, 110)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel        = 0
Scroll.ScrollBarThickness     = 3
Scroll.ScrollBarImageColor3   = C.Border
Scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
Scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
Scroll.ZIndex                 = 41
Scroll.Parent                 = Panel

local Layout = Instance.new("UIListLayout")
Layout.Padding   = UDim.new(0, 10)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent    = Scroll

local PaddingBot = Instance.new("UIPadding")
PaddingBot.PaddingBottom = UDim.new(0, 8)
PaddingBot.Parent        = Scroll

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Name                   = "StatusLbl"
StatusLbl.Size                   = UDim2.new(1, 0, 0, 60)
StatusLbl.BackgroundTransparency = 1
StatusLbl.Text                   = "Press  R  to load servers"
StatusLbl.TextColor3             = C.TextDim
StatusLbl.TextSize               = 12
StatusLbl.Font                   = Enum.Font.Gotham
StatusLbl.ZIndex                 = 42
StatusLbl.Parent                 = Scroll

-- ============================================================
-- BUILD CARD � compact, pendek, lebar
-- Card height: 68px
-- ============================================================
local function buildCard(s, idx)
    local hasEvents = #(s.events or {}) > 0
    local evStr     = hasEvents and table.concat(s.events, ", ") or "No active events"
    local isFull    = (s.playerCount or 0) >= (s.maxPlayers or 20)
    local isStar    = s.starfall == true

    -- Info string: "Players: X / Y  *  Weather  *  WorldStatus  *  Sunken in NM"
    -- Pakai U+2022 BULLET (bukan emoji, aman dari obfuscation)
    local sep = "  -  "
    local infoParts = {}
    table.insert(infoParts, string.format("Players: %d / %d", s.playerCount or 0, s.maxPlayers or 20))
    if s.weather and s.weather ~= "" then
        table.insert(infoParts, s.weather)
    end
    if s.worldStatus and s.worldStatus ~= "" then
        table.insert(infoParts, s.worldStatus)
    end
    local sunkenStr, _ = getNextSunkenIn(s.uptimeSeconds)
    if sunkenStr then
        table.insert(infoParts, "Sunken in " .. sunkenStr)
    end

    -- Card frame
    local Card = Instance.new("Frame")
    Card.Size             = UDim2.new(1, 0, 0, 76)
    Card.BackgroundColor3 = C.BG2
    Card.ZIndex           = 42
    Card.LayoutOrder      = idx
    Card.Parent           = Scroll
    corner(Card, 14)
    stroke(Card, C.Border, 1)

    -- Hover effect on card
    Card.MouseEnter:Connect(function()
        TweenService:Create(Card, TweenInfo.new(0.1), { BackgroundColor3 = C.BG3 }):Play()
    end)
    Card.MouseLeave:Connect(function()
        TweenService:Create(Card, TweenInfo.new(0.1), { BackgroundColor3 = C.BG2 }):Play()
    end)

    -- Accent left bar (hanya kalau ada event aktif)
    if hasEvents then
        local AccentBar = Instance.new("Frame")
        AccentBar.Size             = UDim2.new(0, 3, 0, 36)
        AccentBar.Position         = UDim2.new(0, 0, 0.5, 0)
        AccentBar.AnchorPoint      = Vector2.new(0, 0.5)
        AccentBar.BackgroundColor3 = C.Accent
        AccentBar.ZIndex           = 43
        AccentBar.Parent           = Card
        corner(AccentBar, 99)
    end

    -- Event name (primary text, bold)
    local EvLbl = Instance.new("TextLabel")
    EvLbl.Size                   = UDim2.new(1, -110, 0, 22)
    EvLbl.Position               = UDim2.new(0, 20, 0, 16)
    EvLbl.BackgroundTransparency = 1
    EvLbl.Text                   = evStr
    EvLbl.TextColor3             = hasEvents and C.Text or C.TextDim
    EvLbl.TextSize               = 13
    EvLbl.Font                   = hasEvents and Enum.Font.GothamBold or Enum.Font.Gotham
    EvLbl.TextXAlignment         = Enum.TextXAlignment.Left
    EvLbl.TextTruncate           = Enum.TextTruncate.AtEnd
    EvLbl.ZIndex                 = 43
    EvLbl.Parent                 = Card

    -- Info row (secondary text, bullet separated)
    local InfoLbl = Instance.new("TextLabel")
    InfoLbl.Size                   = UDim2.new(1, -110, 0, 16)
    InfoLbl.Position               = UDim2.new(0, 20, 0, 43)
    InfoLbl.BackgroundTransparency = 1
    InfoLbl.Text                   = table.concat(infoParts, sep)
    InfoLbl.TextColor3             = C.TextDim
    InfoLbl.TextSize               = 11
    InfoLbl.Font                   = Enum.Font.Gotham
    InfoLbl.TextXAlignment         = Enum.TextXAlignment.Left
    InfoLbl.TextTruncate           = Enum.TextTruncate.AtEnd
    InfoLbl.ZIndex                 = 43
    InfoLbl.Parent                 = Card

    -- JOIN Button � pill, di kanan
    local btnColor = isFull and C.BG3 or C.Accent

    local JoinBtn = Instance.new("TextButton")
    JoinBtn.Size             = UDim2.new(0, 68, 0, 36)
    JoinBtn.Position         = UDim2.new(1, -16, 0.5, 0)
    JoinBtn.AnchorPoint      = Vector2.new(1, 0.5)
    JoinBtn.BackgroundColor3 = btnColor
    JoinBtn.Text             = isFull and "FULL" or "JOIN"
    JoinBtn.TextColor3       = isFull and C.TextDim or C.BG
    JoinBtn.TextSize         = 11
    JoinBtn.Font             = Enum.Font.GothamBold
    JoinBtn.AutoButtonColor  = false
    JoinBtn.ZIndex           = 44
    JoinBtn.Parent           = Card
    corner(JoinBtn, 99)

    if not isFull then
        hover(JoinBtn, btnColor, C.AccentH)
        JoinBtn.MouseButton1Click:Connect(function()
            JoinBtn.Text = "..."

            local ok, res = pcall(function()
                return doRequest({
                    Url = FIREBASE_URL .. "/servers/" .. s.jobId .. ".json",
                    Method = "GET"
                })
            end)

            local data = (ok and res.StatusCode == 200) and HttpService:JSONDecode(res.Body) or nil

            if not data or (os.time() * 1000 - (tonumber(data.lastSeen) or 0)) > 15000 then
                JoinBtn.Text             = "GONE"
                JoinBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
                task.spawn(function()
                    doRequest({ Url = FIREBASE_URL .. "/servers/" .. s.jobId .. ".json", Method = "DELETE" })
                end)
                task.wait(1)
                doRefresh()
                return
            end

            JoinBtn.Text = "GO"
            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.jobId, game.Players.LocalPlayer)
        end)
    end
end

-- ============================================================
-- REFRESH
-- ============================================================
local function clearCards()
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
end

function doRefresh()
    if SF_IsRefreshing then return end
    SF_IsRefreshing = true
    clearCards()
    StatusLbl.Text    = "Loading..."
    StatusLbl.Visible = true

    task.spawn(function()
        local servers = SF_Fetch()

        if not servers then
            StatusLbl.Text  = "Failed to connect"
            SF_IsRefreshing = false
            return
        end

        local query    = SearchBox.Text:lower()
        local filtered = {}
        for _, s in ipairs(servers) do
            if query == "" then
                table.insert(filtered, s)
            else
                local matched = false
                for _, ev in ipairs(s.events or {}) do
                    if ev:lower():find(query, 1, true) then
                        matched = true
                        break
                    end
                end
                if not matched and s.worldStatus and s.worldStatus:lower():find(query, 1, true) then
                    matched = true
                end
                if not matched and s.weather and s.weather:lower():find(query, 1, true) then
                    matched = true
                end
                if matched then table.insert(filtered, s) end
            end
        end

        clearCards()
        if #filtered == 0 then
            StatusLbl.Text    = "No servers found"
            StatusLbl.Visible = true
        else
            StatusLbl.Visible = false
            for i, s in ipairs(filtered) do buildCard(s, i) end
        end

        SF_IsRefreshing = false
    end)
end

-- ============================================================
-- ANIMASI PANEL
-- ============================================================
local isOpen = false

local function openPanel()
    Panel.Visible = true
    Panel.Size    = UDim2.new(0, PANEL_W, 0, 0)
    TweenService:Create(Panel, TweenInfo.new(0.2, Enum.EasingStyle.Quint), {
        Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
    }):Play()
    isOpen = true
end

local function closePanel()
    isOpen = false
    local tw = TweenService:Create(Panel, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {
        Size = UDim2.new(0, PANEL_W, 0, 0)
    })
    tw:Play()
    tw.Completed:Once(function() Panel.Visible = false end)
end

-- ============================================================
-- DRAG � TopBtn dan Panel ikut
-- ============================================================
local dragging = false
local dragStart, startPos

TopBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = TopBtn.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local delta = input.Position - dragStart
    local newX = math.clamp(startPos.X.Scale + (delta.X / SG.AbsoluteSize.X), 0.05, 0.95)
    local newY = math.clamp(startPos.Y.Scale + (delta.Y / SG.AbsoluteSize.Y), 0, 0.90)

    TopBtn.Position = UDim2.new(newX, 0, newY, 0)
    Panel.Position  = UDim2.new(newX, 0, newY + (TopBtn.Size.Y.Offset / SG.AbsoluteSize.Y) + 0.005, 0)
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ============================================================
-- EVENTS
-- ============================================================
TopBtn.MouseButton1Click:Connect(function()
    if isOpen then closePanel() else openPanel() end
end)

CloseBtn.MouseButton1Click:Connect(function()
    closePanel()
end)

RefBtn.MouseButton1Click:Connect(function()
    TweenService:Create(RefBtn, TweenInfo.new(0.4), { Rotation = 360 }):Play()
    task.delay(0.42, function()
        TweenService:Create(RefBtn, TweenInfo.new(0), { Rotation = 0 }):Play()
    end)
    doRefresh()
end)

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    doRefresh()
end)
-- SearchBox.FocusLost:Connect(function(enter)
--     if enter then doRefresh() end
-- end)

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not isOpen then return end
    local pos = input.Position
    local function inBounds(obj)
        local a = obj.AbsolutePosition
        local s = obj.AbsoluteSize
        return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
    end
    if not inBounds(Panel) and not inBounds(TopBtn) then closePanel() end
end)

-- ============================================================
-- DB CLEANER
-- ============================================================
local function SF_CleanDatabase()
    local ok, res = pcall(function()
        return doRequest({ Url = FIREBASE_URL .. "/servers.json", Method = "GET" })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok2 or type(data) ~= "table" then return end

    local nowMs = os.time() * 1000
    for id, s in pairs(data) do
        if type(s) == "table" and s.lastSeen then
            local age = nowMs - tonumber(s.lastSeen)
            if age > 25000 then
                task.spawn(function()
                    doRequest({ Url = FIREBASE_URL .. "/servers/" .. id .. ".json", Method = "DELETE" })
                end)
            end
        end
    end
end

-- ============================================================
-- HEARTBEAT
-- ============================================================
task.spawn(function()
    repeat task.wait(1) until game:IsLoaded()
    SF_Register()
    task.wait(1)
    doRefresh()
    while task.wait(8) do
        SF_Register()
    end
end)

task.spawn(function()
    while task.wait(30) do
        SF_CleanDatabase()
    end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
    if player == game.Players.LocalPlayer then
        SF_Unregister()
    end
end)

warn("Server Finder v6 Loaded � New UI")
