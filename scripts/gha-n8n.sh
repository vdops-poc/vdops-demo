#!/usr/bin/env bash
set -x
set -euo pipefail

echo "Preparing sanitized payload for AI DevOps Agent (n8n)..."

# --------------------------------------------------------------------
# 1. Collect logs from the actual log files created during the build
# --------------------------------------------------------------------
RAW_LOG=""

# Collect install logs if they exist
if [ -f "install.log" ]; then
  echo "=== INSTALL LOGS ===" >> combined.log
  tail -n 100 install.log >> combined.log
fi

# Collect test logs if they exist (most important for failures)
if [ -f "test.log" ]; then
  echo "=== TEST LOGS ===" >> combined.log
  tail -n 200 test.log >> combined.log
fi

# Collect docker logs if they exist
if [ -f "docker.log" ]; then
  echo "=== DOCKER BUILD LOGS ===" >> combined.log
  tail -n 100 docker.log >> combined.log
fi

# Read the combined log
if [ -f "combined.log" ]; then
  RAW_LOG=$(cat combined.log)
else
  RAW_LOG="No logs captured - log files not found."
fi

# --------------------------------------------------------------------
# 2. Remove ANSI color codes
# --------------------------------------------------------------------
STRIPPED_LOG=$(printf "%s" "$RAW_LOG" \
  | sed -r "s/\x1B\[[0-9;]*[JKmsu]//g")

# --------------------------------------------------------------------
# 3. JSON escape helper
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
# 4. Truncate extremely large logs
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

echo "..... repository is ${GITHUB_REPOSITORY}......."
echo "......branch is ${GITHUB_REF_NAME}........"
echo "......commit is ${GITHUB_SHA}........"
echo "......actor is ${GITHUB_ACTOR}......"
echo "......workflow is ${GITHUB_WORKFLOW}........"
echo ".... run_id is ${GITHUB_RUN_ID}............."
echo "........job is ${GITHUB_JOB}.........."

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
