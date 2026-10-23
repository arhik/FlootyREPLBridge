# detection.jl — REPL flavor detection from terminal buffer text.
# Owned by lead (reassigned from replbridge-core after runtime failures).

"""
    detectReplFlavor(buffer::AbstractString) :: Union{Nothing,ReplFlavor}

Classify the text of a terminal buffer / startup banner as an interactive REPL
session. Julia variants: plain `julia>` prompts, `Julia Version 1.x` banners,
interactive/`--project` startup hints. Return `nothing` when the buffer does
not look like a REPL.
"""
function detectReplFlavor end

const _JULIA_PROMPT_RE = r"(^|\n)\s*julia> "
const _JULIA_BANNER_RE = r"Julia Version \d+\.\d+"
const _JULIA_HINT_RE = r"\bjulia(\.exe)?\b.*(-i|--project)"

function detectReplFlavor(buffer::AbstractString)::Union{Nothing,ReplFlavor}
    # Strip ANSI escapes so prompt/banner matches survive colored output.
    clean = replace(buffer, r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))" => "")

    if occursin(_JULIA_PROMPT_RE, clean) || occursin(_JULIA_BANNER_RE, clean) ||
       occursin(_JULIA_HINT_RE, clean)
        return replJulia
    end

    return nothing
end
