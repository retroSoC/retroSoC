#import "../style.typ": *

#import "../ip-reference.typ": ip-reference
#import "../system-figures.typ": sequence-diagram

#pagebreak(weak:true)

=== Encryption and Data Integrity

#context metadata((kind:"ip-start",id:"crypto",page:here().page()))

==== Crypto Controller <crypto>

#ip("crypto")

#ip-reference("crypto","crypto",4,functional-note:[
  #minor-title("Private SRAM allocation")
  #ds-table("crypto-private-banks",[Six private 4 KiB SRAM banks; no CPU memory aperture],
    ([Bank],[Owner],[Stored state]),
    (([0],[AES constants],[Forward/inverse S-boxes and Rcon; remaining rows are required zero padding.]),
     ([1],[SHA constants],[Round constants and SHA-224/256 initial states; required zero padding.]),
     ([2],[AES mutable],[Staged/expanded key, IV, chaining state and current block.]),
     ([3],[SHA mutable],[Schedule, block/padding buffer, chaining/compression state and digest.]),
     ([4],[RSA retained],[Sixteen 64-word slots for operands, verified result, preparation and workspace.]),
     ([5],[RSA arithmetic],[Limb-based Montgomery arithmetic, carry, subtraction and preparation workspace.])),
    widths:(0.3fr,0.8fr,3fr))
  #source-note("rtl/ip/security/crypto_mem_pkg.sv",title:"Physical bank and row allocation")
  #minor-title("Initialization and operation admission")
  #figure(sequence-diagram((
    [*Reset scrub* \ Keep PCLK running \ Mutable state invalid],
    [*Load CRYC1* \ BEGIN; write 2048 words \ Reserved padding zero],
    [*Verify and lock* \ COMMIT; readback CRC \ Wait for READY],
    [*Configure and execute* \ Load key / operands \ Wait for terminal engine result],
    [*Clear and recover* \ Drain DMA before ZEROIZE \ Confirm scrub completion],
  )),caption:[Crypto V2 software ordering. Steps are not measured latency or a physical security qualification.])<crypto-init-flow>
  #ds-table("crypto-lifecycle-boundaries",[Crypto initialization, invalidation and completion boundaries],
    ([Operation],[Required observation],[Retained boundary]),
    (([Hard / PCLK reset],[Reset scrub completes; reload and verify constants before READY.],[No valid key/result survives. Stopped PCLK cannot complete scrub.]),
     ([Successful COMMIT],[READY, TABLE_VALID and TABLE_LOCKED with the expected TABLE_CRC.],[Constants remain locked until hard/PCLK reset; the MEMORY_READY test IRQ is not a substitute.]),
     ([Explicit ZEROIZE],[SCRUB_BUSY clears and a new ZEROIZED event is observed; key-valid is clear.],[Valid locked constants survive; mutable banks and FIFO state are cleared asynchronously.]),
     ([Timeout / failure],[Inspect MEM_STATUS/MEM_ERROR and all accepted DMA/engine traffic.],[No erasure or buffer-release guarantee follows from a timeout return.])),
    widths:(0.8fr,1.65fr,1.65fr))
  #source-note("rtl/ip/security/crypto_mem_ctrl.sv",title:"Implemented constant loading, verification and scrub state machine")
  #source-note("crt/src/hal/crypto_lifecycle.c",title:"Initialization, cancellation and zeroize completion checks")
],software-note:[
  #note[Lifecycle calls require *caller serialization* with engine setup and IRQ_TEST. The HAL
  does not implement an internal cross-hart mutex. Each timeout argument is a software work/poll
  budget; the example gives each call its own budget and is not a wall-clock deadline.]
],legacy:[
The engine provides PIO and central-DMA streaming for AES and SHA-2, plus raw RSA-2048 modular
exponentiation. Software must supply *protocol-level padding, key policy and validated operation
parameters*. This is *not a claim of secure key storage*, certified cryptography or side-channel
resistance. HP access is restricted by the management-only control contract.
])

#context metadata((kind:"ip-end",id:"crypto",page:here().page()))
