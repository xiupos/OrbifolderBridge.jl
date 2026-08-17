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
        "API Reference" => "api.md",
        "Upstream Notes" => "upstream_notes.md",
    ],
)

deploydocs(;
    repo = "github.com/xiupos/OrbifolderBridge.jl",
    devbranch = "main",
)
