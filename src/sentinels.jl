# sentinels.jl — BEGIN/END sentinel generation and parsing.
# Owned by lead (reassigned from replbridge-core after runtime failures).
#
# Wire format (single line each, embedded in println statements):
#   \u{f0a7}FLOOTY_EVAL_BEGIN:<evalId>
#   \u{f0a7}FLOOTY_EVAL_END:<evalId>:ok|err
# The private-use marker survives plain-text capture and never collides with
# realistic user text. END prints even when the evaluated expression errored,
# because the Julia REPL proceeds to the next top-level expression after an
# error.

"""
    sentinelBegin(evalId::AbstractString) :: String
    sentinelEnd(evalId::AbstractString, ok::Bool) :: String

Render the sentinel lines injected around an evaluation. Must survive plain-text
capture, embed the eval id, and never collide with realistic user text.
"""
function sentinelBegin end
function sentinelEnd end

# Private-use codepoint constructed at load time (literal escapes of PUA are
# rejected by the Julia parser in this context).
const _SENTINEL_MARKER = string(Char(0xf0a7))
const _BEGIN_TAG = "FLOOTY_EVAL_BEGIN:"
const _END_TAG = "FLOOTY_EVAL_END:"

sentinelBegin(evalId::AbstractString)::String =
    string(_SENTINEL_MARKER, _BEGIN_TAG, evalId)

sentinelEnd(evalId::AbstractString, ok::Bool)::String =
    string(_SENTINEL_MARKER, _END_TAG, evalId, ":", ok ? "ok" : "err")

"""
    wrapWithSentinels(input::AbstractString, evalId::AbstractString) :: Vector{UInt8}

Wrap agent input with BEGIN/END sentinel lines, ready to write to the PTY.
The END line must reach the REPL even when the evaluated expression errors,
so it is emitted as an independent self-contained statement after the input.
"""
function wrapWithSentinels end

function wrapWithSentinels(input::AbstractString, evalId::AbstractString)::Vector{UInt8}
    body = String(input)
    endswith(body, '\n') || (body *= '\n')
    # Embed the RAW sentinel token (not repr): the bytes we type must match the
    # bytes the REPL prints, so echo and executed output carry one uniform
    # token form. evalIds are internally generated from a safe charset.
    wrapped = string("println(\"", sentinelBegin(evalId), "\")\n",
        body,
        "println(\"", sentinelEnd(evalId, true), "\")\n")
    return Vector{UInt8}(codeunits(wrapped))
end

"""
    parseSentinels(bytes::AbstractVector{UInt8}) :: Vector{BridgeEvent}

Scan raw PTY output bytes for BEGIN/END sentinels and return events
(`BeginEval(id)` / `EndEval(id, ok, excerpt)`). Pairing is by eval id and must
tolerate arbitrary interleaved user output between the two markers.
"""
function parseSentinels end

# Strip ANSI escape sequences (CSI + OSC) so PTY echo does not hide tokens.
const _ANSI_RE = r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\))"
const _EXCERPT_CAP = 16384

"""Bounds-safe substring `s[lo:hi]`; clamps to valid indices, empty when inverted."""
function safeSlice(s::AbstractString, lo::Integer, hi::Integer)
    hiC = min(Int(hi), lastindex(s))
    loC = max(Int(lo), 1)
    loC > hiC && return ""
    return SubString(s, loC, hiC)
end

# Full token string: marker + tag + id (+ optional :ok/:err suffix).
# Scanning is plain substring search — robust and free of regex offset math.
isIdChar(c::Char) = isletter(c) || isdigit(c) || c == '-' || c == '_'

"""All occurrences of `marker*tag` in `s` as sorted (byteIndex, evalId)."""
# NOTE: the marker is a 3-byte PUA char, so ALL position math below uses
# character indices via nextind/length — never byte counts.
function _scanTokens(s::AbstractString, marker::AbstractString, tag::AbstractString)
    full = string(marker, tag)
    fullChars = length(full)
    hits = Tuple{Int,String}[]
    from = firstindex(s)
    while (k = findnext(full, s, from)) !== nothing
        i = first(k)
        # Truncated token at end of buffer: skip rather than let nextind throw.
        if i + ncodeunits(full) - 1 > lastindex(s)
            break
        end
        p = nextind(s, i, fullChars)     # first char index after the tag
        q = p
        while q <= lastindex(s) && isIdChar(s[q])
            q = nextind(s, q)
        end
        idStr = s[p:prevind(s, q)]
        isempty(idStr) || push!(hits, (i, idStr))
        from = nextind(s, i)
    end
    return sort(hits; by = first)
end

function parseSentinels(bytes::AbstractVector{UInt8})::Vector{BridgeEvent}
    raw = try
        String(bytes)
    catch
        String(copy(bytes))  # lenient fallback for invalid UTF-8 chunks
    end
    clean = replace(raw, _ANSI_RE => "")
    beginHits = _scanTokens(clean, _SENTINEL_MARKER, _BEGIN_TAG)
    endHits = _scanTokens(clean, _SENTINEL_MARKER, _END_TAG)

    events = BridgeEvent[]
    for (_, id) in beginHits
        push!(events, BeginEval(id))
    end

    beginFull = string(_SENTINEL_MARKER, _BEGIN_TAG)
    endFull = string(_SENTINEL_MARKER, _END_TAG)
    for (i, id) in endHits
        # ':ok'/':err' suffix sits immediately after the id inside the same token.
        afterId = nextind(clean, i, length(endFull) + length(id))
        suffix = safeSlice(clean, afterId, afterId + 3)
        okFlag = !occursin(":err", suffix)

        # Excerpt: between this eval's most recent BEGIN and this END token.
        # prefix starts at clean index 1, so match indices carry over to clean.
        prefix = safeSlice(clean, 1, prevind(clean, i))
        bIdx = findlast(string(beginFull, id), prefix)
        if bIdx === nothing
            continue  # unmatched END token — ignore defensively
        end
        lo = nextind(prefix, first(bIdx), length(beginFull) + length(id))
        hi = prevind(clean, i)
        excerpt = strip(safeSlice(clean, lo, hi))
        length(excerpt) > _EXCERPT_CAP && (excerpt = first(excerpt, _EXCERPT_CAP))
        # ok additionally flips false when the excerpt holds a Python
        # traceback (the typed-wrapper emitters cannot always see it: a
        # traceback printed by the PREVIOUS failed statement leaves
        # sys.last_value set, and ipython prints tracebacks without any
        # "ERROR:" line).
        ok = okFlag && !occursin(r"ERROR:", excerpt) &&
             !occursin("Traceback (most recent call last)", excerpt)
        push!(events, EndEval(id, ok, String(excerpt)))
    end
    return events
end
