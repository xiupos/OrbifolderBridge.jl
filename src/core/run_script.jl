"""
    run_orbifolder_script(mode::Symbol, commands::Vector{<:AbstractString};
                           files::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
                           timeout::Real = 120) -> String

Run a list of CPrompt `commands` against the `orbifolder` (`mode = :susy`) or
`nonSUSYorbifolder` (`mode = :nonsusy`) binary and return the raw text
transcript for the `parse_*` functions in `src/core/parsers.jl` to consume.

Each call gets its own `mktempdir()`, so concurrent calls never share files
(see `parallel.jl`). `files` are extra inputs (e.g. `"model.txt" => ...`)
written into that directory before the binary runs; `Geometry/` is staged
automatically via [`orbifolder_geometry_dir`](@ref).

The two backends are driven differently (see `docs/upstream_notes.md`):
`nonSUSYorbifolder` has a documented `script <file>` CLI mode that writes its
transcript to `result_<file>`; `orbifolder` has no CLI batch mode, so commands
are instead fed via `load program(<file>)` over stdin, followed by a `yes` to
confirm the trailing `exit` command (the quit confirmation reads raw stdin,
not the command file) and its transcript is read back from stdout.
"""
function run_orbifolder_script(
    mode::Symbol,
    commands::Vector{<:AbstractString};
    files::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
    timeout::Real = 120,
)
    _check_mode(mode)
    binary = orbifolder_binary(mode)
    geometry_dir = orbifolder_geometry_dir(mode)

    mktempdir() do dir
        symlink(geometry_dir, joinpath(dir, "Geometry"))
        for (name, content) in files
            write(joinpath(dir, name), content)
        end

        command_file = "commands.txt"
        write(joinpath(dir, command_file), join(vcat(commands, "exit"), '\n') * '\n')

        if mode === :nonsusy
            run_capture(Cmd(`$binary script $command_file`; dir = dir); timeout = timeout)
            result_file = joinpath(dir, "result_$command_file")
            isfile(result_file) ||
                error("nonSUSYorbifolder script mode did not produce $result_file")
            return read(result_file, String)
        else
            return run_capture(
                Cmd(`$binary`; dir = dir);
                input = "load program($command_file)\nyes\n",
                timeout = timeout,
            )
        end
    end
end
