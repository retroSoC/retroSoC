#import "../style.typ": *

#import "../ip-reference.typ": ip-reference
#import "../diagram-packages.typ": apu-instruction-diagram, apu-family-figures
#import "../sections/apu-release.typ": apu-release-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"apu",page:here().page()))

==== Audio Processing Unit (APU, partial) <apu>

#change-start("v05-refresh-apu-chapter","Current codec availability and ordered APU acceptance")
#ip("apu")

#ip-reference("apu","apu",4,functional-note:[
  #let implementation=data.system_reference.apu_implementation
  #minor-title("Checked-in codec image and compatibility")
  #ds-table("apu-image-capacity",[Current checked-in P5 codec image: static assembly result],
    ([Item],[Value],[Interpretation]),
    (([Control-store instructions],[#implementation.instruction_words / #implementation.maximum_instruction_words words],[#implementation.free_instruction_words words remain in the implemented V2 store.]),
     ([Serialized image],[#implementation.bundle_bytes bytes],[Includes the header, entries, instructions and coefficient tables.]),
     ([Coefficient/table payload],[#implementation.table_bytes bytes],[Separate from instruction-word capacity.]),
     ([Entry roles],[WAV; reserved MP3 trap; FLAC],[*MP3 is not a decoder implementation*.]),
     ([Qualification],[*Static assembly only*],[A valid image and capability bits do not establish corpus accuracy, sustained playback or physical signoff.])),
    widths:(1.1fr,0.85fr,2.05fr))
  APUMC V1 retains 2048-word limits and 11-bit control-flow PCs; V2 uses 4096-word limits and
  12-bit PCs. Both retain the common 64-bit instruction fields, seven classes and 62 defined
  opcodes. The 64-byte header, 32-byte entry records and 128-byte job descriptor remain distinct
  formats. New P5 images use V2; an unchanged legacy alias is not the current store capacity.
  #source-note("scripts/build_apu_p5_bundle.py",title:"Deterministic image assembly and high-water report")
  #source-note("rtl/ip/multimedia/apu_p5_codecs.apus",title:"Checked-in WAV/FLAC parser code and reserved MP3 trap")

  #minor-title("KWS implementation and default gate")
  The P7 model loader, MFCC/DS-CNN engine, SRAM client and lifecycle APIs are implemented.
  Default PRODUCT uses #code("EnableP7=0") and does not advertise capability bit 6. KWS discovery
  therefore returns #code("RS_ENOTSUP"); MODEL_LOAD, KWS_ENABLE, RX route 1 and
  #code("KWS_INPUT_CONFIG") at #code("0x23C") are subject to the same implementation gate.
  These registers are not an instruction to enable KWS in an ordinary product build.
  The fixed APUM model container is #implementation.kws_model_bytes bytes with a
  #(implementation.kws_header_bytes)-byte header, #implementation.kws_operators operator records,
  #implementation.kws_tensors tensor records and #implementation.kws_parameter_bytes parameter bytes.
  It is not a general TFLite interpreter or a qualified MLPerf result.
  The 112 KiB logical data map includes a 64 KiB KWS region; the codec/internal macro branch
  uses 12 four-KiB banks. The P9 KWS implementation adds 15 coefficient and 17 proof-memo
  macro wrappers; physical replacement remains subject to the exact synthesis evidence gate.
  #source-note("rtl/ip/multimedia/apb4_apu.sv",title:"Default P7 gate and implemented internal connections")
  #source-note("rtl/ip/multimedia/apu_kws_sram_client.sv",title:"Current KWS storage implementation")
  #source-note("scripts/apu_kws.py",title:"Fixed APUM model-container definitions")
  Full KWS qualification still requires the specified end-to-end PCM corpus, per-layer
  comparisons, sustained WAV/FLAC concurrency and lifecycle evidence. Conditional tests that
  do not execute without tools or local model data are not substitute pass reports.
  #apu-release-reference()
  #block(breakable:false)[
    #figure(apu-instruction-diagram(),kind:image,supplement:[Figure],caption:[APU 64-bit internal microcode fields and source-encoded examples.])<apu-instruction-layout>
    #source-note("scripts/apu_isa.py",title:"Instruction fields and encode/decode definitions")
    #source-note("rtl/ip/multimedia/apu_microcode_pkg.sv",title:"RTL instruction slices and legal-encoding checks")
  ]
  #apu-family-figures()
],legacy:[
Default PRODUCT advertises capability word `0x000001BD`, while the P9 acceptance configuration advertises APB version `0x00010002`, capability `0x000003FD` and ABI digest `0x63E96066`. WAV/FLAC transport, job submission and stream paths are integrated; APUMC V1 images remain loadable, while new P5 release images use APUMC V2. MP3 remains unsupported; KWS and APUC loading are configuration-dependent. The checked-in P5 image can be assembled and fits the current control store. Complete corpus,
sustained real-time and physical qualification require their own reports; they are not inferred from
image availability. KWS implementation exists but EnableP7 defaults to false in PRODUCT.

])

#change-end("v05-refresh-apu-chapter")
#context metadata((kind:"ip-end",id:"apu",page:here().page()))
