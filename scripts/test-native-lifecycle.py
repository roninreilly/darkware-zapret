#!/usr/bin/env python3
"""Run the real supervisor/watchdog scripts against isolated command stubs.
No privileged command from the host is executed. All writes stay in .build/.
"""
import os
import pathlib
import signal
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
(ROOT / '.build').mkdir(exist_ok=True)

def wait_for(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    raise AssertionError('Timed out waiting for native lifecycle event')

with tempfile.TemporaryDirectory(prefix='lifecycle-', dir=ROOT / '.build') as tmp:
    fixture = pathlib.Path(tmp)
    stub_engine = fixture / 'engine.c'
    stub_engine.write_text(r'''
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
  if(argc != 2 || argv[1][0]!='@') return 2;
  FILE *f=fopen(argv[1]+1,"r"); if(!f) return 2;
  char buf[65536]; size_t n=fread(buf,1,sizeof(buf)-1,f); fclose(f); buf[n]=0;
  if(strstr(buf,"--dry-run")) return 0;
  char path[4096]; snprintf(path,sizeof(path),"%s/utun-up",getenv("MOCK_ROOT"));
  f=fopen(path,"w"); if(!f) return 2; fclose(f);
  for(;;) pause();
}
''')
    compiled = fixture / 'engine'
    subprocess.run(['xcrun', 'clang', '-Os', str(stub_engine), '-o', str(compiled)], check=True)
    for scenario in ('engine-exit', 'supervisor-kill', 'pf-load-failure', 'network-change'):
        case = fixture / scenario
        base, runtime, mocks = case / 'service with spaces', case / 'run', case / 'mocks'
        for directory in (base / 'bin', base / 'strategies', base / 'lists', runtime, mocks):
            directory.mkdir(parents=True, exist_ok=True)
        (base / 'bin/utunws').write_bytes(compiled.read_bytes())
        (base / 'bin/utunws').chmod(0o755)
        (base / 'selected-strategy').write_text('general-simple-fake\n')
        (base / 'ipset-mode').write_text('none\n')
        (base / 'strategies/general-simple-fake.conf.in').write_text('--filter-tcp=443\n')
        dispatcher = mocks / 'dispatch.py'
        dispatcher.write_text('''#!/usr/bin/python3
import os,pathlib,subprocess,sys
root=pathlib.Path(os.environ['MOCK_ROOT'])
name=pathlib.Path(sys.argv[0]).name
a=sys.argv[1:]
if name=='id': print('0')
elif name=='stat': print('0' if a[1]=='%u' else '755')
elif name=='ps':
    p=subprocess.run(['/bin/ps']+a,text=True,capture_output=True)
    if p.returncode: sys.exit(p.returncode)
    print('1' if a[-1]=='uid=' else p.stdout.strip())
elif name=='ifconfig':
    if not (root/'utun-up').exists(): sys.exit(1)
elif name=='route':
    print('interface: en1' if (root/'network-changed').exists() else 'interface: en0')
    print('gateway: 192.0.2.1')
elif name=='arp': print('? (192.0.2.1) at 0:1:2:3:4:5 on en0')
elif name=='pfctl':
    with (root/'pf.log').open('a') as f: f.write(' '.join(a)+'\\n')
    if a==['-sr']: print('anchor "com.apple/*" all')
    if a==['-E']: print('Token : 12345')
    if '-f' in a:
        sys.stdin.read()
        if os.environ['MOCK_SCENARIO']=='pf-load-failure': sys.exit(1)
elif name in ('netstat','ping'): pass
else: raise RuntimeError(name)
''')
        dispatcher.chmod(0o755)
        replacements = {
            '/Library/Application Support/DarkwareZapret': str(base),
            '/var/run/com.darkware.zapret.packet.control': str(case / 'control'),
            '/var/run/com.darkware.zapret.packet': str(runtime),
        }
        for path in ('/usr/bin/id', '/usr/bin/stat', '/bin/ps', '/sbin/ifconfig', '/sbin/route',
                     '/usr/sbin/arp', '/sbin/pfctl', '/usr/sbin/netstat', '/sbin/ping'):
            link = mocks / pathlib.Path(path).name
            link.symlink_to(dispatcher)
            replacements[path] = str(link)
        for name in ('common.sh', 'run.sh', 'watchdog.sh'):
            source = (ROOT / 'native' / name).read_text()
            for old, new in replacements.items():
                source = source.replace(old, new)
            # Fail closed if a privileged binary/path escaped the fixture rewrite.
            assert '/sbin/' not in source and '/usr/sbin/' not in source
            (base / name).write_text(source)
        env = dict(os.environ, MOCK_ROOT=str(case), MOCK_SCENARIO=scenario)
        log = (case / 'output.log').open('w')
        process = subprocess.Popen(['/bin/sh', str(base / 'run.sh')], env=env,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            if scenario == 'pf-load-failure':
                process.wait(timeout=8)
                assert process.returncode != 0
            else:
                wait_for(lambda: (runtime / 'ready').exists())
                if scenario == 'engine-exit':
                    os.kill(int((runtime / 'engine.pid').read_text()), signal.SIGTERM)
                elif scenario == 'supervisor-kill':
                    process.kill()
                else:
                    (case / 'network-changed').touch()
                process.wait(timeout=8)
            wait_for(lambda: not (runtime / 'ready').exists())
            wait_for(lambda: '-X 12345' in (case / 'pf.log').read_text())
            pf = (case / 'pf.log').read_text().splitlines()
            assert any('-a com.apple/darkware-zapret -f -' == line for line in pf), pf
            assert any('-a com.apple/darkware-zapret -F all' == line for line in pf), pf
            assert not (runtime / 'pf-token').exists()
        except Exception:
            log.flush()
            print((case / 'output.log').read_text())
            raise
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            process.wait(timeout=5)
            log.close()
        print(f'Native lifecycle mock passed: {scenario}')
