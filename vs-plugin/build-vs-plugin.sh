#!/bin/bash
# Build a .nupkg that installs ReSharperMcp into ReSharper for Visual Studio 2022.
#
# Output: vs-plugin/rtsummit.ReSharperMcp.<version>.nupkg
#
# Prereqs:
#   - dotnet CLI
#   - nuget CLI (https://dist.nuget.org/win-x86-commandline/latest/nuget.exe) on PATH,
#     OR Mono (nuget.exe runs on Mono) — falls back to dotnet CLI pack otherwise
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NUSPEC="$SCRIPT_DIR/ReSharperMcp.nuspec"

echo "Building backend (net472 Release)..."
dotnet build "$REPO_DIR/src/ReSharperMcp/ReSharperMcp.csproj" -c Release -v quiet

DLL="$REPO_DIR/src/ReSharperMcp/bin/Release/net472/ReSharperMcp.dll"
if [ ! -f "$DLL" ]; then
    echo "ERROR: Expected backend DLL not found: $DLL" >&2
    exit 1
fi

echo "Packing nupkg from $NUSPEC..."
cd "$SCRIPT_DIR"
rm -f ./*.nupkg

if command -v nuget >/dev/null 2>&1; then
    nuget pack "$NUSPEC" -OutputDirectory "$SCRIPT_DIR" -NoPackageAnalysis
elif command -v mono >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/nuget.exe" ]; then
    mono "$SCRIPT_DIR/nuget.exe" pack "$NUSPEC" -OutputDirectory "$SCRIPT_DIR" -NoPackageAnalysis
else
    echo "nuget CLI not found; install from https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" >&2
    echo "or drop nuget.exe next to this script and ensure mono is installed." >&2
    exit 2
fi

PKG=$(ls -t "$SCRIPT_DIR"/rtsummit.ReSharperMcp.*.nupkg | head -1)
echo ""
echo "Done! Package: $PKG"
echo ""
echo "To install locally:"
echo "  1. In VS: Extensions -> ReSharper -> Manage Extensions -> gear icon -> Add source"
echo "     Add a source pointing at: $SCRIPT_DIR"
echo "  2. Search for 'ReSharper MCP' under that source and Install."
echo "  3. Restart VS. The MCP server starts on http://127.0.0.1:23741/."
