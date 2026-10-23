module FlootyREPLBridge

using Dates
using Logging
using UUIDs

# ---- types.jl --------------------------------------------------------------
export EvalOutcome, BridgeEvent, BeginEval, EndEval, ReplFlavor, EvalRegistry
# ---- detection.jl ----------------------------------------------------------
export detectReplFlavor, classifyShellError
# ---- sentinels.jl ----------------------------------------------------------
export sentinelBegin, sentinelEnd, wrapWithSentinels, parseSentinels
# ---- classify.jl -----------------------------------------------------------
export classifyError
# ---- history.jl ------------------------------------------------------------
export registerEval!, resolveEval!, recentHistory

include("types.jl")
include("detection.jl")
include("sentinels.jl")
include("classify.jl")
include("history.jl")

end # module FlootyREPLBridge
