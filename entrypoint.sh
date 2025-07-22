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

# 기본값 설정
REPO_BRANCH="main"
VCS_AUTH_TOKEN=""

# 명시적 인자 파싱
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)
      API_KEY="$2"
      shift 2
      ;;
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --repo-branch)
      REPO_BRANCH="$2"
      shift 2
      ;;
    --vcs-auth-token)
      VCS_AUTH_TOKEN="$2"
      shift 2
      ;;
    *)
      echo "[ERROR] Unknown argument: $1"
      exit 1
      ;;
  esac
done

# 필수 인자 확인
if [[ -z "$API_KEY" || -z "$REPO_URL" ]]; then
  echo "[ERROR] --api-key and --repo-url are required."
  exit 1
fi

echo "Sending analysis request..."
RESPONSE_FILE=$(mktemp)
HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST https://dev.ondemand.sparrowcloud.ai/api/v1/analysis/tool/sast \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "$(jq -nc --arg url "$REPO_URL" --arg branch "$REPO_BRANCH" --arg token "$VCS_AUTH_TOKEN" '
    {
      resultVersion: 2,
      memo: "github ondemand-analysis-action analysis",
      sastOptions: {
        analysisSource: {
          type: "VCS",
          vcsInfo: {
            type: "git",
            url: $url,
            branch: $branch
          }
        }
      }
    } | if $token != "" then .sastOptions.analysisSource.vcsInfo.authToken = $token else . end
  ')")

if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "[ERROR] Failed to send analysis request. HTTP status: $HTTP_STATUS"
  cat "$RESPONSE_FILE"
  exit 1
fi

REQUEST=$(cat "$RESPONSE_FILE")
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

# 결과 ZIP 다운로드 및 압축 해제
echo "Downloading analysis result ZIP..."
if ! curl -sfL -X GET "https://dev.ondemand.sparrowcloud.ai/api/v2/analysis/$ANALYSIS_ID/result" \
  -H "Authorization: Bearer $API_KEY" \
  -o result.zip; then
  echo "[ERROR] Failed to download result zip"
  exit 1
fi

echo "Unzipping result.zip..."
unzip -o result.zip -d ./result || {
  echo "[ERROR] Failed to unzip result.zip"
  exit 1
}
echo "Analysis result extracted to ./result"

# summary.json 출력
SUMMARY_JSON=""
echo "Printing summary.json..."
if [ -f ./result/summary.json ]; then
  cat ./result/summary.json
  SUMMARY_JSON=$(jq -c . ./result/summary.json)
else
  echo "[WARNING] summary.json not found in extracted files"
fi

# RESULT.md 생성
REPORT_MD=./result/RESULT.md
echo "# 📊 Analysis Result Summary" > "$REPORT_MD"
echo "" >> "$REPORT_MD"
echo "| Total Issue | Very High | High | Medium | Low | Very Low |" >> "$REPORT_MD"
echo "|------|------|----------|---------|---------|---------|" >> "$REPORT_MD"
jq -r '"| \(.issueCount) | \(.issueCountRisk1) | \(.issueCountRisk2) | \(.issueCountRisk3) | \(.issueCountRisk4) | \(.issueCountRisk5) |"' ./result/summary.json >> "$REPORT_MD"
echo "[INFO] RESULT.md written at $REPORT_MD"

echo "SUMMARY_JSON=$SUMMARY_JSON"
echo "REPORT_MD=$REPORT_MD"

# GitHub Action output 설정
echo "result_summary=$SUMMARY_JSON" >> "$GITHUB_OUTPUT"
echo "report_path=$REPORT_MD" >> "$GITHUB_OUTPUT"
