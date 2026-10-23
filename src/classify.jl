# classify.jl — Julia evaluation excerpt classification.
# Owned by lead (reassigned from replbridge-core after runtime failures).

"""
    classifyError(excerpt::AbstractString) :: Symbol

Classify a Julia evaluation excerpt into one of:
`:none` `:methodError` `:loadError` `:precompileFailure` `:incompleteInput`
`:interrupt` `:other`.

Heuristics (order matters — most specific first):
* `Failed to precompile` / `Error during precompilation` → `:precompileFailure`
* `LoadError` (include/using-time failure wrapper) → `:loadError`
* `MethodError` / `UndefVarError` / `no method matching` / `not defined in`
  → `:methodError` (undefined names are grouped with failed calls)
* Parse errors marked `incomplete` (trailing construct swallowed input)
  → `:incompleteInput`
* `InterruptException` / `^C` interruption banners → `:interrupt`
* Any other `ERROR:` line → `:other`; clean excerpts → `:none`
"""
function classifyError end

function classifyError(excerpt::AbstractString)::Symbol
    isempty(strip(excerpt)) && return :none

    occursin(r"Failed to precompile", excerpt) && return :precompileFailure
    occursin(r"Error during precompilation", excerpt) && return :precompileFailure
    occursin(r"LoadError", excerpt) && return :loadError
    occursin(r"MethodError|UndefVarError|no method matching|not defined in",
             excerpt) && return :methodError
    occursin(r"incomplete:", excerpt) && return :incompleteInput
    occursin(r"ParseError", excerpt) && occursin(r"incomplete", excerpt) &&
        return :incompleteInput
    occursin(r"InterruptException", excerpt) && return :interrupt
    occursin(r"\^C", excerpt) && return :interrupt
    occursin(r"ERROR:", excerpt) && return :other

    return :none
end

"""
    classifyShellError(excerpt::AbstractString) :: Symbol

Shell-output failure classification, for evals resolved WITHOUT the shell's exit
status (prompt-watch mode, where no wrapper is typed and therefore no `\$?` is
captured). Coarse but honest: `:none` means "no failure text was seen", NOT
"exit code 0", so callers must not treat it as a verified success.

Patterns are anchored to whole-line starts where a word like "error" is common
inside ordinary output (grep results, logs), so a search for the word does not
turn a successful command into a failure.
"""
function classifyShellError end

# Tool-prefixed shell failures (`find: |: unknown primary or operator`, `sed: 1:
# "x": invalid command code`, `ls: …: No such file`). A line must START with a
# known tool so ordinary `file:line: text` output is not misclassified.
const SHELL_TOOL_ERROR_RE = Regex(
    "(?m)^\\s*(?:find|sed|awk|grep|egrep|fgrep|ls|cat|head|tail|sort|uniq|" *
    "wc|cp|mv|rm|rmdir|mkdir|chmod|chown|ln|touch|stat|du|df|diff|tar|zip|" *
    "unzip|git|make|cmake|ninja|cc|clang|gcc|julia|python[0-9.]*|pip[0-9.]*|" *
    "curl|wget|ssh|scp|rsync|bat|less|micro|vim|nano|env|which|file):\\s+.*" *
    "(?:unknown|invalid|cannot|not found|No such|error|failed|denied|missing|usage)")

function classifyShellError(excerpt::AbstractString)::Symbol
    s = String(excerpt)
    isempty(strip(s)) && return :none
    occursin(r"command not found|: not found\b", s) && return :commandNotFound
    occursin(r"No such file or directory|cannot access|cannot open", s) && return :notFound
    occursin(r"Permission denied|Operation not permitted", s) && return :permission
    occursin(r"syntax error|unexpected (?:token|EOF)|parse error", s) && return :syntax
    occursin(r"(?i)segmentation fault|core dumped|^Killed\b"m, s) && return :crashed
    # `ERROR:` (Julia/Python style) or a line that STARTS with a failure word.
    occursin(r"(?m)^\s*(?:ERROR:|error:|fatal:|Fatal:|failed\b|FAILED\b)", s) &&
        return :other
    occursin(SHELL_TOOL_ERROR_RE, s) && return :other
    return :none
end
