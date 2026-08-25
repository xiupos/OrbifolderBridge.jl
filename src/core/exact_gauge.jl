"""
    GaugeFactorEmbedding

One non-abelian simple gauge factor together with the exact simple roots
printed by upstream. `index` is the factor's one-based position in
[`GaugeGroup`](@ref)`.nonabelian`; every root is a rational vector in the
16-dimensional heterotic gauge lattice.
"""
struct GaugeFactorEmbedding
    index::Int
    algebra::String
    simple_roots::Vector{Vector{Rational{Int}}}
end
@structural_equality GaugeFactorEmbedding

"""
    ExactGaugeData

Exact gauge-lattice data reported by one upstream VEV configuration.
`factors` preserves the printed non-abelian factor order and groups the simple
roots by the rank of each factor. `u1_generators` uses the same order as the
U(1) charges in spectrum output. `anomalous_u1` is the one-based anomalous
generator index, or `nothing`; supported upstream versions place it first.
`anomalous_tr_q` retains the corresponding trace printed by upstream.

Observable and hidden factor indices are retained explicitly. All embedded
vectors contain exactly 16 rational entries.
"""
struct ExactGaugeData
    gauge_group::GaugeGroup
    factors::Vector{GaugeFactorEmbedding}
    u1_generators::Vector{Vector{Rational{Int}}}
    anomalous_u1::Union{Nothing,Int}
    anomalous_tr_q::Union{Nothing,Float64}
    observable_nonabelian::Vector{Int}
    hidden_nonabelian::Vector{Int}
    observable_u1::Vector{Int}
    hidden_u1::Vector{Int}
end
@structural_equality ExactGaugeData

const _EMBEDDED_VECTOR_RE =
    r"^\s*\(([^()]*)\),\s*\(([^()]*)\)(?:\s+.*)?$"

function _parse_embedded_vectors(output::AbstractString, heading::AbstractString)
    occursin(heading, output) || error("no $heading heading found in output")
    vectors = Vector{Rational{Int}}[]
    after_heading = false
    for line in split(output, '\n')
        if occursin(heading, line)
            after_heading = true
            continue
        end
        after_heading || continue
        m = match(_EMBEDDED_VECTOR_RE, line)
        m === nothing && continue
        vector = vcat(parse_rational_vector(m.captures[1]), parse_rational_vector(m.captures[2]))
        length(vector) == 16 || error("$heading vector has $(length(vector)) entries, expected 16")
        push!(vectors, vector)
    end
    isempty(vectors) && !occursin("Number of", output) &&
        error("no vectors found after $heading heading")
    return vectors
end

"""
    parse_exact_gauge_data(gauge_output, roots_output, u1_output;
                           spectrum_output = nothing) -> ExactGaugeData

Parse `print gauge group`, `print simple roots`, and `print U1 generators`
output from a single upstream configuration. When supplied, `spectrum_output`
identifies the anomalous first U(1) from upstream's explicit summary message.
The parser validates vector lengths and the root/U(1) counts against the
reported gauge group instead of accepting partial output.
"""
function parse_exact_gauge_data(
    gauge_output::AbstractString,
    roots_output::AbstractString,
    u1_output::AbstractString;
    spectrum_output::Union{Nothing,AbstractString} = nothing,
)
    sector = parse_gauge_sector(gauge_output)
    gauge_group = sector.gauge_group
    roots = _parse_embedded_vectors(roots_output, "Simple roots:")
    generators = gauge_group.n_u1 == 0 ? Vector{Rational{Int}}[] :
                 _parse_embedded_vectors(u1_output, "U(1) generators:")

    ranks = [last(algebra_to_cartan_type(algebra)) for algebra in gauge_group.nonabelian]
    sum(ranks) == length(roots) || error(
        "upstream printed $(length(roots)) simple roots for gauge factors of total rank $(sum(ranks))",
    )
    length(generators) == gauge_group.n_u1 || error(
        "upstream printed $(length(generators)) U(1) generators, expected $(gauge_group.n_u1)",
    )

    factors = GaugeFactorEmbedding[]
    offset = 0
    for (index, (algebra, rank)) in enumerate(zip(gauge_group.nonabelian, ranks))
        push!(factors, GaugeFactorEmbedding(index, algebra, roots[offset+1:offset+rank]))
        offset += rank
    end
    anomaly_match = spectrum_output === nothing ? nothing : match(_ANOMALOUS_RE, spectrum_output)
    anomalous_u1 = anomaly_match === nothing ? nothing : 1
    anomalous_tr_q = anomaly_match === nothing ? nothing : parse(Float64, anomaly_match.captures[1])
    return ExactGaugeData(
        gauge_group,
        factors,
        generators,
        anomalous_u1,
        anomalous_tr_q,
        sector.observable_nonabelian,
        sector.hidden_nonabelian,
        sector.observable_u1,
        sector.hidden_u1,
    )
end

"""
    compute_exact_gauge_data(model[, config]; timeout = 120) -> ExactGaugeData

Select `config` explicitly, then obtain the gauge group, embedded simple
roots, U(1) generators, and the spectrum header used to identify the anomalous
generator in one isolated upstream run.
"""
function compute_exact_gauge_data(
    model::OrbifolderModel,
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    timeout::Real = 120,
)
    commands = _configuration_commands(config, [
        "cd gauge group",
        "print gauge group",
        "print simple roots",
        "print U1 generators",
        "cd ..",
        "cd spectrum",
        "print summary",
    ])
    output = _run_model_script(model, commands; timeout = timeout)
    _validate_configuration_selection(output, config)
    pairs = split_transcript(output)
    return parse_exact_gauge_data(
        output_for(pairs, "print gauge group"),
        output_for(pairs, "print simple roots"),
        output_for(pairs, "print U1 generators");
        spectrum_output = output_for(pairs, "print summary"),
    )
end

"""
    compute_exact_gauge_data(model, specification; timeout = 120) -> ExactGaugeData

Replay a declarative VEV configuration and obtain its exact gauge data in the
same isolated upstream run. This is required because a derived upstream
configuration does not persist across subprocesses.
"""
function compute_exact_gauge_data(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec;
    timeout::Real = 120,
)
    tail = [
        "cd ..",
        "cd gauge group",
        "print gauge group",
        "print simple roots",
        "print U1 generators",
        "cd ..",
        "cd spectrum",
        "print summary",
    ]
    run = _run_configuration_spec(model, spec, tail; timeout = timeout)
    pairs = split_transcript(run.output)
    return parse_exact_gauge_data(
        output_for(pairs, "print gauge group"),
        output_for(pairs, "print simple roots"),
        output_for(pairs, "print U1 generators");
        spectrum_output = output_for(pairs, "print summary"),
    )
end
