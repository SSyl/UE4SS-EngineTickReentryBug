--[[
    DirectDelay - Self-rescheduling timer using ExecuteInGameThreadWithDelay

    A single repeating timer that polls every 500ms by rescheduling
    from within the callback. Without a LoopInGameThreadWithDelay API,
    this seemed like the natural way to build a repeating game-thread timer.

    Crashes on the first tick. Compare with WrappedDelay, which uses
    ExecuteWithDelay + ExecuteInGameThread and doesn't crash.

    See README.md for details and crash dump info.
]]

local MOD_NAME = "DirectDelay"

local iterations = 0

local function Log(msg)
    print(string.format("[%s] %s\n", MOD_NAME, msg))
end

local function PollGameState()
    iterations = iterations + 1
    Log(string.format("Polling game state - tick %d", iterations))

    ExecuteInGameThreadWithDelay(500, PollGameState)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    Log("Game started, waiting 10 seconds before beginning test...")
    ExecuteWithDelay(10000, function()
        Log("Starting polling timer (500ms interval)")
        ExecuteInGameThreadWithDelay(500, PollGameState)
    end)
end)

Log("Loaded. Start/join a game to begin the test.")
