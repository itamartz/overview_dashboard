#!/usr/bin/env python3
"""
Checkpoint Firewall Metrics Agent

Gathers system metrics (CPU, memory, cluster state, errors) from Checkpoint Gaia OS
and formats them for API posting.

Usage:
    python3 get_checkpoint_metrics.py
    python3 get_checkpoint_metrics.py --threshold-warning 80 --threshold-error 90
    python3 get_checkpoint_metrics.py --mock (for testing without Checkpoint hardware)
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import re
from typing import Dict, List, Tuple, Any

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

Active PNOTEs: None

Last member state change event:
   Event Code:                 CLUS-114904
   State change:               ACTIVE(!) -> ACTIVE
   Reason for state change:    Reason for ACTIVE! alert has been resolved
   Event time:                 Wed Mar 12 01:33:38 2025

Cluster failover count:
   Failover counter:           0
   Time of counter reset:      Wed Mar 12 00:32:50 2025 (reboot)''',
    'cphaprob_list': 'Device Name: Synchronization\nState: OK\n\nDevice Name: Filter\nState: OK',
    'heavy_conn': '''[fw_60]; conn: 192.168.1.1:3788 -> 192.168.1.3:8080 IPP 6; Instance load: 68%; Connection instance load 91%; StartTime: 17/12/25 03:18:18; Duration: 3; IdentificationTime: 17/12/25 03:18:19; Seervice: 6:8080; Total Bytes: 1123534;
[fw_60]; conn: 10.0.0.1:1234 -> 10.0.0.2:80 IPP 6; Instance load: 50%; Connection instance load 80%; StartTime: 16/12/25 10:00:00; Duration: 3; IdentificationTime: 16/12/25 10:00:00; Seervice: 6:80; Total Bytes: 5000;'''
}

def run_command(command: List[str], mock: bool = False, mock_key: str = None) -> str:
    """
    Run a system command and return stdout.
    If mock is True, returns mock data based on mock_key.
    """
    if mock:
        return MOCK_DATA.get(mock_key, "")
    
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.stdout.strip()
    except Exception as e:
        # Don't print error here, let caller handle empty output
        return ""

def get_cpu_usage(mock: bool = False, warning_threshold: int = 80) -> Tuple[float, float, List[str]]:
    """
    Get current CPU usage percentage, max CPU usage, and list of heavy load CPUs.
    Uses 'cpstat os -f multi_cpu' on Checkpoint.
    Returns: (average_usage, max_usage, list_of_heavy_cpus)
    """
    heavy_cpus = []
    avg_usage = 0.0
    max_usage = 0.0
    
    try:
        # Try cpstat multi_cpu
        output = run_command(['cpstat', 'os', '-f', 'multi_cpu'], mock, 'multi_cpu')
        
        cpus = []
        # Parse table format: |CPU#|...|Usage(%)|...
        lines = output.strip().split('\n')
        for line in lines:
            line = line.strip()
            # Skip headers/separators
            if not line.startswith('|') or 'CPU#' in line:
                continue
                
            parts = line.split('|')
            # Expected split: ['', 'CPU#', 'User', 'Sys', 'Idle', 'Usage', 'Run', 'Int', '']
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

        # Fallback to single CPU check if multi_cpu fails or returns nothing
        output = run_command(['cpstat', 'os', '-f', 'cpu'], mock, 'cpu')
        match = re.search(r'CPU Usage\s*:\s*(\d+)', output)
        if match:
            usage = float(match.group(1))
            if usage >= warning_threshold:
                heavy_cpus.append(f"CPU: {usage}%")
            return usage, usage, heavy_cpus
            
        # Fallback to /proc/stat if cpstat fails (Gaia is Linux)
        if not mock and os.path.exists('/proc/stat'):
            with open('/proc/stat', 'r') as f:
                line = f.readline()
                fields = line.split()
                idle1 = int(fields[4])
                total1 = sum(int(x) for x in fields[1:])
                
                import time
                time.sleep(1)
                
                with open('/proc/stat', 'r') as f:
                    line = f.readline()
                    fields = line.split()
                    idle2 = int(fields[4])
                    total2 = sum(int(x) for x in fields[1:])
                
                idle_delta = idle2 - idle1
                total_delta = total2 - total1
                
                if total_delta > 0:
                    usage = round((1 - (idle_delta / total_delta)) * 100, 2)
                    if usage >= warning_threshold:
                        heavy_cpus.append(f"CPU: {usage}%")
                    return usage, usage, heavy_cpus
                    
    except Exception:
        pass
        
    return 0.0, 0.0, []

def get_memory_usage(mock: bool = False) -> Tuple[float, int, int]:
    """
    Get current memory usage percentage and details.
    Uses 'cpstat os -f memory' on Checkpoint.
    Returns: (used_percent, total_bytes, free_bytes)
    """
    try:
        output = run_command(['cpstat', 'os', '-f', 'memory'], mock, 'memory')
        
        # Parse cpstat output
        # Look for "Total Real Memory (Bytes): X" and "Free Real Memory (Bytes): Y"
        total_match = re.search(r'Total Real Memory \(Bytes\)\s*:\s*(\d+)', output)
        free_match = re.search(r'Free Real Memory \(Bytes\)\s*:\s*(\d+)', output)
        
        if total_match and free_match:
            total_bytes = int(total_match.group(1))
            free_bytes = int(free_match.group(1))
            
            if total_bytes > 0:
                used_bytes = total_bytes - free_bytes
                used_percent = round((used_bytes / total_bytes) * 100, 2)
                return used_percent, total_bytes, free_bytes
                
        # Fallback to old format or other methods if needed
        # Example: Total Memory: 8192MB\nUsed Memory: 4096MB
        total_match = re.search(r'Total Memory\s*:\s*(\d+)', output)
        used_match = re.search(r'Used Memory\s*:\s*(\d+)', output)
        
        if total_match and used_match:
            total_mb = float(total_match.group(1))
            used_mb = float(used_match.group(1))
            if total_mb > 0:
                used_percent = round((used_mb / total_mb) * 100, 2)
                total_bytes = int(total_mb * 1024 * 1024)
                free_bytes = int((total_mb - used_mb) * 1024 * 1024)
                return used_percent, total_bytes, free_bytes
                
    except Exception:
        pass
        
    return 0.0, 0, 0

def get_cluster_state(mock: bool = False) -> str:
    """
    Get Checkpoint ClusterXL state.
    Uses 'cphaprob state'.
    """
    try:
        output = run_command(['cphaprob', 'state'], mock, 'cluster')
        
        # Look for "State: Active" or "State: Standby" or "State: Down" (Old format)
        match = re.search(r'State:\s*(.+)', output)
        if match:
            return match.group(1).strip()
            
        # Parse table format (New format)
        # Look for the line with "(local)" and extract the state (last column)
        # Example: 1 (local)  10.231.149.1    100%            ACTIVE
        for line in output.split('\n'):
            if '(local)' in line:
                parts = line.split()
                if parts:
                    state = parts[-1]
                    # Convert ACTIVE -> Active, STANDBY -> Standby
                    return state.capitalize()

        # Fallback
        if "Active" in output:
            return "Active"
        elif "Standby" in output:
            return "Standby"
            
    except Exception:
        pass
        
    return "Unknown"

def get_errors(mock: bool = False) -> List[str]:
    """
    Check for errors reported by the firewall.
    Uses 'cphaprob list' to check for critical devices.
    """
    errors = []
    try:
        output = run_command(['cphaprob', 'list'], mock, 'cphaprob_list')
        
        # Parse output for devices not in 'OK' state
        # Format: Device Name: X\nState: Y
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
    """
    Check for heavy connections from today.
    Uses 'fw ctl multik print_heavy_conn'.
    """
    heavy_conns = []
    try:
        # Get today's date in DD/MM/YY format
        from datetime import datetime
        today_str = datetime.now().strftime("%d/%m/%y")
        
        # In mock mode, we might need to adjust the date to match the mock data
        # or adjust the mock data to match today. 
        # For simplicity, let's assume the mock data has a specific date we look for,
        # OR we can just use the current date in the mock check if we were generating it dynamically.
        # But since MOCK_DATA is static, let's just check for the date present in MOCK_DATA if mock=True
        if mock:
             # For testing purposes, let's assume "today" is 17/12/25 based on the user request example
             today_str = "17/12/25"

        output = run_command(['fw', 'ctl', 'multik', 'print_heavy_conn'], mock, 'heavy_conn')
        
        if not output:
            return []
            
        lines = output.strip().split('\n')
        # Get last 5 lines
        last_5_lines = lines[-5:]
        
        for line in last_5_lines:
            if today_str in line:
                heavy_conns.append(line.strip())
                
    except Exception:
        pass
        
    return heavy_conns

def calculate_severity(
    cpu_usage: float,
    max_cpu_usage: float,
    memory_usage: float,
    cluster_state: str,
    errors: List[str],
    heavy_connections: List[str],
    warning_threshold: int,
    error_threshold: int
) -> str:
    """
    Calculate overall severity based on metrics.
    """
    severity = 'ok'
    
    # Check CPU (Average or Max)
    if cpu_usage >= error_threshold or max_cpu_usage >= error_threshold:
        severity = 'error'
    elif (cpu_usage >= warning_threshold or max_cpu_usage >= warning_threshold) and severity != 'error':
        severity = 'warning'
    
    # Check Memory
    if memory_usage >= error_threshold:
        severity = 'error'
    elif memory_usage >= warning_threshold and severity != 'error':
        severity = 'warning'
        
    # Check Cluster State (Down is bad)
    if cluster_state.lower() in ['down', 'problem', 'error', 'unknown']:
        severity = 'error'
        
    # Check Errors
    if errors:
        severity = 'error'
        
    # Check Heavy Connections
    if heavy_connections:
        severity = 'error'
        
    return severity

def get_hostname() -> str:
    """Get the system hostname."""
    try:
        return socket.gethostname()
    except Exception:
        return "checkpoint-fw"

def build_payload(
    cpu_usage: float,
    heavy_cpus: List[str],
    memory_usage: float,
    total_mem_bytes: int,
    free_mem_bytes: int,
    cluster_state: str,
    errors: List[str],
    heavy_connections: List[str],
    severity: str,
    project_name: str,
    system_name: str
) -> Dict:
    """Build the JSON payload."""
    hostname = get_hostname()
    
    # Format errors string
    error_str = "No Errors"
    if errors:
        error_str = ", ".join(errors)
        
    # Format CPU string
    cpu_str = f"{cpu_usage}%"
    if heavy_cpus:
        cpu_str += f" (Heavy: {', '.join(heavy_cpus)})"
        
    # Format Memory string
    # Free: X GB (Y%)
    free_gb = round(free_mem_bytes / (1024**3), 3)
    free_percent = 0.0
    if total_mem_bytes > 0:
        free_percent = round((free_mem_bytes / total_mem_bytes) * 100, 3)
        
    mem_str = f"Free: {free_gb:.3f}GB ({free_percent:.3f}%)"
    
    # Format Heavy Connections
    heavy_conn_str = "None"
    if heavy_connections:
        heavy_conn_str = f"{len(heavy_connections)} found"
        
    return {
        'projectName': project_name,
        'systemName': system_name,
        'payload': {
            'Id': hostname,
            'Name': hostname,
            'CPU': cpu_str,
            'Memory': mem_str,
            'Cluster State': cluster_state,
            'Errors': error_str,
            'Heavy Connections': heavy_conn_str,
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
    if sys.stdout.isatty():
        print(f"{colors.get(color, '')}{text}{colors['reset']}")
    else:
        print(text)

def main():
    parser = argparse.ArgumentParser(
        description='Gather Checkpoint firewall metrics'
    )
    parser.add_argument('--threshold-warning', type=int, default=85)
    parser.add_argument('--threshold-error', type=int, default=95)
    parser.add_argument('--project-name', type=str, default='Firewalls')
    parser.add_argument('--system-name', type=str, default='Checkpoint')
    parser.add_argument('--json-only', action='store_true', help='Output only JSON')
    parser.add_argument('--mock', action='store_true', help='Use mock data for testing')
    
    args = parser.parse_args()
    
    try:
        if not args.json_only:
            print_colored("Gathering Checkpoint metrics...", 'cyan')
            
        # Collect metrics
        cpu_usage, max_cpu_usage, heavy_cpus = get_cpu_usage(args.mock, args.threshold_warning)
        memory_usage, total_mem, free_mem = get_memory_usage(args.mock)
        cluster_state = get_cluster_state(args.mock)
        errors = get_errors(args.mock)
        heavy_connections = get_heavy_connections(args.mock)
        
        # Calculate severity
        severity = calculate_severity(
            cpu_usage,
            max_cpu_usage,
            memory_usage,
            cluster_state,
            errors,
            heavy_connections,
            args.threshold_warning,
            args.threshold_error
        )
        
        # Build payload
        payload = build_payload(
            cpu_usage,
            heavy_cpus,
            memory_usage,
            total_mem,
            free_mem,
            cluster_state,
            errors,
            heavy_connections,
            severity,
            args.project_name,
            args.system_name
        )
        
        # Output
        if args.json_only:
            print(json.dumps(payload, indent=2))
        else:
            print_colored("\nMetrics Summary:", 'green')
            print(f"CPU: {cpu_usage}%")
            if heavy_cpus:
                print_colored(f"Heavy CPUs: {', '.join(heavy_cpus)}", 'yellow')
            
            # Memory summary
            free_gb = round(free_mem / (1024**3), 3)
            free_percent = 0.0
            if total_mem > 0:
                free_percent = round((free_mem / total_mem) * 100, 3)
            print(f"Memory: Free {free_gb:.3f}GB ({free_percent:.3f}%)")
            
            print(f"Cluster State: {cluster_state}")
            print(f"Errors: {len(errors)}")
            
            if heavy_connections:
                print_colored(f"Heavy Connections: {len(heavy_connections)} found", 'red')
                for conn in heavy_connections:
                    print(f"  - {conn[:100]}...")
            else:
                print("Heavy Connections: None")
                
            print_colored(f"Severity: {severity}", 'red' if severity == 'error' else 'green')
            
            print_colored("\nJSON Output:", 'cyan')
            print(json.dumps(payload, indent=2))
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
