using AutoDuty.Data;
using AutoDuty.Managers;
using ECommons.DalamudServices;
using FFXIVClientStructs.FFXIV.Client.Game.UI;
using Lumina.Excel.Sheets;

namespace AutoDuty.Helpers
{
    using System.Collections.Generic;
    using System.Linq;

    /// <summary>
    /// Which endings of a variant duty the player has already found.
    ///
    /// Every variant duty writes one notebook note per route, and the notes of a duty are the rows
    /// of its VVDNotebookSeries, in route order. The game remembers the notes a character has
    /// collected in PlayerState, so the routes still missing can be read straight off it.
    /// </summary>
    internal static class VariantHelper
    {
        /// <summary>
        /// One ending of a variant duty. <see cref="Index"/> is the route number the player votes
        /// for and the value path files match on, so it is what <see cref="AutoDuty.VariantPath"/>
        /// holds while that route is being run.
        /// </summary>
        internal readonly record struct VariantRoute(byte Index, uint NoteRowId, string NoteName)
        {
            internal bool Found => NoteFound(this.NoteRowId);
        }

        private static readonly Dictionary<uint, List<VariantRoute>> routesByTerritory = [];

        /// <summary>The routes of the variant duty in <paramref name="territoryType"/>, in route order.</summary>
        internal static IReadOnlyList<VariantRoute> Routes(uint territoryType)
        {
            if (routesByTerritory.TryGetValue(territoryType, out List<VariantRoute>? cached))
                return cached;

            List<VariantRoute> routes = [];

            VVDData? variantData = Svc.Data.GetExcelSheet<VVDData>()?
                                     .FirstOrDefault(data => data.ContentFinderCondition.ValueNullable?.TerritoryType.RowId == territoryType);

            if (variantData is { Series: > 0 } data &&
                Svc.Data.GetExcelSheet<VVDNotebookSeries>()?.GetRowOrDefault(data.Series) is { } series)
            {
                byte index = 0;
                foreach (Lumina.Excel.RowRef<VVDNotebookContents> note in series.Contents)
                {
                    index++;
                    // the series holds a fixed number of note slots, and the shorter series pad the
                    // tail with row 0
                    if (note.RowId == 0)
                        continue;

                    routes.Add(new VariantRoute(index, note.RowId, note.ValueNullable?.Name.ToString() ?? string.Empty));
                }
            }

            routesByTerritory[territoryType] = routes;
            return routes;
        }

        /// <summary>Has this character collected the note a route writes?</summary>
        internal static unsafe bool NoteFound(uint noteRowId)
        {
            PlayerState* playerState = PlayerState.Instance();
            if (playerState == null || noteRowId == 0)
                return false;

            // the notes are rows 1 and up, row 0 being the empty one every sheet carries, and they
            // are tracked from the first bit, so the bit of a note sits one below its row
            return playerState->CompletedVVDNotebookContentsBitArray.TryGet((int)noteRowId - 1, out bool found) && found;
        }

        /// <summary>The routes of a variant duty whose ending the player is still missing.</summary>
        internal static IEnumerable<VariantRoute> MissingRoutes(uint territoryType) =>
            Routes(territoryType).Where(route => !route.Found);

        /// <summary>Is there a path file that can run this route?</summary>
        internal static bool RouteHasPath(uint territoryType, byte route) =>
            ContentPathsManager.DictionaryPaths.TryGetValue(territoryType, out ContentPathsManager.ContentPathContainer? container) &&
            container.Paths.ToList().Any(path => path.RunsVariantRoute(route));

        private static readonly System.Random random = new();

        /// <summary>
        /// The route the next run of this duty should take, from the way routes are being picked.
        /// Null when the vote decides, or when no path file runs any route.
        /// </summary>
        internal static byte? RouteForNextRun(uint territoryType, byte lastRun) =>
            AutoDuty.Configuration.VariantRouteModeEnum switch
            {
                Data.Enums.VariantRouteMode.Fixed         => AutoDuty.Configuration.VariantRouteFixed,
                Data.Enums.VariantRouteMode.Random        => VariantRoutePlan.RandomRoute([..Routes(territoryType).Select(route => route.Index)],
                                                                                          index => RouteHasPath(territoryType, index),
                                                                                          random),
                Data.Enums.VariantRouteMode.Completionist => NextRouteToRun(territoryType, lastRun),
                _                                         => null
            };

        /// <summary>
        /// The route this duty is set to run, for picking its path file before a run is queued. A
        /// route already in flight wins; otherwise it comes from the way routes are being chosen,
        /// and the ways that only decide at queue time have no answer to give yet.
        /// </summary>
        internal static byte RouteForPathSelection(uint territoryType)
        {
            if (AutoDuty.Plugin.VariantPath > 0)
                return AutoDuty.Plugin.VariantPath;

            return AutoDuty.Configuration.VariantRouteModeEnum switch
                   {
                       Data.Enums.VariantRouteMode.Fixed         => AutoDuty.Configuration.VariantRouteFixed,
                       Data.Enums.VariantRouteMode.Completionist => NextRouteToRun(territoryType, 0) ?? (byte)0,
                       _                                         => (byte)0
                   };
        }

        /// <summary>
        /// The route to run next when working through the endings of a variant duty, going on from
        /// <paramref name="lastRun"/>. Null when no path file runs any of its routes.
        /// </summary>
        internal static byte? NextRouteToRun(uint territoryType, byte lastRun)
        {
            IReadOnlyList<VariantRoute> routes = Routes(territoryType);

            return VariantRoutePlan.NextRoute([..routes.Select(route => route.Index)],
                                              index => routes.Any(route => route.Index == index && route.Found),
                                              index => RouteHasPath(territoryType, index),
                                              lastRun);
        }
    }
}
