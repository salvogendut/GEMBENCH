# GEOBENCH Paint

This is GEOBENCH's in-tree MSX2 Paint source. It was imported from
`salvogendut/GB-PAINT` at commit
`61d02f0d246ac3a57f80b7741e7d8927a8b5fa82` as the baseline for Architecture
Milestone 2.

The copy is deliberate. GB-PAINT remains the separately maintained GEOBENCH
application for CPC, MSX2, and PCW, while this directory adopts the newer
MSX2 application/window ownership API without changing or conditionally
complicating the standalone application. GEOBENCH builds this in-tree copy and
has no dependency on the standalone repository.

Application-owned source lives here. Paint tool artwork lives in
`../../assets/paint/`, with the complete source sheet at
`../../assets/paint-tools.png`.

This imported copy is distributed under GEOBENCH's root BSD 3-Clause license.
