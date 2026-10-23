# types.jl — core data structures for the REPL bridge protocol.
# NOTE: pre-written by the lead to pin the cross-package contract.
# Field names are binding: FlootyPTYLayer constructs/consumes these directly.

"""
Flavor of an interactive REPL session detected by the bridge.
Extensible: add e.g. `pythonRepl`, `psqlRepl` later.
"""
@enum ReplFlavor begin
    replJulia
end

"""Abstract event produced by sentinel parsing."""
abstract type BridgeEvent end

"""A BEGIN sentinel was observed: an evaluation started."""
struct BeginEval <: BridgeEvent
    evalId::String
end

"""An END sentinel was observed: an evaluation finished."""
struct EndEval <: BridgeEvent
    evalId::String
    ok::Bool
    excerpt::String
end

"""Outcome record for one agent-initiated evaluation."""
Base.@kwdef struct EvalOutcome
    evalId::String = ""
    ok::Bool = false
    excerpt::String = ""
    errorKind::Symbol = :other
    duration::Float64 = 0.0
end

"""Registry tracking pending and completed evaluations (behavior in history.jl)."""
mutable struct EvalRegistry
    pending::Dict{String,Float64}
    history::Vector{EvalOutcome}
    maxHistory::Int
    lock::ReentrantLock
end
EvalRegistry(; maxHistory::Int = 100) =
    EvalRegistry(Dict{String,Float64}(), EvalOutcome[], maxHistory, ReentrantLock())
