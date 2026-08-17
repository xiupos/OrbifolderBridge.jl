"""
    OrbifolderProcessError <: Exception

Thrown when the `orbifolder`/`nonSUSYorbifolder` subprocess exits with a
non-zero status. Carries the captured `stdout`/`stderr` for debugging.
"""
struct OrbifolderProcessError <: Exception
    message::String
    exitcode::Int
    stdout::String
    stderr::String
end

function Base.showerror(io::IO, e::OrbifolderProcessError)
    print(io, "OrbifolderProcessError: ", e.message, " (exit code ", e.exitcode, ")")
    isempty(e.stderr) || print(io, "\nstderr:\n", e.stderr)
end

"""
    OrbifolderTimeoutError <: Exception

Thrown when the `orbifolder`/`nonSUSYorbifolder` subprocess does not finish
within the requested timeout. The process is killed before this is thrown.
"""
struct OrbifolderTimeoutError <: Exception
    timeout::Real
end

function Base.showerror(io::IO, e::OrbifolderTimeoutError)
    print(io, "OrbifolderTimeoutError: process did not finish within $(e.timeout) seconds")
end

"""
    run_capture(cmd::Cmd; input::AbstractString = "", timeout::Real = 120) -> String

Run `cmd`, feeding it `input` on stdin, and return its captured stdout as a
`String`. Throws [`OrbifolderTimeoutError`](@ref) if `cmd` runs longer than
`timeout` seconds (the process is killed), or [`OrbifolderProcessError`](@ref)
if it exits with a non-zero status.
"""
function run_capture(cmd::Cmd; input::AbstractString = "", timeout::Real = 120)
    outpipe = Pipe()
    errpipe = Pipe()
    proc = run(pipeline(cmd, stdin = IOBuffer(input), stdout = outpipe, stderr = errpipe); wait = false)
    close(outpipe.in)
    close(errpipe.in)
    # Reading the Pipe (rather than an IOBuffer target) blocks until the child
    # closes its end, so fetch() below can't race process_running/wait(proc)
    # going true before the copied bytes have actually landed.
    outtask = @async read(outpipe, String)
    errtask = @async read(errpipe, String)

    t0 = time()
    while process_running(proc)
        if time() - t0 > timeout
            kill(proc)
            wait(proc)
            throw(OrbifolderTimeoutError(timeout))
        end
        sleep(0.02)
    end
    wait(proc)

    out = fetch(outtask)
    err = fetch(errtask)
    if !success(proc)
        throw(OrbifolderProcessError("subprocess failed: $cmd", proc.exitcode, out, err))
    end
    return out
end
