#! Parsing of user-entered variation value specifications.
#!
#! This replaces `Meta.parse |> eval`, which was arbitrary code execution: the expression ran
#! at module scope with `Distributions` in scope, so `(run(`…`); [1.0])` was enough to execute
#! anything, and a benign typo like `inputs = nothing` silently corrupted application state.
#! It also blocks any future `juliac` compilation, which cannot include `eval`.
#!
#! `ModelManager.parseValueFromString` is not a substitute — it handles a single scalar only.
#! What the GUI needs is a small grammar over value *specifications*, so this is Studio's own.
#!
#! The approach is to parse with `Meta.parse` (which only builds an AST and evaluates nothing)
#! and then walk that AST against a whitelist, constructing values ourselves. Anything not
#! explicitly allowed is rejected with a message naming what was wrong.

"""
    ValueSpecError

Raised when a variation value specification cannot be parsed, or names something outside the
whitelist. The message is written for display in the GUI next to the offending field.
"""
struct ValueSpecError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ValueSpecError) = print(io, e.msg)

#! The set of distributions the value editor accepts is DERIVED from Distributions.jl rather
#! than hand-listed, so it cannot drift as Distributions gains or renames types.
#!
#! Scope: every concrete subtype of `UnivariateDistribution` — continuous and discrete. Only
#! univariate: `DistributedVariation` samples via `quantile(dist, u)` on a scalar CDF value, so
#! a multivariate distribution would fail deep inside ModelManager rather than here.
#!
#! Security note: this widens what a user may *name*, not what they may *do*. Arguments are
#! still restricted to numeric literals by `_spec_value`, so the worst case is calling a
#! validating constructor from an already-installed dependency with numbers. There is no path
#! to arbitrary evaluation, which is the property the whole file exists to preserve.
"""
    _numeric_constructible(B)

Whether `B` has a constructor taking one or more arguments that are all `Real`.

Filters out the distribution *wrappers* — `Truncated`, `Censored`, `MixtureModel`,
`AffineDistribution`, `OrderStatistic`, `UnivariateGMM` — plus argument-free types like
`Kolmogorov` and vector-valued ones like `DiscreteNonParametric`. Those are concrete univariate
distributions, but they cannot be built from the numeric literals this grammar allows, so
listing them would advertise choices that always fail.
"""
function _numeric_constructible(B)
    for m in methods(B)
        m.isva && continue
        sig = Base.unwrap_unionall(m.sig)
        params = sig.parameters[2:end]   #! drop the type itself
        isempty(params) && continue
        all_real = all(params) do p
            pu = Base.unwrap_unionall(p)
            pu isa TypeVar && (pu = pu.ub)
            pu isa Type && pu <: Real
        end
        all_real && return true
    end
    return false
end

function _collect_univariate_distributions()
    concrete = Set{Any}()
    function walk(T)
        for S in InteractiveUtils.subtypes(T)
            isabstracttype(S) ? walk(S) : push!(concrete, S)
        end
    end
    walk(ContinuousUnivariateDistribution)
    walk(DiscreteUnivariateDistribution)

    out = Dict{Symbol,Any}()
    for T in concrete
        #! `subtypes` yields parameterized types (`Normal{Float64}`); the user writes the base
        #! name (`Normal`), and `Base.typename(T).wrapper` is the callable constructor for it.
        B = Base.typename(T).wrapper

        #! Distributions.jl ONLY. `subtypes` walks every loaded module, so without this the set
        #! depends on the whole dependency graph: measured on this project, Copulas.jl arrives
        #! transitively through ModelManager and contributes `Logarithmic`, `PStable` and
        #! `Sibuya`. Accepting those would mean a value spec that parses today stops parsing
        #! when an unrelated transitive dependency changes — and the recorded transcript has to
        #! stay runnable (CLAUDE.md, Fixed Constraint 2). Pinning to the one package we depend
        #! on directly makes the accepted set a function of our own [compat] bound.
        parentmodule(B) === Distributions || continue

        _numeric_constructible(B) || continue
        out[nameof(B)] = B
    end
    return out
end

#! Built at load time and restricted to Distributions.jl, so the accepted set is a function of
#! this package's `[compat] Distributions` bound and nothing else — not of load order, not of
#! what else the user happens to have loaded, and not of the transitive dependency graph.
const ALLOWED_DISTRIBUTIONS = _collect_univariate_distributions()

"""
    allowed_distribution_names()

Sorted names of the distributions the value editor accepts. Intended for display in the GUI so
the allowlist is discoverable rather than something the user finds by trial and error.
"""
allowed_distribution_names() = sort!(String.(collect(keys(ALLOWED_DISTRIBUTIONS))))

"""
    parse_value_spec(spec::AbstractString)

Parse a user-entered variation value specification into a value suitable for
`ModelManager.DiscreteVariation` or `ModelManager.DistributedVariation`.

Never evaluates user input. The string is parsed to an AST and that AST is walked against a
whitelist; anything else raises [`ValueSpecError`](@ref).

# Accepted forms
| Input | Result |
|---|---|
| `2.5`, `-3`, `1e-4` | a single number |
| `true`, `false` | a `Bool` |
| `"tumor"`, `'x'` | a `String` |
| `[1.0, 2.0, 3.0]` | a `Vector` |
| `1.0, 2.0, 3.0` | a `Vector` (bare comma list) |
| `0.1:0.2:0.9`, `1:5` | a `Vector`, materialized from the range |
| `Normal(1.0, 0.2)` | a `Distribution` |
| `-Normal(1.0, 0.2)` | negated numeric literals are fine; a negated distribution is not |

Arithmetic, variables, function calls other than an allowed distribution, indexing,
interpolation, and every other expression form are rejected.

# Examples
```julia
julia> ModelManagerStudio.parse_value_spec("0.1:0.2:0.5")
3-element Vector{Float64}:
 0.1
 0.30000000000000004
 0.5

julia> ModelManagerStudio.parse_value_spec("[1.0, 1.2]")
2-element Vector{Float64}:
 1.0
 1.2
```
"""
function parse_value_spec(spec::AbstractString)
    text = strip(String(spec))
    isempty(text) && throw(ValueSpecError("Enter a value, a list, a range, or a distribution."))

    ex = try
        #! Meta.parse builds an AST and evaluates nothing, so this is safe on hostile input.
        Meta.parse(text; raise=true)
    catch e
        throw(ValueSpecError("Could not read \"$(text)\" as a value. $(_hint())"))
    end

    #! Two AST shapes arrive WITHOUT Meta.parse throwing, and both must be refused here:
    #!   - `:toplevel`, from semicolon-separated input — "[1.0] ; run(`ls`)" is the shape that
    #!     would smuggle a second statement past a naive check.
    #!   - `:incomplete`, from truncated input like "[1,2", which `raise=true` does not raise on.
    #! Neither head is handled by `_spec_value`, so both already fall through to its final
    #! rejection; they are named explicitly because relying on a fall-through for the
    #! security-relevant case is how that kind of guard gets refactored away later.
    if _isexpr(ex, :toplevel)
        throw(ValueSpecError("Give a single value — remove the `;` and anything after it."))
    end
    if _isexpr(ex, :incomplete)
        throw(ValueSpecError("\"$(text)\" is incomplete — check for a missing bracket or quote."))
    end

    #! A bare comma list ("1, 2, 3") parses as a tuple; treat it as a vector for convenience,
    #! since it is what a user types most often and requiring brackets is needless friction.
    if _isexpr(ex, :tuple)
        return _collect_elements(ex.args, text)
    end
    return _spec_value(ex, text)
end

_hint() = "Accepted: a number, `true`/`false`, a quoted string, a list like `[1.0, 2.0]`, a range like `0.1:0.2:0.9`, or a distribution like `Normal(1.0, 0.2)`."

_isexpr(ex, head::Symbol) = ex isa Expr && ex.head === head

#! Scalars that may appear anywhere a value is expected.
_spec_scalar(x::Real) = x
_spec_scalar(x::Bool) = x
_spec_scalar(x::AbstractString) = String(x)
_spec_scalar(x::Char) = string(x)
_spec_scalar(::Nothing) = throw(ValueSpecError("`nothing` is not a parameter value."))

function _spec_value(ex, text::AbstractString)
    #! Literals: numbers, Bools, strings, chars.
    if ex isa Real || ex isa Bool || ex isa AbstractString || ex isa Char
        return _spec_scalar(ex)
    end

    #! A bare symbol is either a distribution name used without arguments, or a variable
    #! reference. Both are errors, but they deserve different messages.
    if ex isa Symbol
        if haskey(ALLOWED_DISTRIBUTIONS, ex)
            throw(ValueSpecError("`$(ex)` needs arguments, e.g. `$(ex)(1.0, 0.2)`."))
        end
        throw(ValueSpecError("`$(ex)` is not a value. $(_hint())"))
    end

    ex isa Expr || throw(ValueSpecError("Could not read \"$(text)\" as a value. $(_hint())"))

    #! Negative literals parse as `-(x)`; allow them for numbers only. Negating a distribution
    #! is not meaningful to `DistributedVariation`, so it is rejected rather than silently
    #! producing something odd.
    if _isexpr(ex, :call) && length(ex.args) == 2 && ex.args[1] === :-
        inner = _spec_value(ex.args[2], text)
        inner isa Real || throw(ValueSpecError("`-` can only negate a number."))
        return -inner
    end
    if _isexpr(ex, :call) && length(ex.args) == 2 && ex.args[1] === :+
        inner = _spec_value(ex.args[2], text)
        inner isa Real || throw(ValueSpecError("`+` can only apply to a number."))
        return inner
    end

    #! Vector literal.
    if _isexpr(ex, :vect)
        return _collect_elements(ex.args, text)
    end

    #! Range. `a:b` parses as a 2-arg `:` call, `a:s:b` as 3-arg. Materialize eagerly so the
    #! rest of the pipeline sees a plain Vector — MM's DiscreteVariation wants `Vector{T}`.
    if _isexpr(ex, :call) && ex.args[1] === :(:) && length(ex.args) in (3, 4)
        bounds = [_spec_value(a, text) for a in ex.args[2:end]]
        all(b -> b isa Real, bounds) || throw(ValueSpecError("A range needs numbers, e.g. `0.1:0.2:0.9`."))
        rng = length(bounds) == 2 ? (bounds[1]:bounds[2]) : (bounds[1]:bounds[2]:bounds[3])
        isempty(rng) && throw(ValueSpecError("`$(text)` is an empty range — check the step's sign."))
        return collect(rng)
    end

    #! A whitelisted distribution constructor.
    if _isexpr(ex, :call) && ex.args[1] isa Symbol
        name = ex.args[1]
        haskey(ALLOWED_DISTRIBUTIONS, name) || throw(ValueSpecError(_unknown_distribution_message(name)))
        args = Any[]
        for a in ex.args[2:end]
            #! Keyword arguments are not part of the grammar; a distribution's parameters are
            #! positional in Distributions.jl and allowing `;` would widen the AST surface.
            _isexpr(a, :parameters) && throw(ValueSpecError("`$(name)` takes positional arguments only."))
            v = _spec_value(a, text)
            v isa Real || throw(ValueSpecError("`$(name)` takes numbers, not `$(v)`."))
            push!(args, v)
        end
        try
            return ALLOWED_DISTRIBUTIONS[name](args...)
        catch e
            #! Distributions itself validates parameter domains (e.g. a negative σ), and its
            #! messages are good, so pass them through rather than reinventing the checks.
            throw(ValueSpecError("`$(text)` is not a valid $(name): $(sprint(showerror, e))"))
        end
    end

    throw(ValueSpecError("Could not read \"$(text)\" as a value. $(_hint())"))
end

function _collect_elements(args, text::AbstractString)
    isempty(args) && throw(ValueSpecError("An empty list has no values to vary over."))
    vals = Any[]
    for a in args
        v = _spec_value(a, text)
        v isa Distribution && throw(ValueSpecError("A list cannot contain a distribution — give either a list of values or a single distribution."))
        push!(vals, v)
    end
    #! Narrow the element type so DiscreteVariation gets a concrete Vector{T}. A mixed list
    #! (e.g. [1, true]) promotes to a common type via `identity.(...)`, which is what the
    #! variation database would store anyway.
    return identity.(vals)
end

"""
    _unknown_distribution_message(name::Symbol)

Explain that `name` is not usable, suggesting near matches by name rather than listing all
$(length(ALLOWED_DISTRIBUTIONS) > 0 ? "" : "")available distributions — there are dozens, and a wall of them is not a useful error.
"""
function _unknown_distribution_message(name::Symbol)
    n = String(name)
    lower = lowercase(n)
    #! Prefix/substring match catches the common cases: a typo'd suffix, wrong capitalization,
    #! or reaching for a wrapper (`Truncated`) that this grammar deliberately excludes.
    near = filter(allowed_distribution_names()) do a
        la = lowercase(a)
        startswith(la, lower[1:min(3, end)]) || occursin(lower, la) || occursin(la, lower)
    end
    msg = "`$(n)` is not a univariate distribution this editor accepts."
    if !isempty(near)
        msg *= " Did you mean: $(join(first(sort(near), 5), ", "))?"
    end
    return msg * " $(length(ALLOWED_DISTRIBUTIONS)) are available; multivariate distributions and wrappers such as `Truncated` are not."
end
