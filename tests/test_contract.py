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

    def test_aniskip(self):
        result = self.get('https://api.aniskip.com/v2/skip-times/1735/1?types=op&types=ed&episodeLength=0')
        self.assertTrue(result['found'])
        for entry in result['results']:
            self.assertGreater(entry['interval']['endTime'], entry['interval']['startTime'])
            self.assertGreater(entry['episodeLength'], 0)

if __name__ == '__main__':
    unittest.main()
