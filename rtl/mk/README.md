# Shared RTL/SDK Build Rules

`software.mk` owns common compiler, linker and firmware artifact rules for Mini
and Tiny. Product configuration and application source selection remain explicit.
Both products include this canonical file directly. Changes require both
product configuration tests, affected firmware builds, and SDK gates.
