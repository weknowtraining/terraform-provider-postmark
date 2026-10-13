# WKT GitHub distribution

The WKT fork is distributed as GitHub release assets, not through the Terraform
Registry. Release `wkt-2.0.3-f3a24492bf05` builds exactly source commit
`f3a24492bf05b9588ca69f4e954cd4fb0acbd4ad` from branch `wkt`.
Earlier WKT tags (`wkt-2.0.1-441f6c349ab1`, `wkt-2.0.2-8be38f07fb3d`) and
upstream-style `v2.0.*` releases are different source revisions and must not be
replaced or used for this package.

## Prerequisites

- **Build:** Go **1.23.0** on PATH, `git`, and `python3`.
- **Install:** `curl`, `python3`, and a supported host (`linux_amd64` or `darwin_arm64`).

## Build locally

Put Go **1.23.0** on PATH and run `scripts/build-wkt-release.sh`. The script fetches
the exact source commit and uses its vendored dependencies. It builds Linux AMD64
and macOS ARM64 packages and verifies their audited SHA-256 checksums before
writing assets, SHA256SUMS, and `provenance.json` into
`dist/wkt-2.0.3-f3a24492bf05/`. Set `POSTMARK_RELEASE_DIR` to override that directory.
No provider behavior changes or infrastructure applies are part of this build.

Publish those assets under the unique WKT release tag pointing at the source
commit. Do not overwrite releases or existing assets. The tag deliberately does
not match `v*`, so it does not trigger the existing automated GoReleaser workflow.
These are locally built, checksum-verified assets; no signature is claimed.

## Install

From a checkout of this tooling at a reviewed commit, run
`scripts/install-wkt-release.sh /path/to/terraform/root`. The installer downloads
the fixed release and checks a pinned checksum before copying the ZIP into the
root's `terraform.d/plugins` implicit mirror at
`terraform.d/plugins/app.terraform.io/weknowtraining/postmark/terraform-provider-postmark_2.0.3_<platform>.zip`.
This packed ZIP layout is what Terraform uses for implicit filesystem mirrors and
matches the shared workflow installer; it is not the unpacked
`version/<platform>/` tree used by the Makefile's local dev install target.
It needs no GitHub or TFC token.

Consumers keep provider source `app.terraform.io/weknowtraining/postmark` and
version `2.0.3` for state compatibility, along with the audited lockfile hashes.
The pinned binary keeps the historical `hashicorp.com/mcarey1590/postmark` Serve
address; Terraform still discovers and runs it under the WKT source via this packed
mirror. Terraform finds the package in the mirror without contacting that registry.
Run normal `terraform init -lockfile=readonly` after installation. GitHub Actions
uses the shared workflow's package manifest to perform the same verified download
before validation, planning, and applying; infrastructure jobs do not build Go.

| Platform | SHA-256 |
| --- | --- |
| linux_amd64 | `a6b0698d92072a415660f1116428a830bee8f1a2f4d2e237e9678fd3d0af4eea` |
| darwin_arm64 | `e5391cc73db51876e23889fa13213a545781669e2058bd7a69ab7c973eaf96a2` |

## Credential safety

`2.0.3` removes the Configure-time account-token println present in `2.0.2` and
adds a fake-token subprocess regression covering OS-level stdout/stderr.
