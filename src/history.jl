# history.jl — owned by replbridge-core child agent.
# EvalRegistry behavior: pending tracking, resolution, rolling history.

"""Record that an evaluation started (registers it as pending)."""
function registerEval!(reg::EvalRegistry, id::AbstractString)
    lock(reg.lock)
    try
        reg.pending[id] = time()
    finally
        unlock(reg.lock)
    end
    return id
end

function resolveEval!(reg::EvalRegistry, id::AbstractString, outcome::EvalOutcome)
    lock(reg.lock)
    try
        t0 = get(reg.pending, id, nothing)
        delete!(reg.pending, id)
        # Fill duration from the pending registration time unless the caller
        # supplied one explicitly (EvalOutcome is immutable, so rebuild).
        if outcome.duration == 0.0 && t0 !== nothing
            outcome = EvalOutcome(outcome.evalId, outcome.ok, outcome.excerpt,
                                  outcome.errorKind, time() - t0)
        end
        push!(reg.history, outcome)
        maxH = max(0, reg.maxHistory)
        if length(reg.history) > maxH
            drop = length(reg.history) - maxH
            deleteat!(reg.history, 1:drop)
        end
    finally
        unlock(reg.lock)
    end
    return outcome
end

function recentHistory(reg::EvalRegistry; n::Int = 20)
    n = max(0, min(n, length(reg.history)))
    lock(reg.lock)
    try
        if n <= 0
            return EvalOutcome[]
        end
        start = length(reg.history) - n + 1
        return reverse(copy(reg.history[start:end]))
    finally
        unlock(reg.lock)
    end
end
