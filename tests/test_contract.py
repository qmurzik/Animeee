"""Live provider contract smoke tests; these do not test iOS playback."""
import json
import unittest
from urllib.request import urlopen, Request

class ProviderContract(unittest.TestCase):
    def get(self, url):
        with urlopen(Request(url, headers={'User-Agent': 'curl/8.0'}), timeout=20) as response:
            self.assertEqual(response.status, 200)
            return json.load(response)

    def test_catalog_search_release_and_playlist(self):
        base = 'https://anilibria.top/api/v1/'
        latest = self.get(base + 'anime/releases/latest?limit=1')
        self.assertTrue(latest)
        self.assertIsInstance(latest[0]['name']['main'], str)
        search = self.get(base + 'app/search/releases?query=naruto')
        self.assertTrue(search)
        release = self.get(base + 'anime/releases/10172')
        self.assertEqual(release['id'], 10172)
        episode = next(e for e in release['episodes'] if e.get('hls_480'))
        with urlopen(episode['hls_480'], timeout=20) as response:
            self.assertEqual(response.status, 200)
            self.assertTrue(response.read(256).startswith(b'#EXTM3U'))

    def test_yummyanime_matching_and_voices(self):
        from urllib.parse import urlencode
        query = urlencode({'q': 'Наруто Ураганные хроники', 'limit': 50})
        results = self.get('https://api.yani.tv/anime?' + query)['response']
        matches = [x for x in results if (x.get('remote_ids') or {}).get('myanimelist_id') == 1735]
        self.assertEqual(len(matches), 1)
        videos = self.get('https://api.yani.tv/anime/' + str(matches[0]['anime_id']) + '/videos')['response']
        playable_pages = [x for x in videos if isinstance(x.get('iframe_url'), str) and x['iframe_url'].startswith(('https://', '//'))]
        self.assertTrue(playable_pages)
        self.assertTrue(any((x.get('data') or {}).get('dubbing') for x in playable_pages))

    def test_aksor_dash_manifest(self):
        from urllib.parse import quote
        import xml.etree.ElementTree as ET
        payload = self.get('https://player.aksor.tv/api/video/8d4b9ff83b37b94e542c49fa3a8d2286')
        address = next(x for x in payload['qualities'].values() if x)
        with urlopen(quote(address, safe=':/?=&%'), timeout=20) as response:
            manifest = response.read()
        root = ET.fromstring(manifest)
        self.assertTrue(root.tag.endswith('MPD'))
        self.assertNotIn(b'ContentProtection', manifest)

    def test_cvh_exact_studio_and_mp4(self):
        playlist = self.get('https://plapi.cdnvideohub.com/api/v1/player/sv/playlist?pub=745&id=51404&aggr=mali')
        matches = [x for x in playlist['items'] if x.get('voiceStudio') == 'FumoDub']
        self.assertEqual(len(matches), 1)
        payload = self.get('https://plapi.cdnvideohub.com/api/v1/player/sv/video/' + matches[0]['vkId'])
        address = payload['sources']['mpegMediumUrl']
        with urlopen(Request(address, headers={'Range': 'bytes=0-1023'}), timeout=20) as response:
            self.assertIn(response.status, (200, 206))
            self.assertTrue(response.read(64))

    def test_aniskip(self):
        result = self.get('https://api.aniskip.com/v2/skip-times/1735/1?types=op&types=ed&episodeLength=0')
        self.assertTrue(result['found'])
        for entry in result['results']:
            self.assertGreater(entry['interval']['endTime'], entry['interval']['startTime'])
            self.assertGreater(entry['episodeLength'], 0)

if __name__ == '__main__':
    unittest.main()
