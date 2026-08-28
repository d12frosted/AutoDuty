using AutoDuty.Data;
using Xunit;

namespace AutoDuty.Tests;

public class VariantRouteRandomTests
{
    private static readonly byte[] TwelveRoutes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

    [Fact]
    public void OnlyPicksAnEndingSomePathFileRuns()
    {
        byte[] runnable = [2, 5, 9];

        for (int seed = 0; seed < 50; seed++)
            Assert.Contains(VariantRoutePlan.RandomRoute(TwelveRoutes, runnable.Contains, new Random(seed))!.Value, runnable);
    }

    [Fact]
    public void ReachesEveryRunnableEndingEventually()
    {
        byte[] runnable = [2, 5, 9];
        HashSet<byte> seen = [];

        for (int seed = 0; seed < 50; seed++)
            seen.Add(VariantRoutePlan.RandomRoute(TwelveRoutes, runnable.Contains, new Random(seed))!.Value);

        Assert.Equal(runnable.ToHashSet(), seen);
    }

    [Fact]
    public void HasNothingToPickWhenNoPathFileRunsAnyRoute() =>
        Assert.Null(VariantRoutePlan.RandomRoute(TwelveRoutes, _ => false, new Random(1)));
}
