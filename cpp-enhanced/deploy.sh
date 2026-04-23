#!/bin/bash
# =============================================================================
# Build, deploy, and restart Rider with updated ReSharperMcp plugin
#
# Usage: bash cpp-enhanced/deploy.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_DIR/src/ReSharperMcp"
DLL_SRC="$SRC_DIR/bin/Release/net472/ReSharperMcp.dll"
DLL_DST="$APPDATA/JetBrains/Rider2026.1/plugins/ReSharperMcp/dotnet/ReSharperMcp.dll"

# Rider executable and project
RIDER_EXE="$LOCALAPPDATA/JetBrains/Installations/Rider253/bin/rider64.exe"
RIDER_PROJECT="C:/jhh070_ES_Dev/Client/EsClient/EsClient.uproject"

echo "=== ReSharperMcp C++ Deploy ==="

# 1. Copy master CppHelpers.cs → src
echo "[1/5] Syncing CppHelpers.cs..."
cp "$SCRIPT_DIR/CppHelpers.cs" "$SRC_DIR/CppHelpers.cs"

# 2. Build
echo "[2/5] Building..."
cd "$REPO_DIR"
dotnet build "$SRC_DIR/ReSharperMcp.csproj" -c Release -v quiet
if [ $? -ne 0 ]; then
    echo "BUILD FAILED"
    exit 1
fi
echo "  Build OK"

# 3. Kill Rider
echo "[3/5] Stopping Rider..."
powershell.exe -Command "Stop-Process -Name rider64 -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
sleep 5

# 4. Replace DLL
echo "[4/5] Replacing DLL..."
for i in 1 2 3 4 5; do
    cp "$DLL_SRC" "$DLL_DST" 2>/dev/null && break
    echo "  Retry $i (DLL locked)..."
    sleep 2
done

if [ ! -f "$DLL_DST" ]; then
    echo "FAILED to replace DLL"
    exit 1
fi
echo "  DLL replaced"

# 5. Restart Rider
echo "[5/5] Starting Rider..."
if [ -f "$RIDER_EXE" ]; then
    "$RIDER_EXE" "$RIDER_PROJECT" &
    disown
    echo "  Rider started: $RIDER_PROJECT"
else
    echo "  Rider not found at: $RIDER_EXE — start manually"
fi

# 6. Wait for MCP server
echo "[6/6] Waiting for MCP server..."
MCP_URL="http://127.0.0.1:23741/"
for i in $(seq 1 120); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$MCP_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"deploy","version":"1.0"}}}' \
        2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ] && [ "$HTTP_CODE" != "502" ]; then
        echo "  MCP server up (${i}s)"
        break
    fi
    [ $((i % 10)) -eq 0 ] && echo "  Waiting... (${i}s)"
    sleep 1
done

echo ""
echo "=== Deploy complete! Ready to use ==="
echo "Run in Claude Code: /mcp → Reconnect"
