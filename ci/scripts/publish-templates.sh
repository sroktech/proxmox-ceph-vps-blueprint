#!/usr/bin/env bash
# Record what was built into a committed manifest. Promotion to customer-facing
# is a SEPARATE, human step: flip the panel's template pointer.
set -euo pipefail
OUT=template-manifest.json
echo '{"published":"'"$(date -u +%FT%TZ)"'","commit":"'"${CI_COMMIT_SHORT_SHA:-local}"'","templates":[' > "$OUT"
first=1
for m in packer/manifest-*.json; do
  [ -f "$m" ] || continue
  [ $first -eq 0 ] && echo ',' >> "$OUT"
  jq -c '.builds[-1] | {name: .name, artifact: .artifact_id, time: .build_time}' "$m" >> "$OUT"
  first=0
done
echo ']}' >> "$OUT"
jq . "$OUT"
echo "==> Manifest written. Promote by updating the panel template pointer."
