# Plain value types (parsed data, not identity-bearing objects) should compare
# and hash structurally rather than falling back to Julia's default identity
# semantics for non-isbits structs. Apply this immediately after each struct
# definition so a new field or new type can't silently end up with identity
# semantics by being left out of a separate list.
macro structural_equality(T)
    return quote
        Base.:(==)(a::$(esc(T)), b::$(esc(T))) =
            all(getfield(a, f) == getfield(b, f) for f in fieldnames($(esc(T))))
        Base.hash(a::$(esc(T)), h::UInt) =
            hash(ntuple(i -> getfield(a, i), fieldcount($(esc(T)))), hash($(esc(T)), h))
    end
end
