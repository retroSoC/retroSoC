#import "../style.typ": *

#let apu-release-reference() = [
  #minor-title("Default and P7 acceptance configurations")
  #ds-table("apu-profile-capabilities",[APU capability and digest by committed configuration],
    ([Configuration],[CAPABILITY0],[ABI_DIGEST],[Software boundary]),
    data.system_reference.apu_implementation.profiles.map(r=>([#r.name \ #code(r.profile)],
      code("0x"+upper(str(r.capability,base:16))),code("0x"+upper(str(r.digest,base:16))),
      if r.enabled {[Fixed APUM KWS is enabled; APP=apu_release and CSR-enabled IRQ acceptance.]} else {[WAV/FLAC enabled; KWS discovery returns RS_ENOTSUP.]})),
    widths:(1.45fr,0.65fr,0.65fr,1.25fr))
  The P7 digest is an ABI identity derived from the frozen register, model and microcode
  interfaces. It is not a runtime accuracy result, firmware authentication or a physical
  qualification certificate. MP3 capability remains clear in both configurations.
  #source-note("rtl/ip/multimedia/apu_reg.sv",title:"Actual configured capability and digest values")
  #source-note("scripts/apu_abi_digest.py",title:"Frozen ABI identity checks")

  #minor-title("Implemented LP-to-HP acceptance sequence")
  The dedicated APU release configuration adds an LP orchestration image and a freestanding
  HP payload. It is a reproducible acceptance path, not a Linux ASoC driver or a general audio
  application distribution. The ordinary PRODUCT profile continues to use its existing gate.
  + LP initializes memories and stages the APUMC image, APUM model and workload data.
  + LP quiesces the resource, configures permitted address ranges, then loads and locks the
    microcode and model through the loader interfaces. Existing model-load DMA may continue
    while resource quiesce blocks new jobs; quiesce must not deadlock the accepted load.
  + LP completes the required cache/fence and resource handoff before releasing HP work.
  + HP performs the acceptance WAV and memory-window KWS jobs using cache-maintained
    buffers, checks the restricted LP-only range behavior, and publishes its result to LP.
  + On timeout or fault, preserve ownership and buffers until the engine and accepted DMA
    obligations have drained; capture the terminal result before recovery or reuse.
  #source-note("app/apps/apu_release/main.c",title:"LP asset loading, ACL setup and HP orchestration")
  #source-note("app/ports/hp-apu/main.c",title:"Bare-metal HP cache, job and result sequence")
  #source-note("tests/rtl/apu_p8_quiesce_load_tb.sv",title:"Accepted loader progress under quiesce")

  #minor-title("Smoke, corpus and sustained-audio evidence")
  The accuracy runner selects 1000 locked PCM windows for its full gate, with at least 900
  correct classifications required. Its small smoke subset explicitly does not apply that gate.
  The concurrency runner's release matrix covers WAV and FLAC with continuous RX KWS for
  60 simulated seconds per configuration at the specified 48 MHz test clock; shorter defaults
  and smoke invocations are not that campaign. Model/input identities, layer comparisons,
  underruns, drops, ready-memory assumptions and every scenario result must accompany a claim.
  Missing tools or model data can prevent a test body from executing even when a wrapper
  test returns successfully. No full-corpus, sustained-rate or current physical pass is inferred
  here from a capability bit, runner source or aggregate Pytest count.
  #source-note("scripts/run_apu_p7_kws_rtl.py",title:"Full accuracy gate and subset distinction")
  #source-note("scripts/run_apu_p7_concurrent_rtl.py",title:"Complete sustained-audio matrix and defaults")
]
