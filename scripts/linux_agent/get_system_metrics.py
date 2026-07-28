#!/usr/bin/env python3
"""
Linux System Metrics Agent

Gathers system metrics (CPU, memory, disk, services) and formats them for API posting.
Computes severity (ok/warning/error) based on configurable thresholds.
"""

import argparse
import hashlib
import json
import os
import random
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error
from typing import Dict, List, Any

# Default ignore patterns for services
DEFAULT_IGNORE_SERVICES = [
    'snapd.refresh.timer',
    'apt-daily.timer',
    'apt-daily-upgrade.timer',
    'motd-news.timer',
    'fstrim.timer',
    'anacron.timer',
    'man-db.timer',
    'logrotate.timer',
]

def print_colored(text: str, color: str):
    colors = {
        'red': '\033[91m',
        'green': '\033[92m',
        'yellow': '\033[93m',
        'cyan': '\033[96m',
        'reset': '\033[0m'
    }
    if sys.stdout.isatty():
        print(f"{colors.get(color, '')}{text}{colors['reset']}")
    else:
        print(text)

def get_cpu_usage(mock: bool) -> float:
    if mock: return round(random.uniform(10, 99), 2)
    try:
        with open('/proc/stat', 'r') as f: line1 = f.readline()
        fields1 = line1.split()
        idle1, total1 = int(fields1[4]), sum(int(x) for x in fields1[1:])
        time.sleep(1)
        with open('/proc/stat', 'r') as f: line2 = f.readline()
        fields2 = line2.split()
        idle2, total2 = int(fields2[4]), sum(int(x) for x in fields2[1:])
        idle_d, total_d = idle2 - idle1, total2 - total1
        return 0.0 if total_d == 0 else round((1 - (idle_d / total_d)) * 100, 2)
    except Exception:
        return 0.0

def get_memory_usage(mock: bool) -> float:
    if mock: return round(random.uniform(10, 99), 2)
    try:
        mem = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2: mem[parts[0].rstrip(':')] = int(parts[1])
        total, available = mem.get('MemTotal', 0), mem.get('MemAvailable', 0)
        if total == 0: return 0.0
        if available == 0: available = mem.get('MemFree', 0) + mem.get('Buffers', 0) + mem.get('Cached', 0)
        return round(((total - available) / total) * 100, 2)
    except Exception:
        return 0.0

def get_disk_usage(mock: bool) -> List[Dict[str, Any]]:
    if mock: return [{'device': '/dev/sda1', 'mount_point': '/', 'used_percent': round(random.uniform(10, 99), 2)}]
    disks = []
    excludes = {'tmpfs', 'devtmpfs', 'squashfs', 'overlay', 'proc', 'sysfs', 'devpts', 'cgroup'}
    try:
        res = subprocess.run(['df', '-PT'], capture_output=True, text=True, timeout=10)
        for line in res.stdout.strip().split('\n')[1:]:
            parts = line.split()
            if len(parts) >= 7 and parts[1] not in excludes and parts[0].startswith('/'):
                try: disks.append({'device': parts[0], 'mount_point': parts[6], 'used_percent': float(parts[5].rstrip('%'))})
                except ValueError: pass
    except Exception:
        pass
    return disks

def get_failed_services(mock: bool, ignore_list: List[str]) -> List[str]:
    if mock: return ["mock-service.service"] if random.random() > 0.7 else []
    failed = []
    try:
        res = subprocess.run(['systemctl', 'list-units', '--state=failed', '--no-legend', '--plain'], capture_output=True, text=True, timeout=10)
        for line in res.stdout.strip().split('\n'):
            if line:
                svc = line.split()[0]
                if not any(svc.startswith(p[:-1]) if p.endswith('*') else svc == p for p in ignore_list):
                    failed.append(svc)
    except Exception:
        pass
    return failed

def get_stopped_automatic_services(mock: bool, ignore_list: List[str]) -> List[str]:
    if mock: return []
    stopped = []
    try:
        res = subprocess.run(['systemctl', 'list-unit-files', '--type=service', '--state=enabled', '--no-legend', '--plain'], capture_output=True, text=True, timeout=10)
        for line in res.stdout.strip().split('\n'):
            if line:
                svc = line.split()[0]
                if not any(svc.startswith(p[:-1]) if p.endswith('*') else svc == p for p in ignore_list):
                    act = subprocess.run(['systemctl', 'is-active', svc], capture_output=True, text=True, timeout=5)
                    if act.stdout.strip() not in ('active', 'activating'): stopped.append(svc)
    except Exception:
        pass
    return stopped

def main():
    parser = argparse.ArgumentParser(description='Gather Linux system metrics')
    parser.add_argument('--config-path', type=str, default=os.path.join(os.path.dirname(__file__), 'config.json'))
    parser.add_argument('--api-url', type=str)
    parser.add_argument('--project-name', type=str)
    parser.add_argument('--system-name', type=str)
    parser.add_argument('--ttl', type=int)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--mock', action='store_true')
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    config = {}
    if os.path.exists(args.config_path):
        try:
            with open(args.config_path, 'r') as f:
                config = json.load(f)
        except Exception as e:
            print(f"Failed to read config: {e}")
            sys.exit(1)

    api_url = args.api_url or config.get('apiUrl')
    project_name = args.project_name or config.get('projectName', 'Servers')
    system_name = args.system_name or config.get('systemName', 'Monitoring')
    ttl = args.ttl or config.get('defaultTTL', 120)
    
    thresh = config.get('thresholds', {})
    warn_thresh = thresh.get('warning', 85)
    err_thresh = thresh.get('error', 95)
    ignore_svcs = config.get('services', DEFAULT_IGNORE_SERVICES)

    if not args.quiet:
        print_colored("=============================================", 'cyan')
        print_colored("         Overview Dashboard Agent            ", 'cyan')
        print_colored("         Linux System Metrics                ", 'cyan')
        print_colored("=============================================", 'cyan')
        if args.dry_run: print_colored("[MODE] DryRun - No data will be sent to API", 'yellow')
        if args.mock: print_colored("[MODE] MockRun - Using fake data", 'yellow')

    cpu = get_cpu_usage(args.mock)
    mem = get_memory_usage(args.mock)
    disks = get_disk_usage(args.mock)
    failed = get_failed_services(args.mock, ignore_svcs)
    stopped = get_stopped_automatic_services(args.mock, ignore_svcs)
    all_prob = list(set(failed + stopped))

    severity = 'ok'
    if cpu >= err_thresh: severity = 'error'
    elif cpu >= warn_thresh and severity != 'error': severity = 'warning'
    if mem >= err_thresh: severity = 'error'
    elif mem >= warn_thresh and severity != 'error': severity = 'warning'
    for d in disks:
        if d['used_percent'] >= err_thresh: severity = 'error'
        elif d['used_percent'] >= warn_thresh and severity != 'error': severity = 'warning'
    if all_prob: severity = 'error'

    hostname = socket.gethostname()
    metric_name = "System"
    id_source = f"{system_name}|{project_name}|{hostname}|{metric_name}"
    comp_id = hashlib.md5(id_source.encode()).hexdigest().upper()

    disk_str = ", ".join(f"{d['mount_point']} ({d['used_percent']}%)" for d in disks) if disks else "No disks"
    svc_str = "Down: " + ", ".join(all_prob) if all_prob else "All Enabled Services Running"

    payload_dict = {
        'Id': comp_id,
        'Name': hostname,
        'CPU': f"{cpu}%",
        'Memory': f"{mem}%",
        'Disks': disk_str,
        'Services': svc_str,
        'Severity': severity,
        'TTL': ttl
    }

    body = {
        'systemName': system_name,
        'projectName': project_name,
        'payload': json.dumps(payload_dict)
    }

    if not args.quiet:
        print_colored("\nSystem Metrics Summary:", 'green')
        c_col = 'red' if cpu >= err_thresh else ('yellow' if cpu >= warn_thresh else 'green')
        print_colored(f"CPU Usage: {cpu}%", c_col)
        m_col = 'red' if mem >= err_thresh else ('yellow' if mem >= warn_thresh else 'green')
        print_colored(f"Memory Usage: {mem}%", m_col)
        for d in disks:
            d_col = 'red' if d['used_percent'] >= err_thresh else ('yellow' if d['used_percent'] >= warn_thresh else 'green')
            print_colored(f"Disk {d['mount_point']} Usage: {d['used_percent']}%", d_col)
        if all_prob:
            print_colored(f"Problem Services: {len(all_prob)}", 'red')
            for s in all_prob: print_colored(f"  - {s}", 'red')
        else:
            print_colored("All enabled services running", 'green')
        
        s_col = 'red' if severity == 'error' else ('yellow' if severity == 'warning' else 'green')
        print_colored(f"\nOverall Severity: {severity}", s_col)
        print_colored(f"\nPayload ID: {comp_id}", 'cyan')

    if args.dry_run:
        if not args.quiet:
            print_colored("\n[DRY RUN] Skipping API POST.", 'yellow')
            print(json.dumps(body, indent=2))
        return

    if api_url:
        if not args.quiet: print_colored(f"\nPosting to API: {api_url}", 'cyan')
        try:
            req = urllib.request.Request(api_url, data=json.dumps(body).encode('utf-8'), headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=15) as res:
                if not args.quiet: print_colored("[SUCCESS] Metrics posted successfully.", 'green')
        except Exception as e:
            print_colored(f"[ERROR] Failed to post to API: {e}", 'red')
    else:
        print_colored("[ERROR] No API URL provided via config or args.", 'red')

if __name__ == '__main__':
    main()
