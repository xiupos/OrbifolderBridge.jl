module OrbifolderBridge

using Oscar

export orbifolder_binary, set_orbifolder_binary!
export orbifolder_geometry_dir, set_orbifolder_geometry_dir!
export OrbifolderProcessError, OrbifolderTimeoutError, run_capture
export run_orbifolder_script
export split_transcript, output_for, parse_rational, parse_rational_vector
export GaugeGroup, SpectrumField, Spectrum, Twist, ShiftVector, WilsonLine, WilsonLines
export parse_gauge_group, parse_spectrum, parse_twist, parse_shift_vectors, parse_wilson_lines
export algebra_to_cartan_type
export dual_weight, find_weight_of_dimension, representation_weight
export gauge_group_root_systems, field_weights
export OrbifolderModel, model_file_text
export compute_gauge_group, compute_spectrum, compute_twist, compute_shift_vectors, compute_wilson_lines
export compute_spectra, compute_gauge_groups, compute_twists
export compute_shift_vectors_batch, compute_wilson_lines_batch

include("core/binaries.jl")
include("core/process.jl")
include("core/run_script.jl")
include("core/transcript.jl")
include("core/types.jl")
include("core/parsers.jl")
include("core/model.jl")

include("oscar/cartan_type.jl")
include("oscar/representations.jl")

include("parallel.jl")

end
