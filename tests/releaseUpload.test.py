#!/usr/bin/env python3
"""Each build attaches its own files to the release as soon as it is done.

The binaries used to reach the GitHub Release only in a final job that waited
for all sixteen builds, so a platform built in twenty minutes waited hours for
the slowest one, and a cancelled run attached nothing at all. These tests pin
the shape that replaced it, with a negative test for each rule:

* the build job's LAST step attaches that platform's files, through
  releases/upload-release-assets.sh, with contents: write and the tag of the
  job that creates the release;
* that step runs also when the run is cancelled after the build succeeded
  (always() gated on the naming step's own outcome);
* the final job uploads nothing, runs with always() (not !cancelled()) and
  needs only the release job to have succeeded;
* the upload script itself, run against a fake gh: binaries before checksums,
  retries, size check, and refusal of a missing file.

  python3 -B tests/releaseUpload.test.py
"""
import copy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
ALL = ROOT / '.github/workflows/release-all.yml'
MISSING = ROOT / '.github/workflows/release-all-missing.yml'
SCRIPT = ROOT / 'releases/upload-release-assets.sh'
ATTACH = "Attach this platform's files to the release"


def load(path):
    return yaml.safe_load(path.read_text())


def problems(doc):
    """Everything that breaks 'each build attaches its own files', as text."""
    out = []
    jobs = doc.get('jobs') or {}
    build, publish, release = jobs.get('build') or {}, jobs.get('publish') or {}, jobs.get('release') or {}
    if 'tag' not in (release.get('outputs') or {}):
        out.append('no release job hands out the tag')
    needs = build.get('needs')
    needs = [needs] if isinstance(needs, str) else (needs or [])
    if 'release' not in needs:
        out.append('the build job does not need the release job')
    if (build.get('permissions') or {}).get('contents') != 'write':
        out.append('the build job lacks contents: write')
    steps = build.get('steps') or []
    if not steps or steps[-1].get('name') != ATTACH:
        out.append('attaching is not the last step of the build job')
    else:
        step = steps[-1]
        cond = str(step.get('if', ''))
        run = str(step.get('run', ''))
        if 'releases/upload-release-assets.sh' not in run:
            out.append('the attach step does not use upload-release-assets.sh')
        if 'needs.release.outputs.tag' not in str(step.get('env', {}).get('TAG', '')):
            out.append('the attach step does not take the tag from the release job')
        if 'always()' not in cond:
            out.append('the attach step does not run when the run is cancelled')
        named = [s.get('id') for s in steps if str(s.get('name', '')).startswith('Name it for the release')]
        if not named or not all(i and ("steps.%s.outcome == 'success'" % i) in cond for i in named):
            out.append('the attach step is not gated on the naming step succeeding')
        if 'inputs.publish' not in cond:
            out.append('the attach step ignores the publish input')
    pcond = str(publish.get('if', ''))
    if 'always()' not in pcond or '!cancelled()' in pcond:
        out.append('the final job does not run with always()')
    if "needs.release.result == 'success'" not in pcond:
        out.append('the final job does not require the release job to have succeeded')
    for s in publish.get('steps') or []:
        text = str(s.get('run', '')) + str(s.get('uses', ''))
        if 'gh release upload' in text or 'gh release create' in text or 'download-artifact' in text:
            out.append('the final job still uploads binaries: %s' % s.get('name', s.get('uses')))
    return out


class WorkflowShapeTest(unittest.TestCase):
    def test_release_all_attaches_per_build(self):
        self.assertEqual(problems(load(ALL)), [])

    def test_missing_workflow_builds_through_release_all(self):
        build = load(MISSING)['jobs']['build']
        self.assertEqual(build['uses'], './.github/workflows/release-all.yml')
        self.assertEqual(build['permissions']['contents'], 'write')
        self.assertIs(build['with']['publish'], True)

    # NEGATIVE: each regression this guards against must be noticed.
    def mutated(self, change):
        doc = copy.deepcopy(load(ALL))
        change(doc)
        return problems(doc)

    def test_old_final_upload_is_detected(self):
        def change(doc):
            doc['jobs']['build']['steps'].pop()
            doc['jobs']['publish']['steps'].append({'name': 'upload', 'run': 'gh release upload v1 dist/*'})
        found = self.mutated(change)
        self.assertIn('attaching is not the last step of the build job', found)
        self.assertTrue(any('still uploads binaries' in p for p in found))

    def test_attach_not_last_is_detected(self):
        def change(doc):
            steps = doc['jobs']['build']['steps']
            steps.insert(0, steps.pop())
        self.assertIn('attaching is not the last step of the build job', self.mutated(change))

    def test_attach_skipped_on_cancel_is_detected(self):
        def change(doc):
            step = doc['jobs']['build']['steps'][-1]
            step['if'] = step['if'].replace('always() && ', '')
        self.assertIn('the attach step does not run when the run is cancelled', self.mutated(change))

    def test_attach_ungated_always_is_detected(self):
        def change(doc):
            doc['jobs']['build']['steps'][-1]['if'] = "${{ always() && inputs.publish }}"
        self.assertIn('the attach step is not gated on the naming step succeeding', self.mutated(change))

    def test_final_job_not_cancelled_is_detected(self):
        def change(doc):
            doc['jobs']['publish']['if'] = "${{ !cancelled() && inputs.publish && needs.release.result == 'success' }}"
        self.assertIn('the final job does not run with always()', self.mutated(change))

    def test_final_job_without_release_requirement_is_detected(self):
        def change(doc):
            doc['jobs']['publish']['if'] = '${{ always() && inputs.publish }}'
        self.assertIn('the final job does not require the release job to have succeeded', self.mutated(change))

    def test_missing_permission_and_needs_are_detected(self):
        def change(doc):
            del doc['jobs']['build']['permissions']
            del doc['jobs']['build']['needs']
        found = self.mutated(change)
        self.assertIn('the build job lacks contents: write', found)
        self.assertIn('the build job does not need the release job', found)


FAKE_GH = r'''#!/usr/bin/env python3
# A fake gh: records uploads in $FAKE_STATE, fails the first $FAIL_FIRST uploads.
import json, os, sys
state_path = os.environ['FAKE_STATE']
state = json.load(open(state_path)) if os.path.exists(state_path) else {'assets': {}, 'log': [], 'uploads': 0}
args = sys.argv[1:]
if args[:2] == ['release', 'upload']:
    state['uploads'] += 1
    path = args[3]
    state['log'].append(os.path.basename(path))
    if state['uploads'] <= int(os.environ.get('FAIL_FIRST', '0')):
        json.dump(state, open(state_path, 'w')); sys.exit(1)
    size = os.path.getsize(path) + int(os.environ.get('SIZE_SKEW', '0'))
    state['assets'][os.path.basename(path)] = size
    json.dump(state, open(state_path, 'w')); sys.exit(0)
if args[:2] == ['release', 'view']:
    jq = args[args.index('--jq') + 1]
    name = jq.split('"')[1]
    if name in state['assets']:
        print(state['assets'][name])
    sys.exit(0)
sys.exit(3)
'''


class UploadScriptTest(unittest.TestCase):
    def run_script(self, files, **extra):
        work = Path(self.tmp.name)
        env = dict(os.environ, PATH=str(work / 'bin') + os.pathsep + os.environ['PATH'],
                   FAKE_STATE=str(work / 'state.json'), GH_REPO='wekan/node-patches',
                   UPLOAD_RETRY_DELAY='0', **extra)
        result = subprocess.run(['bash', str(SCRIPT), 'v26.9.0'] + files, cwd=work, env=env,
                                text=True, capture_output=True)
        state = {}
        if (work / 'state.json').exists():
            import json
            state = json.loads((work / 'state.json').read_text())
        return result, state

    def setUp(self):
        base = ROOT / '.tools/tmp'
        base.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix='node-upload-', dir=os.environ.get('TMPDIR') or str(base))
        work = Path(self.tmp.name)
        (work / 'bin').mkdir()
        (work / 'bin/gh').write_text(FAKE_GH)
        (work / 'bin/gh').chmod(0o755)
        (work / 'dist').mkdir()
        for name, body in (('node-win32.sha256sum', 'sum\n'), ('node-win32.exe', 'binary' * 100),
                           ('node-win32.lib.sha256sum', 'sum\n'), ('node-win32.lib', 'lib' * 10)):
            (work / 'dist' / name).write_text(body)
        self.files = ['dist/node-win32.sha256sum', 'dist/node-win32.exe',
                      'dist/node-win32.lib.sha256sum', 'dist/node-win32.lib']

    def tearDown(self):
        self.tmp.cleanup()

    def test_binaries_go_up_before_checksums(self):
        result, state = self.run_script(self.files)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state['log'], ['node-win32.exe', 'node-win32.lib',
                                        'node-win32.sha256sum', 'node-win32.lib.sha256sum'])
        self.assertEqual(len(state['assets']), 4)

    def test_transient_failure_is_retried(self):
        result, state = self.run_script(self.files, FAIL_FIRST='2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(state['assets']), 4)
        self.assertEqual(state['uploads'], 6)

    # NEGATIVE tests.
    def test_persistent_failure_fails_the_step(self):
        result, state = self.run_script(self.files, FAIL_FIRST='99', UPLOAD_ATTEMPTS='3')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state['uploads'], 3)
        self.assertEqual(state['assets'], {})

    def test_wrong_size_on_the_release_fails(self):
        result, _ = self.run_script(self.files, SIZE_SKEW='1', UPLOAD_ATTEMPTS='2')
        self.assertNotEqual(result.returncode, 0)

    def test_missing_file_uploads_nothing(self):
        result, state = self.run_script(self.files + ['dist/node-win32-not-built'])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state, {})

    def test_no_repository_refuses(self):
        work = Path(self.tmp.name)
        env = {k: v for k, v in os.environ.items() if k not in ('GH_REPO', 'GITHUB_REPOSITORY')}
        env['PATH'] = str(work / 'bin') + os.pathsep + env['PATH']
        env['FAKE_STATE'] = str(work / 'state.json')
        result = subprocess.run(['bash', str(SCRIPT), 'v26.9.0'] + self.files, cwd=work, env=env,
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((work / 'state.json').exists())


if __name__ == '__main__':
    unittest.main()
