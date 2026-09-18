# project-intel

`project-intel` is a reusable project-local intelligence substrate for Neovim.

It exists so domain features do not each reinvent:

- project-local persistent caches;
- startup cache loading;
- file fingerprinting;
- incremental reconciliation;
- status/health reporting;
- manual refresh commands.

The initial consumer is `filament-scope`, but Filament is deliberately only a provider/domain feature.

## Lifecycle

```text
Neovim starts
   ↓
load persisted provider state immediately
   ↓
feature is usable
   ↓
background reconcile
   ↓
only changed/removed files are reparsed
```

On save:

```text
one file changes
   ↓
one provider contribution changes
   ↓
derived view is rebuilt from hot per-file contributions
   ↓
persist
```

This replaces the previous pattern where every PHP save triggered a full scan of `app/Filament`.

## Why this matters

The same architectural principle is being explored in the separate `pre-agent-loop` project:

> precompute structural state once, keep it hot, and make interactive operations query prepared state rather than reconstructing the world at point of use.
