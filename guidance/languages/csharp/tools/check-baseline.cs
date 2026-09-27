#:property Nullable=enable
#:property TreatWarningsAsErrors=true

using System.Runtime.CompilerServices;
using System.Xml;
using System.Xml.Linq;

/// <summary>
/// Verifies that a project has adopted dev-qual's C# build baseline:
/// <c>Baseline.props</c>, imported from <c>Directory.Build.props</c>, and
/// <c>Baseline.targets</c>, imported from <c>Directory.Build.targets</c>
/// (split across the two because one setting in <c>Baseline.targets</c>
/// must be evaluated after the project's own package references).
///
/// Looks for each of the project's <c>Directory.Build.*</c> files and
/// checks whether it imports the matching baseline file from this same
/// directory. Prints the exact <c>&lt;Import ... /&gt;</c> line to add for
/// whichever half is missing, so adoption is copy-paste rather than a
/// search.
/// </summary>
internal static class CheckBaseline
{
    /// <summary>One half of the baseline: a Directory.Build.* file name paired with
    /// the dev-qual baseline file it must import.</summary>
    private sealed record BaselinePart(string BuildFileName, string BaselineFileName);

    private static readonly BaselinePart PropsPart = new("Directory.Build.props", "Baseline.props");
    private static readonly BaselinePart TargetsPart = new("Directory.Build.targets", "Baseline.targets");

    private const string Help = """
        check-baseline — verify a project adopts dev-qual's C# build baseline

        Usage:
          dotnet run check-baseline.cs -- [--project <dir>]

        Options:
          --project <dir>  Project directory to check (default: current directory)
          --help           Show this help and exit

        Exit codes:
          0  baseline adopted (both halves), or the directory is not a dotnet project
          1  a baseline half is not adopted (prints the line to add)
          2  invalid arguments, or a Directory.Build.* file could not be parsed
        """;

    /// <summary>Captures this source file's own absolute path at compile time, so the
    /// tool can find Baseline.props/Baseline.targets beside it regardless of the
    /// caller's cwd.</summary>
    private static string ThisFilePath([CallerFilePath] string path = "") => path;

    /// <summary>The directory this script lives in, where the baseline files sit too.</summary>
    private static string ToolsDir { get; } = Path.GetDirectoryName(ThisFilePath())!;

    /// <summary>Reports whether a directory looks like a dotnet project: a solution or
    /// project file at its top level, or one level down.</summary>
    private static bool IsDotnetProject(string dir)
    {
        if (HasProjectMarker(dir))
        {
            return true;
        }
        return Directory.EnumerateDirectories(dir).Any(HasProjectMarker);
    }

    /// <summary>Reports whether a single directory (non-recursively) contains a
    /// solution or project file.</summary>
    private static bool HasProjectMarker(string dir) =>
        Directory.EnumerateFiles(dir, "*.sln").Any() ||
        Directory.EnumerateFiles(dir, "*.slnx").Any() ||
        Directory.EnumerateFiles(dir, "*.csproj").Any();

    /// <summary>Builds a forward-slash path from one directory to a file, MSBuild-style.</summary>
    private static string RelativeImportPath(string fromDir, string target)
    {
        var relative = Path.GetRelativePath(fromDir, target);
        return relative.Replace(Path.DirectorySeparatorChar, '/');
    }

    /// <summary>Builds the exact <c>&lt;Import ... /&gt;</c> line to adopt a baseline
    /// file from a project root: relative via <c>$(MSBuildThisFileDirectory)</c> when
    /// the baseline lives inside the project, absolute otherwise.</summary>
    private static string ImportLine(string projectDir, string baselinePath)
    {
        var relative = RelativeImportPath(projectDir, baselinePath);
        if (!relative.StartsWith("..", StringComparison.Ordinal))
        {
            return $"<Import Project=\"$(MSBuildThisFileDirectory){relative}\" />";
        }
        return $"<Import Project=\"{baselinePath}\" />";
    }

    /// <summary>Builds a complete minimal Directory.Build.props/.targets file to create.</summary>
    private static string MinimalBuildFile(string importLine) =>
        $"""
        <Project>
          {importLine}
        </Project>
        """;

    /// <summary>Reports whether a Directory.Build.* document imports the named baseline file.</summary>
    private static bool AdoptsBaseline(XDocument document, string baselineFileName) =>
        document.Descendants()
            .Where(element => element.Name.LocalName == "Import")
            .Select(element => element.Attribute("Project")?.Value ?? string.Empty)
            .Any(project => project.EndsWith(baselineFileName, StringComparison.Ordinal));

    /// <summary>Checks one half of the baseline (props or targets) for a project,
    /// printing a diagnostic when it isn't fully adopted. Returns the exit code for
    /// this half (1 missing/not-adopted, 2 malformed XML), or null when adopted.</summary>
    private static int? CheckPart(string projectDir, BaselinePart part)
    {
        var baselinePath = Path.Combine(ToolsDir, part.BaselineFileName);
        var buildFile = Path.Combine(projectDir, part.BuildFileName);
        var importLine = ImportLine(projectDir, baselinePath);

        if (!File.Exists(buildFile))
        {
            Console.WriteLine($"No {part.BuildFileName} found. Create one:");
            Console.WriteLine();
            Console.WriteLine(MinimalBuildFile(importLine));
            return 1;
        }

        XDocument document;
        try
        {
            document = XDocument.Load(buildFile);
        }
        catch (XmlException error)
        {
            Console.Error.WriteLine($"error: {error.Message}");
            return 2;
        }

        if (AdoptsBaseline(document, part.BaselineFileName))
        {
            return null;
        }

        Console.WriteLine($"{buildFile} does not adopt the dev-qual baseline. Add:");
        Console.WriteLine(importLine);
        return 1;
    }

    /// <summary>Runs the adoption check for a project directory, printing the result.
    /// Returns the process exit code.</summary>
    private static int Check(string projectDirArg)
    {
        var projectDir = Path.GetFullPath(projectDirArg);

        if (!IsDotnetProject(projectDir))
        {
            Console.WriteLine("not a dotnet project");
            return 0;
        }

        var propsResult = CheckPart(projectDir, PropsPart);
        if (propsResult is { } propsExitCode)
        {
            return propsExitCode;
        }

        var targetsResult = CheckPart(projectDir, TargetsPart);
        if (targetsResult is { } targetsExitCode)
        {
            return targetsExitCode;
        }

        var propsFile = Path.Combine(projectDir, PropsPart.BuildFileName);
        var targetsFile = Path.Combine(projectDir, TargetsPart.BuildFileName);
        Console.WriteLine($"baseline: adopted ({propsFile}, {targetsFile})");
        return 0;
    }

    /// <summary>Parses argv into a project directory. Prints help/usage and exits the
    /// process directly on <c>--help</c> or an invalid argument.</summary>
    private static string ParseArgs(string[] args)
    {
        string? projectDir = null;
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--help":
                    Console.WriteLine(Help);
                    Environment.Exit(0);
                    break;
                case "--project":
                    if (i + 1 >= args.Length)
                    {
                        Console.Error.WriteLine("--project needs a directory");
                        Console.Error.WriteLine(Help);
                        Environment.Exit(2);
                    }
                    projectDir = args[++i];
                    break;
                default:
                    Console.Error.WriteLine($"Unknown argument: {args[i]}");
                    Console.Error.WriteLine(Help);
                    Environment.Exit(2);
                    break;
            }
        }
        return projectDir ?? Directory.GetCurrentDirectory();
    }

    /// <summary>Entry point: runs check-baseline as a CLI tool.</summary>
    private static int Main(string[] args)
    {
        var projectDir = ParseArgs(args);
        return Check(projectDir);
    }
}
