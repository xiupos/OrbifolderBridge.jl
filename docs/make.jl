using OrbifolderBridge
using Documenter

DocMeta.setdocmeta!(OrbifolderBridge, :DocTestSetup, :(using OrbifolderBridge); recursive = true)

makedocs(;
    modules = [OrbifolderBridge],
    authors = "xiupos <me@xiupos.net> and contributors",
    sitename = "OrbifolderBridge.jl",
    format = Documenter.HTML(;
        canonical = "https://xiupos.github.io/OrbifolderBridge.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "User Guide" => [
            "Overview" => "tutorial.md",
            "Models and Geometry" => "models.md",
            "Spectra and Fields" => "spectra.md",
            "VEV Configurations" => "vev_configurations.md",
            "Model Classification and Generation" => "generation.md",
            "Couplings and the Superpotential" => "couplings.md",
            "OSCAR Integration" => "oscar.md",
            "Consistency and Batch Workflows" => "batch.md",
        ],
        "Backend Configuration" => "backend.md",
        "Design and Scope" => "design.md",
        "Upstream Notes" => "upstream_notes.md",
    ],
)

deploydocs(;
    repo = "github.com/xiupos/OrbifolderBridge.jl",
    devbranch = "main",
)
