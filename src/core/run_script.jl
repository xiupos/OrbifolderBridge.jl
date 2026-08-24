# Internal execution primitive. Each call stages inputs and Geometry in an
# isolated temporary directory, normalizes the two backend batch protocols,
# and reads requested output artifacts before cleanup.
function _run_orbifolder_script_artifacts(
    mode::Symbol,
    commands::Vector{<:AbstractString};
    files::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
    collect_files::Vector{<:AbstractString} = String[],
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
            output = read(result_file, String)
        else
            output = run_capture(
                Cmd(`$binary`; dir = dir);
                input = "load program($command_file)\nyes\n",
                timeout = timeout,
            )
        end

        artifacts = Dict{String,String}()
        for name in collect_files
            basename(name) == name || throw(ArgumentError("artifact name must be a basename, got $name"))
            path = joinpath(dir, name)
            isfile(path) && (artifacts[String(name)] = read(path, String))
        end
        return (; output, files = artifacts)
    end
end


function _run_orbifolder_script(
    mode::Symbol,
    commands::Vector{<:AbstractString};
    files::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
    timeout::Real = 120,
)
    result = _run_orbifolder_script_artifacts(
        mode,
        commands;
        files = files,
        timeout = timeout,
    )
    return result.output
end

"""
    run_orbifolder_script(mode::Symbol, commands::Vector{<:AbstractString};
                           files::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
                           timeout::Real = 120) -> String

Run commands using the configured backend and return its raw transcript. The
backend kind and output version are validated before the transcript is
returned. See [`backend_info`](@ref) for configuration inspection.
"""
function run_orbifolder_script(
    mode::Symbol,
    commands::Vector{<:AbstractString};
    files::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
    timeout::Real = 120,
)
    backend_info(mode; timeout = min(timeout, 30))
    return _run_orbifolder_script(mode, commands; files = files, timeout = timeout)
end
