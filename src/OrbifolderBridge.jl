module OrbifolderBridge

using Oscar

export orbifolder_binary, set_orbifolder_binary!
export orbifolder_geometry_dir, set_orbifolder_geometry_dir!
export BackendInfo, BackendCompatibilityError, BackendSelfTest
export backend_info, supports, check_backend
export OrbifolderProcessError, OrbifolderTimeoutError, run_capture
export run_orbifolder_script
export split_transcript, output_for, parse_rational, parse_rational_vector
export GaugeGroup, SpectrumField, Spectrum, FieldID, Sector, FieldLocalization
export GaugeFactorEmbedding, ExactGaugeData
export DetailedField, DetailedSpectrum, Twist, ShiftVector, WilsonLine, WilsonLines
export VEVConfigurationRef, VEVConfigurationSummary, GaugeSector
export VEVAssignment, FieldVEV, VEVConfigurationSpec, VEVConfigurationResult
export VEVConfigurationError, parse_vev_configurations, parse_gauge_sector, parse_field_vevs
export list_vev_configurations, compute_gauge_sector, materialize_vev_configuration
export parse_gauge_group, parse_spectrum, parse_detailed_spectrum, find_fields
export parse_exact_gauge_data, compute_exact_gauge_data
export GaugeEmbeddingComparison, compare_gauge_embeddings
export parse_twist, parse_shift_vectors, parse_wilson_lines
export algebra_to_cartan_type
export dual_weight, find_weight_of_dimension, representation_weight
export gauge_group_root_systems, field_weights
export simple_root_matrix, u1_generator_matrix, u1_gram_matrix
export U1NormalizationData, u1_normalization
export EmbeddedGaugeFactor, embedded_gauge_factor, embedded_gauge_factors
export fundamental_weight_matrix, embed_weight
export RepresentationWeight, representation_from_dynkin_labels
export resolve_representation, resolve_field_representations
export OrbifolderModel, model_file_text
export UpstreamModelParseError, parse_orbifolder_models
export ModelClassification, AnomalyReport, GenerationDiagnostic
export ModelGenerationRequest, ModelGenerationResult
export classify_model, compute_anomaly_report, generate_models, select_inequivalent_models
export ConsistencyResult, check_consistency, is_consistent
export check_consistency_batch, partition_consistent_models
export compute_gauge_group, compute_spectrum, compute_detailed_spectrum
export compute_twist, compute_shift_vectors, compute_wilson_lines
export compute_spectra, compute_gauge_groups, compute_twists
export compute_shift_vectors_batch, compute_wilson_lines_batch

include("core/equality.jl")
include("core/binaries.jl")
include("core/process.jl")
include("core/backend.jl")
include("core/run_script.jl")
include("core/transcript.jl")
include("core/types.jl")
include("core/parsers.jl")
include("core/model.jl")
include("core/configuration.jl")
include("core/exact_gauge.jl")
include("core/consistency.jl")
include("core/generation.jl")

include("oscar/cartan_type.jl")
include("oscar/exact_gauge.jl")
include("oscar/representations.jl")

include("parallel.jl")

end
