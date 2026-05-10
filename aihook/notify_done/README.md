# Codex → Telegram 알림 훅

Codex CLI 0.129+의 hooks 시스템을 통해 turn 완료 / 권한 승인 대기 시점에 텔레그램 메시지를 받습니다.

```
[Codex 이벤트] → notify_telegram.py (stdin JSON) → Telegram Bot API
```

---

## 1. 텔레그램 봇 만들기

### 1-1. 봇 생성 + 토큰 발급

1. 텔레그램에서 [@BotFather](https://t.me/BotFather)를 검색해 대화 시작
2. `/newbot` 입력
3. 봇 이름 (표시용, 자유롭게): 예) `My Codex Notifier`
4. 봇 username (`_bot` 또는 `bot`으로 끝나야 함, 전역 유일): 예) `kdh_codex_notify_bot`
5. BotFather가 다음과 같은 토큰을 줌:
   ```
   123456789:AAH-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```
   → 이걸 `TELEGRAM_BOT_TOKEN`으로 사용

### 1-2. chat_id 알아내기

본인 계정으로 알림을 받으려면:

1. 위에서 만든 봇과 대화 시작 — 봇 검색해서 `/start` 한 번 보내기 (필수: 봇이 먼저 사용자에게 메시지 못 보냄)
2. 브라우저에서 다음 URL 열기 (`<TOKEN>` 자리에 1-1에서 받은 토큰):
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
3. JSON 응답에서 `"chat":{"id":123456789,...}` 의 숫자가 chat_id
   ```json
   {"result":[{"message":{"chat":{"id":123456789,"first_name":"..."}}}]}
   ```

### 1-3. 동작 확인 (선택)

```powershell
$token = "123456789:AAH-xxxxx"
$chat  = "123456789"
Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$token/sendMessage" `
  -Body @{ chat_id = $chat; text = "hello" }
```

이 메시지가 텔레그램에 도착하면 봇 설정 끝.

---

## 2. `.env` 작성

`D:\project\_hook\.env` 생성 (`.env.example` 복사):

```
TELEGRAM_BOT_TOKEN=123456789:AAH-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TELEGRAM_CHAT_ID=123456789
```

`.gitignore`에 이미 `.env`가 등록돼 있어 커밋되지 않음.

### 스크립트 단독 동작 확인

```powershell
'{"hook_event_name":"Stop","cwd":"D:/project/_hook","model":"gpt-5.5"}' | python D:/project/_hook/notify_telegram.py
```

텔레그램에 `✅ Codex turn complete\n📁 _hook\n🤖 gpt-5.5` 도착하면 OK.

---

## 3. Codex `config.toml` 적용

위치: `C:\Users\kdh\.codex\config.toml`

기존 `notify = [...]` 라인이 있다면 제거하고 (구식 메커니즘), top-level keys 영역(즉 첫 `[xxx]` 테이블 직전 — 보통 `[mcp_servers...]` 위)에 다음을 추가:

```toml
[features]
hooks = true

[[hooks.Stop]]
matcher = ".*"
[[hooks.Stop.hooks]]
type = "command"
command = "python D:/project/_hook/notify_telegram.py"
timeout = 15

[[hooks.PermissionRequest]]
matcher = ".*"
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "python D:/project/_hook/notify_telegram.py"
timeout = 15
```

### 이벤트 의미

| Event | 발화 시점 | 메시지 |
|---|---|---|
| `Stop` | agent turn 완료 | ✅ Codex turn complete |
| `PermissionRequest` | 명령어/도구 승인 필요 | ⏸️ Codex needs approval |

다른 이벤트도 동일한 방식으로 추가 가능: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`. 스크립트는 모두 인식합니다.

### TOML 문법 검증 (선택)

```powershell
python -c "import tomllib; tomllib.load(open(r'C:\Users\kdh\.codex\config.toml','rb')); print('OK')"
```

---

## 4. 적용 + 검증

1. **현재 떠 있는 Codex 세션 모두 종료** — config는 시작 시 1회만 로드됨
2. 새 Codex 실행
3. 슬래시 명령 **`/hooks`** — `Stop`, `PermissionRequest` 항목이 보여야 정상 등록
4. 아무 메시지 한 번 보내고 응답이 끝날 때까지 대기
5. 텔레그램 + `D:\project\_hook\notify.log` 확인

### 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| Codex 시작 실패 | `[features] codex_hooks = true` 한 줄 주석 처리 후 재실행 (구버전 호환 이슈 [#19199](https://github.com/openai/codex/issues/19199)). 이 경우 hooks 대신 구식 `notify = [...]` 사용 |
| `/hooks`에 여전히 빈 목록 | (a) Codex 재시작 누락, (b) `codex_hooks` 미활성, (c) TOML 문법 오류 — `tomllib` 검증 명령 실행 |
| `notify.log`에 `start` 줄은 찍히는데 `sent ok` 안 찍힘 | 줄 끝 메모 확인: `missing creds` → `.env` 누락, `send failed: HTTP Error 401` → 토큰 오류, `404` → chat_id 오류 |
| `notify.log`가 아예 없음 | hook이 호출되지 않음 → 위 1~3 재확인 |
| 텔레그램 메시지가 깨짐 | stdin 인코딩 문제 (스크립트가 BOM/UTF-16 자동 처리하지만 비정상 입력 의심 시 `notify.log`의 `start raw=...` 확인) |

---

## 5. 파일 구조

```
D:\project\_hook\
├── README.md              # 이 파일
├── notify_telegram.py     # 메인 스크립트 (stdin JSON → Telegram)
├── .env.example           # 자격증명 템플릿
├── .env                   # 실제 자격증명 (gitignore됨, 직접 생성)
├── .gitignore
└── notify.log             # 호출 로그 (자동 생성)
```

## 6. 보안 메모

- `.env`는 절대 커밋 금지 (`.gitignore`에 등록됨)
- 봇 토큰이 노출되면 BotFather에서 `/revoke` 또는 `/token`으로 재발급
- 채팅 ID 자체는 비공개 정보가 아니지만 봇과 페어링되어 있어야 의미가 있음
