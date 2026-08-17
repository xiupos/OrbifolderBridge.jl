const _PROMPT_RE = r"^(?:/[^>]*)?>(.*)$"

"""
    split_transcript(text::AbstractString) -> Vector{Pair{String,String}}

Split a raw CPrompt transcript (as returned by [`run_orbifolder_script`](@ref))
into `command => output` pairs, keyed on the echoed prompt lines (e.g.
`/Z3_1_1/spectrum> print summary`). CPrompt paths may contain spaces (e.g.
`cd "gauge group"` echoes as `/Z3_1_1/gauge group>`) but never `>`, so the
first (and only) `>` on a line unambiguously separates path from command.

Entries whose command is blank (banner lines echoed against an otherwise
empty prompt, e.g. right after `load program(...)`) are dropped.
"""
function split_transcript(text::AbstractString)
    lines = split(text, '\n')
    pairs = Pair{String,String}[]
    i, n = 1, length(lines)
    while i <= n
        m = match(_PROMPT_RE, lines[i])
        if m === nothing
            i += 1
            continue
        end
        cmd = strip(m.captures[1])
        i += 1
        outstart = i
        while i <= n && match(_PROMPT_RE, lines[i]) === nothing
            i += 1
        end
        if !isempty(cmd)
            push!(pairs, String(cmd) => join(lines[outstart:i-1], '\n'))
        end
    end
    return pairs
end

"""
    output_for(pairs, command::AbstractString) -> String

Return the output text of the last entry in `pairs` (as returned by
[`split_transcript`](@ref)) whose command equals `command`. Throws if no such
command was found in the transcript.
"""
function output_for(pairs::Vector{Pair{String,String}}, command::AbstractString)
    for (cmd, out) in Iterators.reverse(pairs)
        cmd == command && return out
    end
    error("command \"$command\" not found in transcript")
end

"""
    parse_rational(s::AbstractString) -> Rational{Int}

Parse a single number token as printed by CPrint, e.g. `"1/3"`, `"-2/3"`,
`"0"`, `"5"`.
"""
function parse_rational(s::AbstractString)
    s = strip(s)
    if occursin('/', s)
        num, den = split(s, '/'; limit = 2)
        return parse(Int, num) // parse(Int, den)
    end
    return Rational{Int}(parse(Int, s))
end

"""
    parse_rational_vector(s::AbstractString) -> Vector{Rational{Int}}

Parse a comma-separated list of number tokens, e.g. the inside of a `( ... )`
group as printed by CPrint.
"""
function parse_rational_vector(s::AbstractString)
    isempty(strip(s)) && return Rational{Int}[]
    return [parse_rational(tok) for tok in split(s, ',')]
end
