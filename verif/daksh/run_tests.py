from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'verif/daksh'
TESTS = ROOT / 'verif/tests/pipeline_tests'
OUT = HERE / 'build'
NAMES = ['load_use', 'raw_distance', 'branch_delay', 'jalr_flush', 'x0_hazard']


def command(args, log=None):
    result = subprocess.run([str(a) for a in args], cwd=ROOT,
                            text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=300)
    if log:
        log.write_text(result.stdout)
    if result.returncode:
        print(result.stdout)
        raise RuntimeError(f'Command failed: {args[0]}')
    return result.stdout


def build_images():
    for name in NAMES:
        obj, elf, binary = [OUT / (name + suffix)
                            for suffix in ['.o', '.elf', '.bin']]
        command(['riscv64-unknown-elf-as', '-march=rv32i', '-mabi=ilp32',
                 '-I', TESTS, '-o', obj, TESTS / (name + '.s')])
        command(['riscv64-unknown-elf-ld', '-m', 'elf32lriscv', '--no-relax',
                 '-T', HERE / 'link.ld', '-o', elf, obj])
        command(['riscv64-unknown-elf-objcopy', '-O', 'binary', elf, binary])

        data = binary.read_bytes()
        data += bytes((-len(data)) % 4)
        if len(data) > 4000:
            raise RuntimeError('Program exceeds the starter memory loader capacity')
        words = [f'{int.from_bytes(data[i:i+4], "little"):08x}'
                 for i in range(0, len(data), 4)]
        (TESTS / (name + '.x')).write_text('\n'.join(words) + '\n')
        print('Built', name + '.x')


def run_tests():
    for name in NAMES:
        if not (TESTS / (name + '.x')).exists():
            raise RuntimeError('Build the .x inputs first')

    obj = OUT / 'obj_dir'
    command(['verilator', '--binary', '--timing', '--assert', '-Wno-fatal',
             '--timescale', '1ns/1ps', '-I' + str(ROOT / 'code'),
             '-DMEM_DEPTH=1048576', '--top-module', 'tb_daksh',
             '--Mdir', obj, '-j', '2', HERE / 'tb_daksh.sv',
             *sorted((ROOT / 'code').glob('*.sv'))], OUT / 'compile.log')

    for name in NAMES:
        output = command([obj / 'Vtb_daksh', '+TEST=' + name,
                          '+MEM_PATH=' + str(TESTS / (name + '.x'))],
                         OUT / (name + '.log'))
        if f'daksh_pass {name}' not in output:
            raise RuntimeError(f'{name}: no PASS marker; inspect its log')
        print('PASS', name)

    print('All five functional tests passed. Pipeline assertions await integration.')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        if sys.argv[1:] == ['build']:
            build_images()
        elif sys.argv[1:] == ['run']:
            run_tests()
        else:
            raise RuntimeError('Usage: python3 verif/daksh/run_tests.py build|run')
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        print('FAIL:', error)
        sys.exit(1)
