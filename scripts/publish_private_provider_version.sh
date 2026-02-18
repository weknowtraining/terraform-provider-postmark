#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    local value=""
    read -r -p "Enter value for $name: " value
    if [[ -z "$value" ]]; then
      echo "Missing required value: $name" >&2
      exit 1
    fi
    export "$name=$value"
  fi
}

require_cmd curl
require_cmd jq
require_cmd awk

# Required inputs
require_env TFC_TOKEN
require_env TFC_ORG
require_env VERSION
require_env KEY_ID

# Optional inputs
PROVIDER_NAME="${PROVIDER_NAME:-postmark}"
TFC_HOST="${TFC_HOST:-https://app.terraform.io}"
TFC_NAMESPACE="${TFC_NAMESPACE:-$TFC_ORG}"
PROTOCOLS_JSON="${PROTOCOLS_JSON:-[\"5.0\"]}"
GITHUB_REPO="${GITHUB_REPO:-${TFC_ORG}/terraform-provider-${PROVIDER_NAME}}"

VERSION_NO_V="${VERSION#v}"
GITHUB_TAG="${GITHUB_TAG:-v$VERSION_NO_V}"
WORK_DIR="${WORK_DIR:-./.tmp/provider-upload-$VERSION_NO_V}"

mkdir -p "$WORK_DIR"

API_STATUS=""
API_BODY=""

api_json() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local body_file
  body_file="$(mktemp)"

  if [[ -n "$payload" ]]; then
    API_STATUS="$(curl -sS -o "$body_file" -w "%{http_code}" \
      --request "$method" \
      --header "Authorization: Bearer $TFC_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      --data "$payload" \
      "$TFC_HOST$path")"
  else
    API_STATUS="$(curl -sS -o "$body_file" -w "%{http_code}" \
      --request "$method" \
      --header "Authorization: Bearer $TFC_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "$TFC_HOST$path")"
  fi

  API_BODY="$(cat "$body_file")"
  rm -f "$body_file"
}

github_release_json() {
  local url="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$GITHUB_TAG"
  local body_file
  body_file="$(mktemp)"

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    API_STATUS="$(curl -sS -L -o "$body_file" -w "%{http_code}" \
      --header "Authorization: Bearer $GITHUB_TOKEN" \
      --header "Accept: application/vnd.github+json" \
      "$url")"
  else
    API_STATUS="$(curl -sS -L -o "$body_file" -w "%{http_code}" \
      --header "Accept: application/vnd.github+json" \
      "$url")"
  fi

  API_BODY="$(cat "$body_file")"
  rm -f "$body_file"
}

download_asset() {
  local release_json="$1"
  local asset_name="$2"
  local asset_url
  asset_url="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")"

  if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    echo "Release asset not found: $asset_name" >&2
    exit 1
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL \
      --header "Authorization: Bearer $GITHUB_TOKEN" \
      --output "$WORK_DIR/$asset_name" \
      "$asset_url"
  else
    curl -fsSL \
      --output "$WORK_DIR/$asset_name" \
      "$asset_url"
  fi
}

upload_file_if_link_present() {
  local upload_url="$1"
  local file_path="$2"
  local label="$3"

  if [[ -z "$upload_url" || "$upload_url" == "null" ]]; then
    echo "Skipping $label upload (no upload link returned; likely already uploaded)."
    return
  fi

  curl -fsSL -T "$file_path" "$upload_url" >/dev/null
  echo "Uploaded $label: $(basename "$file_path")"
}

create_or_get_platform() {
  local os="$1"
  local arch="$2"
  local filename="$3"
  local shasum="$4"

  local path="/api/v2/organizations/$TFC_ORG/registry-providers/private/$TFC_NAMESPACE/$PROVIDER_NAME/versions/$VERSION_NO_V/platforms"
  local payload
  payload="$(jq -nc \
    --arg os "$os" \
    --arg arch "$arch" \
    --arg shasum "$shasum" \
    --arg filename "$filename" \
    '{data:{type:"registry-provider-platforms",attributes:{os:$os,arch:$arch,shasum:$shasum,filename:$filename}}}')"

  api_json POST "$path" "$payload"

  if [[ "$API_STATUS" == "201" ]]; then
    :
  elif [[ "$API_STATUS" == "422" ]]; then
    # Platform may already exist; fetch it.
    api_json GET "/api/v2/organizations/$TFC_ORG/registry-providers/private/$TFC_NAMESPACE/$PROVIDER_NAME/versions/$VERSION_NO_V/platforms/$os/$arch"
    if [[ "$API_STATUS" != "200" ]]; then
      echo "Failed to create/get platform $os/$arch (status $API_STATUS):" >&2
      echo "$API_BODY" >&2
      exit 1
    fi
  else
    echo "Failed to create platform $os/$arch (status $API_STATUS):" >&2
    echo "$API_BODY" >&2
    exit 1
  fi

  local upload_url
  upload_url="$(jq -r '.data.links["provider-binary-upload"] // empty' <<<"$API_BODY")"
  upload_file_if_link_present "$upload_url" "$WORK_DIR/$filename" "$os/$arch binary"
}

echo "Fetching GitHub release metadata: $GITHUB_REPO@$GITHUB_TAG"
github_release_json
if [[ "$API_STATUS" != "200" ]]; then
  echo "Failed to fetch GitHub release (status $API_STATUS):" >&2
  echo "$API_BODY" >&2
  exit 1
fi
release_json="$API_BODY"

sha_name="$(jq -r '.assets[]?.name | select(test("SHA256SUMS$"))' <<<"$release_json" | head -n1)"
sig_name="$(jq -r '.assets[]?.name | select(test("SHA256SUMS(\\.[A-Za-z0-9]+)?\\.sig$"))' <<<"$release_json" | head -n1)"

if [[ -z "$sha_name" || -z "$sig_name" ]]; then
  echo "Could not locate SHA256SUMS or SHA256SUMS.sig assets in GitHub release." >&2
  exit 1
fi

download_asset "$release_json" "$sha_name"
download_asset "$release_json" "$sig_name"

sha_path="$WORK_DIR/$sha_name"
sig_path="$WORK_DIR/$sig_name"

linux_filename="$(awk '$2 ~ /linux_amd64\.zip$/ {print $2; exit}' "$sha_path")"
darwin_filename="$(awk '$2 ~ /darwin_arm64\.zip$/ {print $2; exit}' "$sha_path")"

if [[ -z "$linux_filename" || -z "$darwin_filename" ]]; then
  echo "SHA256SUMS file does not contain expected linux_amd64 and darwin_arm64 zip entries." >&2
  exit 1
fi

linux_shasum="$(awk -v f="$linux_filename" '$2 == f {print $1; exit}' "$sha_path")"
darwin_shasum="$(awk -v f="$darwin_filename" '$2 == f {print $1; exit}' "$sha_path")"

download_asset "$release_json" "$linux_filename"
download_asset "$release_json" "$darwin_filename"

echo "Creating or reusing provider version: $VERSION_NO_V"
version_payload="$(jq -nc \
  --arg version "$VERSION_NO_V" \
  --arg key_id "$KEY_ID" \
  --argjson protocols "$PROTOCOLS_JSON" \
  '{data:{type:"registry-provider-versions",attributes:{version:$version,"key-id":$key_id,protocols:$protocols}}}')"

api_json POST "/api/v2/organizations/$TFC_ORG/registry-providers/private/$TFC_NAMESPACE/$PROVIDER_NAME/versions" "$version_payload"

if [[ "$API_STATUS" == "201" ]]; then
  :
elif [[ "$API_STATUS" == "422" ]]; then
  # Version may already exist; fetch it.
  api_json GET "/api/v2/organizations/$TFC_ORG/registry-providers/private/$TFC_NAMESPACE/$PROVIDER_NAME/versions/$VERSION_NO_V"
  if [[ "$API_STATUS" != "200" ]]; then
    echo "Failed to create/get provider version (status $API_STATUS):" >&2
    echo "$API_BODY" >&2
    exit 1
  fi
else
  echo "Failed to create provider version (status $API_STATUS):" >&2
  echo "$API_BODY" >&2
  exit 1
fi

version_json="$API_BODY"
shasums_upload_url="$(jq -r '.data.links["shasums-upload"] // empty' <<<"$version_json")"
shasums_sig_upload_url="$(jq -r '.data.links["shasums-sig-upload"] // empty' <<<"$version_json")"

upload_file_if_link_present "$shasums_upload_url" "$sha_path" "SHA256SUMS"
upload_file_if_link_present "$shasums_sig_upload_url" "$sig_path" "SHA256SUMS.sig"

echo "Creating or reusing platforms and uploading binaries"
create_or_get_platform "linux" "amd64" "$linux_filename" "$linux_shasum"
create_or_get_platform "darwin" "arm64" "$darwin_filename" "$darwin_shasum"

echo "Done. Uploaded version $VERSION_NO_V for $TFC_NAMESPACE/$PROVIDER_NAME (linux/amd64 + darwin/arm64)."
