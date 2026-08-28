# GeoBench upstream baseline

GEMBENCH preserves GeoBench's complete Git history and uses it as the native
runtime foundation.

## Remote

```text
Name: upstream
URL:  git@github.com:salvogendut/geobench.git
```

Configure a fresh checkout with:

```sh
git remote add upstream git@github.com:salvogendut/geobench.git
git fetch upstream
```

## Bootstrap base

```text
Commit:  6309ff3dc1414449b0234bcf7dc8a532975ade5c
Date:    2026-08-26
Subject: Merge pull request #486 from salvogendut/qa-directory-reorganization
```

The bootstrap merge preserves both unrelated parent histories. The root README,
Makefile, ignore rules, and licence were reconciled for GEMBENCH; GeoBench's
kernel, libraries, applications, assets, QA media, and platform documentation
were imported without feature changes.

## Reproduction

From a GEMBENCH branch based on the pre-bootstrap history:

```sh
git fetch upstream main
git merge upstream/main --allow-unrelated-histories --no-commit
```

Resolve the four expected add/add conflicts at `.gitignore`, `LICENSE`,
`Makefile`, and `README.md`, then run:

```sh
make check
make gembench-msx
```

The staged MSX configuration must continue to contain `MSXMODE=7`. Any future
upstream merge should identify its old and new upstream commits in the merge
commit or accompanying documentation.
