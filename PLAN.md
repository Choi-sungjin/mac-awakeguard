# Hera Awake Guard 플랜

## 결론
MacBook Air는 덮개를 닫고 배터리 상태로 가방에 넣은 채 계속 온라인 상태를 유지하는 것을 정상/안전 동작으로 보장할 수 없다. macOS의 clamshell sleep은 OS·하드웨어 정책이고, 가방 안 상시 구동은 발열·배터리 위험이 있다.

따라서 앱은 “덮개 닫힘을 강제로 무시”하지 않고, 다음의 안전한 운영 모드를 제공한다.

## 구현 범위
1. 메뉴바 전용 앱 `HeraAwakeGuard.app`
2. `LSUIElement=true` Dock-less 실행
3. 모드
   - 꺼짐
   - 한 시간 유지
   - 계속 유지
   - Gateway Guard: Hermes Gateway/Paperclip 상태를 감시하면서 유지
4. 전원 assertion
   - `PreventUserIdleSystemSleep`
   - `PreventUserIdleDisplaySleep`
5. 상태 점검
   - Hermes Gateway launchd: `ai.hermes.gateway-hera`
   - Paperclip launchd: `ai.paperclip.default`
   - Paperclip health: `http://127.0.0.1:3100/api/health`
   - 덮개 상태: `AppleClamshellState`
6. 한국어 사용법 HTML 제공

## 안전 정책
- 덮개 닫힘 + 배터리 + 가방 안 상시 연결은 “권장하지 않음”으로 명시한다.
- AC 전원 + 통풍 + 외부 디스플레이 + 외부 키보드/마우스/트랙패드 조건의 clamshell만 안전한 장시간 운영으로 안내한다. 외부 입력 장치는 Bluetooth 또는 USB일 수 있지만, Bluetooth 연결만으로 clamshell sleep을 우회한다고 설명하지 않는다.
- 전역 `pmset` 변경은 하지 않는다.
- SIP 비활성화, 커널 확장, 열 안전 우회는 하지 않는다.

## 검증
- 앱 실행 확인
- `pmset -g assertions`에서 `Hera Awake Guard` assertion 확인
- 앱 종료 후 assertion 해제 확인
- Paperclip health 확인
- Hermes Gateway launchd running 확인
