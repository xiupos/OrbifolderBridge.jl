const _ALGEBRA_RE = r"^(SU|SO|Sp)\((\d+)\)$"
const _EXCEPTIONAL_RE = r"^(E)_?(\d+)$"
const _RANK1_EXCEPTIONAL_RE = r"^(F|G)_?(\d+)$"

"""
    algebra_to_cartan_type(algebra::AbstractString) -> Tuple{Symbol,Int}

Map a non-abelian gauge factor name as printed by upstream's `CPrint`
(`SU(N)`, `SO(N)`, or `E_6`/`E_7`/`E_8` with an underscore — see
`CPrint::PrintGaugeGroupFactor` in `cprint.cpp`) to a Cartan type
`(family, rank)` suitable for `Oscar.root_system`.

Since orbifold projections only ever break the simply-laced \$E_8 \\times
E_8\$/\$\\mathrm{SO}(32)\$ heterotic gauge lattice to simply-laced
subalgebras, upstream in practice only ever emits type \$A\$ (\$\\mathrm{SU}(N)
= A_{N-1}\$), \$D\$ (\$\\mathrm{SO}(N), N\$ even, \$= D_{N/2}\$), or \$E\$
factors. `SO(N)` for odd \$N\$ (type \$B\$), `Sp(2N)` (type \$C\$), and
`F_4`/`G_2` are parsed for robustness/completeness but should not appear in
real orbifolder output. `SO(4)` is rejected: it is not simple
(\$\\mathrm{SO}(4) \\cong \\mathrm{SU}(2) \\times \\mathrm{SU}(2)\$), so it
cannot be represented by a single `RootSystem`.
"""
function algebra_to_cartan_type(algebra::AbstractString)
    algebra = strip(algebra)

    m = match(_EXCEPTIONAL_RE, algebra)
    if m !== nothing
        rank = parse(Int, m.captures[2])
        rank in (6, 7, 8) || error("unrecognized exceptional algebra: $algebra")
        return (:E, rank)
    end
    m = match(_RANK1_EXCEPTIONAL_RE, algebra)
    if m !== nothing
        family = Symbol(m.captures[1])
        rank = parse(Int, m.captures[2])
        family === :F && rank == 4 && return (:F, 4)
        family === :G && rank == 2 && return (:G, 2)
        error("unrecognized exceptional algebra: $algebra")
    end

    m = match(_ALGEBRA_RE, algebra)
    m === nothing && error("could not parse gauge factor \"$algebra\" as a Cartan type")
    kind = m.captures[1]
    n = parse(Int, m.captures[2])

    if kind == "SU"
        n >= 2 || error("SU($n) is not a valid special unitary group")
        return (:A, n - 1)
    elseif kind == "SO"
        n == 4 && error("SO(4) is not simple (SO(4) = SU(2) x SU(2)); cannot map to a single RootSystem")
        n >= 3 || error("SO($n) is not a valid special orthogonal group")
        return iseven(n) ? (:D, n ÷ 2) : (:B, (n - 1) ÷ 2)
    elseif kind == "Sp"
        iseven(n) || error("Sp($n) expects an even defining dimension")
        n >= 2 || error("Sp($n) is not a valid symplectic group")
        return (:C, n ÷ 2)
    end
    error("unrecognized gauge factor: $algebra")
end
