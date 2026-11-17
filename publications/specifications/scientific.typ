// Inert display tokens; no Typst eval or numerical-source rewriting.
#let attached(body, role, id)=context {
  let parent=text.size
  let small=calc.max(6.3pt,parent*0.7)
  let inner=context {
    let extent=measure(body)
    [#box(width:extent.width,height:extent.height)[
      #metadata((kind:"scientific-script-info",id:id,text:body,role:role,
        font_size:small.pt(),base_size:parent.pt()))
      #body
    ]<scientific-script-region>]
  }
  if role=="sub" {sub(typographic:false,size:small,baseline:0.2em,inner)}
  else {super(typographic:false,size:small,baseline:-0.5em,inner)}
}
#let render(value, notation, unit:false, mechanical:false)={
  if type(value)==content {return value}
  let raw=str(value)
  let entry=notation.entries.at(if unit {"unit:"+raw} else if mechanical {"mechanical:"+raw} else {raw},default:none)
  if entry==none {raw} else {
    context {metadata((kind:"scientific-use",id:entry.id,page:here().page()))}
    for (index,token) in entry.tokens.enumerate() {
      if token.kind=="text" {token.value} else {
        token.base
        attached(token.value,if token.kind=="symbol" {"sub"} else {"super"},entry.id+":"+str(index))
      }
    }
  }
}
#let plot-image(dataset)=[
  #block(width:172mm,height:104mm,above:0pt,below:0pt)[
    #context {
      for id in dataset.at("scientific_uses",default:()) {
        metadata((kind:"scientific-use",id:id,page:here().page()))
      }
    }
    #image(dataset.paths.svg,width:172mm,height:104mm)
  ]#label("scientific-plot-"+dataset.id)
]
