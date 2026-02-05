# ExecuteInGameThread / ExecuteInGameThreadWithDelay Crash Repros

Two repro mods that seem to trigger crashes related to game-thread action processing. Each uses a different API pattern and appears to crash for different reasons.

## Background

I first noticed this during normal gameplay (~17 minutes in, hosting a multiplayer session). After investigating crash dumps, I put together these minimal reproduction mods.

I have a few hundred hours on UE4SS 553 (the version currently distributed on Nexus for Abiotic Factor) and never encountered this crash, so I think it was introduced sometime after 553.

## The Two Repro Mods

### WrappedDelay (ExecuteWithDelay + ExecuteInGameThread)

Simulates two mods scheduling independent deferred work using the two-call pattern:

```lua
local function ChainA()
    ExecuteWithDelay(50, function()
        ExecuteInGameThread(ChainA)
    end)
end
```

Two chains at 50ms and 75ms intervals. On the official v3.0.1-932 build, this crashes within a few minutes (1k-11k iterations, varies per run).

Martin's test DLL (with per-action Lua stacks) seems to fix this one — I ran 221k+ iterations over 26 minutes with no crash, including with my full mod suite loaded.

### DirectDelay (ExecuteInGameThreadWithDelay)

A single self-rescheduling timer using `ExecuteInGameThreadWithDelay`:

```lua
local function PollGameState()
    -- do work
    ExecuteInGameThreadWithDelay(500, PollGameState)
end
ExecuteInGameThreadWithDelay(500, PollGameState)
```

This is a pattern I'd reach for when building a repeating game-thread timer — there's no `LoopInGameThreadWithDelay` API, so self-rescheduling from within the callback seemed like the natural approach.

This one crashes almost immediately — typically on the first timer tick, even with a 500ms interval. It also crashes on Martin's test DLL, which makes me think it might be a separate issue from what WrappedDelay triggers.

## What I Observed

### WrappedDelay crashes (on official 932)

The crash occurs in `get_function_ref` with "Ref was not function":

```
UE4SS!RC::LuaMadeSimple::Lua::Registry::get_function_ref
UE4SS!RC::process_simple_actions
UE4SS!std::erase_if
UE4SS!RC::engine_tick_hook
```

Martin identified this as Lua stack corruption from reusing a single stack for all callbacks.

### DirectDelay crashes (on Martin's fix DLL)

These look different. WinDbg's `!analyze -v` defaults to an NVIDIA driver thread, but checking thread 0 (game thread) shows:

```
VCRUNTIME140!memcpy
  std::vector<DelayedGameThreadAction>::erase
    std::erase_if
      RC::process_delayed_actions
        RC::engine_tick_hook
```

The crash is in `memcpy` during `vector::erase` inside `std::erase_if` on the delayed actions vector. I'm wondering if this is the vector modification issue — `ExecuteInGameThreadWithDelay` pushes to `m_delayed_game_thread_actions`, and if the callback is being processed by `process_delayed_actions` which iterates that same vector via `std::erase_if`, could the `emplace_back` be invalidating iterators?

I noticed that `ExecuteWithDelay` pushes to `m_pending_actions` (a separate data structure on the async thread), which might explain why the WrappedDelay pattern doesn't hit this — the `emplace_back` happens from a different thread and would block on the mutex instead of re-entering.

The `memcpy` byte count in one of the full dumps was ~26 MB, which seems like a stale pointer calculation rather than a reasonable data size. I have full memory dumps available if it would help to dig into the vector state.

## Reproduction Steps

1. Copy either `WrappedDelay` or `DirectDelay` folder to your `Mods/` directory
2. Start a game session
3. The mod waits 10 seconds after game load, then starts
4. **WrappedDelay**: crashes within a few minutes on official 932 (stable on Martin's fix)
5. **DirectDelay**: crashes almost immediately, even on Martin's fix

Only run one at a time to keep things clean.

## Crash Dumps

### WrappedDelay (official v3.0.1-932)

| Iterations | Notes |
|------------|-------|
| ~1,190 | `get_function_ref` abort |
| ~2,058 | `get_function_ref` abort |
| ~4,300 | `get_function_ref` abort |
| ~10,800 | `luaH_getint` variant |

### DirectDelay (Martin's fix DLL)

| Timing | Notes |
|--------|-------|
| 5ms/10ms aggressive | Crash at ~157 sec |
| 50ms/75ms two chains | Crash at ~49 sec |
| 500ms single timer | Crash on first tick (~68 sec including warmup) |
| 500ms single timer | Full memory dump — available for analysis |

---

Let me know if I can provide any other info, share the dump files, or help test fixes. Thanks!
