**Branch or Release**
v3.0.1-932-ge31aaaa6

**Game and Engine Version**
Abiotic Factor v1.2.x (UE 5.4)

**Describe the bug**
When multiple deferred actions overlap via `ExecuteInGameThread`, whether through `ExecuteWithDelay` chains, direct scheduling from within callbacks, or just multiple mods independently queuing work, the game crashes with `get_function_ref` "Ref was not function" followed by `abort()`.

I first noticed this during normal gameplay (~20 minutes in, hosting a multiplayer session) with my standard mod loadout and another crash about 30 minutes in. After investigating the crash dumps, I created a minimal repro that simulates two mods scheduling independent deferred work.

The crash appears to come from `process_simple_actions` using `std::erase_if` to iterate `m_engine_tick_actions`, while callbacks can push new items to that same vector during iteration:
https://github.com/UE4SS-RE/RE-UE4SS/blob/main/UE4SS/src/Mod/LuaMod.cpp#L3650-L3671

**Mods directory**
Using only default mods and my minimal reproduction mod attached: [EngineTickReentryBug.zip]

The repro simulates two mods with overlapping deferred work:
```lua
-- Chain A: schedules next iteration after 50ms
local function ChainA()
    ExecuteWithDelay(50, function()
        ExecuteInGameThread(ChainA)
    end)
end

-- Chain B: schedules next iteration after 75ms
local function ChainB()
    ExecuteWithDelay(75, function()
        ExecuteInGameThread(ChainB)
    end)
end
```

Why the 50/75ms delays? I felt like they were lenient enough to prove this isn't just a torture test - a hook that runs per frame would be firing every ~8ms at 120fps. You can drop the delays to 25/50 or lower to crash faster, or just call ExecuteInGameThread several times without any delay and it crashes almost instantly. I used two chains to simulate a more realistic scenario where two separate mods are independently doing game-thread work.

**To reproduce**
1. Copy `EngineTickReentryBug` folder into your Mods directory
2. Launch the game (single or multiplayer, doesn't matter)
3. Watch the UE4SS console for iteration count logs
4. Wait for crash (typically 1-5 minutes, varies due to timing-dependent nature)

**Expected behavior**
Deferred callbacks should execute without crashing, even when they schedule additional deferred work.

**Screenshots, UE4SS Log, and .dmp file**
5 crash dumps collected, all showing the same call chain:
```
engine_tick_hook
  → process_simple_actions
    → std::erase_if
      → get_function_ref
        → abort
```

Iteration counts at crash varied significantly (consistent with timing-dependent bug):
- ~1,190 iterations
- ~2,058 iterations
- ~2,299 iterations
- ~4,300 iterations
- ~10,800 iterations

Sample log output before crash:
```
[Lua] [EngineTickReentryBug] Chain A - Iteration 2295
[Lua] [EngineTickReentryBug] Chain B - Iteration 2296
[Lua] [EngineTickReentryBug] Chain A - Iteration 2297
[Lua] [EngineTickReentryBug] Chain B - Iteration 2298
[Lua] [EngineTickReentryBug] Chain A - Iteration 2299
*crash*
```

Dumps available on request - they're large due to full memory dumps.

**Desktop (please complete the following information):**
- OS: Windows 11 25H2

**Additional context**
- I have hundreds of hours on UE4SS v3.0.1-553 (the version currently shipped on Nexus for Abiotic Factor) and never encountered this crash, so I think it was introduced (or at least exposed) via a newer commit
- The original crash during normal gameplay occurred while hosting multiplayer, but the repro crashes in single player as well
- The timing variance (1k-11k iterations) makes me think it's a race condition
