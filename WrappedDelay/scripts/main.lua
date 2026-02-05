--[[
    WrappedDelay - Two deferred chains using ExecuteWithDelay + ExecuteInGameThread

    Simulates two mods scheduling independent deferred work.
    Crashes on official 932 within a few minutes. Stable on Martin's fix DLL.

    See README.md for details and crash dump info.
]]

local MOD_NAME = "WrappedDelay"

local iterations = 0
local isRunning = false

local function Log(msg)
    print(string.format("[%s] %s\n", MOD_NAME, msg))
end

-- Two independent chains with different delays to simulate two mods
-- scheduling deferred work. The mismatched timing means they'll
-- occasionally overlap on the same engine tick.

local function ChainA()
    if not isRunning then return end
    iterations = iterations + 1
    if iterations % 100 == 0 then
        Log(string.format("Chain A - Iteration %d", iterations))
    end

    ExecuteWithDelay(50, function()
        ExecuteInGameThread(ChainA)
    end)
end

local function ChainB()
    if not isRunning then return end
    iterations = iterations + 1
    if iterations % 100 == 0 then
        Log(string.format("Chain B - Iteration %d", iterations))
    end

    ExecuteWithDelay(75, function()
        ExecuteInGameThread(ChainB)
    end)
end

local function StartReproduction()
    if isRunning then
        Log("Already running!")
        return
    end

    isRunning = true
    iterations = 0

    Log("===========================================")
    Log("Starting overlapping deferred action test")
    Log("Two chains: 50ms and 75ms intervals")
    Log("Expect crash within a few minutes")
    Log("===========================================")

    ExecuteInGameThread(ChainA)
    ExecuteInGameThread(ChainB)
end

-- Wait for game to fully load before starting
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    Log("Game started, waiting 10 seconds before beginning test...")
    ExecuteWithDelay(10000, function()
        Log("Starting crash test now.")
        StartReproduction()
    end)
end)

Log("Loaded. Start/join a game to begin the test.")
