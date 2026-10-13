#!/usr/bin/env bash
# Install the audited WKT package into the caller's Terraform filesystem mirror.
set -euo pipefail
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) platform=linux_amd64; checksum=a6b0698d92072a415660f1116428a830bee8f1a2f4d2e237e9678fd3d0af4eea ;;
  Darwin/arm64) platform=darwin_arm64; checksum=e5391cc73db51876e23889fa13213a545781669e2058bd7a69ab7c973eaf96a2 ;;
  *) echo 'Unsupported platform; supported: linux_amd64, darwin_arm64' >&2; exit 1 ;;
esac
asset="terraform-provider-postmark_2.0.3_${platform}.zip"
dest="${1:-.}/terraform.d/plugins/app.terraform.io/weknowtraining/postmark"
stage=$(mktemp -d "${TMPDIR:-/tmp}/wkt-postmark-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  "https://github.com/weknowtraining/terraform-provider-postmark/releases/download/wkt-2.0.3-f3a24492bf05/${asset}" \
  --output "$stage/$asset"
python3 - "$stage/$asset" "$checksum" <<'PY'
import hashlib, pathlib, sys
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit("Postmark package checksum mismatch")
PY
mkdir -p "$dest"
cp "$stage/$asset" "$dest/$asset"
echo "Installed verified Postmark 2.0.3 (${platform})"
