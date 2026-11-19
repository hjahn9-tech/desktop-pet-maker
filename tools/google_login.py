#!/usr/bin/env python3
"""지메일 기능용 구글 로그인 (한 번만).

준비: 구글 클라우드 콘솔에서 OAuth 클라이언트(데스크톱 앱)를 만들고 credentials.json 을 내려받는다.
      Gmail API 를 켜 둔다. (자세한 순서는 docs/EXTENDING.md)
실행: pip install google-auth-oauthlib
      python3 tools/google_login.py ~/Downloads/credentials.json
결과: ~/.config/desktop-pet/google_token.json  (권한: 메일 읽기 전용)
"""
import json
import os
import sys

from google_auth_oauthlib.flow import InstalledAppFlow

if len(sys.argv) < 2:
    sys.exit("사용법: python3 tools/google_login.py <credentials.json 경로>")
SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]
OUT = os.path.expanduser("~/.config/desktop-pet/google_token.json")

flow = InstalledAppFlow.from_client_secrets_file(os.path.expanduser(sys.argv[1]), SCOPES)
creds = flow.run_local_server(port=0, open_browser=True, prompt="consent",
                              success_message="연결됐습니다. 이 창은 닫아도 됩니다.")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump({"client_id": creds.client_id, "client_secret": creds.client_secret,
               "refresh_token": creds.refresh_token}, f, indent=2)
os.chmod(OUT, 0o600)
print("저장:", OUT)
