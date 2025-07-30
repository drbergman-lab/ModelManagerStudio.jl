function (@main)(args)
    try
        launch(args...)
    catch e
        if !(e isa PhysiCellModelManager.PCMMMissingProject)
            rethrow(e)
        end
    end
end