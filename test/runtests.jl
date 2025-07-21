using ModelManagerStudio, pcvct, Test, QML

createProject()

@testset "ModelManagerStudio.jl" begin
    @testset "GUI initialization" begin
        e = ModelManagerStudio.init_model_manager_gui()
        QML.quit(e)
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
