"""In-memory gh double: tests never invoke GitHub or require credentials."""
import hashlib
import json
from pathlib import Path
import subprocess

OLD = 'a' * 40
NEW = 'b' * 40


class RunnerLost(BaseException):
    """Bypass ordinary rollback to model lost runners at individual API boundaries."""


class FakeGitHub:
    def __init__(self, existing=True, tag='nightly'):
        self.releases = {}
        self.tags = {}
        self.calls = []
        self.next_id = 10
        self.cut = None
        self.after = False
        self.exception = RunnerLost
        self.partial = False
        self.omit_digest = False
        self.on_call = None
        if existing:
            self.releases[tag] = {'id': 1, 'draft': False, 'name': 'old title', 'body': 'old notes',
                                  'prerelease': True, 'target_commitish': OLD,
                                  '_bytes': {'app.ipa': b'old ipa', 'unmanaged.txt': b'keep me'}}
            self.tags[tag] = OLD

    @staticmethod
    def error(args, text='HTTP 404: release not found'):
        raise subprocess.CalledProcessError(1, args, stderr=text)

    def view(self, tag):
        item = self.releases[tag]
        output = {key: value for key, value in item.items() if key != '_bytes'}
        output['assets'] = [{'name': name, 'size': len(data),
                             **({} if self.omit_digest else {'digest': 'sha256:' + hashlib.sha256(data).hexdigest()})}
                            for name, data in item['_bytes'].items()]
        return output

    def __call__(self, *args):
        self.calls.append(args)
        cut = len(self.calls) == self.cut
        if cut and not self.after:
            raise self.exception()
        result = self.execute(args)
        if self.on_call:
            self.on_call(self, args)
        if cut and self.after:
            raise self.exception()
        return result

    def execute(self, args):
        def value(flag):
            return args[args.index(flag) + 1]
        if args[0] == 'api':
            endpoint = next(a for a in args if a.startswith('repos/'))
            method = value('--method') if '--method' in args else 'GET'
            if '/releases/' in endpoint:
                identity = int(endpoint.rsplit('/', 1)[1])
                tag = next(t for t, r in self.releases.items() if r['id'] == identity)
                return json.dumps(self.view(tag))
            if endpoint.endswith('/heads/main'):
                return NEW
            if method == 'GET':
                tag = endpoint.split('/tags/', 1)[1]
                if tag not in self.tags:
                    self.error(args)
                return self.tags[tag]
            if method == 'POST':
                tag = next(a for a in args if a.startswith('ref=refs/tags/')).split('ref=refs/tags/', 1)[1]
            else:
                tag = endpoint.split('/tags/', 1)[1]
            if method == 'DELETE':
                self.tags.pop(tag, None)
            else:
                self.tags[tag] = next(a[4:] for a in args if a.startswith('sha='))
            return ''
        assert args[0] == 'release', args
        operation, tag = args[1:3]
        if operation == 'create':
            if tag in self.releases:
                self.error(args, 'already exists')
            self.releases[tag] = {'id': self.next_id, 'draft': '--draft' in args,
                                  'name': value('--title'), 'body': Path(value('--notes-file')).read_text(),
                                  'prerelease': '--prerelease' in args, 'target_commitish': value('--target'), '_bytes': {}}
            self.next_id += 1
            return ''
        if tag not in self.releases:
            self.error(args)
        item = self.releases[tag]
        if operation == 'view':
            return str(item['id'])
        if operation == 'edit':
            for flag, key in [('--title', 'name'), ('--target', 'target_commitish')]:
                if flag in args:
                    item[key] = value(flag)
            if '--notes-file' in args:
                item['body'] = Path(value('--notes-file')).read_text()
            for flag in ('draft', 'prerelease'):
                for boolean in ('true', 'false'):
                    if f'--{flag}={boolean}' in args:
                        item[flag] = boolean == 'true'
                if '--' + flag in args:
                    item[flag] = True
        elif operation == 'upload':
            for raw in args[3:]:
                if raw.startswith('--'):
                    continue
                path = Path(raw)
                item['_bytes'][path.name] = path.read_bytes()
                if self.partial and not tag.startswith('ci-transaction-'):
                    self.partial = False
                    raise self.exception()
        elif operation == 'download':
            folder = Path(value('--dir'))
            folder.mkdir(parents=True, exist_ok=True)
            name = value('--pattern')
            (folder / name).write_bytes(item['_bytes'][name])
        elif operation == 'delete-asset':
            item['_bytes'].pop(args[3], None)
        elif operation == 'delete':
            del self.releases[tag]
        else:
            raise AssertionError(args)
        return ''

    def save(self, path):
        releases = {tag: {**{k: v for k, v in data.items() if k != '_bytes'},
                          '_bytes': {n: b.hex() for n, b in data['_bytes'].items()}}
                    for tag, data in self.releases.items()}
        Path(path).write_text(json.dumps({'releases': releases, 'tags': self.tags, 'next_id': self.next_id}))

    @classmethod
    def load(cls, path):
        data = json.loads(Path(path).read_text())
        fake = cls(existing=False)
        fake.releases = data['releases']
        for item in fake.releases.values():
            item['_bytes'] = {name: bytes.fromhex(raw) for name, raw in item['_bytes'].items()}
        fake.tags = data['tags']
        fake.next_id = data['next_id']
        return fake
