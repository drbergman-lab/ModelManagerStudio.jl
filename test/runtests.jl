using ModelManagerStudio, pcvct, Test, QML

createProject()

@testset "ModelManagerStudio.jl" begin
    @testset "GUI initialization" begin
        @test begin
            ModelManagerStudio.launch(; testing=true)
            true
        end

        for args in [["."], [joinpath(".", "data"), joinpath(".", "PhysiCell")]]
            data_dir, physicell_dir = ModelManagerStudio.get_pcvct_paths(args...)
            @test isdir(data_dir)
            @test isdir(physicell_dir)
            @test abspath(data_dir) == abspath(joinpath(".", "data"))
            @test abspath(physicell_dir) == abspath(joinpath(".", "PhysiCell"))
        end
    end

    @testset "Creating inputs" begin
        ModelManagerStudio.set_input_folders()
        inputs = ModelManagerStudio.inputs
        @test inputs[:config].folder == "0_template"
        @test inputs[:custom_code].folder == "0_template"
    end

    @testset "Reinit Policies" begin
        for policy in [:ask, :update, :keep]
            @test ModelManagerStudio.parse_reinit_policy(policy) == getfield(ModelManagerStudio, policy)
            str_policy = String(policy)
            @test ModelManagerStudio.parse_reinit_policy(str_policy) == getfield(ModelManagerStudio, policy)
        end
        @test_throws ArgumentError ModelManagerStudio.parse_reinit_policy("invalid_policy")
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
