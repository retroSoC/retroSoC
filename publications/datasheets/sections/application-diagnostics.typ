#import "../style.typ": *

=== Diagnostic application sequences <application-diagnostics>
The following inventories describe the checks that the reviewed application sources execute.
They are not newly observed pass results. Run selection and reported coverage must name the
application, profile and stage; an application summary line cannot enlarge the tested scope.
These routines change hardware state and scratch memory and belong in a controlled diagnostic
environment with competing users stopped.

#for app in data.system_reference.software.applications {
  block(breakable:false,sticky:true)[
    #heading(level:4,app.title)
    #par(app.selection)
    #par(app.prerequisites)
  ]
  ds-table("application-coverage-"+app.id,[#app.title: ordered checks and coverage boundaries],
    ([Step / check],[Actual operation],[Not established / side effects]),
    app.stages.map(s=>([#str(s.order). #s.title],s.coverage,s.boundary)),
    widths:(1.05fr,1.7fr,1.7fr))
  source-note(app.source,title:"Actual application sequence and terminal branches")
}

Bringup prints application and ARCHINFO diagnostics between UART setup and the SDIO check.
The ARCHINFO diagnostic routine returns void; its error text is not separately propagated into
bringup's terminal result. The CI smoke application has its own explicit identity check and
is selected by the regression runner's APP override. Do not equate the two sequences.

The SDIO self-test observes controller presence/capabilities and uses the CMD_DONE test-IRQ path;
it does not send a card-initialization or data-transfer command. USB2 self-test requires an idle
controller, injects the fatal-status test IRQ and clears that bit only if it was not already
pending. Neither routine proves CPU interrupt delivery, external device enumeration or a
physical data transfer.

Crypto self-test compares an AES-128 ECB encryption result and a SHA-256 digest against known
answers and requests key zeroization, including on an earlier failure. It does not cover all
algorithm modes or establish side-channel, entropy or security certification. Other CI smoke
checks have similarly bounded meanings: APU is discovery-only, RNG uses diagnostic data, CLINT
and timers are polled, and GPIO31 is exercised without an independent external measurement.

Use @firmware-application-results for terminal codes, C returns and repeated code values.
Record test invocation and logs under @release-verification before publishing a matching pass.
#source-note("crt/src/hal/sdio.c",title:"SDIO controller self-test implementation")
#source-note("crt/src/hal/usb2.c",title:"USB2 controller self-test implementation")
#source-note("crt/src/hal/crypto.c",title:"Crypto known-answer checks and zeroization")
#source-note("scripts/regress.py",title:"Regression selection of CI smoke firmware")
