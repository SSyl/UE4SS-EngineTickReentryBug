# ExecuteInGameThread Reentry Crash

I ran into a crash that seems to occur when `ExecuteInGameThread` is called while another `ExecuteInGameThread` callback is still being processed. This can happen in real-world scenarios like:

- A callback that schedules follow-up work via `ExecuteWithDelay` + `ExecuteInGameThread`
- Multiple mods with overlapping deferred actions
- Event-driven code where one action triggers another

## Minimal Repro

The included mod simulates two mods running independent chains of deferred work:

```lua
-- Chain A: schedules next iteration after 50ms
local function ChainA()
    Log("Chain A iteration")
    ExecuteWithDelay(50, function()
        ExecuteInGameThread(ChainA)
    end)
end

-- Chain B: schedules next iteration after 75ms
local function ChainB()
    Log("Chain B iteration")
    ExecuteWithDelay(75, function()
        ExecuteInGameThread(ChainB)
    end)
end
```

This eventually crashes - typically after several thousand iterations (a few minutes). Decreasing the delay makes it happen faster.

Obviously this pattern is synthetic, but I figured it was close enough to real scenarios (like one hook triggering multiple deferred calls, or two mods scheduling work independently) to be a realistic stress test. The 50/75ms delays are actually pretty lenient - a hook that runs per frame would be firing every ~8ms at 120fps.

## What I Observed

The crash occurs in `get_function_ref` with the error "Ref was not function". Looking at the stack traces:

```
UE4SS!RC::LuaMadeSimple::Lua::Registry::get_function_ref
UE4SS!RC::process_simple_actions
UE4SS!std::erase_if
UE4SS!RC::engine_tick_hook
```

I collected several crash dumps that show different failure modes:

| Crash Type | Failure Bucket |
|------------|----------------|
| Registry lookup fails | `APPLICATION_FAULT_4000...!AbortHandler` |
| Memory access during vector op | `INVALID_POINTER_READ_c0000005_VCRUNTIME140.dll!memcpy` |
| Heap corruption detected | `HEAP_CORRUPTION...DOUBLE_FREE` |
| Lua table lookup corruption | `INVALID_POINTER_READ_c0000005_UE4SS.dll!luaH_getint` |

These different symptoms might point to the same underlying issue. Is it possible the action vector is being modified during iteration here?
https://github.com/UE4SS-RE/RE-UE4SS/blob/main/UE4SS/src/Mod/LuaMod.cpp#L3650-L3671

The Windows heap manager detecting a double-free was what led me down this path.

## Additional Context

- First noticed this during normal gameplay with my mods (~17 minutes in, hosting a multiplayer session)
- All reproductions were done using only default UE4SS mods + the repro mod
- I have a few hundred hours on UE4SS 553 (the version currently distributed on Nexus for Abiotic Factor) and never encountered this crash
- Tested on official v3.0.1-932 build - crashes reliably

## Reproduction Steps

1. Copy `EngineTickReentryBug` folder to `Mods/`
2. Start a game session
3. Wait a few minutes (logs show iteration count)
4. Crash occurs around iteration 10000+ on official build

## Crash Dumps

Tested on **UE4SS 3.0.1-932** - crashes vary widely due to race condition nature:
- ~10,800 iterations
- ~4,300 iterations
- ~2,058 iterations
- ~1,190 iterations

The variance is expected for a timing-dependent bug. I can share dump files if useful.

---

Let me know if I can provide any other info or help test fixes. Thanks!
