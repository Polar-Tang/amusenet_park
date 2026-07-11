# TODO — Mid-join: advertise this running match so the lobby can send late joiners (SHOOTER side)

Goal: a game server running a mid-joinable mode registers itself in a shared
MemoryStore directory with its free slots; lobby servers teleport queued
players straight in. `GameModeService`'s existing
`matchMaid:GiveTask(Players.PlayerAdded:Connect(onPlayerAdded))` already
handles the arriving player — this side only needs discovery + capacity.

Counterpart: `amusenet_lobby/TODO_midjoin.md` (the lobby adds the directory
lookup + short-circuit teleport, and starts sending `accessCode` /
`privateServerId` in the teleport payload).

## Shared contract (MUST stay in sync with the lobby by hand, like MATCH_FOUND_TOPIC already is)
- MemoryStore SortedMap per mode: `"ActiveMatches_" .. mode`.
- Entry: key = `matchId`, value =
  `{ accessCode: string, privateServerId: string, playerCount: number, maxPlayers: number, joinable: boolean }`,
  TTL ~60s, refreshed by heartbeat. Expiry is the crash-cleanup: never rely on
  explicit removal alone.
- Mid-joinable modes: `koht/koth`, `ctf`, `tdm`. **Never `lms`**.

## Tasks

- [ ] **Constants** (`gamemode/src/Shared/GameModeConstants.luau`): add
      `ACTIVE_MATCHES_MAP_PREFIX = "ActiveMatches_"`,
      `ACTIVE_MATCH_TTL = 60`, `ACTIVE_MATCH_HEARTBEAT = 30`,
      `MIDJOIN_CUTOFF_SECONDS` (stop accepting joiners when less than this
      remains of `timeLimitSeconds`).
- [ ] **Types** (`gamemode/src/Shared/gameModeTypes.luau`): extend
      `MatchFoundPayload` / `MatchPayload` with `accessCode: string?` and
      `privateServerId: string?`; add `ActiveMatchEntry`. Depends on the lobby
      actually sending `accessCode` in TeleportData — a reserved server cannot
      read back its own access code, so without it registration is impossible
      (skip registering and log, don't error).
- [ ] **Per-mode flag**: add `midJoinable` to each mode's config (wherever
      `config.timeLimitSeconds` lives, e.g. GameModeConfig). `lms = false`.
- [ ] **New `ActiveMatchRegistry` ServiceBag service** (pattern-match
      `src/server/NPC/MatchListener.luau` — same loader/boot-timing caveats):
      - `register(matchId, mode, accessCode)`: called from
        `GameModeService.StartMatchNow` once the mode strategy resolves; no-op
        when the mode isn't `midJoinable`, when `game.PrivateServerId == ""`
        (Studio/direct-join), or when no `accessCode` arrived.
      - Heartbeat `task.spawn` loop on `matchMaid`: every
        `ACTIVE_MATCH_HEARTBEAT` seconds re-`SetAsync` the entry with fresh
        `playerCount = #Players:GetPlayers()` and recomputed `joinable`.
      - `joinable = false` when: server full (`playerCount >= maxPlayers`),
        remaining match time < `MIDJOIN_CUTOFF_SECONDS`, or
        `MATCH_OVER_ATTRIBUTE` is set.
      - `unregister()` (`RemoveAsync`): on match end — the same paths that set
        `MATCH_OVER_ATTRIBUTE` / start the `POST_MATCH_LOBBY_DELAY` teleport
        back, and in `matchMaid:DoCleaning()`.
- [ ] **Capacity enforcement** (server is the authority; two lobbies can race
      the last slot even with the lobby-side atomic claim): in
      `GameModeService.onPlayerAdded`, if the human count exceeds
      `maxPlayers`, teleport the newcomer back to
      `GameModeConstants.LOBBY_PLACE_ID` with a friendly reason instead of
      spawning them.
- [ ] **Late-joiner flow through existing code** — verify, don't assume:
      - `MatchListener.tryTeleportData` early-returns on `_state.filled`, so a
        late joiner's TeleportData will NOT re-trigger `StartMatch` (correct).
        But their per-player quest/loadout records ride in that same
        TeleportData — make sure whatever reads `questsByUserId`/
        `loadoutByUserId` runs per player on join, not only for the founding
        batch.
      - `onPlayerAdded` is idempotent by contract; check `TeamMode` assigns a
        team (balance to the smaller team) and the joiner gets a spawn +
        default weapon mid-round.
      - Consider trimming bots on human mid-join: if the match started with
        `botCount > 0`, despawn one bot per arriving human to keep match size.
- [ ] **Verify**: publish-place test (Studio fallback path sets
      `PrivateServerId == ""` so registration is skipped there by design).
      Log register/heartbeat/unregister via the debug console; confirm the
      entry expires within TTL after killing the server.
