#!/bin/bash
# =============================================================================
# ReSharper MCP (C++ Enhanced) - 첫 설치 스크립트
#
# 원본 플러그인이 없는 환경에서 처음부터 빌드 + 설치합니다.
# 사전 요구: .NET SDK (dotnet), Rider 설치 완료
#
# Usage: bash cpp-enhanced/install.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_DIR/src/ReSharperMcp"

echo "=== ReSharper MCP (C++ Enhanced) - Install ==="

# 0. Check prerequisites
echo "[0] Checking prerequisites..."
if ! command -v dotnet &>/dev/null; then
    echo "ERROR: dotnet SDK not found. Install .NET SDK first."
    exit 1
fi
echo "  dotnet: $(dotnet --version)"

# Find Rider plugin directory
RIDER_PLUGIN_DIR=""
for dir in "$APPDATA"/JetBrains/Rider*/plugins; do
    if [ -d "$dir" ]; then
        RIDER_PLUGIN_DIR="$dir"
    fi
done

if [ -z "$RIDER_PLUGIN_DIR" ]; then
    echo "ERROR: Rider plugin directory not found."
    echo "  Expected: %APPDATA%/JetBrains/Rider20XX.X/plugins"
    echo "  Make sure Rider has been run at least once."
    exit 1
fi
echo "  Rider plugins: $RIDER_PLUGIN_DIR"

# 1. Apply C++ patch
echo "[1/4] Applying C++ patch..."
bash "$SCRIPT_DIR/apply-patch.sh"

# 2. Restore NuGet packages
echo "[2/4] Restoring NuGet packages..."
cd "$REPO_DIR"
dotnet restore "$SRC_DIR/ReSharperMcp.csproj" --verbosity quiet

# 3. Build
echo "[3/4] Building..."
dotnet build "$SRC_DIR/ReSharperMcp.csproj" -c Release -v quiet
if [ $? -ne 0 ]; then
    echo "BUILD FAILED"
    exit 1
fi
echo "  Build OK"

# 4. Install plugin
echo "[4/4] Installing plugin..."
INSTALL_DIR="$RIDER_PLUGIN_DIR/ReSharperMcp"
mkdir -p "$INSTALL_DIR/dotnet"
mkdir -p "$INSTALL_DIR/lib"

# Copy DLL
cp "$SRC_DIR/bin/Release/net472/ReSharperMcp.dll" "$INSTALL_DIR/dotnet/"

# Copy JAR (if available from a previous build)
JAR_FILE="$REPO_DIR/rider-plugin/build/libs/ReSharperMcp.jar"
if [ -f "$JAR_FILE" ]; then
    cp "$JAR_FILE" "$INSTALL_DIR/lib/"
    echo "  JAR copied"
else
    echo "  WARNING: JAR not found at $JAR_FILE"
    echo "  Frontend (status bar widget) will not be available."
    echo "  The MCP server will still work — the JAR is optional."
fi

echo "  Installed to: $INSTALL_DIR"

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Next steps:"
echo "  1. Start (or restart) Rider"
echo "  2. Add to Claude Code MCP config (settings.json or .mcp.json):"
echo '     { "mcpServers": { "resharper": { "type": "http", "url": "http://127.0.0.1:23741/" } } }'
echo "  3. In Claude Code: /mcp → Connect to resharper"
