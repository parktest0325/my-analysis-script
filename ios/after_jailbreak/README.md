# iOS post-jailbreak auto installer

USB로 연결된 rootless 탈옥 기기에 레포 등록 + 트윅 설치를 한 번에 실행합니다.

## Quick start

### Windows
```powershell
scoop install putty libimobiledevice   # plink, pscp, iproxy
Copy-Item .env.example .env             # ROOT_PASSWORD, PORT 채우기
powershell -ExecutionPolicy Bypass -File .\windows.ps1
```

### macOS
```bash
brew install libimobiledevice
brew install hudochenkov/sshpass/sshpass
cp .env.example .env                     # ROOT_PASSWORD, PORT 채우기
./mac.sh
```

기기는 USB로 연결, 잠금 해제, "이 컴퓨터를 신뢰" 상태여야 합니다.

## 어떤 일이 일어나나

호스트 스크립트는 운반만 합니다 (`iproxy` 터널 → `scp`로 파일 푸시 → `ssh`로 `device.sh` 실행). 실제 설치는 전부 기기 위에서 `device.sh`가 합니다:

1. `repo.txt`의 URL을 `/var/jb/etc/apt/sources.list.d/auto-installer.sources`에 deb822 형식으로 기록 (`Trusted: yes`).  다른 sources 파일에 이미 등록된 URL은 건너뜀 (예: sileo.sources의 chariz).
2. `apt update` — 경고는 표시만 하고 진행 (사용자 기기의 기존 깨진 레포가 우리 작업을 막지 못하게).
3. `tweak.txt`의 패키지를 한 줄씩 `apt install -y` — 패키지마다 ✓/✗ + 실패 사유.
4. `uicache -a`.
5. `additional.txt`를 그대로 출력 (수동 설치 안내 배너).

## 파일

| 파일 | 역할 | 수정 시 |
|------|------|---------|
| `repo.txt` | apt 레포 URL 목록 | 새 레포 추가 |
| `tweak.txt` | apt 패키지(번들 id) 목록 | 새 트윅 추가 |
| `ipa.txt` | TrollStore Lite로 설치할 IPA URL 목록 (GitHub repo URL OR 직접 .ipa/.tipa URL) | 새 IPA 추가 |
| `additional.txt` | 자동설치 불가능한 App Store/IPA 안내 배너 | 항목 추가 |
| `.env` | `ROOT_PASSWORD`, `PORT` | gitignore됨 |
| `device.sh` | 기기에서 도는 본체 | 단계 추가/변경 (예: respring) |
| `windows.ps1` / `mac.sh` | 호스트 운반 스크립트 | 평소엔 만질 일 없음 |
| `_ipas/` | 다운로드된 IPA 캐시 — 파일명이 같으면 재다운로드 안 함 | gitignore됨 |

## ipa.txt 형식

```
# GitHub repo URL — latest release의 .ipa 또는 .tipa 자산 자동 검색
https://github.com/CokePokes/AppStorePlus-TrollStore
https://github.com/mineek/MuffinStore

# 또는 직접 IPA URL
https://example.com/path/foo.ipa
```

IPA 자동설치는 `tweak.txt`에 `com.opa334.trollstorelite`가 있어야 동작합니다 (앱 안의 `trollstorehelper`로 설치).

## 패키지 ID 찾기

레포에 들어있는 패키지의 정확한 식별자는 Sileo의 패키지 상세화면(`Package ID`)이나 `apt-cache search <키워드>`로 확인:
```bash
ssh root@127.0.0.1 -p 2222 "/var/jb/usr/bin/apt-cache search <키워드>"
```

## 알려진 사항

- 호스트키는 매 실행마다 plink로 한 번 probe해서 fingerprint를 얻은 뒤 `-hostkey`로 넘깁니다. dropbear 키가 재생성돼도 자동으로 따라갑니다.
- plink가 stderr에 "Keyboard-interactive authentication prompts from server" 잡담을 흘리는데 windows.ps1은 그걸 버립니다.
- macOS 쪽은 `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null`로 동일한 효과.
