#!/usr/bin/env julia

# Convert Julia's source-line counters into a dependency-free, auditable report.
# Usage: julia --startup-file=no scripts/coverage.jl [package_root] [output_dir]
# Run Pkg.test(coverage=true) in a clean checkout before invoking this script.

using Dates
using TOML

json_string(value) = "\"" * replace(string(value), '\\' => "\\\\", '"' => "\\\"",
    '\n' => "\\n", '\r' => "\\r", '\t' => "\\t") * "\""
html_escape(value) = replace(string(value), '&' => "&amp;", '<' => "&lt;",
    '>' => "&gt;", '"' => "&quot;", '\'' => "&#39;")

function source_counters(root)
    src = joinpath(root, "src")
    isdir(src) || error("Missing source directory: $src")
    counters = Dict{String,Vector{Union{Nothing,Int}}}()
    for (dir, _, files) in walkdir(src), file in sort(files)
        occursin(r"\.jl\.(?:\d+\.)?cov$", file) || continue
        coverage_path = joinpath(dir, file)
        source_path = replace(coverage_path, r"\.(?:\d+\.)?cov$" => "")
        isfile(source_path) || error("Coverage refers to missing source: $coverage_path")
        source_lines = readlines(source_path)
        coverage_lines = readlines(coverage_path)
        length(source_lines) == length(coverage_lines) ||
            error("Coverage/source line count mismatch: $coverage_path")
        path = replace(relpath(source_path, root), '\\' => '/')
        counts = get!(counters, path) do
            Union{Nothing,Int}[nothing for _ in source_lines]
        end
        for (line, (source, record)) in enumerate(zip(source_lines, coverage_lines))
            parsed = match(r"^\s*(-|[0-9]+) (.*)$", record)
            isnothing(parsed) && error("Invalid coverage record: $coverage_path:$line")
            parsed.captures[2] == source ||
                error("Coverage/source content mismatch: $coverage_path:$line")
            parsed.captures[1] == "-" && continue
            hits = parse(Int, parsed.captures[1])
            counts[line] = Base.Checked.checked_add(something(counts[line], 0), hits)
        end
    end
    isempty(counters) && error("No Julia coverage files under $src; run tests with coverage=true first")
    # Julia may omit a module wrapper that only imports, exports, and includes
    # implementation files because none of its lines are instrumentable.
    function module_wrapper_only(path)
        logical = String[]
        exporting = false
        for raw in readlines(path)
            line = strip(first(split(raw, '#'; limit=2)))
            isempty(line) && continue
            if exporting
                endswith(line, ',') && continue
                exporting = false
                continue
            end
            startswith(line, "export ") && (exporting = endswith(line, ','); continue)
            any(startswith(line, prefix) for prefix in
                ("module ", "using ", "import ", "include(")) && continue
            line == "end" && continue
            return false
        end
        return true
    end
    # Missing implementation files must not silently disappear from the denominator.
    for (dir, _, files) in walkdir(src), file in files
        endswith(file, ".jl") || continue
        path = replace(relpath(joinpath(dir, file), root), '\\' => '/')
        haskey(counters, path) || module_wrapper_only(joinpath(dir, file)) ||
            error("Missing coverage for $path; run coverage in a clean checkout")
    end
    return counters
end

function write_report(root, output)
    counters = source_counters(root)
    paths = sort!(collect(keys(counters)))
    measured = Dict(path => count(!isnothing, counters[path]) for path in paths)
    covered = Dict(path => count(x -> !isnothing(x) && x > 0, counters[path]) for path in paths)
    total = sum(values(measured))
    hits = sum(values(covered))
    total > 0 || error("No instrumented source lines in coverage data")
    percentage = 100 * hits / total
    label = string(round(percentage; digits=2), "%")
    package = TOML.parsefile(joinpath(root, "Project.toml"))["name"]
    commit = get(ENV, "GITHUB_SHA", "")
    if isempty(commit)
        commit = try
            strip(read(`git -C $root rev-parse HEAD`, String))
        catch
            "unknown"
        end
    end
    generated = Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SS") * "Z"
    run_url = haskey(ENV, "GITHUB_RUN_ID") ?
        get(ENV, "GITHUB_SERVER_URL", "https://github.com") * "/" *
        ENV["GITHUB_REPOSITORY"] * "/actions/runs/" * ENV["GITHUB_RUN_ID"] : ""
    mkpath(output)
    open(joinpath(output, "summary.json"), "w") do io
        println(io, "{\"schema_version\":1,\"package\":", json_string(package),
            ",\"commit\":", json_string(commit), ",\"generated_at\":", json_string(generated),
            ",\"julia_version\":", json_string(VERSION), ",\"run_url\":", json_string(run_url),
            ",\"scope\":\"Julia instrumented source lines under src/\",",
            "\"covered_lines\":", hits, ",\"instrumented_lines\":", total,
            ",\"percentage\":", percentage, ",\"files\":[")
        for (index, path) in enumerate(paths)
            print(io, "{\"path\":", json_string(path), ",\"covered_lines\":", covered[path],
                ",\"instrumented_lines\":", measured[path], "}")
            println(io, index < length(paths) ? "," : "")
        end
        println(io, "]}")
    end
    open(joinpath(output, "lcov.info"), "w") do io
        for path in paths
            println(io, "TN:\nSF:", path)
            for (line, value) in enumerate(counters[path])
                isnothing(value) || println(io, "DA:", line, ",", value)
            end
            println(io, "LF:", measured[path], "\nLH:", covered[path], "\nend_of_record")
        end
    end
    color = percentage >= 90 ? "#4c1" : percentage >= 75 ? "#dfb317" : "#e05d44"
    open(joinpath(output, "coverage.svg"), "w") do io
        print(io, """
        <svg xmlns="http://www.w3.org/2000/svg" width="148" height="20" role="img" aria-label="Line coverage: $label">
          <title>Line coverage: $label ($hits/$total instrumented source lines)</title>
          <rect width="92" height="20" fill="#555"/><rect x="92" width="56" height="20" fill="$color"/>
          <g fill="#fff" text-anchor="middle" font-family="Verdana,DejaVu Sans,sans-serif" font-size="11">
            <text x="46" y="14">line coverage</text><text x="120" y="14">$label</text>
          </g>
        </svg>
        """)
    end
    summary = """
    ## Source line coverage

    $package: **$label** ($hits / $total instrumented source lines).

    Commit: `$commit` · Julia $VERSION · Generated $generated

    This measures executed Julia-instrumented lines under `src/`, not branch coverage,
    financial model accuracy, or correctness of unexecuted paths. Julia excludes
    non-instrumented lines from the denominator. Run in a clean checkout to avoid stale counters.

    | Source file | Covered | Instrumented |
    | --- | ---: | ---: |
    """
    for path in paths
        summary *= "| `$path` | $(covered[path]) | $(measured[path]) |\n"
    end
    write(joinpath(output, "summary.md"), summary)
    if !isempty(get(ENV, "GITHUB_STEP_SUMMARY", ""))
        open(ENV["GITHUB_STEP_SUMMARY"], "a") do io
            write(io, summary)
        end
    end
    open(joinpath(output, "index.html"), "w") do io
        println(io, "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
            "<title>", html_escape(package), " coverage</title>",
            "<style>body{font:16px system-ui;max-width:60rem;margin:3rem auto;padding:0 1rem;line-height:1.6}",
            "table{border-collapse:collapse;width:100%}td,th{padding:.4rem;text-align:left;border-bottom:1px solid #ddd}",
            "code{overflow-wrap:anywhere}</style><h1>", html_escape(package), " source line coverage</h1>",
            "<p><img src=\"coverage.svg\" alt=\"", html_escape(label), " line coverage\"></p>",
            "<p>", hits, " of ", total, " instrumented source lines executed.</p>",
            "<p>Commit: <code>", html_escape(commit), "</code><br>Julia ", VERSION,
            "<br>Generated ", generated, "</p>",
            "<p>This measures executed Julia-instrumented lines under <code>src/</code>, not branch coverage, ",
            "financial model accuracy, or correctness of unexecuted paths. Non-instrumented lines are excluded ",
            "from the denominator. Reports must be generated in a clean checkout.</p>",
            "<p><a href=\"summary.json\">JSON data</a> · <a href=\"lcov.info\">LCOV data</a></p>")
        isempty(run_url) || println(io, "<p><a href=\"", html_escape(run_url), "\">CI run</a></p>")
        println(io, "<table><tr><th>Source file</th><th>Covered</th><th>Instrumented</th></tr>")
        for path in paths
            println(io, "<tr><td><code>", html_escape(path), "</code></td><td>", covered[path],
                "</td><td>", measured[path], "</td></tr>")
        end
        println(io, "</table></html>")
    end
    println("Coverage: $hits/$total ($label); report: $output")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) <= 2 || error("Usage: coverage.jl [package_root] [output_dir]")
    root = isempty(ARGS) ? dirname(@__DIR__) : abspath(ARGS[1])
    output = length(ARGS) < 2 ? joinpath(root, "coverage-report") : abspath(ARGS[2])
    write_report(root, output)
end
