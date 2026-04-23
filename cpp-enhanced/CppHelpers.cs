using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using JetBrains.DocumentModel;
using JetBrains.ProjectModel;
using JetBrains.ReSharper.Psi;
using JetBrains.ReSharper.Psi.Cpp.Caches;
using JetBrains.ReSharper.Psi.Cpp.Language;
using JetBrains.ReSharper.Psi.Cpp.Symbols;
using JetBrains.ReSharper.Psi.Tree;

namespace ReSharperMcp
{
    /// <summary>
    /// C++ symbol resolution helpers.
    /// Bridges ICppSymbol/ICppLinkageEntity to IDeclaredElement for use with generic PSI tools.
    /// </summary>
    public static class CppHelpers
    {
        /// <summary>
        /// Called from PsiHelpers.ResolveSymbolByName as C++ fallback.
        /// Searches C++ symbols by short name via CppGlobalSymbolCache.
        /// </summary>
        public static PsiHelpers.SymbolResolveResult TryResolveSymbolByName(ISolution solution, string symbolName, string kind)
        {
            // Diagnostic hook for development
            if (symbolName == "__cpp_dump__")
                return new PsiHelpers.SymbolResolveResult(); // not found — triggers dump via search_symbol

            var cache = TryGetGlobalSymbolCache(solution);
            if (cache == null)
                return null;

            // Support "::" qualified names: "UWorld::StreamingLevelsPrefix" → shortName = "StreamingLevelsPrefix"
            var shortName = symbolName;
            string qualifiedPrefix = null;
            var lastSep = symbolName.LastIndexOf("::", StringComparison.Ordinal);
            if (lastSep >= 0)
            {
                shortName = symbolName.Substring(lastSep + 2);
                qualifiedPrefix = symbolName.Substring(0, lastSep);
            }
            // Also support dot notation from the caller
            var lastDot = shortName.LastIndexOf('.');
            if (lastDot >= 0)
            {
                qualifiedPrefix = shortName.Substring(0, lastDot);
                shortName = shortName.Substring(lastDot + 1);
            }

            var symbols = cache.SymbolNameCache.GetSymbolsByShortName(shortName);
            if (symbols.Count == 0)
                return null;

            var psiServices = solution.GetPsiServices();
            var linkageCache = cache.LinkageCache;
            var candidates = new List<(IDeclaredElement element, string fqn)>();
            var seenEntities = new HashSet<ICppLinkageEntity>();

            foreach (var symbol in symbols)
            {
                if (!(symbol is ICppParserSymbol parserSymbol))
                    continue;

                // Get linkage entity for this symbol
                var linkageEntity = linkageCache.FindEntityBySymbol(parserSymbol);
                if (linkageEntity == null)
                    continue;

                // Deduplicate by linkage entity
                if (!seenEntities.Add(linkageEntity))
                    continue;

                // Convert to IDeclaredElement
                var declaredElement = new CppLinkageEntityDeclaredElement(psiServices, linkageEntity);

                // Build qualified name from the symbol's QualifiedName property
                var fqn = GetQualifiedNameFromSymbol(parserSymbol);

                // Filter by qualified prefix if provided
                if (qualifiedPrefix != null)
                {
                    var fqnNormalized = fqn.Replace("::", ".");
                    var prefixNormalized = qualifiedPrefix.Replace("::", ".");
                    if (!fqnNormalized.Contains(prefixNormalized))
                        continue;
                }

                candidates.Add((declaredElement, fqn));
            }

            if (candidates.Count == 0)
                return null;

            if (candidates.Count == 1)
                return new PsiHelpers.SymbolResolveResult { Element = candidates[0].element };

            // Multiple matches — return candidates for disambiguation
            var candidateInfos = new List<PsiHelpers.SymbolCandidate>();
            foreach (var (element, fqn) in candidates)
            {
                string filePath = null;
                var line = 0;
                foreach (var d in element.GetDeclarations())
                {
                    var s = d.GetSourceFile();
                    var path = s?.GetLocation().FullPath;
                    if (!string.IsNullOrEmpty(path))
                    {
                        filePath = path;
                        var range = TreeNodeExtensions.GetDocumentRange(d);
                        if (range.IsValid())
                        {
                            var coords = range.StartOffset.ToDocumentCoords();
                            line = (int)coords.Line + 1;
                        }
                        break;
                    }
                }

                candidateInfos.Add(new PsiHelpers.SymbolCandidate
                {
                    Name = element.ShortName,
                    QualifiedName = fqn,
                    Kind = "cpp_symbol",
                    File = filePath ?? "[no source]",
                    Line = line
                });
            }

            return new PsiHelpers.SymbolResolveResult { Candidates = candidateInfos };
        }

        /// <summary>
        /// Called from PsiHelpers.ResolveFromArgs as C++ fallback for position-based resolution.
        /// When generic PSI resolution fails on C++ engine files, tries C++ specific approach.
        /// </summary>
        public static IDeclaredElement TryResolveCppDeclaredElement(ITreeNode node)
        {
            // Walk up the tree looking for C++ specific declaration types
            var current = node;
            for (var depth = 0; current != null && depth < 10; depth++)
            {
                if (current is IDeclaration decl)
                {
                    var element = decl.DeclaredElement;
                    if (element != null)
                        return element;
                }
                current = current.Parent;
            }
            return null;
        }

        /// <summary>
        /// Get qualified name for a C++ declared element.
        /// </summary>
        public static string GetCppQualifiedName(IDeclaredElement element)
        {
            return element.ShortName;
        }

        /// <summary>
        /// Diagnostic: dump C++ cache info for development.
        /// </summary>
        public static string DumpCppGlobalSymbolCacheMethods(ISolution solution)
        {
            try
            {
                var cache = solution.GetComponent<CppGlobalSymbolCache>();
                var symbolNameCache = cache.SymbolNameCache;
                var results = new List<string>();

                var fieldSymbols = symbolNameCache.GetSymbolsByShortName("StreamingLevelsPrefix");
                results.Add($"=== GetSymbolsByShortName('StreamingLevelsPrefix') returned {fieldSymbols.Count} results ===");
                foreach (var sym in fieldSymbols)
                {
                    results.Add($"  Type: {sym.GetType().Name}, Name: {sym}, ContainingFile: {sym.ContainingFile}");
                    try
                    {
                        var range = sym.LocateDocumentRange(solution);
                        results.Add($"  DocumentRange: {range}, IsValid: {range.IsValid()}");
                        if (range.IsValid())
                            results.Add($"  Document: {range.Document?.GetType().Name}, Path: {range.Document}");
                    }
                    catch (Exception ex) { results.Add($"  LocateDocumentRange error: {ex.Message}"); }

                    try
                    {
                        var linkageCache = cache.LinkageCache;
                        if (sym is ICppParserSymbol parserSymbol)
                        {
                            var entity = linkageCache.FindEntityBySymbol(parserSymbol);
                            results.Add($"  LinkageEntity: {entity}");
                            if (entity != null)
                            {
                                results.Add($"  LinkageEntity type: {entity.GetType().FullName}");
                                results.Add($"  LinkageEntity interfaces: {string.Join(", ", entity.GetType().GetInterfaces().Select(i => i.Name))}");
                                if (entity is IDeclaredElement de)
                                    results.Add($"  ** IS IDeclaredElement: {de.ShortName}");

                                var declElemType = entity.GetType().Assembly.GetTypes()
                                    .FirstOrDefault(t => t.Name == "CppLinkageEntityDeclaredElement");
                                if (declElemType != null)
                                    results.Add($"  Found CppLinkageEntityDeclaredElement type: {declElemType.FullName}");

                                var entitySymbols = linkageCache.FindSymbols(entity);
                                results.Add($"  FindSymbols returned: {entitySymbols?.Count ?? 0} symbols");
                            }
                        }
                    }
                    catch (Exception ex) { results.Add($"  LinkageEntity error: {ex.Message}"); }

                    if (results.Count > 80) break;
                }

                results.Add("\n=== Looking for DeclaredElement wrappers ===");
                try
                {
                    var cppDll = typeof(CppGlobalSymbolCache).Assembly;
                    var declTypes = cppDll.GetTypes()
                        .Where(t => t.Name.Contains("DeclaredElement") && !t.IsAbstract)
                        .Take(10);
                    foreach (var t in declTypes)
                    {
                        results.Add($"  {t.FullName}");
                        foreach (var c in t.GetConstructors(BindingFlags.Public | BindingFlags.Instance))
                            results.Add($"    ctor({string.Join(", ", c.GetParameters().Select(p => $"{p.ParameterType.Name} {p.Name}"))})");
                    }
                }
                catch (Exception ex) { results.Add($"  Error: {ex.Message}"); }

                return string.Join("\n", results);
            }
            catch (Exception ex)
            {
                return $"Error: {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}";
            }
        }

        private static string GetQualifiedNameFromSymbol(ICppParserSymbol symbol)
        {
            try
            {
                var name = symbol.Name;
                return name.ToString();
            }
            catch { }
            return symbol.ToString();
        }

        private static CppGlobalSymbolCache TryGetGlobalSymbolCache(ISolution solution)
        {
            try { return solution.GetComponent<CppGlobalSymbolCache>(); }
            catch { return null; }
        }
    }
}
