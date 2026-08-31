# GB-BASIC import provenance

GB-BASIC was incorporated into GEMBENCH for issue #49 so release builds no
longer depend on a sibling repository.

- Source repository: `salvogendut/GB-BASIC`
- Imported branch: `issue-4-bounded-basrun`
- Imported commit: `1e552ff193f472978407364a0c0f7b362bf78251`
- Import date: 2026-08-31

The source repository had one local, uncommitted change at import time:
`apps/basic/icon.asm`. GEMBENCH imported that current canonical icon source,
whose SHA-256 is
`252191064fafa77b6b9370672bfed57f38da27275ed20568c4433f09e9e09d51`.
At import time all other files matched the commit above. The integration then
adjusted only component-level build-path defaults and documentation for the
new nested location; application/runtime sources and examples remain the
imported versions.

The original README states that GB-BASIC follows GeoBench's BSD-3-Clause
license. GEMBENCH remains BSD-3-Clause and carries the applicable license in
this component as well as at the repository root.
