#!/usr/bin/env bash
# Install the audited WKT package into the caller's Terraform filesystem mirror.
set -euo pipefail
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) platform=linux_amd64; checksum=4cf863dfbde3bb340d99e23f67cb14545dd738d94a40c2f4dbe7f47f1176262f ;;
  Darwin/arm64) platform=darwin_arm64; checksum=ce00a7362a0ce38c3ca12109350db608e38a6ad2a18cc71c6429e76cc84364f3 ;;
  *) echo 'Unsupported platform; supported: linux_amd64, darwin_arm64' >&2; exit 1 ;;
esac
asset="terraform-provider-postmark_2.0.1_${platform}.zip"
dest="${1:-.}/terraform.d/plugins/app.terraform.io/weknowtraining/postmark"
stage=$(mktemp -d "${TMPDIR:-/tmp}/wkt-postmark-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  "https://github.com/weknowtraining/terraform-provider-postmark/releases/download/wkt-2.0.1-441f6c349ab1/${asset}" \
  --output "$stage/$asset"
python3 - "$stage/$asset" "$checksum" <<'PY'
import hashlib, pathlib, sys
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit("Postmark package checksum mismatch")
PY
mkdir -p "$dest"
cp "$stage/$asset" "$dest/$asset"
echo "Installed verified Postmark 2.0.1 (${platform})"
