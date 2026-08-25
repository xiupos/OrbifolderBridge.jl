```@meta
CurrentModule = OrbifolderBridge
```

# Couplings and the Superpotential

Allowed couplings remain an upstream physics computation. OrbifolderBridge
resolves stable field identities to the labels of an explicit VEV
configuration, asks SUSY orbifolder to apply its selection rules, and parses
the resulting native coupling file back into [`FieldID`](@ref) references.

The supported non-SUSY backend exposes an empty `couplings` command directory
and therefore does not advertise the `:couplings` capability.

## Requesting a coupling

A request describes one monomial of order at least three:

```julia
config = VEVConfigurationRef("TestConfig1")
request = CouplingRequest([
    FieldID(11),
    FieldID(37),
    FieldID(39),
])

result = compute_couplings(model, config, request)
result.terms
```

An empty `terms` vector is a successful upstream result: the requested
coupling was not allowed. Infrastructure failures, rejected configuration
selection, malformed saved data, and unknown field numbers remain errors.

The optional `allowed_fields` argument is passed to upstream's corresponding
restriction after every stable ID has been resolved:

```julia
request = CouplingRequest(
    [FieldID(11), FieldID(37), FieldID(39)];
    allowed_fields = [FieldID(11), FieldID(37), FieldID(39)],
)
```

`CouplingTerm.fields` preserves upstream's factor order. Display labels such
as `F_1` are deliberately not stored in the result because they depend on the
selected label scheme.

## Searching through a maximum order

Several explicit candidate monomials can be registered and searched in one
upstream session:

```julia
cubic = CouplingRequest([FieldID(11), FieldID(37), FieldID(39)])
quartic = CouplingRequest([FieldID(15), FieldID(32), FieldID(131), FieldID(333)])

search = search_couplings(
    model,
    config,
    [cubic, quartic];
    involving = [FieldID(11)],
    max_order = 4,
)
```

Only requests through `max_order` are sent to upstream. Each child calculation
is followed by its own `wait(1)` barrier; the bridge then invokes upstream
`find(...)` and returns the
matching canonical terms from the saved file. Repeated entries in `involving`
retain multiplicity semantics.

SUSY orbifolder documents `save couplings(...) of order(X)`, but version 1.2.1
attempts to parse the option from its filename parameter and does not reliably
apply it. OrbifolderBridge therefore enforces the maximum on the explicit
candidate requests before computation instead of relying on that broken
filter.

## Validation and provenance

SUSY orbifolder computes couplings in a child process. The bridge executes
`create coupling(...)`, waits for completion with upstream's `wait(1)`, and
saves the registered result before the isolated temporary directory is
removed. Process identifiers are removed from the retained transcript.

The native saved file starts with the lattice, two shifts, and six Wilson
lines. [`parse_couplings`](@ref) checks all of them exactly against the
supplied model before accepting any field-number row. This prevents a saved
coupling set from being attached to a different gauge embedding.

## OSCAR polynomials and exact VEV substitution

Construct a polynomial ring directly from parsed terms:

```julia
data = coupling_polynomial_ring(result)
superpotential = coupling_polynomial(data, result)
```

The ring is over `QQ` and has one generator `f_<number>` for every stable
field identity. The `generators` dictionary provides the exact inverse map.
Upstream reports allowed monomials but no exact numerical coupling strengths,
so their coefficients are represented as one.

VEV substitution is kept exact by replacing VEV fields with independent
symbols rather than converting upstream's floating-point VEV values:

```julia
substitution = exact_vev_substitution(data, [FieldID(39)])
effective = apply_vev_substitution(substitution, result)
```

The target generator is named `v_39`. Each returned
[`EffectiveCouplingPolynomial`](@ref) retains its source [`CouplingTerm`](@ref),
so coincident effective monomials do not lose provenance.

## Upstream effective superpotential

For a declarative SUSY configuration, the bridge can also ask upstream to
perform its own VEV replacement:

```julia
spec = VEVConfigurationSpec(
    name = "BridgeEffective1",
    assignments = [VEVAssignment(FieldID(39), 1)],
    recompute_unbroken_group = false,
)
effective = compute_effective_couplings(model, spec, [request])
```

The derived configuration, coupling registration, and `print effective
superpotential` command run in the same isolated process. An
[`UpstreamEffectiveCoupling`](@ref) separates remaining `fields` from
angle-bracketed `vev_fields` and links both back to its ordinary `source`.
The parser supports the sums and parenthesized sums of VEV products emitted by
upstream and expands them without recomputing which couplings are allowed.

## Current boundary

Phase 6 supports ordinary couplings, searches across explicitly
registered candidates, maximum-order request limits, OSCAR polynomial-ring
conversion, exact symbolic VEV substitution, and parsing upstream's effective
superpotential. Mass matrices remain Phase 7 work.

The upstream `remove vanishing couplings` command may stop for interactive
`y/n` classification of a previously unknown representation pattern. It is
therefore intentionally not called by the non-interactive API. The bridge
does not guess that answer or reimplement the symmetry analysis.

## API

```@docs
CouplingRequest
CouplingTerm
CouplingResult
CouplingSearchResult
CouplingParseError
CouplingExecutionError
parse_couplings
compute_couplings
search_couplings
CouplingPolynomialRing
ExactVEVSubstitution
EffectiveCouplingPolynomial
UpstreamEffectiveCoupling
EffectiveCouplingResult
coupling_polynomial_ring
coupling_polynomial
exact_vev_substitution
apply_vev_substitution
parse_effective_couplings
compute_effective_couplings
```
