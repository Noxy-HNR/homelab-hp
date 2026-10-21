"""Offline checks for the llama-server settings, unit and health script.

Nothing is built, downloaded or started. The health test runs a fake /health
server on loopback.
"""
import http.server
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import unittest

HERE = Path(__file__).resolve().parent
GIB = 1024 ** 3
# Environment names that llama.cpp v0.7.0 reads (common/arg.cpp), checked against that tag.
KNOWN_LLAMA_ARGS = {
    'LLAMA_ARG_MODEL', 'LLAMA_ARG_ALIAS', 'LLAMA_ARG_CTX_SIZE', 'LLAMA_ARG_HOST', 'LLAMA_ARG_PORT',
    'LLAMA_ARG_CORS_ORIGINS', 'LLAMA_ARG_THREADS', 'LLAMA_ARG_NUMA', 'LLAMA_ARG_LOAD_MODE',
    'LLAMA_ARG_N_PARALLEL', 'LLAMA_ARG_CACHE_RAM', 'LLAMA_ARG_FLASH_ATTN', 'LLAMA_ARG_JINJA',
    'LLAMA_ARG_ENDPOINT_METRICS', 'LLAMA_ARG_TIMEOUT', 'LLAMA_ARG_OFFLINE',
}
OWN_KEYS = {'HOMELAB_LLAMA_THREADS_BATCH', 'HOMELAB_LLAMA_MEMORY_HIGH', 'HOMELAB_LLAMA_MEMORY_MAX'}
# Sizes rounded up from the published GGUF files.
MODEL_BYTES = {'gpt-oss-20b': 13 * GIB, 'gpt-oss-120b': 61 * GIB}


def size(value):
    number, unit = re.fullmatch(r'(\d+)([KMGT]?)', value).groups()
    return int(number) * 1024 ** ' KMGT'.index(unit or ' ')


def profiles():
    """Return the active settings and the commented 96 GB profile as dicts."""
    active, upgrade, in_upgrade = {}, {}, False
    for line in (HERE / 'llama-server.env.example').read_text(encoding='utf-8').splitlines():
        if 'After the 96 GB upgrade' in line:
            in_upgrade = True
        match = re.fullmatch(r'(#\s*)?([A-Z_]+)=(.*)', line)
        if not match:
            continue
        commented, key, value = match.groups()
        if not commented:
            active[key] = value
        elif in_upgrade:
            upgrade[key] = value
    return active, {**active, **upgrade}


class Settings(unittest.TestCase):
    def test_only_known_names(self):
        active, upgrade = profiles()
        for name in set(active) | set(upgrade):
            self.assertIn(name, KNOWN_LLAMA_ARGS | OWN_KEYS, name)

    def test_default_fits_todays_28_gb_beside_other_services(self):
        active, _ = profiles()
        visible, other_services, os_reserve = 26 * GIB, 6 * GIB, 2 * GIB
        self.assertLessEqual(size(active['HOMELAB_LLAMA_MEMORY_MAX']), visible - other_services - os_reserve)
        self.assertLess(size(active['HOMELAB_LLAMA_MEMORY_HIGH']), size(active['HOMELAB_LLAMA_MEMORY_MAX']))
        self.assertGreater(size(active['HOMELAB_LLAMA_MEMORY_HIGH']), MODEL_BYTES[active['LLAMA_ARG_ALIAS']] * 1.1)

    def test_upgrade_profile_fits_96_gb(self):
        _, upgrade = profiles()
        self.assertEqual(upgrade['LLAMA_ARG_ALIAS'], 'gpt-oss-120b')
        self.assertRegex(upgrade['LLAMA_ARG_MODEL'], r'-00001-of-00003\.gguf$')
        self.assertLessEqual(size(upgrade['HOMELAB_LLAMA_MEMORY_MAX']), 96 * GIB * 0.9)
        self.assertGreater(size(upgrade['HOMELAB_LLAMA_MEMORY_HIGH']), MODEL_BYTES['gpt-oss-120b'] * 1.1)

    def test_cpu_and_storage_choices(self):
        active, _ = profiles()
        self.assertEqual(active['LLAMA_ARG_THREADS'], '6')  # E5-2620 physical cores
        self.assertEqual(active['LLAMA_ARG_LOAD_MODE'], 'mmap')
        self.assertNotIn('LLAMA_ARG_NUMA', active)  # one socket today
        self.assertTrue(active['LLAMA_ARG_MODEL'].startswith('/srv/models/'))
        # llama.cpp sends this value verbatim unless it is one origin, "*" or "localhost".
        self.assertNotIn(',', active['LLAMA_ARG_CORS_ORIGINS'])

    def test_unit_requires_key_and_models_mount(self):
        unit = (HERE / 'llama-server.service').read_text(encoding='utf-8')
        self.assertIn('--api-key-file /etc/homelab/llama-server/api-keys', unit)
        self.assertIn('RequiresMountsFor=/srv/models', unit)
        self.assertIn('${HOMELAB_LLAMA_THREADS_BATCH}', unit)
        self.assertIn('User=llama', unit)
        installer = (HERE / 'install-llama-server.sh').read_text(encoding='utf-8')
        self.assertIn('-DBUILD_SHARED_LIBS=OFF', installer)  # only the binary is installed
        self.assertNotRegex(installer, r'\b(hf|huggingface-cli|wget)\b')  # never downloads models


class Status(http.server.BaseHTTPRequestHandler):
    code = 200

    def do_GET(self):
        self.send_response(self.code if self.path == '/health' else 404)
        self.end_headers()

    def log_message(self, *args):
        pass


class Health(unittest.TestCase):
    def run_check(self, port):
        with tempfile.TemporaryDirectory() as tmp:
            env = Path(tmp) / 'llama-server.env'
            env.write_text(f'LLAMA_ARG_PORT={port}\n', encoding='utf-8')
            return subprocess.run(['bash', str(HERE / 'llama-health.sh')], capture_output=True, text=True,
                                  env={**os.environ, 'LLAMA_ENV_FILE': str(env)}).returncode

    def test_ready_loading_and_down(self):
        server = http.server.HTTPServer(('127.0.0.1', 0), Status)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            port = server.server_address[1]
            Status.code = 200
            self.assertEqual(self.run_check(port), 0)
            Status.code = 503
            self.assertEqual(self.run_check(port), 1)
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual(self.run_check(port), 2)


if __name__ == '__main__':
    unittest.main()
