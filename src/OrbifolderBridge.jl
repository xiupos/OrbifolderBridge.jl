module OrbifolderBridge

export orbifolder_binary, set_orbifolder_binary!
export orbifolder_geometry_dir, set_orbifolder_geometry_dir!
export OrbifolderProcessError, OrbifolderTimeoutError, run_capture
export run_orbifolder_script
export split_transcript, output_for, parse_rational, parse_rational_vector
export GaugeGroup, SpectrumField, Spectrum, Twist, ShiftVector, WilsonLine, WilsonLines
export parse_gauge_group, parse_spectrum, parse_twist, parse_shift_vectors, parse_wilson_lines

include("core/binaries.jl")
include("core/process.jl")
include("core/run_script.jl")
include("core/transcript.jl")
include("core/types.jl")
include("core/parsers.jl")

end
