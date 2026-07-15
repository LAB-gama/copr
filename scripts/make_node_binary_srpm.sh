#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: make_node_binary_srpm.sh --spec <path> --outdir <path>
EOF
}

spec=""
outdir=""
node_dist_url="${NODE_DIST_URL:-https://nodejs.org/dist}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --spec)
      spec="$2"
      shift 2
      ;;
    --outdir)
      outdir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$spec" ] || [ -z "$outdir" ]; then
  usage >&2
  exit 1
fi

spec="$(realpath "$spec")"
mkdir -p "$outdir"
outdir="$(realpath "$outdir")"

version="$(awk '$1 == "Version:" { print $2; exit }' "$spec")"
if [ -z "$version" ]; then
  echo "Unable to determine version from $spec" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
sources_dir="${workdir}/sources"
mkdir -p "$sources_dir"

release_url="${node_dist_url}/v${version}"
shasums_name="SHASUMS256.txt"
x64_name="node-v${version}-linux-x64.tar.xz"
arm64_name="node-v${version}-linux-arm64.tar.xz"

curl -fsSL "${release_url}/${shasums_name}" -o "${sources_dir}/${shasums_name}"
curl -fsSL "${release_url}/${x64_name}" -o "${sources_dir}/${x64_name}"
curl -fsSL "${release_url}/${arm64_name}" -o "${sources_dir}/${arm64_name}"

(
  cd "$sources_dir"
  for source_name in "$x64_name" "$arm64_name"; do
    checksum_line="$(awk -v source="$source_name" '$2 == source { print; exit }' "$shasums_name")"
    if [ -z "$checksum_line" ]; then
      echo "No checksum found for ${source_name}" >&2
      exit 1
    fi
    printf '%s\n' "$checksum_line" | sha256sum -c -
  done
)

rpmbuild -bs "$spec" \
  --define "_sourcedir ${sources_dir}" \
  --define "_srcrpmdir ${outdir}"
