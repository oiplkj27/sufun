# Windows로 돌아가기 (USB 없이)

이 Surface Go 3는 **USB로 부팅할 수 없습니다.** 보통은 "Windows 설치 USB"로 되돌리지만, 여기서는
SUFUN 안의 **Windows 복원** 도구(`sufun-windows-restore`)가 **내부 저장장치**에 Windows 설치 파일을
넣고 부팅 메뉴 항목을 만들어, USB 없이 Windows 설치 프로그램을 켭니다.

## 먼저: 어느 경우인가요?

| SUFUN 설치 방법 | Windows로 돌아가려면 |
|---|---|
| **SD카드에 설치 (윈도우 유지)** 또는 라이브만 사용 | Windows가 **아직 있습니다.** 카드를 빼고 켜면 Windows입니다. SUFUN 흔적까지 없애려면 Windows에서 `sufun-sd-setup.ps1 -Uninstall` ([sd-boot-ko.md](sd-boot-ko.md) 6번) |
| **내부 저장장치에 설치 (윈도우 삭제)** | 아래 순서대로 |

## Windows 11 ISO는 직접 받으세요

SUFUN은 Microsoft 파일을 넣거나 자동으로 받지 않습니다. **SUFUN의 Firefox에서**:

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

## 정품 인증

Surface에는 Windows 11 Home 정품 키가 **펌웨어에 들어 있습니다.** 같은 에디션(Home)을 설치하면
인터넷에 연결될 때 **자동으로 정품 인증**됩니다. 설치 중 제품 키를 물으면 **"제품 키가 없음"** 을 누르고,
에디션을 고르라면 **Windows 11 Home** 을 고르세요.

## BitLocker (장치 암호화)

- Windows를 새로 설치하면 예전 디스크와 예전 복구 키는 의미가 없어집니다 (모두 지워짐).
- 새 Windows에 Microsoft 계정으로 로그인하면 장치 암호화가 다시 켜지고, **새 복구 키**가
  <https://aka.ms/myrecoverykey> 에 저장됩니다. 한 번 확인해 적어 두세요.
- 나중에 다시 SUFUN을 카드로 켜려면: Secure Boot를 None으로 바꾸고 [sd-boot-ko.md](sd-boot-ko.md) 처음부터.

## 복원 드라이런 (Windows를 지우기 전)

"내부 저장장치에 설치 (윈도우 삭제)"를 고르면, 설치 프로그램이 먼저 **복원 드라이런**을 권합니다:

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

**시험하지 못한 것:** 진짜 Windows 설치 프로그램이 WININSTALL에서 켜지고 `install.swm` 으로 설치하는지,
Surface의 실제 펌웨어 화면. 그래서 위의 **복원 드라이런**이 중요합니다.
