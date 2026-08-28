using System.Text.RegularExpressions;

namespace AutoDuty.Data;

/// <summary>
/// The older variant duties have one path file per ending, and the ending a file runs is written
/// in its name ("Exit 7 - Middle", "Path 3"). Reading that back is what ties a path file to the
/// route number the player votes for.
/// </summary>
public static partial class VariantRouteNaming
{
    [GeneratedRegex(@"\b(?:Exit|Path|Route)\s+([0-9]{1,2})\b", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)]
    private static partial Regex RouteInNameRegex();

    /// <summary>Reads the route a path file name names, if it names one.</summary>
    public static bool TryParseRoute(string fileName, out byte route)
    {
        route = 0;
        Match match = RouteInNameRegex().Match(fileName);

        // routes are voted for by number, starting at one; zero means "no route chosen yet" and is
        // never a file's own route
        return match.Success && byte.TryParse(match.Groups[1].ValueSpan, out route) && route > 0;
    }
}
