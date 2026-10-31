"""
    main(args)

Entry point for the ModelManagerStudio application. Forwards to [`launch`](@ref); see it for
argument details.

Returns `0` on a clean exit and `1` on failure, so `julia -m ModelManagerStudio` reports a
usable exit status to a shell or a launcher script.

Previously this swallowed a missing-project error entirely, so running it in the wrong
directory printed nothing and exited `0` — indistinguishable from success.
"""
function _studio_main(args)
    try
        launch(args...)
        return 0
    catch e
        #! Deliberately not matching on a backend-specific exception type: that both hardcoded
        #! a simulator reference and hid every other cause. Report whatever happened.
        println(stderr, "ModelManagerStudio could not start.\n")
        println(stderr, sprint(showerror, e))
        #! The backend names its own project-creation function; Studio cannot.
        sim = studio_backend()
        println(stderr, isnothing(sim) ? studio_no_backend_message() : studio_no_project_message(sim))
        return 1
    end
end

#! `@main` requires Julia 1.11+, but `[compat] julia = "1.10"` and CI tests the LTS — so on
#! 1.10 this file used to leave the package with no `main` at all, despite exporting the name.
#! Define the plain function everywhere and attach the `@main` entrypoint only where it exists.
if VERSION >= v"1.11"
    @compat function @main(args)
        return _studio_main(args)
    end
else
    main(args) = _studio_main(args)
    main() = _studio_main(String[])
end
