using System;
using System.Collections.Generic;
using System.Linq;

namespace AutoDuty.Data;

/// <summary>
/// Which ending of a variant duty to run next when the routes are being worked through rather
/// than picked by hand.
/// </summary>
public static class VariantRoutePlan
{
    /// <summary>
    /// The next route to run: walking on from <paramref name="lastRun"/> and wrapping around, the
    /// first route that a path file can run and whose ending has not been found yet. Once every
    /// ending is found this keeps rotating, so a loop that is only farming still moves on rather
    /// than repeating one route. Null when no path file runs any route of the duty.
    /// </summary>
    public static byte? NextRoute(IReadOnlyList<byte> routes, Func<byte, bool> found, Func<byte, bool> runnable, byte lastRun)
    {
        List<byte> candidates = [..routes.Where(runnable)];

        if (candidates.Count == 0)
            return null;

        // start looking after the route that just ran, so a route that did not register as found
        // does not trap the rotation on itself
        int start = candidates.FindIndex(route => route > lastRun);
        if (start < 0)
            start = 0;

        List<byte> order = [..candidates.Skip(start), ..candidates.Take(start)];

        foreach (byte route in order)
            if (!found(route))
                return route;

        return order[0];
    }

    /// <summary>
    /// A route picked at random among the ones a path file can run. Null when no path file runs
    /// any route of the duty.
    /// </summary>
    public static byte? RandomRoute(IReadOnlyList<byte> routes, Func<byte, bool> runnable, Random random)
    {
        List<byte> candidates = [..routes.Where(runnable)];

        return candidates.Count == 0 ? null : candidates[random.Next(candidates.Count)];
    }
}
