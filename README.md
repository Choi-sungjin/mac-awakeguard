# Hera Awake Guard

Hera Awake Guard는 MacBook이 **열려 있는 동안에만** Hermes Gateway와 Paperclip 접근성을 지키기 위한 macOS 메뉴바 앱입니다. 이 앱은 닫힌 뚜껑 상태에서 배터리만으로 안전하지 않게 강제 각성을 약속하지 않습니다.

## 핵심 안전 원칙

- 닫힌 뚜껑 + 배터리 환경에서는 macOS가 계속 깨어 있지 않을 수 있습니다.
- 가방 안에 넣은 채로 각성을 유지하려는 사용 방식은 열 위험이 있으므로 지원하지 않습니다.
- SIP 비활성화, 커널 확장, 전역 `pmset` 변경은 사용하지 않습니다.

## 소스와 설치 위치

- 소스: `/Users/sungjin/Projects/HeraAwakeGuard`
- 앱 번들: `/Users/sungjin/Applications/HeraAwakeGuard.app`
- 앱 로그: `~/Library/Logs/HeraAwakeGuard/hera-awake-guard.log`

## 빌드 및 설치

```bash
cd /Users/sungjin/Projects/HeraAwakeGuard
./scripts/build_and_install.sh
open /Users/sungjin/Applications/HeraAwakeGuard.app
```

앱이 실행되면 Dock 아이콘 없이 메뉴바에 `Hera Awake ...` 텍스트가 나타납니다.

## 메뉴 기능

- `Enable 1h`: 1시간 동안 유휴 시스템 절전을 막습니다.
- `Enable until disabled`: 끌 때까지 유휴 시스템 절전을 막습니다.
- `Gateway Guard`: 각성 유지 + Hermes Gateway / Paperclip 상태를 30초마다 점검합니다.
- `Open logs`: 앱 로그와 게이트웨이 로그를 엽니다.
- `Run health check`: 현재 상태를 즉시 점검하고 결과를 팝업으로 보여줍니다.
- `Open usage`: HTML 사용 가이드를 엽니다.

## QA

터미널에서 가장 작은 스모크 검증은 아래 명령 하나로 끝낼 수 있습니다.

```bash
cd /Users/sungjin/Projects/HeraAwakeGuard
./scripts/qa_smoke.sh
```

이 스크립트는 다음을 검증합니다.

- `LSUIElement=true`
- 헤드리스 assertion 생성/해제
- `pmset -g assertions`에 Hera assertion 노출
- `launchctl`에서 Hermes Gateway / Paperclip running 확인
- `curl http://127.0.0.1:3100/api/health`
- 앱 자체 `--health-check`

## 수동 확인

```bash
open /Users/sungjin/Applications/HeraAwakeGuard.app
pmset -g assertions
```

메뉴에서 `Enable 1h` 또는 `Gateway Guard`를 누른 뒤 `pmset -g assertions` 출력에 `Hera Awake Guard`가 보이면 정상입니다. 메뉴에서 `Disable`을 누른 뒤 같은 문자열이 사라지는지도 확인합니다.

닫힌 뚜껑이나 배터리 상태에서 경고가 보이면 의도된 동작입니다. 이 앱은 그 상황을 감추지 않고 명시적으로 알립니다.
