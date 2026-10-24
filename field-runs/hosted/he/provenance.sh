#!/usr/bin/env bash
# provenance.sh api <run_id> <artifact_name> | content <dir> <mode> <era_or_dash>
# A caller-chosen run id is not trusted provenance by itself. The API check binds it to THIS repository, THIS workflow file and
# THIS workflow commit (same frozen recipe constants), a workflow_dispatch event, a successful conclusion and the expected artifact.
set -euo pipefail
cmd=${1:?}
case "$cmd" in
  api)
    id=${2:?}; name=${3:?}
    [[ "$id" =~ ^[0-9]+$ ]] || { echo "bad run id"; exit 1; }
    : "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}"
    api() { curl -fsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$GITHUB_REPOSITORY/$1"; }
    run=$(api "actions/runs/$id")
    echo "$run" | jq -e --arg sha "$GITHUB_SHA" --arg repo "$GITHUB_REPOSITORY" '
      .status == "completed" and .conclusion == "success" and .event == "workflow_dispatch"
      and .head_sha == $sha and .repository.full_name == $repo and .path == ".github/workflows/field-run-he.yml" and .run_attempt == 1' >/dev/null \
      || { echo "PROVENANCE_BLOCK: run $id is not a successful workflow_dispatch of field-run-he.yml at this commit"; exit 1; }
    arts=$(api "actions/runs/$id/artifacts?per_page=100")
    echo "$arts" | jq -e --arg n "$name" '[.artifacts[] | select(.name == $n and .expired == false)] | length == 1' >/dev/null \
      || { echo "PROVENANCE_BLOCK: run $id has no single unexpired artifact $name"; exit 1; }
    mkdir -p "${PROV_OUT:-.}"
    { echo "$run" | jq '{id, run_attempt, path, head_sha, event, conclusion, created_at, updated_at, repository: .repository.full_name}'
      echo "$arts" | jq --arg n "$name" '.artifacts[] | select(.name == $n) | {id, name, digest, size_in_bytes, created_at}'; } > "${PROV_OUT:-.}/provenance-$id.json"
    echo "PROVENANCE_API_OK run=$id artifact=$name head_sha=$GITHUB_SHA"
    ;;
  fetch)
    # fetch <run_id> <artifact_name> <dest>: authenticated download, zip digest compared with the API digest BEFORE extraction
    id=${2:?}; name=${3:?}; dest=${4:?}
    [[ "$id" =~ ^[0-9]+$ ]] || { echo "bad run id"; exit 1; }
    : "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}"
    arts=$(curl -fsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$id/artifacts?per_page=100")
    aid=$(echo "$arts" | jq -r --arg n "$name" '[.artifacts[] | select(.name == $n and .expired == false)] | if length == 1 then .[0].id else empty end')
    dig=$(echo "$arts" | jq -r --arg n "$name" '[.artifacts[] | select(.name == $n and .expired == false)] | .[0].digest // empty')
    [[ "$aid" =~ ^[0-9]+$ ]] && [[ "$dig" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "PROVENANCE_BLOCK: no single artifact id with a sha256 digest for $name"; exit 1; }
    zip="$(mktemp -d)/artifact.zip"
    curl -fsSL --max-filesize 2147483648 -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -o "$zip" "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/artifacts/$aid/zip"
    got="sha256:$(sha256sum "$zip" | cut -d' ' -f1)"
    [ "$got" = "$dig" ] || { echo "PROVENANCE_BLOCK: downloaded zip $got differs from the API digest $dig"; exit 1; }
    python3 "$(dirname "$0")/safe_unzip.py" "$zip" "$dest" || exit 1
    echo "ARTIFACT_BYTES_VERIFIED name=$name artifact_id=$aid zip_sha256=$got bytes=$(wc -c < "$zip")" | tee -a "${PROV_OUT:-.}/artifact-receipts.txt"
    ;;
  content)
    # content <dir> <mode> <era_or_dash> <run_id> <wf_sha> <recipe_pin_file> <doctor_head> <map_head_or_dash>
    [ "$#" -ge 9 ] && [ "$#" -le 10 ] || { echo "PROVENANCE_BLOCK: usage"; exit 1; }
    python3 "$(dirname "$0")/admit.py" structure "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10:--}"
    ;;
  *) echo "usage"; exit 1 ;;
esac
