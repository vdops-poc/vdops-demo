#!/usr/bin/env bash
set -euo pipefail

echo "Preparing sanitized payload for AI DevOps Agent (n8n)..."

# --------------------------------------------------------------------
# 1. Extract the last meaningful log lines from workflow
#    (adjust tail -n 300 depending on needs)
# --------------------------------------------------------------------
RAW_LOG=$(tail -n 300 "$GITHUB_STEP_SUMMARY" 2>/dev/null || echo "No logs captured.")

# --------------------------------------------------------------------
# 2. Remove ANSI color codes ([31m etc.)
# --------------------------------------------------------------------
STRIPPED_LOG=$(printf "%s" "$RAW_LOG" \
  | sed -r "s/\x1B\[[0-9;]*[JKmsu]//g")

# --------------------------------------------------------------------
# 3. JSON escape helper:
#    Converts: \ → \\ , " → \" , newlines → \n , tabs → \t
# --------------------------------------------------------------------
json_escape() {
  sed -e ':a' -e 'N' -e '$!ba' \
      -e 's/\\/\\\\/g' \
      -e 's/"/\\"/g' \
      -e 's/\t/\\t/g' \
      -e 's/\r/\\r/g' \
      -e 's/\n/\\n/g'
}

ESCAPED_LOG=$(printf "%s" "$STRIPPED_LOG" | json_escape)

# --------------------------------------------------------------------
# 4. Truncate extremely large logs (+ safety margin)
# --------------------------------------------------------------------
MAX=8000
if [ ${#ESCAPED_LOG} -gt $MAX ]; then
  ESCAPED_LOG="${ESCAPED_LOG:0:$MAX}...[TRUNCATED]"
fi

# --------------------------------------------------------------------
# 5. Build final safe JSON payload
# --------------------------------------------------------------------
cat <<EOF > payload.json
{
  "repository": "${GITHUB_REPOSITORY}",
  "branch": "${GITHUB_REF_NAME}",
  "commit": "${GITHUB_SHA}",
  "actor": "${GITHUB_ACTOR}",
  "workflow": "${GITHUB_WORKFLOW}",
  "run_id": "${GITHUB_RUN_ID}",
  "job": "${GITHUB_JOB}",
  "log_snippet": "$ESCAPED_LOG"
}
EOF

echo "Validating JSON before sending..."
if ! jq . payload.json >/dev/null 2>&1; then
  echo "❌ ERROR: Invalid JSON payload generated!"
  cat payload.json
  exit 1
fi
echo "✔ JSON valid"

# --------------------------------------------------------------------
# 6. Send to n8n webhook
# --------------------------------------------------------------------
echo "Sending payload to AI DevOps Agent @ n8n..."
HTTP_CODE=$(curl -s -o response.txt -w "%{http_code}" \
  -X POST "$N8N_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  --data-binary @payload.json)

echo "n8n responded with HTTP $HTTP_CODE"
echo "--- Response Body ---"
cat response.txt || true
echo "---------------------"

if [[ "$HTTP_CODE" -ge 400 ]]; then
  echo "❌ Error sending payload to n8n"
  exit 1
fi

echo "✔ Payload sent successfully to AI DevOps Agent (n8n)"
