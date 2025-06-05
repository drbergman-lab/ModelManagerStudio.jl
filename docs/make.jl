using MMStudio
using Documenter

DocMeta.setdocmeta!(MMStudio, :DocTestSetup, :(using MMStudio); recursive=true)

makedocs(;
    modules=[MMStudio],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="MMStudio.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman.github.io/MMStudio.jl",
        edit_link="development",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/drbergman/MMStudio.jl",
    devbranch="development",
)
