'use strict';
// --version exits before V8 initializes. This script must actually execute on
// the built target, exercising the main and a second V8 context before upload.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const vm = require('node:vm');
const zlib = require('node:zlib');
const expected = {
  ppc64le: 'ppc64', s390x: 's390x',
  'android-arm64': 'arm64', 'android-armv7': 'arm', 'android-x64': 'x64', 'android-x86': 'ia32',
}[process.argv[2]];
if (expected) assert.equal(process.arch, expected, 'built runtime has wrong architecture');
// Android (run inside Termux): the platform is android, and dist/android's
// paths patch put the temporary directory in Termux's prefix, not /tmp.
if (String(process.argv[2]).startsWith('android-')) {
  assert.equal(process.platform, 'android', 'built runtime is not an Android build');
  if (!process.env.TMPDIR) {
    assert.equal(require('node:os').tmpdir(), '/data/data/com.termux/files/usr/tmp', 'tmpdir falls back to Termux');
  }
}
assert.equal(vm.runInNewContext('Array.from({length: 1024}, (_, i) => i).reduce((a,b) => a+b,0)'), 523776);
assert.equal(JSON.parse(JSON.stringify({ text: 'WeKan ✓', value: 123 })).text, 'WeKan ✓');
const bytes = Buffer.from('Node runtime initialization and builtin smoke');
assert.deepEqual(zlib.gunzipSync(zlib.gzipSync(bytes)), bytes);
assert.equal(crypto.createHash('sha256').update('abc').digest('hex'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
setImmediate(() => console.log(`runtime-smoke: ${process.version} ${process.platform}/${process.arch} JavaScript, V8 contexts, crypto and zlib passed`));
