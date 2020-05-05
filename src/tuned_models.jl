## TYPES AND CONSTRUCTOR

mutable struct DeterministicTunedModel{T,M<:Deterministic,A,AR} <: MLJBase.Deterministic
    model::M
    tuning::T  # tuning strategy
    resampling # resampling strategy
    measure
    weights::Union{Nothing,Vector{<:Real}}
    operation
    range
    train_best::Bool
    repeats::Int
    n::Union{Int,Nothing}
    acceleration::A
    acceleration_resampling::AR
    check_measure::Bool
end

mutable struct ProbabilisticTunedModel{T,M<:Probabilistic,A,AR} <: MLJBase.Probabilistic
    model::M
    tuning::T  # tuning strategy
    resampling # resampling strategy
    measure
    weights::Union{Nothing,AbstractVector{<:Real}}
    operation
    range
    train_best::Bool
    repeats::Int
    n::Union{Int,Nothing}
    acceleration::A
    acceleration_resampling::AR
    check_measure::Bool
end

const EitherTunedModel{T,M} =
    Union{DeterministicTunedModel{T,M},ProbabilisticTunedModel{T,M}}

MLJBase.is_wrapper(::Type{<:EitherTunedModel}) = true

#todo update:
"""
    tuned_model = TunedModel(; model=nothing,
                             tuning=Grid(),
                             resampling=Holdout(),
                             measure=nothing,
                             weights=nothing,
                             repeats=1,
                             operation=predict,
                             range=nothing,
                             n=default_n(tuning, range),
                             train_best=true,
                             acceleration=default_resource(),
                             acceleration_resampling=CPU1(),
                             check_measure=true)

Construct a model wrapper for hyperparameter optimization of a
supervised learner.

Calling `fit!(mach)` on a machine `mach=machine(tuned_model, X, y)` or
`mach=machine(tuned_model, X, y, w)` will:

- Instigate a search, over clones of `model`, with the hyperparameter
  mutations specified by `range`, for a model optimizing the specified
  `measure`, using performance evaluations carried out using the
  specified `tuning` strategy and `resampling` strategy.

- Fit an internal machine, based on the optimal model
  `fitted_params(mach).best_model`, wrapping the optimal `model`
  object in *all* the provided data `X`, `y`(, `w`). Calling
  `predict(mach, Xnew)` then returns predictions on `Xnew` of this
  internal machine. The final train can be supressed by setting
  `train_best=false`.

The `range` objects supported depend on the `tuning` strategy
specified. Query the `strategy` docstring for details. To optimize
over an explicit list `v` of models of the same type, use
`strategy=Explicit()` and specify `model=v[1]` and `range=v`.

The number of models searched is specified by `n`. If unspecified,
then `MLJTuning.default_n(tuning, range)` is used. When `n` is
increased and `fit!(mach)` called again, the old search history is
re-instated and the search continues where it left off.

If `measure` supports weights (`supports_weights(measure) == true`)
then any `weights` specified will be passed to the measure. If more
than one `measure` is specified, then only the first is optimized
(unless `strategy` is multi-objective) but the performance against
every measure specified will be computed and reported in
`report(mach).best_performance` and other relevant attributes of the
generated report.

Specify `repeats > 1` for repeated resampling per model evaluation. See
[`evaluate!`](@ref) options for details.

*Important.* If a custom `measure` is used, and the measure is
a score, rather than a loss, be sure to check that
`MLJ.orientation(measure) == :score` to ensure maximization of the
measure, rather than minimization. Override an incorrect value with
`MLJ.orientation(::typeof(measure)) = :score`.

*Important:* If `weights` are left unspecified, and `measure` supports
sample weights, then any weight vector `w` used in constructing a
corresponding tuning machine, as in `tuning_machine =
machine(tuned_model, X, y, w)` (which is then used in *training* each
model in the search) will also be passed to `measure` for evaluation.

In the case of two-parameter tuning, a Plots.jl plot of performance
estimates is returned by `plot(mach)` or `heatmap(mach)`.

Once a tuning machine `mach` has bee trained as above, then
`fitted_params(mach)` has these keys/values:

key                 | value
--------------------|--------------------------------------------------
`best_model`        | optimal model instance
`best_fitted_params`| learned parameters of the optimal model

The named tuple `report(mach)` includes these keys/values:

key                 | value
--------------------|--------------------------------------------------
`best_model`        | optimal model instance
`best_result`       | corresponding "result" entry in the history
`best_report`       | report generated by fitting the optimal model
`history`           | tuning strategy-specific history of all evaluations

plus others specific to the `tuning` strategy, such as `history=...`.


### Summary of key-word arguments

- `model`: `Supervised` model prototype that is cloned and mutated to
  generate models for evaluation

- `tuning=Grid()`: tuning strategy to be applied (eg, `RandomSearch()`)

- `resampling=Holdout()`: resampling strategy (eg, `Holdout()`, `CV()`),
  `StratifiedCV()`) to be applied in performance evaluations

- `measure`: measure or measures to be applied in performance
  evaluations; only the first used in optimization (unless the
  strategy is multi-objective) but all reported to the history

- `weights`: sample weights to be passed the measure(s) in performance
  evaluations, if supported (see important note above for behaviour in
  unspecified case)

- `repeats=1`: for generating train/test sets multiple times in
  resampling; see [`evaluate!`](@ref) for details

- `operation=predict`: operation to be applied to each fitted model;
  usually `predict` but `predict_mean`, `predict_median` or
  `predict_mode` can be used for `Probabilistic` models, if
  the specified measures are `Deterministic`

- `range`: range object; tuning strategy documentation describes
  supported types

- `n`: number of iterations (ie, models to be evaluated); set by
  tuning strategy if left unspecified

- `train_best=true`: whether to train the optimal model

- `acceleration=default_resource()`: mode of parallelization for
  tuning strategies that support this

- `acceleration_resampling=CPU1()`: mode of parallelization for
  resampling

- `check_measure`: whether to check `measure` is compatible with the
  specified `model` and `operation`)

"""
function TunedModel(; model=nothing,
                    tuning=Grid(),
                    resampling=MLJBase.Holdout(),
                    measures=nothing,
                    measure=measures,
                    weights=nothing,
                    operation=predict,
                    ranges=nothing,
                    range=ranges,
                    train_best=true,
                    repeats=1,
                    n=nothing,
                    acceleration=default_resource(),
                    acceleration_resampling=CPU1(),
                    check_measure=true)

    range === nothing && error("You need to specify `range=...`.")
    model == nothing && error("You need to specify model=... .\n"*
                              "If `tuning=Explicit()`, any model in the "*
                              "range will do. ")

    if model isa Deterministic
        tuned_model = DeterministicTunedModel(model, tuning, resampling,
                                       measure, weights, operation, range,
                                              train_best, repeats, n,
                                              acceleration,
                                              acceleration_resampling,
                                              check_measure)
    elseif model isa Probabilistic
        tuned_model = ProbabilisticTunedModel(model, tuning, resampling,
                                       measure, weights, operation, range,
                                              train_best, repeats, n,
                                              acceleration,
                                              acceleration_resampling,
                                              check_measure)
    else
        error("Only `Deterministic` and `Probabilistic` "*
              "model types supported.")
    end

    message = clean!(tuned_model)
    isempty(message) || @info message

    return tuned_model

end

function MLJBase.clean!(tuned_model::EitherTunedModel)
    message = ""
    if tuned_model.measure === nothing
        tuned_model.measure = default_measure(tuned_model.model)
        if tuned_model.measure === nothing
            error("Unable to deduce a default measure for specified model. "*
                  "You must specify `measure=...`. ")
        else
            message *= "No measure specified. "*
            "Setting measure=$(tuned_model.measure). "
        end
    end
    if (tuned_model.acceleration isa CPUProcesses && 
        tuned_model.acceleration_resampling isa CPUProcesses)
        message *= 
        "The combination acceleration=$(tuned_model.acceleration) and"*
        " acceleration_resampling=$(tuned_model.acceleration_resampling) is"*
        "  not generally optimal. You may want to consider setting"*
        " `acceleration = CPUProcesses()` and"*
        " `acceleration_resampling = CPUThreads()`."
     end
    if (tuned_model.acceleration isa CPUThreads && 
        tuned_model.acceleration_resampling isa CPUProcesses)
        message *= 
        "The combination acceleration=$(tuned_model.acceleration) and"*
        " acceleration_resampling=$(tuned_model.acceleration_resampling) is"*
        "  not generally optimal. You may want to consider setting"*
        " `acceleration = CPUProcesses()` and"*
        " `acceleration_resampling = CPUThreads()`."
     end
    return message
end


## FIT AND UPDATE METHODS

# A *metamodel* is either a `Model` instance, `model`, or a tuple
# `(model, s)`, where `s` is extra data associated with `model` that
# the tuning strategy implementation wants available to the `result`
# method for recording in the history.

_first(m::MLJBase.Model) = m
_last(m::MLJBase.Model) = nothing
_first(m::Tuple{Model,Any}) = first(m)
_last(m::Tuple{Model,Any}) = last(m)

# returns a (model, result) pair for the history:
function event(metamodel,
               resampling_machine,
               verbosity,
               tuning,
               history,
               state)
    model = _first(metamodel)
    metadata = _last(metamodel)
    resampling_machine.model.model = model
    verb = (verbosity >= 2 ? verbosity - 3 : verbosity - 1)
    fit!(resampling_machine, verbosity=verb)
    e = evaluate(resampling_machine)
    r = result(tuning, history, state, e, metadata)

    if verbosity > 2
        println("hyperparameters: $(params(model))")
    end

    if verbosity > 1
        println("result: $r")
    end

    return model, r
end

function assemble_events(metamodels,
                         resampling_machines,
                         verbosity,
                         tuning,
                         history,
                         state,
                         acceleration::CPU1)
     local ret
     resampling_machine = resampling_machines[1]
     n_metamodels = length(metamodels)
     verbosity < 1 || begin
                 p = Progress(n_metamodels,
                 dt = 0,
                 desc = "Evaluating over $(n_metamodels) metamodels: ",
                 barglyphs = BarGlyphs("[=> ]"),
                 barlen = 25,
                 color = :yellow)
                 update!(p,0)
      end
    
      @sync begin   
        ret = map(metamodels) do m
            r= event(m, resampling_machine, verbosity, tuning, history, state)
            verbosity < 1 || next!(p)
            r
       end
      end

    return ret
end

function assemble_events(metamodels,
                         resampling_machines,
                         verbosity,
                         tuning,
                         history,
                         state,
                         acceleration::CPUProcesses)
  resampling_machine = resampling_machines[1]

  ret = if verbosity < 1
       pmap(metamodels) do m
            event(m, resampling_machine, verbosity, tuning, history, state)
       end
  else
      n_metamodels = length(metamodels)
      p = Progress(n_metamodels,
                 dt = 0,
                 desc = "Evaluating over $(n_metamodels) metamodels: ",
                 barglyphs = BarGlyphs("[=> ]"),
                 barlen = 25,
                 color = :yellow)
      update!(p,0)
      progress_pmap(metamodels, progress=p) do m
            event(m, resampling_machine, verbosity, tuning, history, state)
      end

  end
    
    return ret
end

@static if VERSION >= v"1.3.0-DEV.573"
# one machine for each thread; cycle through available threads:
function assemble_events(metamodels,
                         resampling_machines,
                         verbosity,
                         tuning,
                         history,
                         state,
                         acceleration::CPUThreads)
    
    if Threads.nthreads() == 1
        return assemble_events(metamodels,
                         resampling_machines,
                         verbosity,
                         tuning,
                         history,
                         state,
                         CPU1())
   end
    n_metamodels = length(metamodels)
    n_threads = Threads.nthreads()
    M = typeof(_first(first(metamodels)))
    ret = Vector{Tuple{M,Any}}(undef, n_metamodels)
    verbosity < 1 || (p = Progress(n_metamodels,
                 dt = 0,
                 desc = "Evaluating over $(n_metamodels) metamodels: ",
                 barglyphs = BarGlyphs("[=> ]"),
                 barlen = 25,
                 color = :yellow))
    verbosity < 1 || update!(p,0)
    lock_ = ReentrantLock()
    partitions = Iterators.partition(1:n_metamodels, 
                    max(1,cld(n_metamodels, n_threads)))
   @sync begin
    @sync for parts in partitions    
      Threads.@spawn begin        
        foreach(parts) do m
            id = Threads.threadid()
            if !haskey(resampling_machines, id)
               resampling_machines[id] =
                   machine(Resampler(model= resampling_machines[1].model.model,
                      resampling    = resampling_machines[1].model.resampling,
                      measure       = resampling_machines[1].model.measure,
                      weights       = resampling_machines[1].model.weights,
                      operation     = resampling_machines[1].model.operation,
                      check_measure = resampling_machines[1].model.check_measure,
                      repeats       = resampling_machines[1].model.repeats,
                      acceleration  = resampling_machines[1].model.acceleration),
                      resampling_machines[1].args...)
            end
            ret[m] = event(metamodels[m], resampling_machines[id], 
                                verbosity, tuning, history, state)
            verbosity < 1 || @sync begin
                            lock(lock_)do
                                p.counter +=1 
                                ProgressMeter.updateProgress!(p)
                            end
                         end
        end

      end

    end
    end

    return ret         
end


end

# history is intialized to `nothing` because it's type is not known.
_vcat(history, Δhistory) = vcat(history, Δhistory)
_vcat(history::Nothing, Δhistory) = Δhistory
_length(history) = length(history)
_length(::Nothing) = 0

# builds on an existing `history` until the length is `n` or the model
# supply is exhausted (method shared by `fit` and `update`). Returns
# the bigger history:
function build(history,
               n,
               tuning,
               model,
               state,
               verbosity,
               acceleration,
               resampling_machines)
    j = _length(history)
    models_exhausted = false
    while j < n && !models_exhausted
        metamodels = models!(tuning,
                             model,
                             history,
                             state,
                             n - j,
                             verbosity)
        Δj = _length(metamodels)
        Δj == 0 && (models_exhausted = true)
        shortfall = n - Δj
        if models_exhausted && shortfall > 0 && verbosity > -1
            @info "Only $j (of $n) models evaluated.\n"*
            "Model supply exhausted. "
        end
        Δj == 0 && break
        shortfall < 0 && (metamodels = metamodels[1:n - j])
        j += Δj

        Δhistory = assemble_events(metamodels,
                                   resampling_machines,
                                   verbosity,
                                   tuning,
                                   history,
                                   state,
                                   acceleration)

        history = _vcat(history, Δhistory)
    end
    return history
end

function MLJBase.fit(tuned_model::EitherTunedModel{T,M},
                     verbosity::Integer, data...) where {T,M}
    tuning = tuned_model.tuning
    model = tuned_model.model
    range = tuned_model.range
    n = tuned_model.n === nothing ?
        default_n(tuning, range) : tuned_model.n

    verbosity < 1 || @info "Attempting to evaluate $n models."

    acceleration = tuned_model.acceleration

    state = setup(tuning, model, range, verbosity)

    # instantiate resampler (`model` to be replaced with mutated
    # clones during iteration below):
    resampler = Resampler(model=model,
                          resampling    = tuned_model.resampling,
                          measure       = tuned_model.measure,
                          weights       = tuned_model.weights,
                          operation     = tuned_model.operation,
                          check_measure = tuned_model.check_measure,
                          repeats       = tuned_model.repeats,
                          acceleration  = tuned_model.acceleration_resampling)
    resampling_machine = machine(resampler, data...)
    # For multithreading we need a clone of `resampling_machine` for each thread
    # doing work. We have to be careful about data race.
    resampling_machines = Dict(1 => resampling_machine)
    history = build(nothing, n, tuning, model, state,
                    verbosity, acceleration, resampling_machines)

    best_model, best_result = best(tuning, history)
    fitresult = machine(best_model, data...)

    if tuned_model.train_best
        fit!(fitresult, verbosity=verbosity - 1)
        prereport = (best_model=best_model, best_result=best_result,
                     best_report=MLJBase.report(fitresult))
    else
        prereport = (best_model=best_model, best_result=best_result,
                     best_report=missing)
    end

    report = merge(prereport, tuning_report(tuning, history, state))
    meta_state = (history, deepcopy(tuned_model), state, resampling_machines)

    return fitresult, meta_state, report
end

function MLJBase.update(tuned_model::EitherTunedModel, verbosity::Integer,
                        old_fitresult, old_meta_state, data...)

    history, old_tuned_model, state, resampling_machines = old_meta_state
    acceleration = tuned_model.acceleration

    tuning = tuned_model.tuning
    range = tuned_model.range
    model = tuned_model.model

    # exclamation points are for values actually used rather than
    # stored:
    n! = tuned_model.n === nothing ?
        default_n(tuning, range) : tuned_model.n

    old_n! = old_tuned_model.n === nothing ?
        default_n(tuning, range) : old_tuned_model.n

    if MLJBase.is_same_except(tuned_model, old_tuned_model, :n) &&
        n! >= old_n!

        verbosity < 1 || @info "Attempting to add $(n! - old_n!) models "*
        "to search, bringing total to $n!. "

        history = build(history, n!, tuning, model, state,
                        verbosity, acceleration, resampling_machines)

        best_model, best_result = best(tuning, history)

        fitresult = machine(best_model, data...)

        if tuned_model.train_best
            fit!(fitresult, verbosity=verbosity - 1)
            prereport = (best_model=best_model, best_result=best_result,
                         best_report=MLJBase.report(fitresult))
        else
            prereport = (best_model=best_model, best_result=best_result,
                         best_report=missing)
        end

        _report = merge(prereport, tuning_report(tuning, history, state))

        meta_state = (history, deepcopy(tuned_model), state,
                      resampling_machines)

        return fitresult, meta_state, _report

    else

        return fit(tuned_model, verbosity, data...)

    end

end

MLJBase.predict(tuned_model::EitherTunedModel, fitresult, Xnew) =
    predict(fitresult, Xnew)

function MLJBase.fitted_params(tuned_model::EitherTunedModel, fitresult)
    if tuned_model.train_best
        return (best_model=fitresult.model,
                best_fitted_params=fitted_params(fitresult))
    else
        return (best_model=fitresult.model,
                best_fitted_params=missing)
    end
end


## METADATA

MLJBase.supports_weights(::Type{<:EitherTunedModel{<:Any,M}}) where M =
    MLJBase.supports_weights(M)

MLJBase.load_path(::Type{<:DeterministicTunedModel}) =
    "MLJTuning.DeterministicTunedModel"
MLJBase.package_name(::Type{<:EitherTunedModel}) = "MLJTuning"
MLJBase.package_uuid(::Type{<:EitherTunedModel}) = "MLJTuning"
MLJBase.package_url(::Type{<:EitherTunedModel}) =
    "https://github.com/alan-turing-institute/MLJTuning.jl"
MLJBase.is_pure_julia(::Type{<:EitherTunedModel{T,M}}) where {T,M} =
    MLJBase.is_pure_julia(M)
MLJBase.input_scitype(::Type{<:EitherTunedModel{T,M}}) where {T,M} =
    MLJBase.input_scitype(M)
MLJBase.target_scitype(::Type{<:EitherTunedModel{T,M}}) where {T,M} =
    MLJBase.target_scitype(M)
