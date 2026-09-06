#import "style.typ": *
#show: template
#include "sections/overview.typ"
#pagebreak()
#{
  set text(size: 9.5pt)
  set par(leading: 0.4em, spacing: 0.4em)
  outline(title: [Contents], depth: 5)
}
#pagebreak()
#include "sections/architecture.typ"
#include "sections/peripherals.typ"
#include "sections/pins.typ"
#pagebreak()
#include "sections/software.typ"
#include "sections/appendices.typ"
