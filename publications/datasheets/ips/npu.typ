#import "../style.typ": *
#import "../ip-reference.typ": ip-reference
#import "../sections/npu-usage.typ": npu-functional, npu-protocol, npu-software

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"npu",page:here().page()))
==== Neural Processing Unit (NPU) <npu>
#change-start("v05-npu","Integrated NPU functional, programming and register reference",category:"added")
#ip("npu")
#ip-reference("npu","npu",4,functional-note:npu-functional(),protocol-note:npu-protocol(),software-note:npu-software())
#change-end("v05-npu")
#context metadata((kind:"ip-end",id:"npu",page:here().page()))
