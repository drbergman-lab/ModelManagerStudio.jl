using Dates

global path_to_record::String = ""
global last_record::Symbol = :none

function initialize_record()
    global path_to_record
    mms_record_dir = "mms_records"
    isdir(mms_record_dir) || mkdir(mms_record_dir)
    path_base() = joinpath(mms_record_dir, Dates.format(now(), "yyyy-mm-dd_HH-MM"))
    current_time = Dates.format(now(), "yyyy-mm-dd_HH-MM")
    if isempty(path_to_record)
        path_to_record = path_base() * ".jl"
    end

    ind = 0
    while isfile(path_to_record)
        ind += 1
        path_to_record = path_base() * "_$(ind).jl"
    end

    msg = """
    # Record of ModelManagerStudio.jl actions.
    # This file can be run on its own to reproduce the simulations run in this session.
    #
    # Date created: $(current_time)

    using pcvct, Distributions
    initializeModelManager(\"$(pcvct.pcvct_globals.physicell_dir)\", \"$(pcvct.pcvct_globals.data_dir)\")\n
    """
    open(path_to_record, "w") do file
        write(file, msg)
    end
    global last_record = :initialize
end

function record_inputs()
    global path_to_record, last_record, inputs
    pl = pcvct.projectLocations()
    required_args = join(["\"$(inputs[location].folder)\"" for location in pl.required], ", ")
    included_optional_locs = filter(location -> !isempty(inputs[location].folder), setdiff(pl.all, pl.required))

    optional_args = isempty(included_optional_locs) ? "" :
                    ";\n\t" * join(["$location=\"$(inputs[location].folder)\"" for location in included_optional_locs], ",\n\t")

    msg = """
    $(inputs_marker())
    inputs = InputFolders(
        $required_args$optional_args
    )\n
    """

    trim_record(:inputs)

    open(path_to_record, "a") do file
        write(file, msg)
    end

    last_record = :inputs
end

function record_variations()
    global path_to_record, last_record, tokens_avs

    avs_text = "avs = []\n"
    for token_av in tokens_avs
        avs_text *= """

        xml_path = $(pcvct.variationTarget(token_av[2]).xml_path)
        val = $(value_string(token_av[2]))
        push!(avs, ElementaryVariation(xml_path, val))
        """
    end

    msg = """
    $(variations_marker())
    $avs_text
    """

    trim_record(:variations)

    open(path_to_record, "a") do file
        write(file, msg)
    end
    last_record = :variations
end

function record_run()
    global path_to_record, last_record, inputs, tokens_avs

    msg = """
    $(run_marker())
    run(inputs, avs)\n
    """

    trim_record(:run)

    open(path_to_record, "a") do file
        write(file, msg)
    end
    last_record = :run
end

value_string(dv::DiscreteVariation) = pcvct.variationValues(dv)

function value_string(dv::DistributedVariation)
    d = dv.distribution
    typename = typeof(d)
    params = join(["$(getfield(d, p))" for p in fieldnames(typename)], ", ")
    return "$(typename)($params)"
end

function trim_record(record_type::Symbol)
    global path_to_record, last_record
    if record_type != last_record
        return
    end

    if record_type == :inputs
        marker = inputs_marker()
    elseif record_type == :variations
        marker = variations_marker()
    elseif record_type == :run
        marker = run_marker()
    else
        error("Unknown record type for trimming: $record_type")
    end

    lines = readlines(path_to_record)
    ind = findlast(line == marker for line in lines)
    @assert !isnothing(ind) "No previous record found for $record_type"
    lines = lines[1:ind-1]  # Remove the previous variations record
    open(path_to_record, "w") do file
        for line in lines
            println(file, line)
        end
    end
end

inputs_marker() = "## Creating inputs"
variations_marker() = "## Creating variations"
run_marker() = "## Running simulation(s)"