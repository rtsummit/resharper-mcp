# ReSharper MCP - C++ Enhanced

원본 [resharper-mcp](https://github.com/joshua-light/resharper-mcp) 플러그인에 **C++ 심볼 검색** 기능을 추가한 인하우스 패치입니다.

## 뭐가 달라졌나?

원본 플러그인은 C#/F#/VB 심볼만 검색합니다. 이 패치를 적용하면:

- **C++ 엔진 심볼** `find_usages` 가능 (예: `UWorld::StreamingLevelsPrefix`)
- **C++ 프로젝트 심볼** `symbolName`으로 직접 검색 가능
- **position 기반** (filePath + line + column) C++ 심볼 resolve 개선

내부적으로 `CppGlobalSymbolCache` → `CppLinkageEntityDeclaredElement` 변환을 통해 C++ 심볼을 `IDeclaredElement`로 만들어 기존 find_usages 파이프라인에 태웁니다.

## 사전 요구사항

- **Rider** (2025.3+)
- **.NET SDK** (`dotnet` CLI 사용 가능해야 함)
- **Claude Code** (또는 다른 MCP 클라이언트)

## 첫 설치 (원본 플러그인이 없는 경우)

```bash
cd resharper-mcp
bash cpp-enhanced/install.sh
```

이 스크립트가 하는 일:
1. C++ 패치 적용 (NuGet 패키지 추가 + 소스 파일 복사 + dispatch 코드 삽입)
2. NuGet 복원 + 빌드
3. Rider 플러그인 폴더에 DLL 설치

설치 후 Rider를 시작하면 MCP 서버가 `http://127.0.0.1:23741/`에서 자동 시작됩니다.

## 클린 재설치 (플러그인이 꼬였을 때)

기존 플러그인을 완전히 삭제한 뒤 다시 설치하는 절차입니다.

> **참고**: 아래 경로의 Rider 버전(`Rider2026.1`)과 Windows 사용자 계정명은 환경마다 다릅니다. 본인 환경에 맞게 바꿔주세요.

### 1단계: 플러그인 폴더 삭제

```
%APPDATA%\JetBrains\Rider2026.1\plugins\ReSharperMcp
```

이 폴더를 통째로 삭제합니다. Rider가 실행 중이면 먼저 종료하세요.

### 2단계: install.sh 실행

```bash
cd resharper-mcp
bash cpp-enhanced/install.sh
```

`apply-patch.sh`는 멱등(idempotent)하므로, 이미 패치된 소스에 다시 실행해도 안전합니다.

### 3단계: Rider 시작 → MCP 재연결

1. Rider를 시작하고 C++ 인덱싱이 완료될 때까지 대기
2. Claude Code에서 `/mcp` → resharper에 Connect

## Claude Code MCP 설정

프로젝트 루트 `.mcp.json` 또는 Claude Code `settings.json`에 추가:

```json
{
  "mcpServers": {
    "resharper": {
      "type": "http",
      "url": "http://127.0.0.1:23741/"
    }
  }
}
```

Claude Code에서 `/mcp` → resharper에 Connect하면 사용 가능합니다.

## 로컬 플러그인 ZIP 빌드 (Install Plugin from Disk)

마켓플레이스 자동 업데이트가 C++ 패치를 덮어쓰는 것을 방지하려면, 로컬 ZIP을 만들어 **Install Plugin from Disk**로 설치합니다.

> **사전 요구**: `JAVA_HOME` 환경변수가 설정되어 있어야 합니다 (jar 명령 사용).

### 빌드

```bash
cd resharper-mcp

# 1. C++ 패치 적용 (git pull + 패치 + 버전 suffix)
bash cpp-enhanced/apply-patch.sh

# 2. 백엔드(.NET) 빌드
dotnet build src/ReSharperMcp/ReSharperMcp.csproj -c Release

# 3. 프론트엔드(JAR) 빌드
cd rider-plugin && ./gradlew jar --quiet && cd ..

# 4. ZIP 생성
mkdir -p .build-staging/ReSharperMcp/lib .build-staging/ReSharperMcp/dotnet
cp rider-plugin/build/libs/ReSharperMcp.jar .build-staging/ReSharperMcp/lib/
cp src/ReSharperMcp/bin/Release/net472/ReSharperMcp.dll .build-staging/ReSharperMcp/dotnet/
cd .build-staging
"$JAVA_HOME/bin/jar" -cMf "../ReSharperMcp.zip" ReSharperMcp/
cd ..
rm -rf .build-staging
```

결과물: `resharper-mcp/ReSharperMcp.zip`

### 설치

1. Rider → **Settings → Plugins → ⚙ → Install Plugin from Disk**
2. `ReSharperMcp.zip` 선택
3. Rider 재시작

마켓플레이스에서 설치한 플러그인이 이미 있다면 먼저 제거 후 설치하세요.

## 원본 플러그인 업데이트 후 재적용

원작자가 업데이트를 올렸을 때:

```bash
bash cpp-enhanced/apply-patch.sh   # git pull + C++ 패치 재적용 + 버전 suffix
dotnet build src/ReSharperMcp/ReSharperMcp.csproj -c Release  # 빌드
```

이후 위의 "로컬 플러그인 ZIP 빌드" 절차를 따라 ZIP을 만들고 재설치합니다.

## 개발용 배포 스크립트 (deploy.sh)

CppHelpers.cs 수정 후 빠르게 테스트하려면:

```bash
bash cpp-enhanced/deploy.sh
```

이 스크립트는 빌드 → Rider 종료 → DLL 교체 → Rider 재시작 → MCP 서버 대기까지 자동으로 수행합니다.

**주의**: `deploy.sh`의 `RIDER_EXE`와 `RIDER_PROJECT` 변수를 본인 환경에 맞게 수정해야 합니다.

## 파일 구조

```
cpp-enhanced/
├── README.md         ← 이 파일
├── CppHelpers.cs     ← C++ 심볼 검색 구현 (마스터 복사본)
├── apply-patch.sh    ← 원본 코드에 최소 수정 적용
├── install.sh        ← 첫 설치용 스크립트
└── deploy.sh         ← 개발용 빌드+배포+재시작 자동화
```

패치가 원본 코드에 추가하는 것:
- `ReSharperMcp.csproj` — NuGet 패키지 1줄 (`JetBrains.Psi.Features.Cpp.src.core`)
- `PsiHelpers.cs` — C++ fallback dispatch 2줄 (`// [CPP]` 태그로 표시)
- `CppHelpers.cs` — C++ 전용 헬퍼 파일 (새 파일)
- `plugin.xml` — 버전에 `-cpp1` suffix 추가 (마켓플레이스 덮어쓰기 방지)

### Dispatch 위치 상세

원본 `src/ReSharperMcp/PsiHelpers.cs`에서 C# 심볼 resolve가 실패할 때 C++ fallback으로 분기하는 지점 2곳:

**1. `ResolveFromArgs()` — position 기반 (filePath + line + column)**

```csharp
// PsiHelpers.cs — ResolveFromArgs 메서드 내부
var element = GetDeclaredElement(node);
if (element == null) element = CppHelpers.TryResolveCppDeclaredElement(node); // [CPP]
```

C# PSI에서 `GetDeclaredElement()`가 null을 반환하면 `CppHelpers.TryResolveCppDeclaredElement()`로 C++ 심볼 resolve를 시도합니다.

**2. `ResolveSymbolByName()` — 이름 기반 (symbolName)**

```csharp
// PsiHelpers.cs — ResolveSymbolByName 메서드 내부
if (candidates.Count == 0)
{
    var r = CppHelpers.TryResolveSymbolByName(solution, symbolName, kind); // [CPP]
    if (r != null) return r;
    return new SymbolResolveResult();
}
```

C# symbol cache에서 후보가 0개일 때 `CppHelpers.TryResolveSymbolByName()`으로 C++ 심볼 검색을 시도합니다.

두 곳 모두 `// [CPP]` 태그로 표시되어 있어 `grep -n "\[CPP\]" src/ReSharperMcp/PsiHelpers.cs`로 찾을 수 있습니다.

## 사용 예시

Claude Code에서:

```
# 엔진 심볼 사용처 검색
> UWorld::StreamingLevelsPrefix의 모든 사용처를 찾아줘

# 프로젝트 C++ 심볼 검색
> GetPartComponent의 사용처를 심볼검색으로 찾아줘

# position 기반 검색 (헤더 파일 선언 위치)
> Engine/Source/Runtime/Engine/Classes/Components/SkeletalMeshComponent.h:1475 사용처 검색
```
