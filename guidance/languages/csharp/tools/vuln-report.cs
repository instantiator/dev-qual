#:property Nullable=enable
#:property TreatWarningsAsErrors=true
#:property PublishAot=false

using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>
/// Turns <c>dotnet list package --vulnerable --include-transitive --format
/// json</c> into a ranked, actionable next-steps report.
///
/// JSON shape (verified against a live run of the command, .NET SDK
/// 10.0.401, and https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-list-package):
/// <c>{"version":1,"projects":[{"path","frameworks":[{"framework","topLevelPackages":[{"id","requestedVersion","resolvedVersion","vulnerabilities":[{"severity","advisoryurl"}]}],"transitivePackages":[...]}]}]}</c>.
/// A project with nothing to report omits its <c>frameworks</c> array
/// entirely, and a package with nothing vulnerable omits
/// <c>vulnerabilities</c> — every list field below is therefore nullable.
///
/// There is no fixed-in version in this output (unlike <c>npm audit</c> or
/// <c>pip-audit</c>): the recommended action instead points at the
/// advisory URL and, for a transitive package, at the top-level package
/// that brought it in.
/// </summary>
internal static class VulnReport
{
    private const string DependenciesDoc = "guidance/standards/dependencies.md";

    private const string Help = """
        vuln-report — ranked, actionable dotnet list package --vulnerable report

        Usage:
          dotnet run vuln-report.cs -- [--project <dir>] [--input <file>]

        Options:
          --project <dir>  Project or solution directory to audit (default: current directory)
          --input <file>   Read a saved `dotnet list package --vulnerable --include-transitive
                            --format json` report instead of running the command
          --help           Show this help and exit

        Exit codes:
          0  no vulnerabilities
          1  vulnerabilities found (report printed)
          2  error (bad JSON, dotnet missing, or the command could not run)
        """;

    private static readonly string[] SeverityOrder = ["Critical", "High", "Moderate", "Low"];

    /// <summary>One vulnerability entry as `dotnet list package` reports it.</summary>
    private sealed record Vulnerability(
        [property: JsonPropertyName("severity")] string Severity,
        [property: JsonPropertyName("advisoryurl")] string AdvisoryUrl);

    /// <summary>One package entry (top-level or transitive) as `dotnet list package` reports it.</summary>
    private sealed record Package(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("resolvedVersion")] string? ResolvedVersion,
        [property: JsonPropertyName("vulnerabilities")] List<Vulnerability>? Vulnerabilities);

    /// <summary>One target framework's package lists, as `dotnet list package` reports it.</summary>
    private sealed record Framework(
        [property: JsonPropertyName("topLevelPackages")] List<Package>? TopLevelPackages,
        [property: JsonPropertyName("transitivePackages")] List<Package>? TransitivePackages);

    /// <summary>One project's frameworks, as `dotnet list package` reports it.</summary>
    private sealed record ProjectReport(
        [property: JsonPropertyName("path")] string Path,
        [property: JsonPropertyName("frameworks")] List<Framework>? Frameworks);

    /// <summary>The full `dotnet list package --format json` document.</summary>
    private sealed record AuditReport(
        [property: JsonPropertyName("projects")] List<ProjectReport>? Projects);

    /// <summary>One vulnerable package, de-duplicated across projects/frameworks and ready to rank.</summary>
    private sealed record Finding(
        string Id,
        string ResolvedVersion,
        bool IsTopLevel,
        string Severity,
        string AdvisoryUrl,
        List<string> Projects);

    /// <summary>Builds the recommended action for a vulnerable package.</summary>
    private static string DescribeAction(Finding finding) => finding.IsTopLevel
        ? $"dotnet add {finding.Projects[0]} package {finding.Id}  " +
          $"(check {finding.AdvisoryUrl} for the fixed version; MAJOR bumps — ask the user first)"
        : $"update the top-level package that brings it in, or pin {finding.Id} explicitly with " +
          $"dotnet add package (see {DependenciesDoc})";

    /// <summary>Ranks the severity of a vulnerability entry into worst-first order (0 = worst).</summary>
    private static int SeverityRank(string severity)
    {
        var index = Array.IndexOf(SeverityOrder, severity);
        return index < 0 ? SeverityOrder.Length : index;
    }

    /// <summary>Flattens every (package, vulnerability) pair out of one project's report,
    /// tagging each with whether it came from the top-level or transitive list.</summary>
    private static IEnumerable<(Package Package, bool IsTopLevel, string ProjectPath, Vulnerability Vuln)>
        FlattenVulnerabilities(ProjectReport project)
    {
        foreach (var framework in project.Frameworks ?? [])
        {
            foreach (var package in framework.TopLevelPackages ?? [])
            {
                foreach (var vuln in package.Vulnerabilities ?? [])
                {
                    yield return (package, true, project.Path, vuln);
                }
            }
            foreach (var package in framework.TransitivePackages ?? [])
            {
                foreach (var vuln in package.Vulnerabilities ?? [])
                {
                    yield return (package, false, project.Path, vuln);
                }
            }
        }
    }

    /// <summary>Builds the de-duplicated, ranked findings from a parsed audit report.
    /// A package appearing in several projects or frameworks is merged into one finding
    /// that lists every project it came from.</summary>
    private static List<Finding> BuildFindings(AuditReport report)
    {
        var flattened = (report.Projects ?? [])
            .SelectMany(FlattenVulnerabilities)
            .ToList();

        var grouped = flattened
            .GroupBy(entry => (entry.Package.Id, entry.Vuln.Severity, entry.Vuln.AdvisoryUrl));

        var findings = grouped
            .Select(group =>
            {
                var first = group.First();
                return new Finding(
                    Id: first.Package.Id,
                    ResolvedVersion: first.Package.ResolvedVersion ?? "unknown",
                    IsTopLevel: group.Any(entry => entry.IsTopLevel),
                    Severity: first.Vuln.Severity,
                    AdvisoryUrl: first.Vuln.AdvisoryUrl,
                    Projects: group.Select(entry => entry.ProjectPath).Distinct().ToList());
            })
            .ToList();

        return findings
            .OrderBy(finding => SeverityRank(finding.Severity))
            .ThenBy(finding => finding.IsTopLevel ? 0 : 1)
            .ThenBy(finding => finding.Id, StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>Formats one finding as a fixed-column report line.</summary>
    private static string FormatRow(Finding finding)
    {
        var directness = finding.IsTopLevel ? "direct" : "transitive";
        var severity = finding.Severity.ToUpperInvariant().PadRight(8);
        return $"{severity}  {finding.Id}  {finding.ResolvedVersion}  {directness}  {DescribeAction(finding)}";
    }

    /// <summary>Builds the summary line: counts by severity plus the next-step guidance.</summary>
    private static string FormatSummary(List<Finding> findings)
    {
        var counts = string.Join(", ", SeverityOrder
            .Select(severity => (severity, count: findings.Count(finding =>
                string.Equals(finding.Severity, severity, StringComparison.OrdinalIgnoreCase))))
            .Where(pair => pair.count > 0)
            .Select(pair => $"{pair.count} {pair.severity.ToLowerInvariant()}"));

        return $"Summary: {findings.Count} vulnerable package(s) ({counts}). " +
               "Next: apply fixes in small groups, security first, running check.sh after each (skills/deps-audit)";
    }

    /// <summary>Builds the full report text and exit code from a parsed audit report.</summary>
    private static (string Text, int ExitCode) BuildReport(AuditReport report)
    {
        var findings = BuildFindings(report);
        if (findings.Count == 0)
        {
            return ("No vulnerabilities found.", 0);
        }

        var lines = findings.Select(FormatRow).Append(string.Empty).Append(FormatSummary(findings));
        return (string.Join('\n', lines), 1);
    }

    /// <summary>Runs `dotnet list package --vulnerable --include-transitive --format json`
    /// in a project directory and returns its stdout.</summary>
    private static string RunDotnetListPackage(string projectDir)
    {
        var startInfo = new ProcessStartInfo("dotnet", "list package --vulnerable --include-transitive --format json")
        {
            WorkingDirectory = projectDir,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("could not start dotnet");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0 && string.IsNullOrWhiteSpace(output))
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "dotnet list package failed" : error);
        }
        return output;
    }

    /// <summary>Loads the raw audit JSON text, from --input or by running dotnet.</summary>
    private static string LoadAuditJson(string? inputFile, string projectDir) =>
        inputFile is not null ? File.ReadAllText(inputFile) : RunDotnetListPackage(projectDir);

    /// <summary>Options for deserialising the audit report: case-insensitive property
    /// matching handles the lowercase `advisoryurl` field alongside the camelCase rest.</summary>
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>Parses command-line arguments into (projectDir, inputFile), or prints
    /// help/usage and exits the process directly on --help or an invalid argument.</summary>
    private static (string ProjectDir, string? InputFile) ParseArgs(string[] args)
    {
        string? projectDir = null;
        string? inputFile = null;
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--help":
                    Console.WriteLine(Help);
                    Environment.Exit(0);
                    break;
                case "--project":
                    projectDir = RequireValue(args, ref i, "--project");
                    break;
                case "--input":
                    inputFile = RequireValue(args, ref i, "--input");
                    break;
                default:
                    Console.Error.WriteLine($"Unknown argument: {args[i]}");
                    Console.Error.WriteLine(Help);
                    Environment.Exit(2);
                    break;
            }
        }
        return (projectDir ?? Directory.GetCurrentDirectory(), inputFile);
    }

    /// <summary>Reads the value following a flag at position `i`, advancing `i`, or exits 2.</summary>
    private static string RequireValue(string[] args, ref int i, string flag)
    {
        if (i + 1 >= args.Length)
        {
            Console.Error.WriteLine($"{flag} needs a value");
            Console.Error.WriteLine(Help);
            Environment.Exit(2);
        }
        return args[++i];
    }

    /// <summary>Entry point: runs vuln-report as a CLI tool.</summary>
    private static int Main(string[] args)
    {
        var (projectDir, inputFile) = ParseArgs(args);

        string rawJson;
        try
        {
            rawJson = LoadAuditJson(inputFile, projectDir);
        }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            Console.Error.WriteLine($"vuln-report: could not run dotnet list package: {error.Message}");
            return 2;
        }

        AuditReport? report;
        try
        {
            report = JsonSerializer.Deserialize<AuditReport>(rawJson, JsonOptions);
        }
        catch (JsonException error)
        {
            Console.Error.WriteLine($"vuln-report: could not parse dotnet list package output: {error.Message}");
            return 2;
        }

        if (report is null)
        {
            Console.Error.WriteLine("vuln-report: dotnet list package output was empty");
            return 2;
        }

        var (text, exitCode) = BuildReport(report);
        Console.WriteLine(text);
        return exitCode;
    }
}
