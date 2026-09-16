#!/usr/bin/env bash
# Build the pinned WKT source locally for publication as GitHub release assets.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST="${POSTMARK_RELEASE_DIR:-${ROOT}/../dist/wkt-2.0.1-441f6c349ab1}"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/wkt-postmark-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
COMMIT=441f6c349ab16a977c522994475053cc3e805abe
REPOSITORY=weknowtraining/terraform-provider-postmark
VERSION=2.0.1
GO=1.23.0
FINGERPRINT='cgo0-modvendor-trimpath-buildvcs0-ldflags-s-w-gotoolchain-local-goenv-off-goamd64-v1-goarm64-v8.0-zip-stored'

EXPECTED_ZH_darwin_arm64=ce00a7362a0ce38c3ca12109350db608e38a6ad2a18cc71c6429e76cc84364f3
EXPECTED_ZH_linux_amd64=4cf863dfbde3bb340d99e23f67cb14545dd738d94a40c2f4dbe7f47f1176262f

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
    python3 - "$tmp_zip" "$work" "$builddir/$bin" "$bin" <<'PY' || exit $?
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
PY
  )
  rm -rf "$builddir"
  chmod 0644 "$tmp_zip"
  echo "built ${zip_name} fingerprint=${FINGERPRINT}"
}

verify_zip() {
  local platform="$1" zip_path expected
  zip_path="${STAGE}/terraform-provider-postmark_${VERSION}_${platform}.zip"
  case "$platform" in
    darwin_arm64) expected=$EXPECTED_ZH_darwin_arm64 ;;
    linux_amd64) expected=$EXPECTED_ZH_linux_amd64 ;;
    *) echo "no expected zh for ${platform}" >&2; return 1 ;;
  esac
  python3 - "$zip_path" "$expected" <<'PY'
import hashlib, pathlib, sys
zip_path, expected = sys.argv[1:3]
zh = hashlib.sha256(pathlib.Path(zip_path).read_bytes()).hexdigest()
if zh != expected:
    raise SystemExit(f"zh mismatch for {pathlib.Path(zip_path).name}: got {zh} expected {expected}")
print(f"verify {pathlib.Path(zip_path).name} zh={zh}")
PY
}

for platform in "${platforms[@]}"; do
  case "$platform" in
    darwin_arm64|linux_amd64) ;;
    *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
  esac
done

for platform in "${platforms[@]}"; do
  build_zip "$platform"
  verify_zip "$platform"
done

for platform in "${platforms[@]}"; do
  zip_name="terraform-provider-postmark_${VERSION}_${platform}.zip"
  mv -f "${STAGE}/${zip_name}" "${DEST}/${zip_name}"
done

python3 - "$DEST" "$COMMIT" "$GO" "$FINGERPRINT" "${platforms[@]}" <<'PY'
import hashlib, json, pathlib, sys
dest = pathlib.Path(sys.argv[1])
assets = {}
for platform in sys.argv[5:]:
    name = f"terraform-provider-postmark_2.0.1_{platform}.zip"
    assets[name] = hashlib.sha256((dest / name).read_bytes()).hexdigest()
(dest / "terraform-provider-postmark_2.0.1_SHA256SUMS").write_text(
    "".join(f"{checksum}  {name}\n" for name, checksum in sorted(assets.items()))
)
(dest / "provenance.json").write_text(json.dumps({
    "repository": "weknowtraining/terraform-provider-postmark",
    "source_commit": sys.argv[2], "go_version": sys.argv[3],
    "build_fingerprint": sys.argv[4], "provider_version": "2.0.1",
    "release": "wkt-2.0.1-441f6c349ab1", "sha256": assets,
}, indent=2) + "\n")
PY
echo "Release assets written to ${DEST}"
