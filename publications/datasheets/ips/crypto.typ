#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

=== Encryption and Data Integrity

#context metadata((kind:"ip-start",id:"crypto",page:here().page()))

==== Crypto Controller <crypto>

#ip("crypto")

#ip-reference("crypto","crypto",4,legacy:[
The engine provides PIO and central-DMA streaming for AES and SHA-2, plus raw RSA-2048 modular
exponentiation. Software must supply protocol-level padding, key policy and validated operation
parameters. This is not a claim of secure key storage, certified cryptography or side-channel
resistance. HP access is restricted by the management-only control contract.
])

#context metadata((kind:"ip-end",id:"crypto",page:here().page()))
