#!/usr/bin/env python3
"""Exercise the real cross-qemu shell block without an hours-long Node build."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = yaml.safe_load((ROOT / '.github/workflows/release-all.yml').read_text())
JOB = WORKFLOW['jobs']['build']


class RuntimeWorkflowTest(unittest.TestCase):
    def test_ppc64le_and_s390x_use_real_target_tools_and_mandatory_smoke(self):
        matrix = {row['platform']: row for row in JOB['strategy']['matrix']['include']}
        steps = JOB['steps']
        step = next(s for s in steps if s.get('name') == 'Build (cross compile, run target build-tools under qemu-user)')
        self.assertNotIn('continue-on-error', step)
        self.assertIn("matrix.mode == 'cross-qemu'", step['if'])
        upload_index = next(i for i, s in enumerate(steps) if str(s.get('uses', '')).startswith('actions/upload-artifact@'))
        self.assertLess(steps.index(step), upload_index)
        for platform in ('ppc64le', 's390x'):
            row = matrix[platform]
            self.assertEqual(row['mode'], 'cross-qemu')
            self.assertIn('sh _patches/tests/runtime-smoke.sh ./out/Release/node', step['run'])
            for status in (0, 133):
                with self.subTest(platform=platform, runtime_status=status), tempfile.TemporaryDirectory(prefix='node-runtime-workflow-') as directory:
                    work = Path(directory)
                    (work / '_patches').symlink_to(ROOT, target_is_directory=True)
                    (work / 'bin').mkdir()
                    (work / 'out/Release').mkdir(parents=True)
                    def executable(name, contents):
                        path = work / name
                        path.write_text(contents)
                        path.chmod(0o755)
                    executable('bin/docker', '''#!/usr/bin/env python3
import os, subprocess, sys
args=sys.argv[1:]; env=dict(os.environ)
for i,arg in enumerate(args):
 if arg=='-e':
  key,value=args[i+1].split('=',1);env[key]=value
script=args[args.index('-c')+1]
raise SystemExit(subprocess.call(['sh','-c',script],env=env))
''')
                    executable('bin/apt-get', '#!/bin/sh\nexit 0\n')
                    executable('bin/make', '''#!/bin/sh
# The actual configure-edit-check block must select target build tools.
grep -qE 'want_separate_host_toolset.: *0' config.gypi
''')
                    executable('bin/' + row['triple'] + '-strip', '#!/bin/sh\nexit 0\n')
                    executable('configure', '''#!/bin/sh
printf '%s\n' '{"want_separate_host_toolset": 1}' > config.gypi
''')
                    executable('out/Release/node', '''#!/bin/sh
if [ "$1" = --version ]; then echo v24.20.0; exit 0; fi
case "$1" in */runtime-smoke.cjs) ;; *) exit 99 ;; esac
[ "$2" = "$EXPECTED_TARGET" ] || exit 98
printf 'JavaScript invoked\n' > runtime-invoked
exit "$RUNTIME_STATUS"
''')
                    script = re.sub(r'\$\{\{ matrix\.([a-z_]+) \}\}', lambda m: str(row.get(m[1], '')), step['run'])
                    env = dict(os.environ, PATH=str(work / 'bin') + os.pathsep + os.environ['PATH'], EXPECTED_TARGET=platform, RUNTIME_STATUS=str(status))
                    # A --version-only gate would pass even for the broken fixture.
                    self.assertEqual(subprocess.run([str(work / 'out/Release/node'), '--version'], env=env, capture_output=True).returncode, 0)
                    result = subprocess.run(['bash', '-c', script], cwd=work, env=env, text=True, capture_output=True)
                    self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                    self.assertTrue((work / 'runtime-invoked').exists())


if __name__ == '__main__':
    unittest.main()
