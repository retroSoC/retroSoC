#import "style.typ": *
#show: template
#include "sections/overview.typ"
#pagebreak()
#include "sections/product-use.typ"
#pagebreak()
#include "sections/reading.typ"
#pagebreak()
#change-start("contents", "Contents", category:"navigation")
#contents(depth:5)
#change-end("contents")
#pagebreak()
#change-start("table-directory", "List of tables", category:"navigation")
#figure-directory(tables:true)
#change-end("table-directory")
#pagebreak()
#change-start("figure-directory", "List of figures", category:"navigation")
#figure-directory()
#change-end("figure-directory")
#pagebreak()
#include "sections/architecture.typ"
#include "sections/peripherals.typ"
#include "sections/pins.typ"
#pagebreak()
#include "sections/software.typ"
#include "sections/appendices.typ"
