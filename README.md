# Boggle Kills

An in-world kill board for Garry's Mod. It counts lifetime player and NPC kills,
saves them across restarts, and draws a live leaderboard on a board placed in
the map.

The addon is the `boggle_kills/` folder. Copy it into `garrysmod/addons/`.

## What's new in 2.1

### On the board
- **Five pages that rotate:** Lifetime, Player kills, NPC kills, Best kill streaks and
  K/D ratio. Lifetime stays up for 20 seconds and the others for 8. Tabs across the top
  show which page is up, and the active tab's underline doubles as the timer.
- **Press E (your use key) while looking at a board** to flip to the next page. The page
  you flip to stays up for 30 seconds. Only you see the flip.
- **Gold, silver and bronze badges** for the top three. Each row is shaded in proportion
  to its score against the page leader.
- **A green dot** next to players who are on the server right now.
- **Rank movement since the map started:** ▲ green, ▼ red, or `NEW` for someone who
  wasn't ranked at map start.
- **A streak badge** (`7 STREAK`) next to anyone currently on 3 or more kills without
  dying.
- **A live ticker** showing the latest kills, such as `Boggle ▸ Antlion Guard 4s`, using
  the game's own NPC names.
- **Server totals** in the header: total kills and the number of fighters.
- **A footer with your own line:** rank, kills, players, NPCs, deaths, plus your current
  streak, K/D and best streak when they fit.
- A new row flashes when it scores, and a highlight sweeps along the accent bar.

The board keeps the same size and anchor point as 2.0, so boards already placed on
the map don't move or clip into walls.

### In chat
- `!kills` shows your stats, and `!kills <name>` shows anyone's (partial names work and
  online players are matched first). `!top` lists the top 5.
- With a `/` prefix (`/kills`, `/top`) the command doesn't appear in chat, like ULX.
- Announcements go out for a new #1, kill streaks of 10/25/50/100/250/500/1000, and a
  streak of 10+ ending ("Alice ended Boggle's 25 kill streak!").

### For admins
- **Pick what a board shows:** hold C and right-click the board's logo (the small cube
  behind it is the prop), then open **Kill Board View**. You can also look at the board
  and run `boggle_kills_view <default|rotate|1-5>` in the console. Dupes keep the choice.
- **Fixed:** pasting a board with the duplicator used to spawn it at the map origin. It
  now spawns where it was pasted.

## Your data

Nothing is removed or reset.

- Every existing row keeps every field. 2.1 adds one field, `streak` (best kill streak),
  starting at 0. Fields it doesn't recognise are carried over untouched.
- The first time 2.1 loads, it copies your current save to
  `data/boggle_kills/scores_pre_v2_1.json` before it writes anything. That copy is
  never touched again.
- Rolling back is safe. 2.0 reads 2.1 saves; it simply ignores `streak`.
- Everything from 2.0 is unchanged: the backup rotation (`scores_backup.json`),
  corrupt-file quarantine, merging of pre-2.0 rows as players rejoin, and the
  `boggle_kills_reset` archive.

## Settings

| Convar | Default | |
|---|---|---|
| `boggle_kills_npc` | 1 | Count NPC / NextBot kills |
| `boggle_kills_top` | 10 | Rows shown per page (1-10) |
| `boggle_kills_bots` | 0 | Track bots, and count kills of bots |
| `boggle_kills_announce` | 1 | Chat announcements (new #1, streaks) |
| `boggle_kills_chat` | 1 | `!kills` / `!top` chat commands |
| `boggle_kills_kd_min` | 25 | Kills needed to appear on the K/D page |
| `boggle_kills_board_mode` | 0 | View for boards set to "Server default": 0 rotates, 1-5 pins one page (lifetime, players, NPCs, streaks, K/D) |

| Command | Who | |
|---|---|---|
| `boggle_kills_view <default\|rotate\|1-5>` | admin | Set the view of the board you're looking at |
| `boggle_kills_reset` | superadmin | Archive the current scores to a file, then clear them |

The brand name and the lifetime subtitle are set in `BoggleKills.Config` in
`lua/autorun/boggle_kills.lua`.

## Tests

`tests/run.sh` runs the addon's real server and client Lua under stubbed GMod APIs.
It checks that a 2.0 save survives loading and re-saving field for field, that kills
and streaks are counted correctly, and that every net message reads back exactly as
it was written. `tests/run.sh --preview` also renders each board page to
`tests/preview/`. The preview uses DejaVu Sans as a deliberately wider stand-in for
Tahoma. You need `luajit` and `lua-cjson`; the preview also needs Python with Pillow.
