#import "../style.typ": *

#let npu-functional() = [
  #let n=data.system_reference.npu_implementation
  #minor-title("Deployed configuration and arithmetic")
  The default PRODUCT integration contains an *executable NPU*. The control registers use PCLK;
  computation, private SRAM and payload DMA use HP. Launch, completion, snapshot and lifecycle
  state cross through explicit control mailboxes. There is no payload CDC or AXI width converter
  on the NPU master. The NPU is independent of the APU's fixed KWS engine.
  #ds-table("npu-configuration",[Source-derived NPU configuration],([Item],[Implemented value],[Boundary]),
    (([Identity],[#code("0x"+upper(str(n.ip_id,base:16))) / ABI 1.0],[Check identity, numeric profile and capabilities before use.]),
     ([Capabilities],[#code("0x0000007F") / operators #code("0x000001FE")],[Execution, private DMA, IRQs, double rounding, HP clock and abort.]),
     ([Dense / depthwise],[#n.dense_macs / #n.depthwise_macs MAC lanes],[Dense parallelism is not end-to-end model throughput.]),
     ([Local storage],[#(n.local_bytes/1024) KiB; #n.bank_count banks],[Private scratch only; no new CPU-addressable SRAM aperture.]),
     ([Accumulators],[#n.accumulator_contexts contexts × #n.accumulator_bytes bytes],[Separate checked INT32 sums, not part of the 64 KiB SRAM.]),
     ([Transport],[AXI64; up to #n.max_burst_beats beats],[One read and one write may overlap; source ID zero.]),
     ([Job records],[#n.descriptor_bytes bytes],[Linear descriptor list; one active job token.])),widths:(0.9fr,1.1fr,2fr))

  Tensor elements are *signed INT8*. Subtracting the input zero point produces signed nine-bit
  activations; multiplication uses signed 9-by-8 operands. Accumulation uses *checked INT32
  arithmetic*. Bias is applied once per output, while K slices preserve the partial sum. Overflow
  is a reported arithmetic fault, not silent wraparound. Numeric profile 1 uses the implemented
  double-rounding multiplier/shift rules, then output zero point and activation clamp.
  Preserve tie handling and negative values; a host floating-point rescale is not bit equivalent.
  #source-note("rtl/ip/multimedia/npu_pkg.sv",title:"Compute widths, lane counts and memory geometry")
  #source-note("rtl/ip/multimedia/npu_requantizer.sv",title:"Implemented integer requantization")

  #minor-title("Supported operator subset")
  The compiler uses *static batch-one NHWC tensors*. Each dimension is within 1…#n.max_dimension;
  a spatial tile contains at most eight output positions and each K slice is at most #n.max_k_slice.
  These individual maxima do not imply that every combination fits local storage or a valid job.
  Padding, allocation spans, packing, alignment and overlap are checked before execution.
  #ds-table("npu-operators",[NPU operator admission and integration limits],([Opcode],[Operation],[Implemented restrictions]),
    (([1],[Conv2D],[Kernel 1…16, stride 1 or 2, dilation 1; packed weights and per-output-channel parameters.]),
     ([2],[Depthwise],[3×3, stride 1 or 2, channel multiplier 1; eight physical lanes.]),
     ([3],[Fully connected],[1×1 spatial input/output; dense reduction over input channels.]),
     ([4],[Add],[Equal shapes/channels; no broadcasting; separate two-input requantization parameters.]),
     ([5],[Max pool],[Kernel 1…16, stride 1 or 2; channel count and input/output zero point preserved.]),
     ([6],[Average pool],[Same geometry restrictions as max pool; integer rounding follows profile 1.]),
     ([7],[Global average pool],[One output position per channel; input/output zero point preserved.]),
     ([8],[Clamp],[Shape, channels and zero point preserved; no weights or parameter payload.])),widths:(0.4fr,0.95fr,2.65fr))
  Unused descriptor fields and *reserved words must be zero*. Conv/pool output geometry must
  match kernel, stride and padding; Add/Clamp are not implicit reshape operations. The compiler
  can remove storage-preserving reshapes, but *unknown operators fail compilation*. Only the
  explicitly supported terminal Softmax becomes a CPU finalizer; this is not arbitrary CPU fallback.
  #source-note("rtl/ip/multimedia/npu_job_decoder.sv",title:"Descriptor and operator admission checks")
  #source-note("scripts/npu_compiler_p0.py",title:"Static lowering and explicit CPU boundary")

  #minor-title("Local memory and parameter ownership")
  The sixteen 4 KiB banks are partitioned into raw gather, packed activation, packed weights,
  output staging and descriptor/parameter regions. The bank-backed implementation has synchronous
  reads and byte write strobes. Reset invalidates ownership and control metadata; it *does not
  erase SRAM contents*. Software cannot treat that reset as sanitization. Input packing, local-bank
  conflicts and scalar requantization can limit useful throughput below the dense-MAC ceiling.
  Descriptor, weight and parameter bases are 64-byte aligned. Tensor payload edges may use
  narrower reads or write strobes, but the declared allocation and stride bounds still apply.
  Weighted operators use a 16-byte parameter record per output channel; Add uses one 32-byte
  parameter block. These payloads are not the 16-byte C #code("rs_npu_job_t") launch structure.
  #source-note("rtl/ip/multimedia/npu_local_sram.sv",title:"Bank implementation, synchronous access and reset semantics")
  #source-note("scripts/npu_descriptors.py",title:"Descriptor and parameter serialization/admission")
]

#let npu-protocol() = [
  #minor-title("Launch, completion and ordered recovery")
  START requires a ready link, resource permission, idle execution, no pending terminal IRQ
  and no active snapshot. Configuration is latched with JOB_ID; BUSY is not queue capacity.
  The core fetches and validates each descriptor, performs packing/compute, and retires output
  writes before publishing the terminal result. A previous DONE cannot satisfy a different token.
  #ds-table("npu-lifecycle",[NPU observations and safe software responses],([Observation],[Meaning and required action]),
    (([DONE],[All descriptors retired and accepted writes completed. Snapshot counters, acknowledge IRQ and perform output cache handoff.]),
     ([ERROR],[Read the first fault code/address/descriptor/info and recovery generation. A terminal error does not authorize a blind retry.]),
     ([Polling timeout],[The engine may still be active. Keep buffers and request abort; do not infer DMA stop from a software timeout.]),
     ([ABORTED],[Cancellation has completed its drain. The wait HAL maps this terminal result to RS_EIO; inspect the result code.]),
     ([Clock pause],[Coordinated pause preserves the job and presented AXI addresses; resume continues it. It is not an abort.]),
     ([Quiesce / epoch reset],[Block new work and reconcile the control domain with HP. Drain accepted transactions; reset cancellation does not report DONE.])),widths:(1fr,3fr))
  The integrated DMA issues INCR bursts of at most eight 64-bit beats, splits at 4 KiB
  boundaries, avoids read overfetch at payload edges and preserves partial writes with WSTRB.
  An error drains accepted obligations; presented VALID and its address remain stable under
  backpressure. The fabric admits noncacheable data requests to the allowed memory targets,
  with XPI read-only. NPU priority is fixed by the fabric policy, not raised by request QoS.
  #source-note("rtl/ip/multimedia/apb4_npu.sv",title:"Deployed core/DMA parameters and domain integration")
  #source-note("rtl/ip/multimedia/npu_core.sv",title:"Job retirement, first fault and lifecycle recovery")
  #source-note("rtl/ip/multimedia/npu_dma.sv",title:"AXI obligations, byte edges and drain")
]

#let npu-software() = [
  #minor-title("Model deployment and software boundary")
  The supplied deployment path targets the locked KWS and VWW integer graphs. The compiler
  emits aligned static C workspace, relocations, packed weights/parameters, capability checks,
  cache handoff and submit/wait calls. Audio/image preprocessing and terminal Softmax run on
  the CPU. No general TFLite runtime, dynamic shapes, APUM binary compatibility or native
  Linux NPU driver ABI is supplied. The HP smoke payload is freestanding acceptance software.
  #source-note("scripts/npu_compiler.py",title:"Static C exporter and cache/launch/finalizer sequence")
  #source-note("app/ports/linux/smoke/npu_acceptance.c",title:"Freestanding HP acceptance payload")

  #minor-title("Counter interpretation and qualification")
  Snapshot returns a bank tied to JOB_ID and RECOVERY_GENERATION. Separate HP active cycles,
  coordinated clock-pause cycles, useful MACs, packing/local-bank/DMA/requantization stalls,
  bytes and retired descriptors. Some intervals overlap; summing them does not reconstruct
  elapsed time. Full model latency also includes preprocessing, cache maintenance and CPU work.
  The verification contract records earlier host and bounded dual-simulator results. Matching
  raw artifacts for this source revision are not supplied with this publication. Test sources,
  capability bits and the P6 runners do not establish full-corpus accuracy, model speedup,
  72 MHz timing closure or silicon qualification. See @release-verification for evidence scope.
  #source-note("crt/src/hal/npu.c",title:"Actual HAL return, timeout and counter snapshot semantics")
  #source-note("docs/ip/npu-verification.md",title:"Workload and historical evidence boundaries")
]
