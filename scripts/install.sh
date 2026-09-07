#!/usr/bin/env bash
#
# Install this fork of AutoDuty into a local XIV on Mac setup, as a dalamud dev
# plugin.
#
# AutoDuty is normally installed from a plugin repository, and a build from this
# working tree is not in it. Both copies would register the same command and IPC
# names, so the normal install is parked aside while the dev build is active and
# put back by --uninstall.
#
# Two things about the registration are easy to get wrong, and both fail with
# dalamud reporting that the path does not exist:
#
#   - the path must name the assembly, not the folder holding it. Dalamud tests
#     it with FileInfo.Exists, which is false for a directory.
#   - DevMode has to be on. Dev plugin locations are only scanned when it is,
#     so an otherwise perfect registration is silently never looked at.
#
# Dalamud watches the registered file, but `dotnet build` deletes and recreates
# its own output, which replaces the inode and kills the watch. So the build is
# deployed by a post-build copy into devPlugins, and dalamud watches that copy.
# Once installed, `dotnet build` alone is the whole deploy step, and running this
# script again is only a build and a copy, so both work with the game running.
# Only the first install has to wait for the game to quit, because dalamud writes
# its whole config back out on exit and would undo the registration.
#
# The build needs dalamud's dev libraries. XIV on Mac keeps a copy under its own
# data directory, so that is used by default and there is no need for the
# %appdata% layout the csproj assumes. Override with DALAMUD_LIB=/some/path/.
#
#   ./scripts/install.sh              build Debug and install
#   ./scripts/install.sh --release    build Release and install
#   ./scripts/install.sh --no-build   install whatever is already built
#   ./scripts/install.sh --dry-run    print what would happen, change nothing
#   ./scripts/install.sh --status     show what is built and what is installed
#   ./scripts/install.sh --uninstall  unregister, and put the normal install back
#   ./scripts/install.sh --paths      copy this tree's path files into the game
#
# Path files are not part of the build. The plugin keeps them in its config
# directory and syncs them from erdelf/AutoDuty on startup, so a locally edited
# path file is overwritten unless the sync is off. --paths copies them over and
# says what to turn off.
#
# Override the setup location with XOM_ROOT=/some/path.

set -euo pipefail

PLUGIN="AutoDuty"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XOM_ROOT="${XOM_ROOT:-$HOME/Library/Application Support/XIV on Mac}"

CONFIG="Debug"
ACTION="install"
DRY=0
BUILD=1
FORCE=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
run() {
    if [ "$DRY" -eq 1 ]; then
        printf '  would: %s\n' "$*"
    else
        "$@"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --release) CONFIG="Release" ;;
        --debug) CONFIG="Debug" ;;
        --no-build) BUILD=0 ;;
        --dry-run) DRY=1 ;;
        --status) ACTION="status" ;;
        --uninstall) ACTION="uninstall" ;;
        --paths) ACTION="paths" ;;
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

BUILD_DIR="$REPO_ROOT/$PLUGIN/bin/$CONFIG"
PLUGINS_DIR="$XOM_ROOT/installedPlugins/$PLUGIN"
DISABLED_DIR="$XOM_ROOT/$PLUGIN-installed-disabled"   # normal install parked here while the dev build is active
DEV_DIR="$XOM_ROOT/devPlugins/$PLUGIN"
CONFIG_DIR="$XOM_ROOT/pluginConfigs/$PLUGIN"
PATHS_DIR="$CONFIG_DIR/paths"
DALAMUD_CFG="$XOM_ROOT/dalamudConfig.json"

# dalamud's dev libraries to compile against. the game's own copy is right here
# and always matches the dalamud that will load the result.
DALAMUD_LIB="${DALAMUD_LIB:-}"
if [ -z "$DALAMUD_LIB" ]; then
    if [ -f "$XOM_ROOT/dalamud/Hooks/dev/Dalamud.dll" ]; then
        DALAMUD_LIB="$XOM_ROOT/dalamud/Hooks/dev/"
    elif [ -f "$HOME/.xlcore/dalamud/Hooks/dev/Dalamud.dll" ]; then
        DALAMUD_LIB="$HOME/.xlcore/dalamud/Hooks/dev/"
    fi
fi

[ -d "$XOM_ROOT" ] || die "XIV on Mac setup not found at: $XOM_ROOT (set XOM_ROOT to override)"

# wine maps the mac filesystem onto Z:, and dalamud stores windows-shaped paths
win_path() { printf 'Z:%s' "$(printf '%s' "$1" | tr '/' '\\')"; }

# parse rather than grep: the config stores the path json-escaped, with doubled backslashes
dev_registered() {
    [ -f "$DALAMUD_CFG" ] || return 1
    python3 - "$DALAMUD_CFG" "$(win_path "$DEV_DIR/$PLUGIN.dll")" <<'DEVCHECK'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
locs = (d.get("DevPluginLoadLocations") or {}).get("$values") or []
hit = next((v for v in locs if v.get("Path") == sys.argv[2] and v.get("IsEnabled")), None)
sys.exit(0 if hit and d.get("DevMode") else 1)
DEVCHECK
}

# dalamud's crash handler carries the game's own path in its command line, and it
# outlives the game often enough that matching the path alone reports a game that
# quit hours ago. match the game process itself.
game_running() {
    pgrep -fl "ffxiv_dx11" 2>/dev/null | grep -vi "DalamudCrashHandler" | grep -q .
}

# dalamud holds its configuration in memory and writes the whole file out when the
# game exits, so anything edited underneath a running game is thrown away. it also
# holds the plugin assemblies open.
assert_game_stopped() {
    [ "$DRY" -eq 1 ] && return 0
    if game_running; then
        [ "$FORCE" -eq 1 ] || die "FFXIV looks like it is running - quit the game first (or pass --force)"
        info "warning: FFXIV appears to be running, dalamud will overwrite this on exit"
    fi
}

build() {
    [ "$BUILD" -eq 1 ] || return 0
    # ECommons and friends are built from source as submodules, and a fresh clone
    # does not have them, which otherwise fails as a missing project reference.
    [ -f "$REPO_ROOT/ECommons/ECommons/ECommons.csproj" ] \
        || die "submodules are empty - run: git submodule update --init --recursive"

    local args=()
    [ -n "$DALAMUD_LIB" ] && args+=("-p:DalamudLibPath=$DALAMUD_LIB")
    info "building $CONFIG..."
    run dotnet build "$REPO_ROOT/$PLUGIN/$PLUGIN.csproj" -c "$CONFIG" -v q --nologo ${args[@]+"${args[@]}"}
}

do_status() {
    info "setup:      $XOM_ROOT"
    info "dalamud:    ${DALAMUD_LIB:-(not found, the build will use the csproj default)}"
    info "build dir:  $BUILD_DIR"
    if [ -f "$BUILD_DIR/$PLUGIN.dll" ]; then
        info "  built:    $(date -r "$BUILD_DIR/$PLUGIN.dll" '+%Y-%m-%d %H:%M')"
        [ -d "$BUILD_DIR/Localization" ] || info "  warning:  no Localization/ beside the assembly, the UI will fall back to keys"
    else
        info "  built:    (nothing built yet)"
    fi
    info "deployed:   $DEV_DIR"
    if [ -f "$DEV_DIR/$PLUGIN.dll" ]; then
        info "  copied:   $(date -r "$DEV_DIR/$PLUGIN.dll" '+%Y-%m-%d %H:%M')"
    else
        info "  copied:   (nothing deployed yet)"
    fi
    if dev_registered; then
        info "dev:        registered, hot reload on"
    else
        info "dev:        (not registered)"
    fi
    if [ -d "$PLUGINS_DIR" ]; then
        info "normal:     $PLUGINS_DIR ($(ls "$PLUGINS_DIR" | tr '\n' ' '))"
    else
        info "normal:     (not installed)"
    fi
    [ -d "$DISABLED_DIR" ] && info "parked:     $DISABLED_DIR"
    info "config:     $CONFIG_DIR"
    if [ -d "$PATHS_DIR" ]; then
        info "  paths:    $(find "$PATHS_DIR" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ') files"
        local differing
        differing="$(paths_differing | wc -l | tr -d ' ')"
        info "  vs repo:  $differing file(s) differ from this tree (see --paths)"
    fi
}

# path files in this tree that are missing from the game, or differ from what is there
paths_differing() {
    local f name
    for f in "$REPO_ROOT/$PLUGIN/Paths"/*.json; do
        name="$(basename "$f")"
        if [ ! -f "$PATHS_DIR/$name" ] || ! cmp -s "$f" "$PATHS_DIR/$name"; then
            printf '%s\n' "$name"
        fi
    done
}

do_paths() {
    [ -d "$PATHS_DIR" ] || die "no paths directory at $PATHS_DIR (start the plugin once first)"
    local names count
    names="$(paths_differing)"
    count="$(printf '%s' "$names" | grep -c . || true)"
    if [ "$count" -eq 0 ]; then
        info "paths are already identical to this tree."
        return
    fi
    info "copying $count path file(s) into $PATHS_DIR"
    # path file names carry spaces, quotes and parentheses, so read whole lines
    local name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        info "  $name"
        run cp "$REPO_ROOT/$PLUGIN/Paths/$name" "$PATHS_DIR/$name"
    done <<< "$names"
    info ""
    info "note: the plugin re-downloads path files from erdelf/AutoDuty on startup."
    info "turn 'Update Paths on Startup' off in the config tab, or mark the files you"
    info "are editing as do-not-update, or this copy is undone on the next launch."
}

# edits dalamudConfig.json in place, preserving the $type annotations newtonsoft needs
edit_dalamud_config() {
    local mode="$1" dll="$2"
    python3 - "$DALAMUD_CFG" "$mode" "$dll" <<'PY'
import json, sys, shutil, uuid, os
cfg, mode, dll = sys.argv[1], sys.argv[2], sys.argv[3]
bak = cfg + ".autoduty-backup"
if not os.path.exists(bak):
    shutil.copy(cfg, bak)
d = json.load(open(cfg))

locs = d.setdefault("DevPluginLoadLocations", {
    "$type": "System.Collections.Generic.List`1[[Dalamud.Configuration.DevPluginLocationSettings, Dalamud]], System.Private.CoreLib",
    "$values": []})
vals = locs.setdefault("$values", [])
settings = d.setdefault("DevPluginSettings", {
    "$type": "System.Collections.Generic.Dictionary`2[[System.String, System.Private.CoreLib],[Dalamud.Configuration.Internal.DevPluginSettings, Dalamud]], System.Private.CoreLib"})

# any other registration of this same dll name, left over from an earlier layout or from the
# other build config, would load a second copy and fight over the command and IPC names
leaf = dll.rsplit("\\", 1)[-1].lower()
stale = [v.get("Path") for v in vals
         if v.get("Path") != dll and (v.get("Path") or "").lower().endswith(leaf)]

# read the id before dropping the old entries, so it can be carried onto the new one
carried = next((settings[p].get("WorkingPluginId") for p in stale
                if p in settings and settings[p].get("WorkingPluginId")), None)
for path in stale:
    print("dropping stale registration: " + path)
    settings.pop(path, None)
vals[:] = [v for v in vals if v.get("Path") not in stale]

existing = next((v for v in vals if v.get("Path") == dll), None)

if mode == "add":
    if existing is None:
        vals.append({
            "$type": "Dalamud.Configuration.DevPluginLocationSettings, Dalamud",
            "Path": dll, "IsEnabled": True, "Nickname": None})
    else:
        existing["IsEnabled"] = True
    prev = settings.get(dll, {})
    settings[dll] = {
        "$type": "Dalamud.Configuration.Internal.DevPluginSettings, Dalamud",
        "StartOnBoot": True,
        "NotifyForErrors": True,
        "AutomaticReloading": True,
        # keep the id dalamud already assigned, so it does not treat this as a new plugin
        "WorkingPluginId": prev.get("WorkingPluginId") or carried or str(uuid.uuid4()),
        "DismissedValidationProblems": {
            "$type": "System.Collections.Generic.List`1[[System.String, System.Private.CoreLib]], System.Private.CoreLib",
            "$values": []},
    }
    d["DevMode"] = True
    print("registered dev plugin location")
else:
    locs["$values"] = [v for v in vals if v.get("Path") != dll]
    settings.pop(dll, None)
    print("unregistered dev plugin location")

json.dump(d, open(cfg, "w"), indent=2)
PY
}

# what a fresh install has to change: the dev registration in dalamud's config, and the
# normal install standing in the way. neither survives being edited under a running game,
# and neither is touched again once done, which is what lets a rebuild deploy mid-session.
config_change_needed() {
    ! dev_registered || [ -d "$PLUGINS_DIR" ]
}

do_install() {
    local first_time=0
    if config_change_needed; then
        first_time=1
        assert_game_stopped
    fi

    build
    [ "$DRY" -eq 1 ] || [ -f "$BUILD_DIR/$PLUGIN.dll" ] || die "no build output at $BUILD_DIR/$PLUGIN.dll"
    [ "$DRY" -eq 1 ] || [ -f "$BUILD_DIR/$PLUGIN.json" ] || die "no manifest at $BUILD_DIR/$PLUGIN.json"

    # two copies would both register /autoduty and the same IPC names, so park the normal install
    if [ "$first_time" -eq 1 ] && [ -d "$PLUGINS_DIR" ]; then
        if [ -d "$DISABLED_DIR" ]; then
            info "normal install already parked at $DISABLED_DIR, removing the live copy"
            run rm -rf "$PLUGINS_DIR"
        else
            info "parking normal install at $DISABLED_DIR"
            run mv "$PLUGINS_DIR" "$DISABLED_DIR"
        fi
    fi

    # the post-build copy is what makes hot reload work: dalamud watches the file it
    # was given, and only a path we write in place keeps that watch alive.
    info "installing post-build deploy to $DEV_DIR"
    if [ "$DRY" -eq 1 ]; then
        printf '  would: write %s/Directory.Build.targets\n' "$REPO_ROOT"
    else
        mkdir -p "$DEV_DIR"
        cat > "$REPO_ROOT/Directory.Build.targets" <<XML
<Project>
  <Target Name="DeployDalamudDev" AfterTargets="Build" Condition="'\$(MSBuildProjectName)' == '$PLUGIN'">
    <Exec Command="cp -f '\$(OutDir)'*.dll '\$(OutDir)'*.json '$DEV_DIR/' &amp;&amp; cp -Rf '\$(OutDir)Localization' '$DEV_DIR/'" />
  </Target>
</Project>
XML
        # rebuild so the copy actually runs once
        [ "$BUILD" -eq 1 ] && build >/dev/null
        # --no-build still has to get the current output over there
        [ "$BUILD" -eq 1 ] || { cp -f "$BUILD_DIR"/*.dll "$BUILD_DIR"/*.json "$DEV_DIR/"; cp -Rf "$BUILD_DIR/Localization" "$DEV_DIR/"; }
    fi

    if [ "$first_time" -eq 0 ]; then
        info ""
        info "done. already registered, so the config was left alone and dalamud reloads the"
        info "new build on its own. 'dotnet build' by itself does the same."
        return
    fi

    local dll
    dll="$(win_path "$DEV_DIR/$PLUGIN.dll")"
    info "dalamud path: $dll"
    if [ "$DRY" -eq 1 ]; then
        printf '  would: register %s in dalamudConfig.json with AutomaticReloading\n' "$dll"
    else
        edit_dalamud_config add "$dll"
    fi

    info ""
    info "done. start the game and check /autoduty."
    info "after this, 'dotnet build' alone deploys and dalamud reloads on its own."
    info "config and path files stay in: $CONFIG_DIR"
    info "dalamud config backed up once at $DALAMUD_CFG.autoduty-backup"
}

do_uninstall() {
    assert_game_stopped
    local dll
    dll="$(win_path "$DEV_DIR/$PLUGIN.dll")"

    if [ "$DRY" -eq 1 ]; then
        printf '  would: unregister %s\n' "$dll"
        [ -d "$DEV_DIR" ] && printf '  would: delete the deployed copy at %s\n' "$DEV_DIR"
        [ -f "$REPO_ROOT/Directory.Build.targets" ] && printf '  would: delete %s/Directory.Build.targets\n' "$REPO_ROOT"
    else
        [ -f "$DALAMUD_CFG" ] && edit_dalamud_config remove "$dll"
        rm -rf "$DEV_DIR"
        rm -f "$REPO_ROOT/Directory.Build.targets"
    fi

    if [ -d "$DISABLED_DIR" ] && [ ! -d "$PLUGINS_DIR" ]; then
        info "putting the normal install back"
        run mv "$DISABLED_DIR" "$PLUGINS_DIR"
    fi
    info "done."
}

case "$ACTION" in
    status) do_status ;;
    install) do_install ;;
    uninstall) do_uninstall ;;
    paths) do_paths ;;
esac
