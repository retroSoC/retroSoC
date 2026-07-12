# Metrics Policy

The policy starts in `observe` mode. Exactly ten successful `main` run metric files are required to
create the median baseline. Promotion to `gate` is a reviewed commit containing both
`baseline.json` and the policy mode change. See `docs/engineering.md` for the command and thresholds.
