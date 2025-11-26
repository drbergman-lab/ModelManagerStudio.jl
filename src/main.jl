"""
    main(args)

Entry point for ModelManagerStudio application.
Calls [`launch`](@ref) to start the application.
See [`launch`](@ref) for argument details.
"""
@compat function @main(args)
    try
        launch(args...)
    catch e
        if !(e isa PhysiCellModelManager.PCMMMissingProject)
            rethrow(e)
        end
    end
end