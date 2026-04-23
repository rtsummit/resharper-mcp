# ReSharper MCP — Visual Studio build

동일한 `ReSharperMcp.dll` 백엔드를 **Visual Studio 2022의 ReSharper 확장**에서 로드하기 위한 `.nupkg` 패키징.

Rider용 `rider-plugin/` 은 JVM `.jar + plugin.xml`, VS용 이 폴더는 NuGet `.nupkg`. 백엔드 바이너리는 같은 `net472` DLL 하나를 재사용한다.

## 요구 사항

- Visual Studio 2022/2026 + **ReSharper 2026.1**(Wave 261)
  - Wave 253(ReSharper 2025.3) 대상으로 빌드하려면 `ReSharperMcp.nuspec`의 `Wave` 의존성과 `ReSharperMcp.csproj`의 `JetBrains.ReSharper.SDK` 버전을 함께 내려야 한다.
- 빌드 머신에 `dotnet` CLI, `nuget` CLI (또는 mono + `nuget.exe`)

Wave는 ReSharper의 binary-compat 세대 번호. 2025.3 = 253, 2026.1 = 261. **Wave 표기는 반드시 4-segment** (`[261.0.0.0]`) — 2-segment(`[261.0]`)는 파싱에서 "Input string was not in a correct format. offset 14" 에러가 발생하니 주의. ReSharper 버전이 바뀌면 `ReSharperMcp.nuspec`의 `<dependency id="Wave" version="[261.0.0.0]" />`와 `ReSharperMcp.csproj`의 SDK 버전을 함께 올려 재빌드해야 한다.

## 빌드

```bash
bash vs-plugin/build-vs-plugin.sh
# -> vs-plugin/rtsummit.ReSharperMcp.<version>.nupkg
```

내부적으로 `dotnet build -c Release` 후 `nuget pack ReSharperMcp.nuspec` 을 수행한다. `.nuspec` 은 `DotFiles/` 경로에 DLL/PDB만 담는다 — ReSharper 9+ 규격.

## 로컬 사이드로드

1. VS → **Extensions → ReSharper → Manage Extensions** 창을 연다.
2. 설정(⚙) 아이콘 → **Add source** → 빌드한 `.nupkg` 가 있는 폴더(`vs-plugin/`)를 가리키는 로컬 피드 추가.
3. 검색창에서 `rtsummit.ReSharperMcp` 찾아 Install.
4. VS 재시작. 솔루션 열면 `http://127.0.0.1:23741/` 에 MCP 서버가 자동 시작.

제거하려면 같은 Manage Extensions 창에서 Uninstall.

## 디버깅

- 설치 실패 로그: `%LOCALAPPDATA%\JetBrains\Installations\ReSharperPlatformVs17_*\*.log`
- 로드된 플러그인 위치: `%LOCALAPPDATA%\JetBrains\plugins\rtsummit.ReSharperMcp.*\DotFiles\`
- `devenv.exe` 에 attach해서 ReSharper host 내부 코드 디버깅 가능 (같은 프로세스).

## 퍼블리시

JetBrains Marketplace 가 Rider 플러그인과 동일 파이프라인으로 `.nupkg` 도 받는다. Upload: https://plugins.jetbrains.com/plugin/add — Wave 의존성이 있는 패키지는 자동으로 ReSharper 피드로 라우팅된다.

## Rider와의 차이

| 항목 | Rider | VS ReSharper |
|------|-------|--------------|
| 패키지 | `ReSharperMcp.zip` (lib/*.jar + dotnet/*.dll) | `rtsummit.ReSharperMcp.*.nupkg` (DotFiles/*.dll) |
| 프론트엔드 | IntelliJ `plugin.xml` (JAR) | 없음 (백엔드 only) |
| 설치 위치 | `%APPDATA%\JetBrains\Rider<ver>\plugins\ReSharperMcp\` | `%LOCALAPPDATA%\JetBrains\plugins\rtsummit.ReSharperMcp.*\` |
| Wave 의존성 | 불필요 | 필수 (`[253.0]`) |

백엔드(`src/ReSharperMcp/`)는 수정할 필요 없다. `[ShellComponent]`/`[SolutionComponent]`, `IShellLocks`, PSI API 전부 두 호스트에서 동일하게 동작한다.
