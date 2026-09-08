#import "style.typ": *
#show: template
#include "sections/overview.typ"
#pagebreak()
#include "sections/reading.typ"
#pagebreak()
#contents(depth:5)
#pagebreak()
#figure-directory(tables:true)
#pagebreak()
#figure-directory()
#pagebreak()
#include "sections/architecture.typ"
#include "sections/peripherals.typ"
#include "sections/pins.typ"
#pagebreak()
#include "sections/software.typ"
#include "sections/appendices.typ"
