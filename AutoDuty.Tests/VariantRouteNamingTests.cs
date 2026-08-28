using AutoDuty.Data;
using Xunit;

namespace AutoDuty.Tests;

public class VariantRouteNamingTests
{
    [Theory]
    [InlineData("(1069) The Sil'dihn Subterrane - Exit 1 - Left.json", 1)]
    [InlineData("(1069) The Sil'dihn Subterrane - Exit 12 - Right.json", 12)]
    [InlineData("(1137) Mount Rokkon - Exit 7 - Middle.json", 7)]
    [InlineData("(1176) Aloalo Island - Path 3.json", 3)]
    public void ReadsTheRouteAFileNameNames(string fileName, byte expected)
    {
        Assert.True(VariantRouteNaming.TryParseRoute(fileName, out byte route));
        Assert.Equal(expected, route);
    }

    [Theory]
    [InlineData("(1315) The Merchant's Tale.json")]                  // one file, branches inside
    [InlineData("(1069) The Sil'dihn Subterrane.json")]              // no route in the name
    [InlineData("(1176) Aloalo Island - Path.json")]                 // no number to read
    public void SaysNothingWhenTheNameNamesNoRoute(string fileName) =>
        Assert.False(VariantRouteNaming.TryParseRoute(fileName, out _));

    [Fact]
    public void DoesNotReadTheTerritoryAsARoute() =>
        Assert.False(VariantRouteNaming.TryParseRoute("(1176) Aloalo Island.json", out _));

    [Fact]
    public void RejectsARouteThatCannotBeAVariantRoute() =>
        Assert.False(VariantRouteNaming.TryParseRoute("(1069) The Sil'dihn Subterrane - Exit 0 - Left.json", out _));
}
