# Variant duty endings

Every variant duty has twelve endings (thirteen for The Merchant's Tale). Running one writes a note
into that duty's notebook, and the game remembers which notes a character has collected. AutoDuty
reads that, so the main tab can show which endings are still missing.

The route dropdown sits with the duty selection and again inside the duty, and holds both the routes
and the ways of choosing one:

- **Follow the vote** — whatever the vote window has selected, the old behaviour.
- **One route** — the ending you picked, every run.
- **Random ending** — a route picked at random from the ones a path file can run.
- **Work through missing endings** — the next ending this character has not found yet, going on from
  the last run. Once they are all found it keeps rotating.

Picking inside the duty also applies to the run in progress. Playlists are left alone: a playlist
entry names its own route.

## What runs which ending

The route number is the position of the note in the duty's notebook series, which is also the number
the vote window uses and the value path files match on.

Path files come in two shapes:

- one file per ending, with the route in the file name (`Exit 7 - Middle`, `Path 3`). The older
  duties work this way, and the file bakes in the choices that lead to its ending.
- one file for the whole duty, branching on the route in `VariantPath` conditions and voting for it
  with a `VariantVote` action. The Merchant's Tale works this way.

## Coverage

| Duty | Endings | Path files | Missing |
| --- | --- | --- | --- |
| (1069) The Sil'dihn Subterrane | 12 | 12, one per ending | none |
| (1137) Mount Rokkon | 12 | 12, one per ending | none |
| (1176) Aloalo Island | 12 | 4, all in the first branch | routes 5-12 |
| (1315) The Merchant's Tale | 13 | 1, branches inside | none |

An ending with no path file is marked in the route picker and skipped when working through them, so
Aloalo currently rotates through four of its twelve endings.

## Recording a missing Aloalo route

Path files live in the plugin's config directory (`pluginConfigs/AutoDuty/paths`) and are synced from
erdelf/AutoDuty on startup, so a new or edited file has to be protected from that sync first:

1. turn "Update Paths on Startup" off in the config tab, or mark the file as do-not-update once it
   exists.
2. enter Aloalo Island and take the branch that leads to the ending you are recording. The route
   picker in the main tab names every ending, so you can tell which number you are after.
3. record the run in the Build tab and save it as `(1176) Aloalo Island - Path <route>.json`, where
   `<route>` is that ending's number. The name is what ties the file to the route.
4. copy it into `AutoDuty/Paths/` in this repo and run `./scripts/install.sh --paths` to push the
   tree's path files back into the game, so the copy under test and the copy in git stay the same.

If Aloalo shows the vote window (`VVDVoteRoute`) rather than only in-dungeon choices, the file can
vote for its own route with a `VariantVote` action, the way the Merchant's Tale file does.

## Checking the numbering

Route N is taken to be the Nth note of the duty's notebook series. That is confirmed for The
Merchant's Tale: running route 2 wrote its second note, "A Carpet Soars", and the note groups line
up with the branch groups in its path file.

The older duties have not been checked the same way, and their path files were named by hand, so it
is worth confirming once per duty: note which endings the list calls missing, run one, and check
that the note the game gives you is the one it named. The tally beside the list counts the same
entries the duty's notebook does, which makes a mismatch easy to spot.
