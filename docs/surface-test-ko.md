# 실제 Surface에서 확인할 것 (두 번째 테스트)

CI(가상 머신)로는 확인할 수 없는 것들입니다. 새 ISO로 `sufun-sd-setup.ps1` 을 다시 실행한 뒤
(Surface UEFI → Boot configuration → **SUFUN (SD)** 밀기) 아래를 확인해 주세요.
결과(잘 됨 / 안 됨 + 사진)를 알려 주시면 다음 수정에 씁니다.

## 1. 부팅
- [ ] 켜질 때 글자 대신 **SUFUN 로고** 화면이 나오나요? (**Esc** = 글자 보기)
- [ ] 부팅 메뉴에 **SUFUN Live (microSD, text mode)** 가 있나요?
- [ ] 처음에 **언어 / 시간대 / 키보드** 선택 화면이 나오고, 손가락으로 고를 수 있나요?
- [ ] 한국어를 고르면 바탕 화면이 한국어이고, 시계가 한국 시간인가요?

## 2. 터치패드 (Type Cover)
- [ ] 한 손가락 탭 = 클릭, 두 손가락 탭 = 오른쪽 클릭, 두 손가락 위로 = 페이지가 아래로 (Windows와 같음)
- [ ] **로그인 화면**에서 터치패드로 포인터가 움직이나요?
- [ ] 로그아웃 → 다시 로그인 후에도 터치패드가 되나요? (3번 반복해 보세요)
- [ ] 덮개를 닫았다 열어(절전 → 깨우기) 후에도 되나요?

## 3. 화면 회전과 화상 키보드
- [ ] 덮개를 펼친 노트북 자세에서 기울여도 화면이 **가로로 고정**되나요?
- [ ] 태블릿 모드(덮개를 뒤로 접기)에서는 화면이 돌아가나요?
- [ ] 작업 표시줄 오른쪽 아이콘 **화면 회전 잠금** 이 동작하나요?
- [ ] 부팅 후 **처음** 태블릿 모드로 바꿨을 때 글자 칸을 누르면 화상 키보드가 나오나요?
- [ ] 시스템 설정의 검색 칸을 **손가락으로** 누르면 커서가 들어가나요? (안 되면 어떤 앱에서 안 되는지 알려 주세요)

## 4. 덮개(lid)와 절전
- [ ] 덮개를 닫으면 절전, **열면 깨어나나요?**
- [ ] 깨어난 뒤 잠금 화면까지 몇 초 걸리나요?
- 안 깨어나면 터미널(Konsole)에서 아래를 실행한 뒤, 덮개를 닫고 10초 기다렸다가 열고(안 깨면 전원 버튼),
  다시 터미널에서 마지막 명령의 결과를 사진으로 보내 주세요:
  ```
  sudo sh -c 'echo 1 > /sys/power/pm_debug_messages'
  cat /sys/module/acpi/parameters/ec_no_wakeup
  grep . /sys/bus/acpi/devices/PNP0C0D:00/power/wakeup /sys/devices/platform/PNP0C0D:00/power/wakeup 2>/dev/null
  sudo dmesg | grep -iE 'wakeup|lid|EC|s2idle|PM:' | tail -n 40
  ```

## 5. 카메라
- [ ] 카메라 앱(앞 카메라): 세로 이음새가 아직 있나요? 밝기는 나아졌나요?
- [ ] 뒤 카메라도 나오나요?
- [ ] Firefox에서 <https://webcamtests.com> 또는 수업용 화상 회의: 카메라 허용 후 화면이 나오나요?
- 이음새가 남아 있으면 크기별로 사진을 찍어 보내 주세요 (Konsole):
  ```
  cam -l
  cam -c1 -s role=viewfinder,width=1280,height=720 -C5 -F/tmp/c720-#.ppm
  cam -c1 -s role=viewfinder,width=1920,height=1080 -C5 -F/tmp/c1080-#.ppm
  cam -c1 -s role=viewfinder,width=640,height=480 -C5 -F/tmp/c480-#.ppm
  ```

## 6. 속도와 메모리
- [ ] 시작 메뉴 / 검색 / 전원 메뉴가 전보다 빨리 열리나요?
- [ ] YouTube 검색 결과 스크롤, 탭 닫기가 덜 끊기나요?
- [ ] 1시간 정도 쓴 뒤 YouTube를 열어도 화면이 멈추지 않나요? (멈추면 그 시각을 적어 주세요)
- [ ] Firefox의 uBlock 아이콘(빨간 방패)이 보이고, 전원 버튼으로 끌 수 있나요?
- [ ] **Ctrl+Shift+Esc** 로 작업 관리자(시스템 모니터)가 열리고, "센서가 없습니다" 경고가 사라졌나요?
