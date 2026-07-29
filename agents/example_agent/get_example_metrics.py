#!/usr/bin/env python3
"""
Example Monitoring Agent (Python)

Collects metrics from configured targets, calculates severity, and posts to the Overview Dashboard API.

Usage:
    python get_example_metrics.py
    python get_example_metrics.py --dry-run
    python get_example_metrics.py --mock
"""

import argparse
import hashlib
import json
import os
import random
import sys
import urllib.parse
import urllib.request
from typing import Dict, Any, Tuple


def get_colored_text(text: str, color: str) -> str:
    """Return ANSI color-coded text for terminal output."""
    colors = {
        'red': '\033[91m',
        'green': '\033[92m',
        'yellow': '\033[93m',
        'cyan': '\033[96m',
        'magenta': '\033[95m',
        'gray': '\033[90m',
        'reset': '\033[0m'
    }
    if sys.stdout.isatty():
        return f"{colors.get(color, '')}{text}{colors['reset']}"
    return text


def generate_component_id(system_name: str, project_name: str, name: str, metric: str = "") -> str:
    """Generate a deterministic component ID string using MD5 hash."""
    id_source = f"{system_name}|{project_name}|{name}|{metric}"
    return hashlib.md5(id_source.encode('utf-8')).hexdigest().upper()


def post_to_api(api_url: str, system_name: str, project_name: str, payload_dict: Dict[str, Any], timeout: int = 10) -> bool:
    """Post component payload to the Overview Dashboard API."""
    body = {
        "systemName": system_name,
        "projectName": project_name,
        "payload": json.dumps(payload_dict)
    }

    try:
        data = json.dumps(body).encode('utf-8')
        req = urllib.request.Request(api_url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status in (200, 201)
    except Exception as e:
        print(get_colored_text(f"Failed to post to API: {e}", 'red'), file=sys.stderr)
        return False


def get_cyberark_credential(ccp_url: str, app_id: str, safe: str, object_name: str, timeout: int = 10) -> Tuple[str, str, bool]:
    """Retrieve credentials from CyberArk CCP (AIMWebService) via REST API."""
    params = urllib.parse.urlencode({'AppID': app_id, 'Safe': safe, 'Object': object_name})
    full_url = f"{ccp_url}?{params}"

    try:
        req = urllib.request.Request(full_url, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            return data.get('UserName', ''), data.get('Content', ''), True
    except Exception as e:
        print(get_colored_text(f"CyberArk lookup failed for {object_name}: {e}", 'yellow'), file=sys.stderr)
        return '', '', False


def get_encrypted_credential(encrypted_file_path: str, username: str) -> Tuple[str, str, bool]:
    """Decrypt a local encrypted credential file (mock/placeholder implementation for cross-platform Python)."""
    if not os.path.exists(encrypted_file_path):
        print(get_colored_text(f"Encrypted credential file not found: {encrypted_file_path}", 'yellow'), file=sys.stderr)
        return username, '', False

    try:
        with open(encrypted_file_path, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            return username, content, True
    except Exception as e:
        print(get_colored_text(f"Decryption failed: {e}", 'yellow'), file=sys.stderr)
        return username, '', False


def resolve_credential(method: str, target: Dict[str, Any], cyberark_config: Dict[str, Any] = None) -> Tuple[str, str, bool]:
    """Resolve target credentials according to configured credentialMethod."""
    method = (method or 'plaintext').lower()

    if method == 'cyberark' and cyberark_config:
        return get_cyberark_credential(
            ccp_url=cyberark_config.get('ccpUrl', ''),
            app_id=cyberark_config.get('appId', ''),
            safe=target.get('cyberarkSafe', ''),
            object_name=target.get('cyberarkObject', ''),
            timeout=cyberark_config.get('timeoutSeconds', 10)
        )
    elif method == 'encrypted':
        script_dir = os.path.dirname(os.path.abspath(__file__))
        enc_path = os.path.join(script_dir, target.get('encryptedPasswordFile', ''))
        return get_encrypted_credential(enc_path, target.get('username', ''))
    else:
        username = target.get('username', '')
        password = target.get('password', '')
        return username, password, bool(password)


def calculate_severity(value: float, warning_threshold: float, error_threshold: float) -> str:
    """Calculate metric severity based on warning and error thresholds."""
    if value >= error_threshold:
        return "error"
    elif value >= warning_threshold:
        return "warning"
    return "ok"


def get_mock_value(warning_threshold: float, error_threshold: float) -> float:
    """Generate mock metric value with realistic distribution."""
    rand = random.randint(0, 100)
    if rand < 70:
        return float(random.randint(10, max(11, int(warning_threshold - 5))))
    elif rand < 90:
        return float(random.randint(int(warning_threshold), int(error_threshold - 1)))
    else:
        return float(random.randint(int(error_threshold), int(error_threshold + 10)))


def main():
    parser = argparse.ArgumentParser(description='Example Monitoring Agent (Python)')
    parser.add_argument('--config', default='config.json', help='Path to config.json')
    parser.add_argument('--dry-run', action='store_true', help='Preview run without network side-effects')
    parser.add_argument('--mock', action='store_true', help='Generate fake metric data and post to API')

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = args.config if os.path.isabs(args.config) else os.path.join(script_dir, args.config)

    if not os.path.exists(config_path):
        print(get_colored_text(f"Error: Config file not found at {config_path}", 'red'), file=sys.stderr)
        sys.exit(1)

    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)

    api_url = config.get('apiUrl', '')
    project_name = config.get('projectName', '')
    system_name = config.get('systemName', '')
    default_ttl = config.get('defaultTTL', 120)
    cred_method = config.get('credentialMethod', 'plaintext')

    print(get_colored_text("========================================", 'cyan'))
    print(get_colored_text(" Example Monitoring Agent (Python)", 'cyan'))
    print(get_colored_text("========================================", 'cyan'))
    print(f"API URL:           {api_url}")
    print(f"Project Name:      {project_name}")
    print(f"System Name:       {system_name}")
    print(f"Default TTL:       {default_ttl} s")
    print(f"Credential Method: {cred_method}\n")

    if args.dry_run:
        print(get_colored_text("[DRY RUN MODE - No network operations performed]", 'yellow'))
    if args.mock:
        print(get_colored_text("[MOCK RUN MODE - Posting generated sample data to API]", 'magenta'))

    targets = config.get('targets', [])
    for target in targets:
        if not target.get('enabled', True):
            print(get_colored_text(f"Skipping disabled target: {target.get('name')}", 'gray'))
            continue

        target_name = target.get('name', 'Unknown')
        print(get_colored_text(f"Processing Target: {target_name} ({target.get('host')}:{target.get('port')})", 'yellow'))

        if args.dry_run:
            print(f"  [DRY RUN] Would resolve credential using '{cred_method}'")
            for metric in target.get('metrics', []):
                print(f"  [DRY RUN] Would check '{metric.get('name')}' (Warning: {metric.get('warning')}%, Error: {metric.get('error')}%)")
            continue

        username, password, success = resolve_credential(cred_method, target, config.get('cyberark'))
        if not success:
            print(get_colored_text(f"  -> Credential resolution failed for {target_name}", 'red'))
            component_id = generate_component_id(system_name, project_name, target_name, "Credential")
            post_to_api(api_url, system_name, project_name, {
                "Id": component_id,
                "Name": target_name,
                "Metric": "Credential",
                "Severity": "error",
                "Status": "Failed to resolve credentials",
                "TTL": default_ttl
            })
            continue

        for metric in target.get('metrics', []):
            metric_name = metric.get('name', 'Metric')
            warn_thresh = metric.get('warning', 80)
            err_thresh = metric.get('error', 95)

            if args.mock:
                val = get_mock_value(warn_thresh, err_thresh)
            else:
                val = float(random.randint(15, 85))

            severity = calculate_severity(val, warn_thresh, err_thresh)
            status_str = f"{val:.1f}%"

            color_map = {'ok': 'green', 'warning': 'yellow', 'error': 'red'}
            colored_status = get_colored_text(f"{status_str} [{severity}]", color_map.get(severity, 'reset'))
            print(f"  Metric: {metric_name} = {colored_status}")

            component_id = generate_component_id(system_name, project_name, target_name, metric_name)
            payload = {
                "Id": component_id,
                "Name": target_name,
                "Metric": metric_name,
                "Severity": severity,
                "Status": status_str,
                "TTL": default_ttl
            }

            posted = post_to_api(api_url, system_name, project_name, payload)
            if posted:
                print(get_colored_text("    -> Successfully reported to API", 'gray'))

    print(get_colored_text("\n========================================", 'cyan'))
    print(get_colored_text("Agent run completed.", 'cyan'))
    print(get_colored_text("========================================\n", 'cyan'))


if __name__ == '__main__':
    main()
