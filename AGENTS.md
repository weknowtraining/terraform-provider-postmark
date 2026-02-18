# AGENTS.md

## Purpose
Working agreement for automated agents and contributors in `terraform-provider-postmark`.

## Repository Map
- `main.go`: provider server entrypoint (`hashicorp.com/mcarey1590/postmark`).
- `internal/provider/`: hand-written provider, resources, data sources, and shared helpers.
- `internal/provider/*_gen.go` and subfolders like `resource_*`, `datasource_*`, `provider_postmark/`: generated schema/model code.
- `provider_code_spec.json`: source of truth for generated provider schemas/models.
- `docs/`: generated Terraform provider docs.
- `examples/`: example provider/resource/data-source configs.
- `scripts/gofmtcheck.sh`: formatting gate used by `make fmtcheck`.
- `tools/tools.go`: `go generate` hooks for docs generation.

## Tech Stack
- Go module: `terraform-provider-postmark`
- Go version: `1.23` (see `go.mod`)
- Terraform Plugin Framework: `github.com/hashicorp/terraform-plugin-framework`
- Postmark client: `github.com/mrz1836/postmark`
- Vendored dependencies are committed (`vendor/`); CI/lint run with vendor mode.

## Generated Code Rules
- Treat `internal/provider/**/*_gen.go` as generated artifacts.
- Do not hand-edit generated files unless explicitly requested.
- To update generated provider/resource/data-source schema/model code:
  1. Edit `provider_code_spec.json`.
  2. Run `make generate-schema`.
- If schema changes affect docs/examples, regenerate docs and reformat examples.

## Common Commands
- Install dev tools: `make tools`
- Format Go: `make fmt`
- Check formatting: `make fmtcheck`
- Lint: `make lint`
- Build: `make build`
- Unit-style test sweep: `make test`
- Acceptance tests: `make testacc` (requires Postmark credentials + environment)
- Generate schema code: `make generate-schema`
- Generate docs: `make generate-docs`

## Expected Validation Flow For Code Changes
1. `make fmtcheck`
2. `make lint`
3. `make test`
4. If provider behavior/schema changed: `make generate-docs` and ensure `docs/` and `examples/` are consistent.

## Terraform Provider Conventions (This Repo)
- Resources and data sources are paired by domain object (`server`, `domain`, `sender_signature`, `webhook`).
- `Configure` methods pass a shared `*postmark.Client` through provider data.
- IDs are stored as Terraform strings and often converted via helper functions in `internal/provider/util.go`.
- Import support is implemented via `resource.ImportStatePassthroughID` where applicable.

## Editing Guidance
- Prefer edits in hand-written files under `internal/provider/*.go` (non-`_gen.go`).
- Keep error handling consistent with existing `diag.NewErrorDiagnostic(...)` patterns.
- Preserve Terraform state mapping behavior when touching `Read/Create/Update/Delete` logic.
- Avoid touching `vendor/` unless dependency/vendor updates are explicitly requested.

## CI Notes
- CI workflow runs: `make tools`, `make lint`, `make build`, `make test`.
- Release workflow uses Goreleaser on tags `v*`.

## Credentials and Safety
- Never hardcode real Postmark tokens.
- Acceptance tests and local example runs require user-supplied secrets.
- Keep sensitive values in environment variables or `terraform.tfvars` that are not committed.

## Known Gaps to Keep in Mind
- Repository currently has little/no `_test.go` coverage; most safety comes from lint, build, and acceptance testing.
- There is a `TODO` in provider configuration about early connection validation; avoid introducing breaking behavior there without explicit request.
