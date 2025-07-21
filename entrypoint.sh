#!/bin/bash
set -e

WORKING_DIR=$1
OUTPUT_FILE=$2

echo "Sending analysis request..."
RESPONSE=$(curl -s -X POST https://your.api/analyze \
  -H "Content-Type: application/json" \
  -d "{\"target\": \"$WORKING_DIR/\"}")

echo "Response: $RESPONSE"
JOB_ID=$(echo "$RESPONSE" | jq -r '.jobId')

echo "Polling analysis status..."
for i in {1..30}; do
  STATUS=$(curl -s https://your.api/status/$JOB_ID | jq -r '.status')
  echo "Status: $STATUS"
  if [ "$STATUS" = "DONE" ]; then break; fi
  sleep 10
done

if [ "$STATUS" != "DONE" ]; then
  echo "Analysis timed out or failed"
  exit 1
fi

echo "Downloading result..."
RESULT=$(curl -s https://your.api/result/$JOB_ID)
echo "$RESULT" > analysis-result.json

echo "Writing output to GitHub Actions..."
echo "result_json=$RESULT" >> "$GITHUB_OUTPUT"

echo "Updating README.md..."
TARGET=$(echo "$RESULT" | jq -r '.target')
ROWS=$(echo "$RESULT" | jq -r '.rowCount')
ANOMALY=$(echo "$RESULT" | jq -r '.anomalyCount')
STATUS=$(echo "$RESULT" | jq -r '.status')

TABLE_ROW="| $TARGET | $ROWS | $ANOMALY | ✅ $STATUS |"

awk '/<!-- ANALYSIS-RESULTS:START -->/{print;print "\n| 대상 파일 | 총 행 수 | 이상 탐지 수 | 상태 |";print "|-------------|----------|------------------|--------|";next}
     /<!-- ANALYSIS-RESULTS:END -->/ && !p {print ENVIRON["TABLE_ROW"]; p=1} 1' README.md > README.tmp

mv README.tmp README.md