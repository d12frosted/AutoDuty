using AutoDuty.Data;
using Xunit;

namespace AutoDuty.Tests;

public class VariantRoutePlanTests
{
    private static readonly byte[] TwelveRoutes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

    private static byte? Next(byte[] routes, byte[] found, byte[] runnable, byte lastRun) =>
        VariantRoutePlan.NextRoute(routes, route => found.Contains(route), route => runnable.Contains(route), lastRun);

    [Fact]
    public void StartsAtTheFirstEndingThatIsStillMissing() =>
        Assert.Equal((byte)3, Next(TwelveRoutes, [1, 2], TwelveRoutes, 0));

    [Fact]
    public void SkipsEndingsNoPathFileCanRun() =>
        Assert.Equal((byte)5, Next(TwelveRoutes, [], [5, 6, 7], 0));

    [Fact]
    public void GoesOnFromTheRouteJustRun() =>
        Assert.Equal((byte)8, Next(TwelveRoutes, [], TwelveRoutes, 7));

    [Fact]
    public void WrapsAroundToReachTheEndingsBeforeIt() =>
        Assert.Equal((byte)2, Next(TwelveRoutes, [11, 12, 1], TwelveRoutes, 10));

    [Fact]
    public void KeepsRotatingOnceEveryEndingIsFound() =>
        Assert.Equal((byte)4, Next(TwelveRoutes, TwelveRoutes, TwelveRoutes, 3));

    [Fact]
    public void HasNothingToRunWhenNoPathFileRunsAnyRoute() =>
        Assert.Null(Next(TwelveRoutes, [], [], 0));

    [Fact]
    public void HasNothingToRunWhenTheDutyHasNoRoutes() =>
        Assert.Null(Next([], [], [], 0));

    [Fact]
    public void TreatsAnUnknownLastRouteAsAFreshStart() =>
        Assert.Equal((byte)1, Next(TwelveRoutes, [], TwelveRoutes, 200));
}
