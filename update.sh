#!/bin/bash
# 구글맵 저장 목록 → places.json 업데이트 스크립트
# 사용법: ./update.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST_ID="hVTMansrhDfa4gdnJrNVwLn2cT5DLQ"
PLACES_JSON="$SCRIPT_DIR/places.json"
TEMP_FILE="$SCRIPT_DIR/.gmaps_raw.txt"

echo "🗺️  구글맵 맛집 목록 가져오는 중..."

curl -s -L \
  "https://www.google.com/maps/preview/entitylist/getlist?authuser=0&hl=ko&gl=kr&pb=%211m1%211s${LIST_ID}%212e2%213e2%214i500%216m3%211s2fTZacD_BuObvr0P9PW1kAk%2115i204459%2128e2%2116b1" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept-Language: ko-KR,ko;q=0.9,en;q=0.8" \
  > "$TEMP_FILE" 2>/dev/null

if [ ! -s "$TEMP_FILE" ]; then
  echo "❌ 데이터를 가져오지 못했습니다."
  rm -f "$TEMP_FILE"
  exit 1
fi

python3 << 'PYEOF'
import re, json, sys
from datetime import datetime

script_dir = sys.argv[1] if len(sys.argv) > 1 else "."
temp_file = f"{script_dir}/.gmaps_raw.txt"
places_json = f"{script_dir}/places.json"

with open(temp_file, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

content = content.lstrip(")]}'\n")

pattern = r'\[null,null,([\d.]+),([\d.]+)\].*?\],"([^"]{2,})","([^"]*)"'
matches = re.findall(pattern, content)

# 기존 places.json 로드
try:
    with open(places_json, 'r', encoding='utf-8') as f:
        data = json.load(f)
except FileNotFoundError:
    data = {
        "meta": {"listId": "hVTMansrhDfa4gdnJrNVwLn2cT5DLQ", "listName": "맛집"},
        "places": [], "spots": [], "schedule": {}, "accommodation": {}, "members": []
    }

# 기존 장소 이름 세트 (spots, schedule 등은 유지)
existing_names = {p["name"] for p in data.get("places", [])}

# 일본 범위 필터 (lat 33~36, lng 130~140)
new_places = []
for lat_s, lng_s, name, note in matches:
    lat, lng = float(lat_s), float(lng_s)
    if not (33.0 <= lat <= 36.0 and 130.0 <= lng <= 140.0):
        continue

    # 지역 자동 분류
    area = "기타"
    if 34.5 <= lat <= 34.8 and 135.3 <= lng <= 135.6:
        if lat >= 34.70: area = "우메다"
        elif lat >= 34.67: area = "도톤보리" if lng < 135.505 else "신사이바시"
        elif lat >= 34.66: area = "난바"
        elif lat >= 34.65: area = "신세카이" if lng > 135.504 else "난바"
        else: area = "신세카이"
    elif 35.0 <= lat <= 35.2 and 136.8 <= lng <= 137.0:
        area = "나고야"
    elif 34.9 <= lat <= 35.1 and 135.5 <= lng <= 135.8:
        area = "교토"

    new_places.append({
        "name": name,
        "lat": round(lat, 6),
        "lng": round(lng, 6),
        "area": area,
        "category": "",
        "note": note,
        "source": "googlemap"
    })

# 기존 places의 카테고리/노트 보존
old_map = {p["name"]: p for p in data.get("places", [])}
merged = []
seen = set()
for p in new_places:
    if p["name"] in seen:
        continue
    seen.add(p["name"])
    if p["name"] in old_map:
        old = old_map[p["name"]]
        p["category"] = old.get("category", p["category"])
        if not p["note"] and old.get("note"):
            p["note"] = old["note"]
    merged.append(p)

data["places"] = merged
data["meta"]["lastUpdated"] = datetime.now().astimezone().isoformat()

with open(places_json, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

added = len(seen - existing_names)
removed = len(existing_names - seen)
print(f"✅ 완료! 총 {len(merged)}개 장소")
if added: print(f"   + {added}개 새로 추가됨")
if removed: print(f"   - {removed}개 삭제됨")
if not added and not removed: print("   변경사항 없음")
PYEOF

rm -f "$TEMP_FILE"
echo "📄 $PLACES_JSON 업데이트 완료"
