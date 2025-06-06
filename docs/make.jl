using ModelManagerStudio
using Documenter

DocMeta.setdocmeta!(ModelManagerStudio, :DocTestSetup, :(using ModelManagerStudio); recursive=true)

makedocs(;
    modules=[ModelManagerStudio],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="ModelManagerStudio.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman.github.io/ModelManagerStudio.jl",
        edit_link="development",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/drbergman/ModelManagerStudio.jl",
    devbranch="development",
)
