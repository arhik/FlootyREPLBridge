using FlootyREPLBridge
using FlootyREPLBridge: sentinelBegin, sentinelEnd, wrapWithSentinels, parseSentinels, classifyError, detectReplFlavor, registerEval!, resolveEval!, recentHistory, EvalRegistry, EvalOutcome, BeginEval, EndEval, ReplFlavor, replJulia

fail = 0
function check(name, cond)
    global fail
    if cond; println("PASS: ", name)
    else; println("FAIL: ", name); fail += 1; end
end

# --- sentinels round trip ---
b = wrapWithSentinels("x = 1 + 1\nprintln(\"hi\")", "abc-123")
s = String(b)
check("wrap contains BEGIN println", occursin("FLOOTY_EVAL_BEGIN:abc-123", s))
check("wrap contains END println", occursin("FLOOTY_EVAL_END:abc-123:ok", s))
evts = parseSentinels(codeunits(s))
check("roundtrip 2 events", length(evts) == 2)
check("roundtrip begin id", evts[1] isa BeginEval && evts[1].evalId == "abc-123")
check("roundtrip end ok", evts[2] isa EndEval && evts[2].ok && evts[2].evalId == "abc-123")

# --- interleaved user chatter between markers ---
toks = split(s, "\n")
inter = toks[1] * "\nUSER CHATTER\nERROR: unrelated noise from user command\nx = 5\n" *
       join(toks[2:end], "\n") * "\nmore user output\n"
evts2 = parseSentinels(codeunits(inter))
check("interleaved still pairs", length(evts2) == 2)
check("interleaved excerpt has chatter", any(e -> e isa EndEval && occursin("USER CHATTER", e.excerpt), evts2))

# --- ERROR in excerpt forces err even when END says ok ---
errwrap = string("println(\"", sentinelBegin("e1"), "\")\n",
                 "ERROR: MethodError: no method matching foo(Int64)\n",
                 "println(\"", sentinelEnd("e1", true), "\")\n")
evts3 = parseSentinels(codeunits(errwrap))
check("error event detected", length(evts3) == 2 && evts3[2] isa EndEval && !evts3[2].ok)
check("methodError classified", classifyError(evts3[2].excerpt) === :methodError)

# --- ANSI-wrapped tokens survive ---
ansi = "\x1b[32m" * sentinelBegin("a1") * "\x1b[0m\nbody\n\x1b[36m" * sentinelEnd("a1", true) * "\x1b[0m\n"
evts4 = parseSentinels(codeunits(ansi))
check("ANSI stripped pairing", length(evts4) == 2 && evts4[2].ok)

# --- classification table ---
check("clean is none", classifyError("1+1\n2") === :none)
check("precompileFailure", classifyError("ERROR: Failed to precompile X [uuid]") === :precompileFailure)
check("loadError", classifyError("ERROR: LoadError: something bad") === :loadError)
check("undefVarError classified", classifyError("ERROR: UndefVarError: `nope` not defined in `Main`") === :methodError)
check("incompleteInput", classifyError("ERROR: ParseError: incomplete: \"foo(\" at") === :incompleteInput)
check("interrupt", classifyError("InterruptException:\nStacktrace:") === :interrupt)

# --- shell error table (prompt-watch has no exit status) ---
check("command not found", classifyShellError("zsh: command not found: foo") === :commandNotFound)
check("find unknown primary", classifyShellError("find: |: unknown primary or operator") === :other)
check("sed invalid command", classifyShellError("sed: 1: \"x\": invalid command code") === :other)
check("file:line text is not an error",
      classifyShellError("src/a.jl:12: unknown primary or operator") === :none)

# --- detection ---
check("detect julia prompt", detectReplFlavor("\nJulia Version 1.12.7\njulia> ") === replJulia)
check("detect nothing", detectReplFlavor("bash-3.2\$ echo hi") === nothing)

# --- history registry ---
reg = EvalRegistry(maxHistory = 3)
registerEval!(reg, "e1"); sleep(0.01); resolveEval!(reg, "e1", EvalOutcome(evalId="e1", ok=true, excerpt="ok"))
registerEval!(reg, "e2"); sleep(0.01); resolveEval!(reg, "e2", EvalOutcome(evalId="e2", ok=false, excerpt="bad", errorKind=:other))
h = recentHistory(reg; n=10)
check("history newest first", length(h) == 2 && h[1].evalId == "e2")
check("duration filled from pending", h[2].duration > 0.0)
for i in 3:6
    id = "x$i"; registerEval!(reg, id); resolveEval!(reg, id, EvalOutcome(evalId=id, ok=true))
end
check("history capped at maxHistory", length(recentHistory(reg; n=100)) == 3)

# --- sentinel helpers ---
check("sentinelBegin format", sentinelBegin("zz") == string(Char(0xf0a7), "FLOOTY_EVAL_BEGIN:zz"))
check("sentinelEnd err format", sentinelEnd("zz", false) == string(Char(0xf0a7), "FLOOTY_EVAL_END:zz:err"))

println(fail == 0 ? "ALL PASS" : "FAILURES: $fail")
exit(fail == 0 ? 0 : 1)
