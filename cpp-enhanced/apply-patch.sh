#!/bin/bash
# =============================================================================
# ReSharper MCP - C++ Enhancement Patch
#
# Usage:
#   1. bash cpp-enhanced/apply-patch.sh
#   2. dotnet build src/ReSharperMcp/ReSharperMcp.csproj -c Release
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_DIR/src/ReSharperMcp"
PLUGIN_XML="$REPO_DIR/rider-plugin/src/main/resources/META-INF/plugin.xml"

echo "=== Applying C++ Enhancement Patch ==="

# 0. Pull latest from git
echo "[0/4] Pulling latest from git..."
cd "$REPO_DIR"
git pull || echo "  WARNING: git pull failed (offline or no remote?)"

# 1. Copy our files
echo "[1/4] Copying C++ helper files..."
cp "$SCRIPT_DIR/CppHelpers.cs" "$SRC_DIR/CppHelpers.cs"

# 2. Add NuGet package
echo "[2/4] Checking NuGet package..."
if ! grep -q "Psi.Features.Cpp.src.core" "$SRC_DIR/ReSharperMcp.csproj"; then
    sed -i '/<PackageReference Include="JetBrains.ReSharper.SDK"/a\    <PackageReference Include="JetBrains.Psi.Features.Cpp.src.core" Version="253.0.20260219.74415" PrivateAssets="all" />' "$SRC_DIR/ReSharperMcp.csproj"
    echo "  Added NuGet package"
else
    echo "  Already present"
fi

# 3. Patch dispatch points (idempotent - skips if already patched)
echo "[3/4] Patching dispatch points..."

# 3a. PsiHelpers.cs: ResolveFromArgs - C++ fallback after GetDeclaredElement
if ! grep -q "CppHelpers.TryResolveCppDeclaredElement" "$SRC_DIR/PsiHelpers.cs"; then
    # Insert one line after "var element = GetDeclaredElement(node);"
    sed -i '/var element = GetDeclaredElement(node);/a\                if (element == null) element = CppHelpers.TryResolveCppDeclaredElement(node); // [CPP]' "$SRC_DIR/PsiHelpers.cs"
    echo "  Patched PsiHelpers.ResolveFromArgs"
else
    echo "  PsiHelpers.ResolveFromArgs already patched"
fi

# 3b. PsiHelpers.cs: ResolveSymbolByName - C++ fallback before empty return
if ! grep -q "CppHelpers.TryResolveSymbolByName" "$SRC_DIR/PsiHelpers.cs"; then
    # Replace "if (candidates.Count == 0)\n                return new SymbolResolveResult();"
    # with a block that tries C++ first
    sed -i '/if (candidates.Count == 0)/{N;s|if (candidates.Count == 0)\n                return new SymbolResolveResult();|if (candidates.Count == 0)\n            {\n                var r = CppHelpers.TryResolveSymbolByName(solution, symbolName, kind); // [CPP]\n                if (r != null) return r;\n                return new SymbolResolveResult();\n            }|}' "$SRC_DIR/PsiHelpers.cs"
    echo "  Patched PsiHelpers.ResolveSymbolByName"
else
    echo "  PsiHelpers.ResolveSymbolByName already patched"
fi

# 4. Append -cpp1 suffix to plugin version (prevents marketplace overwrite)
echo "[4/4] Patching plugin version..."
ORIG_VER=$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$PLUGIN_XML" | head -1)
if [[ "$ORIG_VER" != *-cpp* ]]; then
    sed -i "s|<version>${ORIG_VER}</version>|<version>${ORIG_VER}-cpp1</version>|" "$PLUGIN_XML"
    echo "  ${ORIG_VER} → ${ORIG_VER}-cpp1"
else
    echo "  Already patched: ${ORIG_VER}"
fi

echo ""
echo "=== Done! Build: dotnet build src/ReSharperMcp/ReSharperMcp.csproj -c Release ==="
