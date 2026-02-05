--[[
    EngineTickReentryBug - Minimal reproduction mod

    Simulates two mods scheduling independent deferred work via
    ExecuteWithDelay + ExecuteInGameThread. When these overlapping
    actions land during the same engine tick, a crash occurs in
    get_function_ref with "Ref was not function".

    See README.md for full details and crash dump analysis.
]]

local MOD_NAME = "EngineTickReentryBug"

local iterations = 0
local startTime = nil
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
    Log(string.format("Chain A - Iteration %d", iterations))

    ExecuteWithDelay(50, function()
        ExecuteInGameThread(ChainA)
    end)
end

local function ChainB()
    if not isRunning then return end
    iterations = iterations + 1
    Log(string.format("Chain B - Iteration %d", iterations))

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
    startTime = os.clock()

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
        Log("Starting in 3...")
        ExecuteWithDelay(1000, function()
            Log("2...")
            ExecuteWithDelay(1000, function()
                Log("1...")
                ExecuteWithDelay(1000, function()
                    StartReproduction()
                end)
            end)
        end)
    end)
end)

Log("Loaded. Start/join a game to begin the test.")
