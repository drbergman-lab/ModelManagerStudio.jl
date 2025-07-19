using ModelManagerStudio, pcvct, Test, QML

createProject()

@testset "ModelManagerStudio.jl" begin
    e = ModelManagerStudio.init_model_manager_gui()
    QML.quit(e)
end
