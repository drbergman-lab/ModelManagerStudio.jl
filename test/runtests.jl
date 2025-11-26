using ModelManagerStudio, PhysiCellModelManager, Test, QML

createProject()

@testset "ModelManagerStudio.jl" begin
    @testset "GUI initialization" begin
        @test begin
            ModelManagerStudio.launch()
            true
        end

        for args in [["."], [joinpath(".", "PhysiCell"), joinpath(".", "data")]]
            physicell_dir, data_dir = ModelManagerStudio.get_pcmm_paths(args...)
            @test isdir(data_dir)
            @test isdir(physicell_dir)
            @test abspath(physicell_dir) == abspath(joinpath(".", "PhysiCell"))
            @test abspath(data_dir) == abspath(joinpath(".", "data"))
        end
    end

    @testset "Creating inputs" begin
        ModelManagerStudio.set_input_folders()
        inputs = ModelManagerStudio.inputs
        @test inputs[:config].folder == "0_template"
        @test inputs[:custom_code].folder == "0_template"
    end

    @testset "Colors" begin
        for scheme in ModelManagerStudio.random_color_scheme_list()
            ENV["STUDIO_COLOR_TOKEN"] = scheme
            colors = ModelManagerStudio.color_scheme()
            for color in values(colors)
                @test occursin(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", color)
            end
        end
    end

end
