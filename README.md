# 🔍 Analyze Repository GitHub Action

This GitHub Action analyzes a target GitHub repository via external API and updates the README with a summary table.

## 📥 Inputs

| Name         | Required | Description                          |
|--------------|----------|--------------------------------------|
| `repo_url`   | ✅       | URL of the repository to analyze     |
| `branch`     | ✅       | Branch to checkout                   |
| `working_dir`| ❌       | Local directory (default: `target-repo`) |

## 📤 Outputs

| Name           | Description                          |
|----------------|--------------------------------------|
| `result_json`  | The raw result JSON returned by the API |

## ▶️ Example Usage

```yaml
- uses: minwoo-dev/analyze-action@v1
  with:
    repo_url: https://github.com/octocat/Hello-World
    branch: main
