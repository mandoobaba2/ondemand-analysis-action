#!/bin/bash
set -e

# jq 존재 여부 확인
if ! command -v jq &> /dev/null; then
  echo "[INFO] jq not found. Installing jq..."
  if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu 계열
    sudo apt-get update
    sudo apt-get install -y jq
  elif [ -f /etc/redhat-release ]; then
    # RHEL/CentOS 계열
    sudo yum install -y epel-release
    sudo yum install -y jq
  else
    echo "[ERROR] Unsupported OS. Please install jq manually."
    exit 1
  fi
else
  echo "[INFO] jq is already installed."
fi

REPO_URL=$1
REPO_BRANCH=$2
API_KEY=$3

echo "Sending analysis request..."
REQUEST=$(curl -s -X POST https://dev.ondemand.sparrowcloud.ai/api/v1/analysis/tool/sast \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"resultVersion\": 2,\"memo\": \"github ondemand-analysis-action analysis\",\"sastOptions\": {\"analysisSource\": {\"type\": \"VCS\",\"vcsInfo\": {\"type\": \"git\",\"url\": \"$REPO_URL\",\"branch\": \"$REPO_BRANCH\"}}}}")

echo "Response: $REQUEST"
ANALYSIS_ID=$(echo "$REQUEST" | jq -r '.analysisList[0].analysisId')

echo "Polling analysis $ANALYSIS_ID status..."
for i in {1..100}; do
  ANALYSIS=$(curl -s -X GET https://dev.ondemand.sparrowcloud.ai/api/v3/analysis/$ANALYSIS_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY")
  echo "ANALYSIS: $ANALYSIS"
  RESULT=$(echo "$ANALYSIS" | jq -r '.result')

  if [ "$RESULT" != null ]; then break; fi
  sleep 10
done

if [ "$RESULT" = null ]; then
  echo "Analysis timed out or failed"
  exit 1
fi

echo "Downloading result..."
RESULT=$(curl -s https://your.api/result/$ANALYSIS_ID)
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