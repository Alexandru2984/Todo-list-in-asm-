"""Public rendering resources stay crawlable while private application paths do not."""
from html.parser import HTMLParser
from pathlib import Path
import unittest
from urllib.robotparser import RobotFileParser

ROOT=Path(__file__).resolve().parents[1]


class Resources(HTMLParser):
    def __init__(self,text):
        super().__init__();self.urls=[];self.feed(text)
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='script' and 'src' in attrs:self.urls.append(attrs['src'])
        if tag=='link' and attrs.get('rel')=='stylesheet':self.urls.append(attrs['href'])


class PublicSEOTests(unittest.TestCase):
    def test_public_home_can_render_under_robots_policy_without_allowing_private_routes(self):
        robots=RobotFileParser();robots.parse((ROOT/'web/robots.txt').read_text().splitlines())
        resources=Resources((ROOT/'web/index.html').read_text()).urls
        self.assertTrue(resources)
        for path in ['/',*resources]:
            with self.subTest(path=path):self.assertTrue(robots.can_fetch('Googlebot','https://asm.micutu.com'+path))
        for path in ['/app','/app?f=all','/export.json','/export.csv','/recovery','/stats.svg','/import-preview','/board/complete']:
            with self.subTest(path=path):self.assertFalse(robots.can_fetch('Googlebot','https://asm.micutu.com'+path))
