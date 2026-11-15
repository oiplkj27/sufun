# SUFUN 서명 키 만들기와 시험판(pre-release) 업데이트

SUFUN 업데이트 파일(`.sufun`)은 **서명**되어 있습니다. 설치된 SUFUN은 서명이 맞는 파일만 설치합니다.
그래서 **키를 먼저 만들고, 그 공개 키가 들어 있는 ISO로 설치해야** 나중에 업데이트를 받을 수 있습니다.

- 키가 없는 ISO로 설치하면: 업데이트(.sufun)를 **영영 설치할 수 없습니다** (다시 설치해야 함).
  설치 프로그램이 이 경우 빨간 경고를 보여 줍니다.
- 비밀 키는 **본인만** 만들고 봅니다. AI 도우미(Claude)는 비밀 키를 만들지도, 보지도 않습니다.

## 버전 번호 규칙 (왜 VERSION 파일은 1.0 그대로인가)

| 종류 | 버전 번호 | 어떻게 만드나 |
|---|---|---|
| 시험용 빌드 (main에 push할 때마다) | `1.0dev` | 자동 (서명 없음, .sufun 없음) |
| **시험판 N** (pre-release) | `1.0rc1`, `1.0rc2`, … | 태그 `v1.0rc1` 을 push → 본인이 승인 |
| 정식 버전 | `1.0` | 태그 `v1.0` 을 push → 본인이 승인 |

SUFUN(pacman)은 버전을 이렇게 비교합니다: `1.0dev < 1.0rc1 < 1.0rc2 < … < 1.0`.
그래서 `VERSION` 파일은 정식 출시까지 `1.0` 으로 두고, 지금 설치한 시험판은 다음 시험판과 정식 버전을
**보통 업데이트처럼** 받을 수 있습니다. 옛 버전으로 되돌리는 파일은 서명이 맞아도 거부됩니다.

---

## 1. 키 만들기 (처음 한 번, 약 10분)

**준비물**

- **USB 메모리** (키 백업용). 이 Surface의 USB-C는 데이터가 안 되므로, **USB가 되는 다른 PC**에서 하는 것이 가장 좋습니다.
  다른 PC가 없으면 **SUFUN용이 아닌 다른 microSD 카드**를 백업 장소로 쓰세요.
- ⚠️ 백업 폴더를 **C: 에만 두지 마세요.** SUFUN을 내부 저장장치에 설치하면 C: 가 통째로 지워집니다.
- Git for Windows (Git Bash), GitHub CLI (`gh`, <https://cli.github.com>). `gh auth login` 을 한 번 해 두세요.
- 종이와 펜 (암호를 적어 둘 것).

**순서**

1. **Git Bash** 를 엽니다 (시작 메뉴 → "Git Bash"). PowerShell이 아닙니다.
2. 저장소 폴더로 갑니다:

   ```bash
   cd "/c/Surface go 3 OS"
   git pull
   ```

3. 키를 만듭니다. `E:/SUFUN-KEY` 는 백업 USB의 폴더입니다 (USB가 E: 가 아니면 글자를 바꾸세요):

   ```bash
   bash scripts/sufun-key.sh create E:/SUFUN-KEY
   ```

4. 물어보는 것:
   - `Name on the key [SUFUN Release Signing]:` → 그냥 **Enter**
   - `E-mail on the key (optional, it becomes public):` → 그냥 **Enter** (비워 두기. 적으면 누구나 볼 수 있습니다)
   - `New passphrase for the key (12 or more characters...)` → **암호를 정해서 입력** (화면에 아무것도 안 보이는 것이 정상).
     12자 이상. 예: 서로 관계없는 낱말 4~5개. **종이에 적어 두세요.**
   - `The same passphrase again:` → 같은 암호를 한 번 더
5. 끝나면 이렇게 됩니다:
   - `keys/sufun.asc` = **공개 키** (저장소 안, 커밋해도 안전)
   - `E:/SUFUN-KEY/` = **백업** (비밀 키. 절대 커밋·업로드 금지)
     - `sufun-primary-SECRET.asc` : 기본 키 (도장). **오프라인 USB에만.**
     - `sufun-signing-subkey-for-github.asc` : 서명 하위 키 (GitHub에 올릴 것)
     - `README-KEY.txt`, `*.rev` : 키 정보와 취소 증명서
6. **서명 하위 키와 암호를 GitHub에 올립니다** (환경 `release` 의 비밀값). 같은 Git Bash 창에서:

   ```bash
   gh secret set SUFUN_SIGNING_KEY --env release --repo oiplkj27/sufun < E:/SUFUN-KEY/sufun-signing-subkey-for-github.asc
   gh secret set SUFUN_SIGNING_PASSPHRASE --env release --repo oiplkj27/sufun
   ```

   두 번째 명령은 `? Paste your secret` 라고 묻습니다. **4번에서 정한 암호**를 입력하고 Enter.
7. **공개 키를 커밋하고 push합니다:**

   ```bash
   git add keys/sufun.asc
   git commit -m "Add the SUFUN public signing key"
   git push
   ```

8. **백업을 안전하게:**
   - `E:/SUFUN-KEY` 폴더를 **USB 두 개**에 복사해 서로 다른 곳에 보관하면 가장 좋습니다.
   - 클라우드(OneDrive, Google Drive), 메일, 메신저에 올리지 마세요.
   - `sufun-signing-subkey-for-github.asc` 는 GitHub에 올린 뒤 USB에서 지워도 됩니다.
   - 암호를 적은 종이는 USB와 **다른 곳**에 두세요.

9. Claude에게 **"키를 커밋했어"** 라고 알려 주세요. 그러면:
   - 빌드가 키를 넣은 `sufun-keyring` 패키지를 만드는지 확인하고,
   - 첫 시험판 태그 `v1.0rc1` 을 만들 준비를 합니다 (아래 2번).

### 잘못됐을 때

| 증상 | 할 일 |
|---|---|
| `already has a key` | 그 폴더에 이미 키가 있습니다. 새로 만들려면 다른 빈 폴더를 쓰세요 |
| `the backup folder must be outside the repository` | 백업 폴더가 저장소 안입니다. USB 경로를 쓰세요 |
| 암호를 잊음 | 키를 쓸 수 없습니다. 아직 아무것도 배포하기 전이면 `keys/sufun.asc` 를 지우고 새 폴더로 `create` 를 다시 하세요 |
| `gh: command not found` | <https://cli.github.com> 에서 설치 후 Git Bash를 다시 열기 |

---

## 2. 시험판(pre-release) 만들기

1. (선택) `release-notes/prerelease.txt` 에 이번 시험판에서 바뀐 점을 한국어로 적고 커밋합니다.
2. 태그를 push합니다. N은 1부터 하나씩 올립니다:

   ```bash
   git tag v1.0rc1
   git push origin v1.0rc1
   ```

3. GitHub → **Actions** → "Release" 실행이 시작됩니다 (빌드 + 모든 테스트, 약 2시간).
4. 테스트가 통과하면 **승인 대기** 상태가 됩니다: 실행 화면의 **Review deployments** → `release` 체크 → **Approve and deploy**.
5. 서명이 끝나면 GitHub → **Releases** 에 "SUFUN 1.0rc1 (시험판 / pre-release)" 이 생깁니다:
   - `sufun-1.0rc1-x86_64.iso` (2 GiB보다 크면 `.part00`, `.part01` 로 나뉨. `ISO-합치는-방법.txt` 참고)
   - `sufun-update-1.0rc1.sufun` (업데이트 파일)
   - `SHA256SUMS`, `SHA256SUMS.asc` (서명된 체크섬)

워크플로는 게시하기 **전에** 방금 서명한 `.sufun` 을 저장소의 공개 키로 다시 검사합니다.
설치된 SUFUN이 거부할 파일이라면 릴리스가 만들어지지 않습니다.

## 3. 어떤 ISO로 설치하나

- **권장: Releases의 시험판 ISO** (`sufun-1.0rcN-…iso`). 키가 들어 있고, 다음 시험판과 정식 버전을 업데이트로 받습니다.
- Actions의 시험용 ISO (`1.0dev`)도 **키를 커밋한 뒤에 만든 것**이면 키가 들어 있어서 시험판 업데이트를 받을 수 있습니다.
- 키를 커밋하기 **전에** 만든 ISO로는 설치하지 마세요 (설치 프로그램이 경고합니다).

## 4. 설치된 SUFUN에서 업데이트 받기

1. Firefox로 GitHub Releases에서 `sufun-update-1.0rc2.sufun` 을 내려받습니다.
2. 파일을 더블클릭 (또는 앱 메뉴 → **SUFUN 업데이트**) → 릴리스 노트 확인 → 관리자 암호 → 설치.
3. 업데이트 전에 Timeshift 백업이 자동으로 만들어집니다.

## 5. 나중에

- **2년마다** (만료 1~2달 전): `bash scripts/sufun-key.sh extend E:/SUFUN-KEY` → 새 하위 키 파일을 6번 명령으로 다시 올리고, `keys/sufun.asc` 커밋, 새 버전 릴리스.
- **GitHub 계정이 해킹됐을 때**: `bash scripts/sufun-key.sh rotate E:/SUFUN-KEY` (README의 "서명 키 관리" 참고).
