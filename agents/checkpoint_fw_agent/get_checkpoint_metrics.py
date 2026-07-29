#!/usr/bin/env python3
"""
Checkpoint Firewall Metrics Agent

Gathers system metrics (CPU, memory, cluster state, errors) from Checkpoint Gaia OS
and formats them for API posting. Includes built-in API posting logic.
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import re
import hashlib
import urllib.request
import urllib.error
import ssl
from typing import Dict, List, Tuple

# Mock data for testing
MOCK_DATA = {
    'cpu': 'CPU Usage: 15%',
    'multi_cpu': '''Processors load
---------------------------------------------------------------------------------
|CPU#|User Time(%)|System Time(%)|Idle Time(%)|Usage(%)|Run queue|Interrupts/sec|
---------------------------------------------------------------------------------
|   1|           0|             1|          99|       1|        ?|          3715|
|   2|           1|             2|          97|       3|        ?|          3715|
|   3|           2|             4|          94|       6|        ?|          3715|
|   4|          80|            10|          10|      90|        ?|          3715|
---------------------------------------------------------------------------------''',
    'memory': '''Total Virtual Memory (Bytes):  14564306944
Active Virtual Memory (Bytes): 3293835264
Total Real Memory (Bytes):     5977120768
Active Real Memory (Bytes):    3293835264
Free Real Memory (Bytes):      2683285504
Memory Swaps/Sec:              -
Memory To Disk Transfers/Sec:  -''',
    'cluster': '''Cluster Mode:   High Availability (Active Up)

Sync Mode:   Optimized Sync

ID         Unique Address  Assigned Load   State

1 (local)  10.231.149.1    100%            ACTIVE
2          10.231.149.2    0%              STANDBY

Active PNOTEs: None''',
    'cphaprob_list': 'Device Name: Synchronization\nState: OK\n\nDevice Name: Filter\nState: OK',
    'heavy_conn': '''[fw_60]; conn: 192.168.1.1:3788 -> 192.168.1.3:8080 IPP 6; Instance load: 68%; Connection instance load 91%; StartTime: 17/12/25 03:18:18; Duration: 3; IdentificationTime: 17/12/25 03:18:19; Seervice: 6:8080; Total Bytes: 1123534;'''
}

COLORS = {
    'red': '\033[91m',
    'green': '\033[92m',
    'yellow': '\033[93m',
    'cyan': '\033[96m',
    'magenta': '\033[95m',
    'reset': '\033[0m'
}

def print_color(text: str, color: str, quiet: bool = False):
    """Print colorized output to terminal."""
    if quiet and color != 'red':
        return
    if sys.stdout.isatty():
        print(f"{COLORS.get(color, '')}{text}{COLORS['reset']}")
    else:
        print(text)

def print_banner(config: dict, args: argparse.Namespace):
    """Print the standard startup banner."""
    if args.quiet:
        return
    mode = "MOCK RUN" if args.mock else "DRY RUN" if args.dry_run else "NORMAL RUN"
    print_color("==================================================", 'cyan')
    print_color(f"  Overview Dashboard - Checkpoint Agent", 'cyan')
    print_color(f"  Mode:         {mode}", 'yellow')
    print_color(f"  System Name:  {config['systemName']}", 'cyan')
    print_color(f"  Project Name: {config['projectName']}", 'cyan')
    print_color(f"  API URL:      {config['apiUrl']}", 'cyan')
    print_color("==================================================", 'cyan')

def run_command(command: List[str], mock: bool = False, mock_key: str = None) -> str:
    if mock:
        return MOCK_DATA.get(mock_key, "")
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except Exception:
        return ""

def get_cpu_usage(mock: bool = False, warning_threshold: int = 80) -> Tuple[float, float, List[str]]:
    heavy_cpus = []
    avg_usage = 0.0
    max_usage = 0.0
    try:
        output = run_command(['cpstat', 'os', '-f', 'multi_cpu'], mock, 'multi_cpu')
        cpus = []
        lines = output.strip().split('\n')
        for line in lines:
            line = line.strip()
            if not line.startswith('|') or 'CPU#' in line:
                continue
            parts = line.split('|')
            if len(parts) >= 6:
                try:
                    cpu_id = parts[1].strip()
                    usage = float(parts[5].strip())
                    cpus.append(usage)
                    if usage >= warning_threshold:
                        heavy_cpus.append(f"CPU{cpu_id}: {usage}%")
                except (ValueError, IndexError):
                    continue
        if cpus:
            avg_usage = round(sum(cpus) / len(cpus), 2)
            max_usage = max(cpus)
            return avg_usage, max_usage, heavy_cpus
        
        output = run_command(['cpstat', 'os', '-f', 'cpu'], mock, 'cpu')
        match = re.search(r'CPU Usage\s*:\s*(\d+)', output)
        if match:
            usage = float(match.group(1))
            if usage >= warning_threshold:
                heavy_cpus.append(f"CPU: {usage}%")
            return usage, usage, heavy_cpus
    except Exception:
        pass
    return 0.0, 0.0, []

def get_memory_usage(mock: bool = False) -> Tuple[float, int, int]:
    try:
        output = run_command(['cpstat', 'os', '-f', 'memory'], mock, 'memory')
        total_match = re.search(r'Total Real Memory \(Bytes\)\s*:\s*(\d+)', output)
        free_match = re.search(r'Free Real Memory \(Bytes\)\s*:\s*(\d+)', output)
        if total_match and free_match:
            total_bytes = int(total_match.group(1))
            free_bytes = int(free_match.group(1))
            if total_bytes > 0:
                used_percent = round(((total_bytes - free_bytes) / total_bytes) * 100, 2)
                return used_percent, total_bytes, free_bytes
    except Exception:
        pass
    return 0.0, 0, 0

def get_cluster_state(mock: bool = False) -> str:
    try:
        output = run_command(['cphaprob', 'state'], mock, 'cluster')
        match = re.search(r'State:\s*(.+)', output)
        if match:
            return match.group(1).strip()
        for line in output.split('\n'):
            if '(local)' in line:
                parts = line.split()
                if parts:
                    return parts[-1].capitalize()
        if "Active" in output:
            return "Active"
        elif "Standby" in output:
            return "Standby"
    except Exception:
        pass
    return "Unknown"

def get_errors(mock: bool = False) -> List[str]:
    errors = []
    try:
        output = run_command(['cphaprob', 'list'], mock, 'cphaprob_list')
        devices = output.split('\n\n')
        for device in devices:
            name_match = re.search(r'Device Name:\s*(.+)', device)
            state_match = re.search(r'State:\s*(.+)', device)
            if name_match and state_match:
                name = name_match.group(1).strip()
                state = state_match.group(1).strip()
                if state != 'OK':
                    errors.append(f"{name}: {state}")
    except Exception:
        pass
    return errors

def get_heavy_connections(mock: bool = False) -> List[str]:
    heavy_conns = []
    try:
        from datetime import datetime
        today_str = datetime.now().strftime("%d/%m/%y")
        if mock:
             today_str = "17/12/25"
        output = run_command(['fw', 'ctl', 'multik', 'print_heavy_conn'], mock, 'heavy_conn')
        if not output:
            return []
        lines = output.strip().split('\n')
        last_5_lines = lines[-5:]
        for line in last_5_lines:
            if today_str in line:
                heavy_conns.append(line.strip())
    except Exception:
        pass
    return heavy_conns

def calculate_severity(
    cpu_usage: float, max_cpu_usage: float, memory_usage: float,
    cluster_state: str, errors: List[str], heavy_connections: List[str],
    warning_threshold: int, error_threshold: int
) -> str:
    severity = 'ok'
    if cpu_usage >= error_threshold or max_cpu_usage >= error_threshold:
        severity = 'error'
    elif (cpu_usage >= warning_threshold or max_cpu_usage >= warning_threshold) and severity != 'error':
        severity = 'warning'
        
    if memory_usage >= error_threshold:
        severity = 'error'
    elif memory_usage >= warning_threshold and severity != 'error':
        severity = 'warning'
        
    if cluster_state.lower() in ['down', 'problem', 'error', 'unknown']:
        severity = 'error'
    if errors:
        severity = 'error'
    if heavy_connections:
        severity = 'error'
        
    return severity

def get_hostname() -> str:
    try:
        return socket.gethostname()
    except Exception:
        return "checkpoint-fw"

def generate_md5_id(system_name: str, project_name: str, hostname: str) -> str:
    unique_string = f"{system_name}-{project_name}-{hostname}".encode('utf-8')
    return hashlib.md5(unique_string).hexdigest()

def post_to_api(payload: dict, config: dict, args: argparse.Namespace):
    if args.dry_run:
        print_color(f"[DRY-RUN] Would post: {payload['payload']['Name']} ({payload['payload']['Severity']})", 'magenta', args.quiet)
        return

    json_data = json.dumps(payload).encode('utf-8')
    request = urllib.request.Request(
        config['apiUrl'],
        data=json_data,
        headers={'Content-Type': 'application/json', 'Accept': 'application/json'},
        method='POST'
    )
    
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(request, timeout=10, context=ctx) as response:
            if response.status in [200, 201]:
                print_color(f"[SUCCESS] Posted {payload['payload']['Name']} - {payload['payload']['Severity']}", 'green', args.quiet)
            else:
                print_color(f"[WARNING] API returned status {response.status} for {payload['payload']['Name']}", 'yellow', args.quiet)
    except Exception as e:
        print_color(f"[ERROR] Failed to post {payload['payload']['Name']}: {str(e)}", 'red')

def main():
    parser = argparse.ArgumentParser(description='Checkpoint Firewall Agent')
    parser.add_argument('--config-path', type=str, default='config.json', help='Path to config.json')
    parser.add_argument('--api-url', type=str, help='Override API URL')
    parser.add_argument('--project-name', type=str, help='Override Project Name')
    parser.add_argument('--system-name', type=str, help='Override System Name')
    parser.add_argument('--ttl', type=int, help='Override TTL')
    parser.add_argument('--dry-run', action='store_true', help='Do not post to API')
    parser.add_argument('--mock', action='store_true', help='Use mock data')
    parser.add_argument('--quiet', action='store_true', help='Suppress non-error output')
    
    args = parser.parse_args()

    # Load configuration
    config = {
        "apiUrl": "https://overview/api/components",
        "projectName": "Firewalls",
        "systemName": "Checkpoint",
        "defaultTTL": 120,
        "thresholds": {
            "warning": 80,
            "error": 90
        }
    }
    
    if os.path.exists(args.config_path):
        try:
            with open(args.config_path, 'r') as f:
                file_config = json.load(f)
                config.update(file_config)
        except Exception as e:
            print_color(f"Error reading config {args.config_path}: {e}", 'red')
            sys.exit(1)

    if args.api_url: config['apiUrl'] = args.api_url
    if args.project_name: config['projectName'] = args.project_name
    if args.system_name: config['systemName'] = args.system_name
    if args.ttl: config['defaultTTL'] = args.ttl

    print_banner(config, args)
    
    warn_thresh = config.get('thresholds', {}).get('warning', 80)
    err_thresh = config.get('thresholds', {}).get('error', 90)

    try:
        cpu_usage, max_cpu_usage, heavy_cpus = get_cpu_usage(args.mock, warn_thresh)
        memory_usage, total_mem, free_mem = get_memory_usage(args.mock)
        cluster_state = get_cluster_state(args.mock)
        errors = get_errors(args.mock)
        heavy_connections = get_heavy_connections(args.mock)
        
        severity = calculate_severity(
            cpu_usage, max_cpu_usage, memory_usage,
            cluster_state, errors, heavy_connections,
            warn_thresh, err_thresh
        )
        
        hostname = get_hostname()
        component_id = generate_md5_id(config['systemName'], config['projectName'], hostname)
        
        error_str = "No Errors" if not errors else ", ".join(errors)
        cpu_str = f"{cpu_usage}%" + (f" (Heavy: {', '.join(heavy_cpus)})" if heavy_cpus else "")
        free_gb = round(free_mem / (1024**3), 3)
        free_percent = round((free_mem / total_mem) * 100, 3) if total_mem > 0 else 0.0
        mem_str = f"Free: {free_gb:.3f}GB ({free_percent:.3f}%)"
        heavy_conn_str = f"{len(heavy_connections)} found" if heavy_connections else "None"
            
        payload = {
            'projectName': config['projectName'],
            'systemName': config['systemName'],
            'payload': {
                'Id': component_id,
                'Name': hostname,
                'CPU': cpu_str,
                'Memory': mem_str,
                'Cluster State': cluster_state,
                'Errors': error_str,
                'Heavy Connections': heavy_conn_str,
                'Severity': severity,
                'TTL': config['defaultTTL']
            }
        }
        
        post_to_api(payload, config, args)
        
    except Exception as e:
        print_color(f"Error: {e}", 'red')
        sys.exit(1)

if __name__ == '__main__':
    main()
