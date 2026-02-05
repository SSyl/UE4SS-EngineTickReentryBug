Hey, wanted to report back on testing the fix DLL.

**Good news first:** The fix seems solid for the original repro. I tested it with both my repro mod (the `ExecuteWithDelay` + `ExecuteInGameThread` pattern at 50ms/75ms) and my full mod suite during regular gameplay. 221k+ iterations over about 26 minutes with no crashes. Really nice work.

**Then I got curious.** One of the things I've been looking forward to in newer UE4SS versions is `ExecuteInGameThreadWithDelay`, having a single API call is really nice instead of the `ExecuteWithDelay` + `ExecuteInGameThread` nesting we've had to do. So I figured I'd do pretty much the same test as my repro mod, except using that for a self-rescheduling timer:

```lua
local function PollGameState()
    -- do work
    ExecuteInGameThreadWithDelay(500, PollGameState)
end
ExecuteInGameThreadWithDelay(500, PollGameState)
```

You can obviously do this with `ExecuteWithDelay` + `ExecuteInGameThread` instead, but I wanted to test the single-call API since it's cleaner and seems like the direction things are heading. Unfortunately, this crashes almost immediately (so fast that a few of my dumps came back as 0kb, so probably before the crash reporter could even start), on the very first timer tick, even with a 500ms interval. It also crashes with the fix DLL, so it seems like it might be a different issue from the shared Lua stack problem.

**What the dumps look like:** The crashes are a bit tricky to analyze. WinDbg's `!analyze -v` defaults to an NVIDIA driver thread with various access violations (null pointer, invalid read, NX fault, different each time). But checking thread 0 (game thread) with `~0 kp` shows a consistent stack:

```
VCRUNTIME140!memcpy
  std::vector<DelayedGameThreadAction>::erase
    std::erase_if
      RC::process_delayed_actions
        RC::engine_tick_hook
```

The NVIDIA crashes seem like secondary heap corruption, the GPU driver is probably just the first thing to trip over corrupted memory after whatever happens on the game thread.

**I grabbed a full memory dump** (using `-fullcrashdumpalways`) and tried to poke around a bit. The thing that stood out to me was that the vector's data was at one address, but the `memcpy` that crashed was reading and writing to a completely different address range. And the byte count on the `memcpy` was something like 26 MB, which seems way too large for a vector that only had 2 elements in it.

It looks to me like the `memcpy` might be working with pointers to where the vector *used to be* rather than where it is now. Is it possible that the `emplace_back` from `ExecuteInGameThreadWithDelay` inside the callback is causing a reallocation while `std::erase_if` is still iterating?

My guess for why the `ExecuteWithDelay` + `ExecuteInGameThread` pattern doesn't hit this: `ExecuteWithDelay` runs on a separate thread, so by the time `ExecuteInGameThread` pushes to the vector, the iteration from the previous tick is already done. With `ExecuteInGameThreadWithDelay`, the push happens right in the middle of it.

I've attached the updated repro mod with both variants: `WrappedDelay` (the original, stable with your fix) and `DirectDelay` (the `ExecuteInGameThreadWithDelay` version that crashes).

You can also find it here with my updated readme containing more info/speculation:

 I've also attached the non-zero KB minidumps (the dll and pdb will be the same as the one you posted in your previous quoted reply):

[LinkToZippedDumps]


I have my full ~8GB dump as well which you can find here: https://drive.google.com/drive/folders/1q1ptjA997bq--7_Nuk71zIR2gBLFIkNM
