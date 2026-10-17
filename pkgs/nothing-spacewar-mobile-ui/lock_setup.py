import copy
import hashlib
import json
import os
from pathlib import Path

LINE = 'dofile("/usr/share/nothing-spacewar/mobile/phone-lock.lua") -- spacewar-lock\n'
OWNED = ['spacewar.lock', 'omarchy.lock']


def check_upstream(root, upstream):
    expected = json.loads((root / 'lock-upstream.json').read_text())
    for name, digest in expected.items():
        path = upstream / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'lock drift from r7031: {path}; review/rebase before --lock')


def configure(config, state, root, atomic, encode, load_config, undo=False):
    journal = state / 'lock-setup.json'
    shell = config / 'omarchy/shell.json'
    lua = config / 'hypr/hyprland.lua'
    link = config / 'omarchy/plugins/spacewar.lock'
    # r7031's idle service deliberately uses HOME, not XDG_STATE_HOME.
    markers = [Path.home() / '.local/state/omarchy/indicators/stay-awake',
               Path.home() / '.local/state/omarchy/toggles/screensaver-off']
    for path in [shell, lua, *markers]:
        if path.is_symlink():
            raise ValueError(f'refusing symlink: {path}')
    raw = shell.read_text() if shell.exists() else None
    current = load_config(raw)
    lua_raw = lua.read_text() if lua.exists() else None
    if undo:
        if not journal.exists():
            return
        saved = json.loads(journal.read_text())
        original = load_config(saved['shell'])
        if current == saved['applied']:
            if saved['shell'] is None: shell.unlink(missing_ok=True)
            else: atomic(shell, saved['shell'])
        else:
            for key in ['plugins', 'disabledPlugins']:
                ident = lambda e: e.get('id') if isinstance(e, dict) else e
                current[key] = [e for e in current.get(key, []) if ident(e) not in OWNED]
                current[key] += [e for e in original.get(key, []) if ident(e) in OWNED]
                if not current[key] and key not in original: current.pop(key)
            for key, value in saved['applied']['idle'].items():
                if current.get('idle', {}).get(key) == value:
                    if key in original.get('idle', {}): current['idle'][key] = original['idle'][key]
                    else: current['idle'].pop(key, None)
            if not current.get('idle') and 'idle' not in original: current.pop('idle', None)
            atomic(shell, encode(current))
        if lua_raw == saved['lua_applied']:
            if saved['lua'] is None: lua.unlink(missing_ok=True)
            else: atomic(lua, saved['lua'])
        elif lua_raw is not None: atomic(lua, lua_raw.replace(LINE, ''))
        if saved['link'] and link.is_symlink() and os.readlink(link) == str(root / 'plugins/spacewar.lock'):
            link.unlink()
        for path, value in zip(markers, saved['markers']):
            if not path.exists() and value is not None: atomic(path, value)
        # An explicit rollback always disables idle locking, including recovery
        # after an interrupted enable which removed the original marker.
        if not markers[0].exists(): atomic(markers[0], '')
        journal.unlink()
        return
    check_upstream(root, Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell/plugins/lock')
    if journal.exists():
        print('Spacewar lock already configured; leaving user changes intact.')
        return
    if not (root / 'plugins/spacewar.lock/manifest.json').is_file():
        raise ValueError('missing installed spacewar.lock plugin')
    if os.path.lexists(link) and not (link.is_symlink() and os.readlink(link) == str(root / 'plugins/spacewar.lock')):
        raise ValueError(f'plugin path already owned by user: {link}')
    applied = copy.deepcopy(current)
    if not isinstance(applied.get('idle', {}), dict): raise ValueError('idle must be an object')
    applied.setdefault('idle', {}).update(lock=60, screensaver=0)
    applied['plugins'] = [e for e in applied.get('plugins', []) if e['id'] != 'spacewar.lock'] + [{'id': 'spacewar.lock'}]
    applied['disabledPlugins'] = [e for e in applied.get('disabledPlugins', []) if e not in OWNED] + ['omarchy.lock']
    lua_applied = lua_raw or ''
    if LINE not in lua_applied: lua_applied += ('' if not lua_applied or lua_applied.endswith('\n') else '\n') + LINE
    saved = dict(shell=raw, applied=applied, lua=lua_raw, lua_applied=lua_applied,
                 link=not os.path.lexists(link), markers=[p.read_text() if p.exists() else None for p in markers])
    atomic(journal, encode(saved))
    link.parent.mkdir(parents=True, exist_ok=True)
    if saved['link']: link.symlink_to(root / 'plugins/spacewar.lock')
    atomic(lua, lua_applied)
    atomic(shell, encode(applied))
    for path in markers: path.unlink(missing_ok=True)
    print('Spacewar lock enabled; reload Hyprland and restart the unlocked shell. Idle lock: 60 seconds.')


if __name__ == '__main__':
    check_upstream(Path(__file__).resolve().parent,
                   Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell/plugins/lock')
