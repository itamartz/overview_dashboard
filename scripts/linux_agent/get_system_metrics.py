#!/usr/bin/env python3
"""
Linux System Metrics Agent

Gathers system metrics (CPU, memory, disk, services) and formats them for API posting.
Computes severity (ok/warning/error) based on configurable thresholds.

Usage:
    python3 get_system_metrics.py
    python3 get_system_metrics.py --threshold-warning 80 --threshold-error 90
    python3 get_system_metrics.py --project-name "MyProject" --system-name "Servers"
"""

import argparse
import json
import os
import socket
import subprocess
import sys
from typing import Dict, List, Tuple, Any

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


def get_cpu_usage() -> float:
    """
    Get current CPU usage percentage.
    Uses /proc/stat for accurate measurement over a 1-second interval.
    """
    try:
        # Read initial CPU stats
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        
        fields = line.split()
        idle1 = int(fields[4])
        total1 = sum(int(x) for x in fields[1:])
        
        # Wait 1 second
        import time
        time.sleep(1)
        
        # Read CPU stats again
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        
        fields = line.split()
        idle2 = int(fields[4])
        total2 = sum(int(x) for x in fields[1:])
        
        # Calculate CPU usage
        idle_delta = idle2 - idle1
        total_delta = total2 - total1
        
        if total_delta == 0:
            return 0.0
        
        cpu_usage = (1 - (idle_delta / total_delta)) * 100
        return round(cpu_usage, 2)
    
    except Exception as e:
        print(f"Warning: Could not get CPU usage from /proc/stat: {e}", file=sys.stderr)
        # Fallback: try using top
        try:
            result = subprocess.run(
                ['top', '-bn1'],
                capture_output=True,
                text=True,
                timeout=5
            )
            for line in result.stdout.split('\n'):
                if 'Cpu' in line or '%Cpu' in line:
                    # Parse the idle percentage and calculate usage
                    parts = line.split()
                    for i, part in enumerate(parts):
                        if 'id' in part or 'idle' in part.lower():
                            try:
                                idle = float(parts[i-1].replace(',', '.'))
                                return round(100 - idle, 2)
                            except (ValueError, IndexError):
                                pass
        except Exception:
            pass
        return 0.0


def get_memory_usage() -> float:
    """
    Get current memory usage percentage.
    Uses /proc/meminfo for accurate measurement.
    """
    try:
        meminfo = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    key = parts[0].rstrip(':')
                    value = int(parts[1])
                    meminfo[key] = value
        
        total = meminfo.get('MemTotal', 0)
        available = meminfo.get('MemAvailable', 0)
        
        if total == 0:
            return 0.0
        
        # If MemAvailable is not present (older kernels), calculate it
        if available == 0:
            free = meminfo.get('MemFree', 0)
            buffers = meminfo.get('Buffers', 0)
            cached = meminfo.get('Cached', 0)
            available = free + buffers + cached
        
        used = total - available
        usage_percent = (used / total) * 100
        return round(usage_percent, 2)
    
    except Exception as e:
        print(f"Warning: Could not get memory usage: {e}", file=sys.stderr)
        return 0.0


def get_disk_usage() -> List[Dict[str, Any]]:
    """
    Get disk usage for all mounted filesystems.
    Excludes virtual filesystems (tmpfs, devtmpfs, etc.)
    """
    disks = []
    exclude_types = {'tmpfs', 'devtmpfs', 'squashfs', 'overlay', 'aufs', 'proc', 'sysfs', 'devpts', 'cgroup', 'cgroup2', 'securityfs', 'pstore', 'debugfs', 'hugetlbfs', 'mqueue', 'fusectl', 'configfs', 'binfmt_misc', 'autofs', 'efivarfs', 'tracefs'}
    exclude_mounts = {'/boot/efi', '/snap'}
    
    try:
        result = subprocess.run(
            ['df', '-PT'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        lines = result.stdout.strip().split('\n')
        for line in lines[1:]:  # Skip header
            parts = line.split()
            if len(parts) >= 7:
                filesystem = parts[0]
                fs_type = parts[1]
                mount_point = parts[6]
                used_percent_str = parts[5].rstrip('%')
                
                # Skip virtual filesystems and specific mounts
                if fs_type in exclude_types:
                    continue
                if any(mount_point.startswith(exc) for exc in exclude_mounts):
                    continue
                if not filesystem.startswith('/'):
                    continue
                
                try:
                    used_percent = float(used_percent_str)
                    disks.append({
                        'device': filesystem,
                        'mount_point': mount_point,
                        'used_percent': used_percent
                    })
                except ValueError:
                    continue
    
    except Exception as e:
        print(f"Warning: Could not get disk usage: {e}", file=sys.stderr)
    
    return disks


def get_failed_services(ignore_list: List[str] = None) -> List[str]:
    """
    Get list of failed systemd services.
    Only includes services that are in a failed state.
    """
    if ignore_list is None:
        ignore_list = DEFAULT_IGNORE_SERVICES
    
    failed_services = []
    
    try:
        # Check for failed systemd services
        result = subprocess.run(
            ['systemctl', 'list-units', '--state=failed', '--no-legend', '--plain'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split()
                if parts:
                    service_name = parts[0]
                    
                    # Check if service should be ignored
                    should_ignore = False
                    for pattern in ignore_list:
                        if pattern.endswith('*'):
                            if service_name.startswith(pattern[:-1]):
                                should_ignore = True
                                break
                        elif pattern == service_name:
                            should_ignore = True
                            break
                    
                    if not should_ignore:
                        failed_services.append(service_name)
    
    except FileNotFoundError:
        # systemctl not available, try alternative method
        print("Warning: systemctl not found, skipping service check", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Could not check services: {e}", file=sys.stderr)
    
    return failed_services


def get_stopped_automatic_services(ignore_list: List[str] = None) -> List[str]:
    """
    Get list of enabled services that are not running.
    Similar to Windows automatic services that are stopped.
    """
    if ignore_list is None:
        ignore_list = DEFAULT_IGNORE_SERVICES
    
    stopped_services = []
    
    try:
        # Get enabled services
        result = subprocess.run(
            ['systemctl', 'list-unit-files', '--type=service', '--state=enabled', '--no-legend', '--plain'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        enabled_services = set()
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split()
                if parts:
                    enabled_services.add(parts[0])
        
        # Check which enabled services are not running
        for service in enabled_services:
            # Check if service should be ignored
            should_ignore = False
            for pattern in ignore_list:
                if pattern.endswith('*'):
                    if service.startswith(pattern[:-1]):
                        should_ignore = True
                        break
                elif pattern == service:
                    should_ignore = True
                    break
            
            if should_ignore:
                continue
            
            # Check if service is running
            result = subprocess.run(
                ['systemctl', 'is-active', service],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.stdout.strip() not in ('active', 'activating'):
                stopped_services.append(service)
    
    except FileNotFoundError:
        print("Warning: systemctl not found, skipping stopped services check", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Could not check stopped services: {e}", file=sys.stderr)
    
    return stopped_services


def calculate_severity(
    cpu_usage: float,
    memory_usage: float,
    disks: List[Dict],
    failed_services: List[str],
    warning_threshold: int,
    error_threshold: int
) -> str:
    """
    Calculate overall severity based on all metrics.
    Returns: 'ok', 'warning', or 'error'
    """
    severity = 'ok'
    
    # Check CPU
    if cpu_usage >= error_threshold:
        severity = 'error'
    elif cpu_usage >= warning_threshold and severity != 'error':
        severity = 'warning'
    
    # Check Memory
    if memory_usage >= error_threshold:
        severity = 'error'
    elif memory_usage >= warning_threshold and severity != 'error':
        severity = 'warning'
    
    # Check Disks
    for disk in disks:
        if disk['used_percent'] >= error_threshold:
            severity = 'error'
        elif disk['used_percent'] >= warning_threshold and severity != 'error':
            severity = 'warning'
    
    # Check Services
    if failed_services:
        severity = 'error'
    
    return severity


def get_hostname() -> str:
    """Get the system hostname."""
    try:
        return socket.gethostname()
    except Exception:
        return os.uname().nodename if hasattr(os, 'uname') else 'unknown'


def format_disks_string(disks: List[Dict]) -> str:
    """Format disk information as a readable string."""
    if not disks:
        return "No disks found"
    
    disk_strings = []
    for disk in disks:
        disk_strings.append(f"{disk['mount_point']} ({disk['used_percent']}%)")
    
    return ", ".join(disk_strings)


def format_services_string(failed_services: List[str]) -> str:
    """Format service information as a readable string."""
    if failed_services:
        return "Down: " + ", ".join(failed_services)
    return "All Enabled Services Running"


def build_payload(
    cpu_usage: float,
    memory_usage: float,
    disks: List[Dict],
    failed_services: List[str],
    severity: str,
    project_name: str,
    system_name: str
) -> Dict:
    """Build the JSON payload for API posting."""
    hostname = get_hostname()
    
    return {
        'projectName': project_name,
        'systemName': system_name,
        'payload': {
            'Id': hostname,
            'Name': hostname,
            'CPU': f"{cpu_usage}%",
            'Memory': f"{memory_usage}%",
            'Disks': format_disks_string(disks),
            'Services': format_services_string(failed_services),
            'Severity': severity
        }
    }


def print_colored(text: str, color: str):
    """Print colored text to terminal."""
    colors = {
        'red': '\033[91m',
        'green': '\033[92m',
        'yellow': '\033[93m',
        'cyan': '\033[96m',
        'reset': '\033[0m'
    }
    
    # Check if terminal supports colors
    if sys.stdout.isatty():
        print(f"{colors.get(color, '')}{text}{colors['reset']}")
    else:
        print(text)


def main():
    parser = argparse.ArgumentParser(
        description='Gather Linux system metrics for monitoring dashboard'
    )
    parser.add_argument(
        '--threshold-warning',
        type=int,
        default=85,
        help='Warning threshold percentage (default: 85)'
    )
    parser.add_argument(
        '--threshold-error',
        type=int,
        default=95,
        help='Error threshold percentage (default: 95)'
    )
    parser.add_argument(
        '--project-name',
        type=str,
        default='Servers',
        help='Project name for the payload (default: Servers)'
    )
    parser.add_argument(
        '--system-name',
        type=str,
        default='Monitoring',
        help='System name for the payload (default: Monitoring)'
    )
    parser.add_argument(
        '--ignore-services',
        type=str,
        nargs='*',
        default=DEFAULT_IGNORE_SERVICES,
        help='List of service names or patterns to ignore'
    )
    parser.add_argument(
        '--json-only',
        action='store_true',
        help='Output only JSON without summary'
    )
    parser.add_argument(
        '--check-stopped',
        action='store_true',
        help='Also check for stopped enabled services (not just failed)'
    )
    
    args = parser.parse_args()
    
    try:
        if not args.json_only:
            print_colored("Gathering system metrics...", 'cyan')
        
        # Collect metrics
        cpu_usage = get_cpu_usage()
        memory_usage = get_memory_usage()
        disks = get_disk_usage()
        
        # Get failed services (and optionally stopped services)
        failed_services = get_failed_services(args.ignore_services)
        if args.check_stopped:
            stopped_services = get_stopped_automatic_services(args.ignore_services)
            # Combine and deduplicate
            all_problem_services = list(set(failed_services + stopped_services))
        else:
            all_problem_services = failed_services
        
        # Calculate severity
        severity = calculate_severity(
            cpu_usage,
            memory_usage,
            disks,
            all_problem_services,
            args.threshold_warning,
            args.threshold_error
        )
        
        # Build payload
        payload = build_payload(
            cpu_usage,
            memory_usage,
            disks,
            all_problem_services,
            severity,
            args.project_name,
            args.system_name
        )
        
        # Output
        if args.json_only:
            print(json.dumps(payload, indent=2))
        else:
            # Display summary
            print_colored("\nSystem Metrics Summary:", 'green')
            
            # CPU
            cpu_color = 'red' if cpu_usage >= args.threshold_error else ('yellow' if cpu_usage >= args.threshold_warning else 'green')
            print_colored(f"CPU Usage: {cpu_usage}%", cpu_color)
            
            # Memory
            mem_color = 'red' if memory_usage >= args.threshold_error else ('yellow' if memory_usage >= args.threshold_warning else 'green')
            print_colored(f"Memory Usage: {memory_usage}%", mem_color)
            
            # Disks
            for disk in disks:
                disk_color = 'red' if disk['used_percent'] >= args.threshold_error else ('yellow' if disk['used_percent'] >= args.threshold_warning else 'green')
                print_colored(f"Disk {disk['mount_point']}: {disk['used_percent']}%", disk_color)
            
            # Services
            if all_problem_services:
                print_colored(f"Problem Services: {len(all_problem_services)}", 'red')
                for service in all_problem_services:
                    print_colored(f"  - {service}", 'red')
            else:
                print_colored("All enabled services are running (or ignored)", 'green')
            
            # Overall severity
            sev_color = 'red' if severity == 'error' else ('yellow' if severity == 'warning' else 'green')
            print_colored(f"\nOverall Severity: {severity}", sev_color)
            
            print_colored("\nJSON Output:", 'cyan')
            print(json.dumps(payload, indent=2))
        
        return payload
    
    except Exception as e:
        print(f"Error gathering metrics: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
