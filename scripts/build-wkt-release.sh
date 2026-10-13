#!/usr/bin/env bash
# Build the pinned WKT source locally for publication as GitHub release assets.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST="${POSTMARK_RELEASE_DIR:-${ROOT}/../dist/wkt-2.0.3-f3a24492bf05}"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/wkt-postmark-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
COMMIT=f3a24492bf05b9588ca69f4e954cd4fb0acbd4ad
REPOSITORY=weknowtraining/terraform-provider-postmark
VERSION=2.0.3
GO=1.23.0
FINGERPRINT='cgo0-modvendor-trimpath-buildvcs0-ldflags-s-w-gotoolchain-local-goenv-off-goamd64-v1-goarm64-v8.0-zip-stored'

EXPECTED_ZH_darwin_arm64=e5391cc73db51876e23889fa13213a545781669e2058bd7a69ab7c973eaf96a2
EXPECTED_ZH_linux_amd64=a6b0698d92072a415660f1116428a830bee8f1a2f4d2e237e9678fd3d0af4eea

platforms=(darwin_arm64 linux_amd64)
if (($# > 0)); then
  platforms=("$@")
fi

go_bin=$(command -v go || true)
if [[ -z "$go_bin" ]]; then
  echo "go must be on PATH (exact go${GO}); no bootstrapping in this script" >&2
  exit 1
fi
go_version_out=$(GOTOOLCHAIN=local GOENV=off "$go_bin" version)
if [[ "$go_version_out" != *"go${GO} "* ]]; then
  echo "Go compiler version mismatch: expected go${GO}, got: ${go_version_out}" >&2
  exit 1
fi

work=$(mktemp -d "${STAGE}/source.XXXXXX")
git -C "$work" init -q
git -C "$work" remote add origin "https://github.com/${REPOSITORY}.git"
git -C "$work" fetch --depth 1 origin "$COMMIT"
git -C "$work" checkout --force FETCH_HEAD

mkdir -p "$STAGE" "$DEST"

build_zip() {
  local platform="$1" goos goarch zip_name bin builddir tmp_zip
  goos=${platform%_*}
  goarch=${platform#*_}
  zip_name="terraform-provider-postmark_${VERSION}_${platform}.zip"
  bin="terraform-provider-postmark_v${VERSION}"
  builddir=$(mktemp -d "${STAGE}/platform.XXXXXX")
  tmp_zip="${STAGE}/${zip_name}"

  (
    cd "$work" || exit 1
    unset GOROOT GOPATH GOCACHE || true
    export GOTOOLCHAIN=local
    export GOENV=off
    export GOWORK=off
    export GOFLAGS=
    export GOEXPERIMENT=
    export CGO_ENABLED=0
    export GOOS="$goos"
    export GOARCH="$goarch"
    case "$goarch" in
      amd64) export GOAMD64=v1 ;;
      arm64) export GOARM64=v8.0 ;;
    esac
    "$go_bin" build -mod=vendor -trimpath -buildvcs=false \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -o "$builddir/$bin" . || exit $?
    chmod 0755 "$builddir/$bin" || exit $?
    python3 - "$tmp_zip" "$work" "$builddir/$bin" "$bin" <<'PYZ' || exit $?
import pathlib, sys, zipfile

out_zip, src_root, binary_path, arcname = sys.argv[1:5]
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
src = pathlib.Path(src_root)
members = [(arcname, pathlib.Path(binary_path), 0o755)]
for name, mode in (("LICENSE", 0o644), ("README.md", 0o644)):
    path = src / name
    if path.is_file():
        members.append((name, path, mode))
with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_STORED) as zf:
    for name, path, mode in sorted(members, key=lambda item: item[0]):
        data = path.read_bytes()
        info = zipfile.ZipInfo(filename=name, date_time=ZIP_EPOCH)
        info.compress_type = zipfile.ZIP_STORED
        info.create_system = 3
        info.external_attr = (mode & 0xFFFF) << 16
        zf.writestr(info, data)
PYZ
  )
  rm -rf "$builddir"
  chmod 0644 "$tmp_zip"
  echo "built ${zip_name} fingerprint=${FINGERPRINT}"
}

verify_zip() {
  local platform="$1" zip_path expected actual
  zip_path="${STAGE}/terraform-provider-postmark_${VERSION}_${platform}.zip"
  case "$platform" in
    darwin_arm64) expected=$EXPECTED_ZH_darwin_arm64 ;;
    linux_amd64) expected=$EXPECTED_ZH_linux_amd64 ;;
    *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
  esac
  actual=$(python3 - "$zip_path" <<'PYV'
import hashlib, pathlib, sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PYV
)
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for ${platform}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
  echo "verified ${platform} sha256=${actual}"
}

for platform in "${platforms[@]}"; do
  case "$platform" in
    darwin_arm64|linux_amd64) ;;
    *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
  esac
done

for platform in "${platforms[@]}"; do
  build_zip "$platform"
done

for platform in "${platforms[@]}"; do
  verify_zip "$platform"
done

for platform in "${platforms[@]}"; do
  zip_name="terraform-provider-postmark_${VERSION}_${platform}.zip"
  mv -f "${STAGE}/${zip_name}" "${DEST}/${zip_name}"
done

python3 - "$DEST" "$COMMIT" "$GO" "$FINGERPRINT" "${platforms[@]}" <<'PYP'
import hashlib, json, pathlib, sys
dest = pathlib.Path(sys.argv[1])
version = "2.0.3"
release = "wkt-2.0.3-f3a24492bf05"
assets = {}
for platform in sys.argv[5:]:
    name = f"terraform-provider-postmark_{version}_{platform}.zip"
    assets[name] = hashlib.sha256((dest / name).read_bytes()).hexdigest()
(dest / f"terraform-provider-postmark_{version}_SHA256SUMS").write_text(
    "".join(f"{checksum}  {name}\n" for name, checksum in sorted(assets.items()))
)
(dest / "provenance.json").write_text(json.dumps({
    "repository": "weknowtraining/terraform-provider-postmark",
    "source_commit": sys.argv[2], "go_version": sys.argv[3],
    "build_fingerprint": sys.argv[4], "provider_version": version,
    "release": release, "sha256": assets,
}, indent=2) + "\n")
PYP
echo "Release assets written to ${DEST}"
