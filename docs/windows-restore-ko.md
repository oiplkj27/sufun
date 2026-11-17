# Windows로 돌아가기 (USB 없이)

이 Surface Go 3는 **USB로 부팅할 수 없습니다.** 보통은 "Windows 설치 USB"로 되돌리지만, 여기서는
SUFUN 안의 **Windows 복원** 도구(`sufun-windows-restore`)가 **내부 저장장치**에 Windows 설치 파일을
넣고 부팅 메뉴 항목을 만들어, USB 없이 Windows 설치 프로그램을 켭니다.

## 먼저: 어느 경우인가요?

| SUFUN 설치 방법 | Windows로 돌아가려면 |
|---|---|
| **SD카드에 설치 (윈도우 유지)** 또는 라이브만 사용 | Windows가 **아직 있습니다.** 카드를 빼고 켜면 Windows입니다. SUFUN 흔적까지 없애려면 Windows에서 `sufun-sd-setup.ps1 -Uninstall` ([sd-boot-ko.md](sd-boot-ko.md) 6번) |
| **내부 저장장치에 설치 (윈도우 삭제)** | 아래 순서대로 |

## 0단계: 복원 리허설 (Windows를 지우기 **전에**, Windows에서)

**왜 하나요?** SUFUN을 내부 저장장치에 설치하면 Windows가 지워집니다. 이 Surface는 USB로 부팅할 수
없어서, 돌아오는 길은 "내부 저장장치에서 Windows 설치 프로그램을 켜는 것" 하나뿐입니다.
그 길이 **이 Surface에서 정말 되는지** 를, 아직 Windows가 있을 때 미리 한 번 해 보는 것이 리허설입니다.
Windows와 내 파일은 지워지지 않습니다.

**필요한 것:** Windows 11 ISO (아래 "Windows 11 ISO는 직접 받으세요"),
`sufun-sd-setup.ps1` (SUFUN 저장소의 `scripts\windows` 폴더), 그리고 C: 를 **줄일 수 있는 공간**:

| 리허설 | C: 를 줄이는 양 | 넣는 파일 | 확인하는 것 |
|---|---|---|---|
| **전체 리허설** | ISO 크기 + 약 0.5 GB (ISO가 8.1 GB면 9 GB) | ISO 내용 전부 | 진짜 Windows 설치 화면이 뜸 + 설치 파일이 모두 들어 있음 |
| **가벼운 리허설** (`-Light`) | 약 1.5 GB | 부팅에 필요한 파일만 (`install.wim` 은 뺌) | 진짜 Windows 설치 화면이 뜸 (**부팅 경로**) |

스크립트가 먼저 C: 를 얼마나 줄일 수 있는지 확인합니다. 전체 리허설이 안 들어가면 이유를 설명하고
**가벼운 리허설**을 권합니다. 이 Surface에서는 전체 리허설이 들어가지 않았습니다
(아래 "가벼운 리허설" 참고).

### 리허설 순서

1. Windows에서 **시작 단추 오른쪽 클릭 → 터미널(관리자)** 를 엽니다.
2. 스크립트가 있는 폴더로 가서 실행합니다 (ISO 경로는 내 것으로 바꾸세요):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\sufun-sd-setup.ps1 -RestoreRehearsal "C:\Users\내이름\Downloads\Win11_24H2_Korean_x64.iso"
   ```

3. 스크립트가 하는 일 (10~20분). 중간에 `YES` 를 한 번 입력합니다.
   - BitLocker(장치 암호화)가 켜져 있으면 **복구 키를 준비했는지** 묻고, 다음 재시작 1번 동안 일시 중지합니다.
   - C: 를 얼마나 줄일 수 있는지 확인합니다. 전체 리허설이 안 들어가면 설명한 뒤 "가벼운 리허설로 진행할까요?" 라고 묻습니다 (Enter = 예).
   - C: 를 줄이고 (전체: ISO 크기 + 약 0.5 GB / 가벼운: 약 1.5 GB), 그 자리에 FAT32 파티션 **WININSTALL** 을 만듭니다.
   - 전체 리허설: ISO 내용을 복사합니다. 4 GB보다 큰 `install.wim` 은 Windows의 DISM으로 `install.swm`, `install2.swm`… 으로 나눕니다.
   - 가벼운 리허설: `install.wim` 만 빼고 복사합니다 (1~3분).
   - 펌웨어 부팅 항목 **Windows Setup** 을 부팅 순서 **맨 끝**에 추가합니다. 기본값은 그대로라서 Windows가 평소처럼 켜집니다.
4. **실제로 켜 보기:**
   1. Surface를 끕니다.
   2. **볼륨 위(+) 버튼을 누른 채 전원 버튼** 을 눌러 Surface UEFI를 엽니다.
   3. **Boot configuration** → **Windows Setup** 을 **왼쪽으로 밀기(swipe)**.
   4. 잠시 뒤 **Windows 설치 화면** (언어·키보드 고르기)이 나오면 **성공**입니다.
   5. **아무것도 설치하지 마세요.** 창 오른쪽 위 **X** → "설치를 취소하시겠습니까?" **예**. Surface가 다시 시작되고 Windows가 켜집니다.
      (가벼운 리허설에는 설치 파일이 없으므로 "다음"으로 더 가지 말고 이 첫 화면에서 닫으세요.)
5. **되돌리기:** Windows에서 다시 터미널(관리자)을 열고

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\sufun-sd-setup.ps1 -Uninstall
   ```

   - "Windows 설치 화면이 나왔습니까?" 라고 묻습니다. 본 대로 `y` 또는 `n` 을 입력하세요.
     이 답은 SUFUN 부팅 파일 옆에 적혀서, 나중에 SUFUN 설치 프로그램이 요약 화면에 보여 줍니다
     (전체 리허설 성공 = "성공", 가벼운 리허설 성공 = "성공 (가벼운 리허설: 부팅 경로 확인됨)").
   - **Windows Setup** 항목과 **WININSTALL** 파티션을 지우고, **C: 를 리허설 전 크기로 정확히** 되돌립니다.
   - SUFUN microSD 부팅 준비("SUFUN (SD)")는 그대로 둡니다 (SUFUN 라이브를 켜는 데 필요).
     그것까지 지우려면 `-Uninstall` 을 한 번 더 실행하거나 `-Uninstall -All` 을 쓰세요.

### 가벼운 리허설 (C: 를 충분히 줄일 수 없을 때)

**왜 필요한가요?** 전체 리허설은 C: 를 ISO 크기만큼 (약 9 GB) 줄여야 합니다. 그런데 C: 에 빈 공간이
20 GB 넘게 있어도 Windows가 "줄일 수 없다"고 할 수 있습니다. Windows는 C: 의 **뒤쪽**만 잘라 낼 수 있는데,
그 뒤쪽에 **옮길 수 없는 파일**이 하나라도 있으면 그 앞까지만 줄일 수 있기 때문입니다.

**이 Surface에서 실제로 확인한 것:** C: 56.1 GB, 빈 공간 23 GB인데 줄일 수 있는 가장 작은 크기가 47.8 GB였습니다
(8.3 GB만 줄일 수 있는데 9 GB가 필요). 막고 있는 파일은 **NTFS 변경 저널** (`$Extend\$UsnJrnl`, 이벤트 뷰어의 이벤트 259에 나옴)이었습니다.

> **이 파일을 쫓아다니지 마세요.** 최대 절전 끄기(`powercfg /h off`), 복원 지점 지우기(`vssadmin delete shadows`),
> 페이지 파일 끄기 + 다시 시작, 변경 저널 지우기(`fsutil usn deletejournal /d C:`)를 모두 해 봤지만 소용이 없었습니다.
> 저널을 지우면 Windows가 곧바로 새로 만드는데, **더 뒤쪽에** 만들어서 오히려 나빠졌습니다 (47.8 GB → 49.2 GB).
> (그때 페이지 파일이나 최대 절전을 껐다면 다시 켜 두세요. 리허설에는 필요 없습니다.)

**그래서 가벼운 리허설:** 이 Surface에서 정말 확인해야 하는 것은 하나입니다.
**"펌웨어가 USB 없이, 내부 저장장치의 작은 FAT32 파티션에서 진짜 Windows 설치 프로그램을 켜는가?"**
이것은 9 GB가 없어도 확인할 수 있습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\sufun-sd-setup.ps1 -RestoreRehearsal "C:\Users\내이름\Downloads\Win11_24H2_Korean_x64.iso" -Light
```

(`-Light` 를 붙이지 않아도, 전체 리허설이 안 들어가면 스크립트가 설명하고 가벼운 리허설을 권합니다.)

- C: 를 **약 1.5 GB만** 줄입니다 (정확한 크기는 화면에 나옵니다).
- **WININSTALL** 파티션에 넣는 것: ISO에서 `sources\install.wim` (또는 `install.esd`) **만 빼고 전부.**
  즉 EFI 부팅 파일(`efi\`, `bootmgr.efi`), `boot\` 폴더, 설치 프로그램 자체가 들어 있는 `sources\boot.wim`,
  그리고 `sources` 폴더의 작은 파일들.
- 부팅 항목 **Windows Setup** 은 전체 리허설과 **똑같이** 만듭니다 (부팅 순서 맨 끝, 같은 형식).
- 그다음은 위 "리허설 순서"의 4번, 5번과 같습니다. **성공 = Windows 설치 화면(언어 고르기)이 나옴.**
- `-Uninstall` 이 전부 되돌립니다 (항목 삭제, 파티션 삭제, C: 를 정확히 원래 크기로). 결과는 "가벼운 리허설 성공"으로 적힙니다.

**가벼운 리허설이 확인해 주는 것**

- Surface 펌웨어가 Boot configuration에 **Windows Setup** 항목을 보여 주고, 그 항목으로 부팅한다.
- 펌웨어가 내부 저장장치의 FAT32 파티션에서 Windows 부팅 관리자(`bootx64.efi`)를 읽어 시작한다.
- Windows 부팅 관리자가 같은 파티션의 `boot.wim` 을 읽어 **진짜 Windows 설치 프로그램**을 켠다 (터치·키보드가 되는 화면까지).
- 즉 **USB 없이 Windows 설치 프로그램까지 가는 길(부팅 경로)** 이 이 Surface에서 된다.
  SUFUN 설치 프로그램은 이 결과를 "부팅 경로 확인됨"으로 보고, 전체 리허설 성공과 같이 다룹니다.

**가벼운 리허설이 확인하지 않는 것, 그리고 괜찮은 이유**

| 확인하지 않는 것 | 괜찮은 이유 |
|---|---|
| 설치 파일(`install.wim` → `install.swm`) 복사와 나누기 | 자동 테스트가 매번 확인합니다 (Windows 쪽 DISM, SUFUN 쪽 wimlib 모두. 아래 "무엇을 시험했고") |
| 설치 프로그램이 "지금 설치" 다음 단계에서 설치 파일을 찾는지 | 설치 파일은 부팅 파일과 **같은 파티션, 같은 폴더**(`sources\`)에 있습니다. 설치 프로그램이 `boot.wim` 을 그 파티션에서 읽었다면 그 파티션은 읽을 수 있는 것입니다. Microsoft가 안내하는 설치 USB(FAT32, 큰 `install.wim` 은 `install.swm` 으로 나눔)와 같은 구조입니다. 다만 **진짜 Microsoft 파일로 끝까지 해 본 것은 아닙니다** (전체 리허설에서도 설치를 끝까지 하지는 않습니다) |
| 내부 저장장치에 설치 파일 6~9 GB가 들어갈 공간이 있는지 | 지금 공간이 모자란 것은 **Windows의 C: 를 줄일 수 없어서**입니다. 실제 복원은 **SUFUN에서** 합니다. 그때는 Windows가 없고 내부 저장장치 전체(64 GB)를 SUFUN이 쓰며, SUFUN 파티션(btrfs)은 "옮길 수 없는 파일" 문제 없이 줄일 수 있습니다 (자동 테스트에서 매번 확인). SUFUN에 빈 공간 10 GB만 있으면 됩니다 |

### 리허설이 실패하면

| 증상 | 뜻 | 할 일 |
|---|---|---|
| Boot configuration에 **Windows Setup** 이 안 보임 | 펌웨어가 이 부팅 항목을 받아들이지 않음 | **Windows를 지우지 마세요.** "SD카드에 설치 (윈도우 유지)" 를 쓰세요 |
| 항목은 보이는데 밀어도 Windows가 그냥 켜지거나 오류 화면 | 부팅 파일을 못 읽음 | 위와 같음. 스크립트 출력과 함께 알려 주세요 |
| Windows 설치 화면이 뜨지만 "드라이버를 찾을 수 없음" 같은 오류 | 설치 프로그램이 WININSTALL의 파일을 못 읽음 | 위와 같음 |
| BitLocker 복구 키를 물어봄 | 부팅 설정이 바뀌어서 생기는 정상 동작 | 준비해 둔 48자리 복구 키 입력 (<https://aka.ms/myrecoverykey>) |
| 스크립트가 "전체 리허설은 지금 할 수 없습니다" 라고 함 | C: 를 ISO 크기만큼 줄일 수 없음 (옮길 수 없는 파일 `$UsnJrnl`) | 실패가 아닙니다. **가벼운 리허설**로 진행하세요 (위). 파일을 지우거나 저널을 지우려고 하지 마세요 |
| 가벼운 리허설에서 설치 화면 대신 파란 오류 화면 (0xc000000f 등) | 부팅 관리자는 켜졌지만 필요한 파일을 못 찾음 | 화면의 파일 이름과 오류 코드를 사진으로 찍어 알려 주세요. 펌웨어 → 부팅 관리자까지는 된 것입니다 |

### 리허설과 실제 복원의 차이 (같은 것과 다른 것)

리허설은 나중에 SUFUN의 **Windows 복원** 이 하는 일을 Windows에서 그대로 해 보는 것입니다.

| | 리허설 (Windows에서) | 실제 복원 (SUFUN에서) | 같은가요? |
|---|---|---|---|
| 설치 파일 파티션 | FAT32, 이름 `WININSTALL`, 종류 "기본 데이터" | FAT32, 이름 `WININSTALL`, 종류 "기본 데이터" | 같음 |
| 파티션 크기 | ISO 크기 + 512 MB, GB 단위로 올림 | 같은 계산 | 같음 (**가벼운 리허설은 다름**: 약 1.5 GB, `install.wim` 없음) |
| 부팅 파일 | ISO의 `\efi\boot\bootx64.efi` + `\efi\microsoft\boot\bcd` | 같음 | 같음 |
| 큰 `install.wim` | `install.swm` 으로 나눔 (3800 MB씩) | 같음 | 나누는 도구만 다름: Windows는 **DISM**, SUFUN은 **wimlib** |
| 펌웨어 부팅 항목 | `Windows Setup`, 순서 맨 끝 | `Windows Setup`, 순서 맨 끝 | **바이트까지 같음** (자동 테스트가 두 결과를 비교함) |
| 항목을 만드는 방법 | 펌웨어 변수에 직접 씀 | Linux의 `efibootmgr` | 결과물이 같음 |
| 파티션 위치 | C: 바로 뒤 (보통 복구 파티션 앞) | SUFUN 파티션 바로 뒤 (디스크 끝) | **다름** (펌웨어는 위치가 아니라 파티션 고유 번호로 찾으므로 영향 없음) |
| GPT의 파티션 "이름표" | `Basic data partition` (Windows 기본값) | `WININSTALL` | **다름** (표시용, 부팅과 무관) |
| 줄이는 파티션 | C: (NTFS) | SUFUN (btrfs) | **다름** (SUFUN 쪽은 가상 머신에서 매번 테스트) |

> 펌웨어 변수에 직접 쓰는 것이 안 되는 PC에서는 스크립트가 `bcdedit` 로 항목을 만듭니다 (화면에 알려 줌).
> 이 경우 항목에 Windows 전용 데이터가 조금 더 붙어서 실제 복원의 항목과 완전히 같지는 않습니다.
> 그때는 SUFUN 설치 프로그램의 **복원 드라이런** (아래)도 함께 해 보세요.

## Windows 11 ISO는 직접 받으세요

SUFUN은 Microsoft 파일을 넣거나 자동으로 받지 않습니다. **Windows의 Edge(리허설 때) 또는 SUFUN의 Firefox(실제 복원 때)에서**:

1. <https://www.microsoft.com/ko-kr/software-download/windows11> 을 엽니다.
2. **"x64 장치용 Windows 11 디스크 이미지(ISO) 다운로드"** → **Windows 11 (multi-edition ISO)** → 다운로드
3. 제품 언어 **한국어** → 확인 → **64-bit 다운로드** (약 6 GB, `다운로드` 폴더에 저장)

> 다른 방법: Microsoft의 **Surface 복구 이미지** (<https://support.microsoft.com/surface-recovery-image>,
> 일련 번호 필요)는 Surface 드라이버가 들어 있지만 ZIP 형식이라 이 도구에서는 쓰지 않습니다.
> 일반 Windows 11 ISO로 설치한 뒤 Windows Update가 드라이버 대부분을 설치하고,
> 나머지는 "Surface Go 3 드라이버 및 펌웨어" (MSI)를 Microsoft 웹사이트에서 받으면 됩니다.

## 1단계: 준비 (아직 아무것도 지우지 않음)

1. 앱 메뉴 → **Windows 복원** 을 엽니다.
2. 설명을 읽고 **예** → 받은 ISO 파일을 고릅니다 → 관리자 암호를 입력합니다.
3. 도구가 하는 일 (10~20분):
   - 내부 저장장치에 빈 공간이 없으면 **SUFUN 파티션을 약 7 GB 줄입니다** (파일은 지우지 않음).
     SUFUN에 빈 공간이 최소 10 GB 정도 있어야 합니다.
   - 그 자리에 FAT32 파티션 **WININSTALL** 을 만들고 ISO 내용을 복사합니다.
     FAT32는 4 GB보다 큰 파일을 담지 못해서, 큰 `install.wim` 은 `install.swm`, `install2.swm`… 으로 나눕니다
     (Windows 설치 프로그램이 그대로 읽습니다).
   - 펌웨어 부팅 메뉴에 **Windows Setup** 항목을 부팅 순서 **맨 끝**에 추가합니다.
     SUFUN은 계속 기본으로 켜집니다. (펌웨어 화면에는 한글 글꼴이 없어 영어 이름입니다.)
4. 마음이 바뀌면: **Windows 복원** 을 다시 열고 **준비한 것 지우기** → 파티션과 항목이 지워지고
   SUFUN 파티션이 원래 크기로 돌아갑니다.

## 2단계: Windows 설치 프로그램 시작

- **Windows 복원** 을 열고 **지금 Windows 설치 시작 (다시 시작)** 을 누르면, 다음 부팅 한 번만
  Windows Setup으로 켜집니다.
- 또는 꺼진 상태에서 **볼륨 위(+) + 전원** → Surface UEFI → **Boot configuration** →
  **Windows Setup** 을 왼쪽으로 밀기(swipe).

Windows 설치 프로그램은 **메모리(RAM)에서** 실행되므로(boot.wim), 그 안에서 SUFUN 파티션을 지울 수 있습니다.

## 3단계: 어떤 파티션을 지우나요? (중요)

설치 프로그램의 **"Windows를 설치할 위치를 선택하세요"** 화면 (드라이브 0 = 내부 저장장치):

| 파티션 (예) | 크기 | 무엇 | 할 일 |
|---|---|---|---|
| 드라이브 0 파티션 1 | 약 1 GB, 시스템 | SUFUN의 EFI 파티션 (부팅 파일) | **삭제** |
| 드라이브 0 파티션 2 | 가장 큼 (약 50 GB) | SUFUN 시스템과 내 파일 (sufun-root) | **삭제** |
| 드라이브 0 파티션 3 | 약 7 GB | **WININSTALL** — 지금 쓰고 있는 Windows 설치 파일 | ❌ **지우지 마세요** |
| 드라이브 1 … | | microSD 카드 (보이는 경우) | 건드리지 않음 |

1. 파티션 1과 2를 각각 고르고 **삭제** → "할당되지 않은 공간" 하나가 생깁니다.
2. 그 **할당되지 않은 공간** 을 고르고 **다음** → Windows가 필요한 파티션을 스스로 만들고 설치합니다.
3. WININSTALL(파티션 3)을 지우면 설치 파일이 사라져 설치가 실패합니다. 그러면 SUFUN도 없으므로
   **다시 시작할 방법이 없습니다** (USB 불가). 반드시 남겨 두세요.

**SUFUN의 모든 파일이 지워집니다.** 필요한 파일은 1단계 전에 백업하세요 (클라우드, microSD 카드 등).

## 4단계: 설치가 끝난 뒤

1. Windows에서 시작 단추 오른쪽 클릭 → **디스크 관리**.
2. **WININSTALL** 파티션을 오른쪽 클릭 → **볼륨 삭제**.
3. **C:** 를 오른쪽 클릭 → **볼륨 확장** → 남은 공간을 모두 C:에 추가.
   (C: 바로 뒤에 복구 파티션이 있으면 확장이 안 될 수 있습니다. 그대로 두어도 문제는 없습니다.)

## Surface 드라이버와 펌웨어 (Windows를 다시 설치한 뒤 꼭)

일반 Windows 11 ISO에는 Surface 전용 드라이버가 다 들어 있지 않습니다 (터치, 카메라, 배터리 표시 등이 안 될 수 있음).

1. Wi-Fi에 연결하고 **설정 → Windows 업데이트** 를 끝까지 실행합니다 (여러 번 다시 시작).
2. Microsoft 웹사이트에서 **"Surface Go 3 Drivers and Firmware"** 를 내려받아 설치합니다:
   <https://www.microsoft.com/download/details.aspx?id=103504>
   (`SurfaceGo3_Win11_....msi` 파일. 실행 → 다음 → 다시 시작)
3. Wi-Fi 드라이버가 없어서 인터넷이 안 되면: 다른 PC에서 위 MSI 파일을 받아 **microSD 카드**에 넣어 옮기세요
   (이 Surface의 USB-C는 데이터가 안 되므로 카드가 유일한 방법입니다). **미리 받아서 카드에 넣어 두는 것을 권장합니다.**

## 정품 인증

Surface에는 Windows 11 Home 정품 키가 **펌웨어에 들어 있고**, Microsoft 서버에도 이 기기의
**디지털 라이선스**가 기록되어 있습니다. 같은 에디션(Home)을 설치하면
인터넷에 연결될 때 **자동으로 정품 인증**됩니다 (키를 입력하거나 살 필요 없음). 설치 중 제품 키를 물으면 **"제품 키가 없음"** 을 누르고,
에디션을 고르라면 **Windows 11 Home** 을 고르세요.

## BitLocker (장치 암호화)

- Windows를 새로 설치하면 예전 디스크와 예전 복구 키는 의미가 없어집니다 (모두 지워짐).
- 새 Windows에 Microsoft 계정으로 로그인하면 장치 암호화가 다시 켜지고, **새 복구 키**가
  <https://aka.ms/myrecoverykey> 에 저장됩니다. 한 번 확인해 적어 두세요.
- 나중에 다시 SUFUN을 카드로 켜려면: Secure Boot를 None으로 바꾸고 [sd-boot-ko.md](sd-boot-ko.md) 처음부터.

## 복원 드라이런 (작은 두 번째 테스트, SUFUN 라이브에서)

위의 **0단계 복원 리허설**이 진짜 테스트입니다 (진짜 Windows 설치 프로그램을 켜 봄).
리허설을 하지 않았다고 답하면, "내부 저장장치에 설치 (윈도우 삭제)" 때 설치 프로그램이 대신 이 **복원 드라이런**을 권합니다:

1. Linux에서 만든 **Windows Setup** 부팅 항목을 추가합니다 (이때는 지금 있는 Windows를 켜도록).
2. 컴퓨터를 끄고 **볼륨 위(+) + 전원** → **Boot configuration** 에 **Windows Setup** 이 보이는지
   확인하고, 왼쪽으로 밀어 부팅합니다. **Windows가 켜지면 성공**입니다.
3. 다시 SUFUN 라이브를 켜고(Surface UEFI → Boot configuration → SUFUN (SD) 밀기) 설치 프로그램을 실행하면, 결과를 묻고 테스트 항목을 지웁니다.

이 테스트로 "이 Surface의 펌웨어가 Linux에서 만든 부팅 항목을 보여 주고 켠다"는 것을 Windows를 지우기 전에 확인합니다.
Windows는 절대 자동으로 지우지 않습니다 (`ERASE` 를 직접 입력해야 함).

## 무엇을 시험했고, 무엇을 못 했나

자동 테스트(가상 머신)에서 **Microsoft 파일 없이** 같은 구조의 가짜 ISO로 확인하는 것:
SUFUN 파티션 줄이기, WININSTALL 만들기와 복사, install.wim 나누기, 부팅 항목이 순서 맨 끝에 생기는지,
"다음 부팅 한 번" 설정으로 펌웨어가 실제로 그 파티션의 부팅 파일을 켜는지, 그리고 되돌리기.

리허설 쪽 (Windows 스크립트)도 자동 테스트합니다. GitHub의 Windows 가상 머신에서 가상 디스크에 실제로 실행해서:
C: 줄이기, WININSTALL 만들기, 복사, DISM으로 나누기, `-Uninstall` 뒤 C: 크기가 **정확히** 돌아오는지,
그 디스크를 다른 가상 머신에서 켜면 펌웨어가 WININSTALL의 부팅 파일을 시작하는지, 그리고
Windows 스크립트가 만든 부팅 항목이 `efibootmgr` 가 만드는 것과 **바이트까지 같은지**.

**가벼운 리허설**도 같은 방법으로 자동 테스트합니다: "Windows" 파티션을 일부러 가득 채워 ISO 전체가 안 들어가게 만든 뒤,
스크립트가 스스로 알아채고 설명한 다음 가벼운 리허설로 넘어가는지, 작은 WININSTALL 파티션에 설치 파일(`install.wim`)이
**없는지**, `-Uninstall` 뒤 크기가 정확히 돌아오고 결과가 "가벼운 리허설 성공"으로 적히는지, 그리고 그 디스크를
가상 머신에서 켜면 펌웨어가 그 작은 파티션의 부팅 파일을 시작하는지.

**시험하지 못한 것 (가상 머신으로는 불가능):** 진짜 Windows 설치 프로그램이 WININSTALL에서 켜지고
`install.swm` 으로 설치하는지, Surface의 실제 펌웨어 화면. **그래서 0단계 복원 리허설을 실제 Surface에서
한 번 해 보는 것이 꼭 필요합니다.** 리허설은 (전체든 가벼운 것이든) "설치 화면이 뜨는 것"까지 확인합니다.
설치를 끝까지 해 보는 것은 아닙니다 (그러면 Windows가 새로 깔리기 때문).
