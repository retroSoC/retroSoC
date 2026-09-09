#import "../style.typ": *
#import "../ip-reference.typ": inline

= Appendix: Fault and Status Code Reference <fault-code-reference>
This appendix is a lookup aid for the reviewed implementation. Begin with the producing
module and the validity/ownership state, then decode its value. An equal number in two tables
does not imply an equal fault. Numeric enums select one value; bitmasks can contain several
independent causes. Source-declared codes are not proof that every associated optional
function or end-to-end path is implemented.

Capture first-fault address, master, direction, engine progress and descriptor state before
acknowledging or resetting anything. The detailed register and recovery contracts in
@system-diagnostics remain authoritative. The global address lookup is @global-register-index.

== Diagnostic Code Namespaces
#for group in data.system_reference.retrieval.codes {
  block(breakable:false,sticky:true)[
    #heading(level:3,group.title)
    #par(group.observation)
  ]
  ds-table("code-"+group.id,[#group.title (#group.kind)],
    ([Value],[Symbol / namespace],[Meaning]),
    group.rows.map(r=>(code(r.display),code(r.name.replace("_","_\u{200b}")),r.meaning)),
    widths:(0.4fr,1.5fr,2.1fr))
  par(group.handling)
  block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
    #set text(size:9pt)
    #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
    #link(label(group.link))[Register and recovery reference] ·
    #source(group.source,title:"Encoding declaration / producing branch")
  ]
}

== Status Registers and Capture Points
The following diagnostic fields reuse the register reference with source-checked decoding
of selected packed producer values. Bit positions identify fields, not enum values. Reserved
bits are omitted; the linked register defines full-word access and acknowledgement. A status
field's width does not define its own codebook.

#for group in data.system_reference.retrieval.status_registers {
  block(breakable:false,sticky:true)[
    #heading(level:3,group.title)
    #par(group.observation)
  ]
  for register in group.rows {
    minor-title(link(label(register.link),register.name))
    ds-table("status-"+group.id+"-"+register.name,[#register.name diagnostic fields],
      ([Bits],[Field],[Interpretation]),
      register.fields.map(f=>(str(f.msb)+if f.msb!=f.lsb {":"+str(f.lsb)} else {""},
        code(f.name.replace("_","_\u{200b}")),inline(f.description))),widths:(0.4fr,1.1fr,2.5fr))
  }
  par(group.handling)
  [Read/write details and recovery: #link(label(group.link))[#group.link].]
}

== Firmware Application Results <firmware-application-results>
These tables distinguish application-specific TEST_STATUS values from C return values and
intermediate console messages. The same integer can denote different stages, including within
one application. Preserve application identity, execution order and preceding log markers.

=== HP Boot Application Results
These result codes belong to the supplied HP boot application. TEST_STATUS's result byte is
application-defined; other firmware can assign different meanings. Code 1 can be written
before a reliable console exists. A missing ready event does not generate a new firmware
code: the current final mailbox wait has no firmware-local deadline.

#ds-table("boot-result-codes",[HP boot application terminal result codes],
  ([Code],[Meaning / producing stage]),
  data.system_reference.retrieval.boot.rows.map(r=>(str(r.value),r.meaning)),widths:(0.4fr,3.6fr))

The #code("HP_BOOT_FAILED:<code>") diagnostic is emitted by the failure helper before its
terminal status write; UART initialization failure uses the direct terminal path. Entry-copy
failure is reported only after both the DMA attempt and software copy/CRC fallback fail.
After copying, HP release and Linux readiness are distinct checkpoints. See @boot-configuration
for prerequisites and @image-maintenance for separate programming-tool result semantics.
#source-note("app/apps/hp_boot/main.c",title:"Actual boot failure branches and ready-event handling")

#for app in data.system_reference.software.applications {
  heading(level:3,app.title)
  par(app.selection)
  ds-table("application-results-"+app.id,[#app.title: stage-scoped results],
    ([Stage],[Observation],[Meaning / distinction]),
    app.stages.map(s=>(s.title,s.result,s.boundary)),widths:(1.15fr,1.05fr,2.25fr))
  source-note(app.source,title:"Result-producing branches in this application")
}

Bringup's early UART failure returns 1 from main without calling the terminal writer; the
generic CRT spins after the return. Later bringup failures and all CI smoke terminal paths
call rs_test_finish, which writes TEST_STATUS and loops. The final C return zero following
that call is not an independently reached success path. A stall before main produces no
application result; see @lp-runtime.

CI smoke code 12 is shared by SRAM and USB2 failure branches; code 13 is shared by the monitor
setup and observation branches. The code alone cannot identify the exact stage. Inspect
preceding stage logs together with the selected source revision. Detailed check operations
and coverage limits are listed in @application-diagnostics.
#source-note("crt/src/service/test.c",title:"Terminal status writer and non-returning loop")

== Automated Completion and Simulator Verdicts
#ds-table("terminal-status-format",[SYSCTRL TEST_STATUS result format],
  ([Field],[Bits],[Meaning]),
  (([VALID],[31],[A terminal result is present.]),([PASS],[0],[One means pass; zero means fail when VALID is set.]),
   ([Application code],[15:8],[Application-specific result byte, including the HP boot table above.])),widths:(0.9fr,0.5fr,2.6fr))

The first valid full-word write is sticky until reset. Read VALID before interpreting PASS
or the code. UART startup text, a debugger connection and a successfully generated flash
script do not supply this hardware terminal verdict.

#ds-table("simulator-result-markers",[Simulator terminal markers],
  ([Marker],[Interpretation]),
  ((code("SIM_TEST_PASS"),[The testbench/emulator observed the terminal pass status.]),
   (code("SIM_TEST_FAIL"),[The testbench/emulator observed a terminal failure.]),
   (code("SIM_TEST_TIMEOUT"),[The configured simulator observation deadline expired.])),widths:(1.3fr,2.7fr))

A regression passes only when its command succeeds, the configured success marker is present
and forbidden failure markers are absent. Preserve the simulator log and structured flow
result together. Simulator wall-clock duration and a simulated firmware timestamp describe
different measurements. This appendix supplies no new successful hardware run.
#source-note("crt/src/service/test.c",title:"Firmware terminal result writer")
#source-note("rtl/mini/dv/tb/retrosoc_tb.sv",title:"Icarus testbench completion")
#source-note("rtl/mini/dv/verilator/csrc/Emulator.cpp",title:"Verilator completion")
#source-note("docs/engineering.md",title:"Regression verdict and evidence rules")
