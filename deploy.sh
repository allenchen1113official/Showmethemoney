#!/bin/bash
# ============================================
# Show Me The Money - GitHub 部署腳本
# 執行前請確認已安裝 gh CLI 並已登入
# ============================================

set -e

REPO_NAME="Showmethemoney"
GITHUB_USER="allenchen1113official"

echo "🚀 開始部署 $REPO_NAME 到 GitHub Pages..."
echo ""

# 1. 登入 GitHub CLI (如已登入可跳過)
echo "📋 步驟 1: 檢查 GitHub 登入狀態..."
if ! gh auth status &>/dev/null; then
  echo "請先登入 GitHub..."
  gh auth login
fi
echo "✅ GitHub 已登入"
echo ""

# 2. 建立 GitHub repo
echo "📋 步驟 2: 建立 GitHub Repository..."
if gh repo view "$GITHUB_USER/$REPO_NAME" &>/dev/null; then
  echo "⚠️  Repo 已存在，跳過建立步驟"
else
  gh repo create "$REPO_NAME" \
    --public \
    --description "Show Me The Money - 台股看盤系統 | Taiwan Stock Market Dashboard" \
    --homepage "https://$GITHUB_USER.github.io/$REPO_NAME/"
  echo "✅ Repo 建立完成"
fi
echo ""

# 3. 設定 remote 並推送
echo "📋 步驟 3: 推送程式碼..."
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
git branch -M main
git push -u origin main --force
echo "✅ 程式碼推送完成"
echo ""

# 4. 啟用 GitHub Pages
echo "📋 步驟 4: 啟用 GitHub Pages..."
sleep 2
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/$GITHUB_USER/$REPO_NAME/pages" \
  -f source='{"branch":"main","path":"/"}' \
  2>/dev/null || \
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$GITHUB_USER/$REPO_NAME/pages" \
  -f source='{"branch":"main","path":"/"}' \
  2>/dev/null || \
echo "⚠️  GitHub Pages 設定請手動至 Repo Settings > Pages 啟用"
echo ""

echo "============================================"
echo "🎉 部署完成！"
echo ""
echo "📌 程式庫：https://github.com/$GITHUB_USER/$REPO_NAME"
echo "🌐 網站：  https://$GITHUB_USER.github.io/$REPO_NAME/"
echo ""
echo "注意：GitHub Pages 首次啟用需等約 1-2 分鐘才會生效"
echo "============================================"
