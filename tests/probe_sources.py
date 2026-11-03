"""Public interface probes. Reports unavailability; never labels an HTTP 200 as successful playback."""
import json
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.error import HTTPError

report = {'checked_at': datetime.now(timezone.utc).isoformat(), 'environment': 'GitHub macOS runner', 'playback_verified': False, 'requests': []}

def probe(name, url, summarize, headers=None):
    item = {'name': name, 'url': url}
    try:
        request = Request(url, headers={'User-Agent': 'AnimeApp/0.8 (iOS client)', 'Accept': 'application/json, text/html;q=0.9', **(headers or {})})
        with urlopen(request, timeout=20) as response:
            body = response.read(12_000_001)
            item.update(status=response.status, final_url=response.url)
            if len(body) > 12_000_000:
                raise ValueError('Response exceeds limit')
            item['result'] = summarize(body)
    except HTTPError as error:
        item.update(status=error.code, error=str(error), final_url=error.url)
    except Exception as error:
        item['error'] = str(error)
    report['requests'].append(item)
    print(json.dumps(item, ensure_ascii=False))

probe('Shikimori search', 'https://shikimori.io/api/animes?search=naruto&limit=3', lambda body: [{'id': x['id'], 'title': x.get('russian') or x['name']} for x in json.loads(body)])
probe('Shikimori clips', 'https://shikimori.io/api/animes/1735/videos', lambda body: {'clips': len(json.loads(body)), 'kinds': sorted({x['kind'] for x in json.loads(body)})})
probe('AnimeLIB search', 'https://hapi.hentaicdn.org/api/anime?q=naruto&site_id%5B%5D=5', lambda body: [{'id': x['id'], 'title': x.get('rus_name') or x['name'], 'shikimori_href': x.get('shikimori_href')} for x in json.loads(body)['data'][:3]], {'Site-Id': '5', 'Content-Type': 'application/json', 'Client-Time-Zone': 'UTC', 'Origin': 'https://animelib.org', 'Referer': 'https://animelib.org/'})
probe('AnimeLIB episodes', 'https://hapi.hentaicdn.org/api/episodes?anime_id=11--naruto-anime', lambda body: {'episodes': len(json.loads(body)['data'])}, {'Site-Id': '5', 'Content-Type': 'application/json', 'Client-Time-Zone': 'UTC', 'Origin': 'https://animelib.org', 'Referer': 'https://animelib.org/'})
probe('AnimeLIB episode 455 translations', 'https://hapi.hentaicdn.org/api/episodes/455', lambda body: [{'player': x['player'], 'studio': (x.get('team') or {}).get('name'), 'translation': (x.get('translation_type') or {}).get('label'), 'returns_embed': bool(x.get('src'))} for x in json.loads(body)['data']['players']], {'Site-Id': '5', 'Content-Type': 'application/json', 'Client-Time-Zone': 'UTC', 'Origin': 'https://animelib.org', 'Referer': 'https://animelib.org/'})
for address in ['https://animego.me', 'https://animego.org']:
    probe('AnimeGO public search', address + '/search/anime?q=naruto', lambda body: {'bytes': len(body), 'has_anime_links': b'/anime/' in body})
with open('sources-report.json', 'w') as file:
    json.dump(report, file, ensure_ascii=False, indent=2)
