# Backyamon Socket.IO Protocol

**Single source of truth for the realtime contract** between the server
(`apps/server`) and every client — the web app (`apps/web`) and the iOS app
(`backyamon-swift`). When you change an event here, update **all** clients.

- **Transport:** Socket.IO 4 (default path `/socket.io`)
- **Endpoint:** `wss://backyamon.com` (web, same-origin) / `wss://api.backyamon.com` (iOS)
- **Shared types** (`Move`, `GameState`, `Player`, `WinType`, dice) are defined in
  `packages/engine`. The iOS app mirrors these in Swift — keep them aligned.
- The **server is authoritative**: clients send intents, the server validates and
  broadcasts the resulting state. Never trust a client-computed game state.

---

## Connection lifecycle

```
1. connect  ──────────────▶  (Socket.IO handshake)
2. register {token?}  ─────▶  registered {playerId, token, ...}
3. quick-match | create-room | join-room  ─▶  match-found | room-created | room-joined
4. game-start {state}  ◀────  (both players)
5. ── gameplay loop ──
   roll-dice  ─▶  dice-rolled {dice}  ─▶  (make-move ─▶ move-made)…  ─▶ end-turn ─▶ turn-ended
6. game-over {winner, winType, pointsWon}
```

Reconnect: a client that drops can re-`register` with its saved `token`, then
`reconnect-to-game {playerId, roomId}` to resume; the server replies `room-joined`
(or `error`).

---

## Client → Server (intents)

| Event | Payload | Purpose |
|-------|---------|---------|
| `register` | `{ token?: string }` | Start/resume a session. New guest if no token. |
| `claim-username` | `{ username: string }` | Claim a permanent username for the guest. |
| `create-room` | `{ roomName?: string }` | Create a private room (invite code). |
| `join-room` | `{ roomId: string }` | Join a room by id/code. |
| `leave-room` | — | Leave the current room. |
| `quick-match` | — | Enter the matchmaking queue. |
| `leave-queue` | — | Leave the matchmaking queue. |
| `list-rooms` | — | Request the list of waiting rooms. |
| `list-players` | — | Request the online-players list. |
| `roll-dice` | — | Roll for your turn (also used for the opening roll). |
| `make-move` | `{ move: Move }` | Apply one checker move. |
| `end-turn` | — | End your turn after using your dice. |
| `offer-double` | — | Offer the doubling cube ("Turn It Up"). |
| `respond-double` | `{ accept: boolean }` | Accept or decline a double offer. |
| `reconnect-to-game` | `{ playerId, roomId }` | Resume an in-progress game after a drop. |
| `disconnect` | — | (built-in) triggers `opponent-disconnected` to the peer. |

> **Asset/gallery events** (`list-gallery` and the `/create` upload/report/delete
> events) are a separate, web-only feature surface — see `apps/server/src/index.ts`.
> The iOS app reads published assets but does not create them.

## Server → Client (events)

### Session & lobby

| Event | Payload | Meaning |
|-------|---------|---------|
| `registered` | `{ playerId, displayName, username, token }` | Session established. Persist `token`. |
| `username-claimed` | `{ username, ... }` | Username claim succeeded. |
| `username-error` | `{ message }` | Username claim failed. |
| `room-created` | `{ roomId }` | Your room was created. |
| `room-joined` | `{ roomId, player: Player, state: GameState, opponent: { displayName } }` | You're in a room; `player` is your color. |
| `room-list` | `{ rooms }` | Waiting rooms (response to `list-rooms`). |
| `player-list` | `{ players }` | Online players (response to `list-players`). |
| `match-found` | `{ roomId }` | Matchmaking paired you; `room-joined` follows. |
| `error` | `{ message }` | Rejected intent (not your turn, illegal move, etc.). |

### Gameplay (broadcast to both players in the room)

| Event | Payload | Meaning |
|-------|---------|---------|
| `game-start` | `{ state: GameState }` | Game begins (full authoritative state). |
| `opening-roll-tied` | `{ goldDie, redDie }` | Opening roll tied; reroll. |
| `opening-roll-result` | `{ goldDie, redDie, firstPlayer: Player, dice }` | Opening roll decided; first player + their dice. |
| `dice-rolled` | `{ dice }` | A player rolled for their turn. |
| `move-made` | `{ move: Move, state: GameState }` | A checker moved; new state attached. |
| `turn-ended` | `{ state: GameState, currentPlayer: Player }` | Turn passed to `currentPlayer`. |
| `double-offered` | `{ currentCubeValue }` | Opponent offered the cube. |
| `double-response` | `{ accepted: boolean, state: GameState }` | Cube offer resolved. |
| `game-over` | `{ winner: Player, winType: WinType, pointsWon }` | Game ended. |

### Presence

| Event | Payload | Meaning |
|-------|---------|---------|
| `opponent-disconnected` | — | Peer dropped; may reconnect. |
| `opponent-reconnected` | — | Peer came back. |
| `opponent-left` | — | Peer left the room for good. |

---

## Conventions

- **`Player`** is the color enum (`Gold` / `Red`) from `packages/engine`.
- **`GameState`** is the full board/turn/cube state; clients render from it rather
  than tracking their own. Every state-changing event ships the new `GameState`.
- **Errors** are non-fatal: the server emits `error { message }` and leaves state
  unchanged. Clients should surface the message and re-sync from the last `state`.
- **Source of truth:** the server in `apps/server/src/index.ts`. If this doc and the
  code disagree, the code wins — fix this doc.

> ⚠️ **GameState/Move sync (the real drift risk).** Every gameplay event carries
> `state: GameState` (and `make-move` carries a `Move`). These types are defined in
> `packages/engine` and consumed by the web client for free, but the **iOS app has
> its own Swift `Codable` models** for them. When you add/rename/retype a field in
> `GameState` or `Move`, update the Swift models in `backyamon-swift` in the **same
> change** — otherwise iOS silently drops the field or fails to decode. The event
> names rarely change; these payload shapes are where web and iOS quietly diverge.
