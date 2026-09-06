#!/usr/bin/env python3
"""Exercise the real player and compact UI on a disposable emulator, using demo data."""
import argparse
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--adb', default='adb')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]


def adb(*command):
    return subprocess.check_output([args.adb, '-s', args.serial, *command], text=True)


def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/telisten-smoke.xml')
    return list(ET.fromstring(adb('shell', 'cat', '/sdcard/telisten-smoke.xml')).iter('node'))


def find(value, desc=False):
    for node in nodes():
        if node.get('content-desc' if desc else 'text') == value:
            return node
    raise AssertionError(f'UI element not found: {value}')


def bounds(node):
    return tuple(map(int, re.findall(r'\d+', node.get('bounds'))))


def tap_node(node):
    x1, y1, x2, y2 = bounds(node)
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    time.sleep(.3)


def tap(value, desc=False):
    tap_node(find(value, desc))


def media_state(expected):
    for _ in range(12):
        output = adb('shell', 'dumpsys', 'media_session')
        own = output.split('package=ad.neko.player', 1)[-1].split('metadata:', 1)[0]
        if f'state={expected}' in own:
            return own
        time.sleep(.5)
    raise AssertionError(f'Expected {expected}: {own}')


def shot(name):
    (root/'screenshots').mkdir(exist_ok=True)
    with (root/'screenshots'/name).open('wb') as output:
        subprocess.run([args.adb, '-s', args.serial, 'exec-out', 'screencap', '-p'], stdout=output, check=True)


# Refuse to clear/relaunch a personal phone session as a fixture test.
assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == '1', 'Run this fixture test on an emulator.'
adb('shell', 'am', 'force-stop', 'ad.neko.player')
adb('shell', 'am', 'start', '-n', 'ad.neko.player/ad.neko.telisten.MainActivity', '--ez', 'demo', 'true')
time.sleep(3)
find('Songs')
# Six songs and both main navigation levels must fit on the initial phone screen.
initial = nodes()
nav_top = bounds(next(n for n in initial if n.get('text') == 'Library'))[1]
for title in ['Warm light', 'A slower pace', 'Between the trees', 'Blue hour', 'Little things', 'Stay a while']:
    song = next(n for n in initial if n.get('text') == title)
    assert bounds(song)[3] < nav_top, f'{title} was pushed off the first screen'
shot('library.png')

# Favorites are reachable directly from each row.
tap('Favorite Warm light', True)
tap('Favorites')
find('Warm light')
tap('Library')

# Collections are separate from songs; choosing a source opens its tracks.
tap('Playlists')
find('Soft focus')
shot('playlists.png')
tap('Chats')
tap('The listening room')
find('Warm light')
tap('Back to library', True)

# Search, clear, and empty-state behavior.
tap('Search library', True)
adb('shell', 'input', 'text', 'zzzzzz')
tap('Search', True)
find('No matching songs')
tap('Clear search', True)
find('Warm light')

# This plays the actual local PCM fixture through Media3.
tap('Shuffle all', True)
media_state('PLAYING')
time.sleep(2)
state = media_state('PLAYING')
assert 'speed=1.0' in state
assert any(re.fullmatch(r'0:(?:0[1-9]|[12][0-9])', n.get('text', '')) for n in nodes())
# Lyrics and transport controls should be visible together without scrolling.
find('Pause', True)
find('A little room to breathe')
shot('player.png')
tap('Shuffle', True)
tap('Repeat one')
adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
media_state('PLAYING')
adb('shell', 'cmd', 'media_session', 'dispatch', 'pause')
media_state('PAUSED')
adb('shell', 'cmd', 'media_session', 'dispatch', 'play')
media_state('PLAYING')
adb('shell', 'am', 'start', '-n', 'ad.neko.player/ad.neko.telisten.MainActivity')
time.sleep(.6)
tap('Pause', True)
media_state('PAUSED')
slider = next(n for n in nodes() if n.get('class') == 'android.widget.SeekBar')
x1, y1, x2, y2 = bounds(slider)
adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
time.sleep(.5)
state = media_state('PAUSED')
assert 10000 < int(re.search(r'position=(\d+)', state).group(1)) < 20000

tap('Queue')
find('Move Warm light down', True)
shot('queue.png')
tap('Move Warm light down', True)
tap('Minimize player', True)
tap('Downloads')
find('Between the trees')
shot('downloads.png')
tap('Library')
tap('Settings', True)
find('Settings')
shot('settings.png')
adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
print('PASS: compact first screen, favorites, collections, search/clear, player/lyrics, repeat, background media keys, seek, queue reordering, downloads, settings')
