#!/usr/bin/env python3
"""
Post Linux System Metrics to Monitoring API

Gathers system metrics using get_system_metrics.py and posts them to the API endpoint.

Usage:
    python3 post_system_metrics.py
    python3 post_system_metrics.py --api-url "http://localhost:5000/api/components"
    python3 post_system_metrics.py --timeout 30
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error

# Import the metrics gathering module
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from get_system_metrics import (
    get_cpu_usage,
    get_memory_usage,
    get_disk_usage,
    get_failed_services,
    get_stopped_automatic_services,
    calculate_severity,
    build_payload,
    print_colored,
    DEFAULT_IGNORE_SERVICES
)


def post_metrics(payload: dict, api_url: str, timeout: int) -> dict:
    """
    Post metrics to the API endpoint.
    
    Args:
        payload: The metrics payload dictionary
        api_url: The API endpoint URL
        timeout: Request timeout in seconds
    
    Returns:
        The API response as a dictionary
    """
    json_data = json.dumps(payload).encode('utf-8')
    
    request = urllib.request.Request(
        api_url,
        data=json_data,
        headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_data = response.read().decode('utf-8')
            if response_data:
                return json.loads(response_data)
            return {'status': 'success', 'code': response.status}
    
    except urllib.error.HTTPError as e:
        error_body = ''
        try:
            error_body = e.read().decode('utf-8')
        except Exception:
            pass
        
        raise Exception(f"HTTP Error {e.code}: {e.reason}. Response: {error_body}")
    
    except urllib.error.URLError as e:
        raise Exception(f"URL Error: {e.reason}")


def main():
    parser = argparse.ArgumentParser(
        description='Post Linux system metrics to the monitoring API'
    )
    parser.add_argument(
        '--api-url',
        type=str,
        default='http://localhost:5000/api/components',
        help='API endpoint URL (default: http://localhost:5000/api/components)'
    )
    parser.add_argument(
        '--timeout',
        type=int,
        default=10,
        help='Request timeout in seconds (default: 10)'
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
        default='Workstations',
        help='Project name for the payload (default: Workstations)'
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
        '--check-stopped',
        action='store_true',
        help='Also check for stopped enabled services (not just failed)'
    )
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='Suppress output except for errors'
    )
    
    args = parser.parse_args()
    
    try:
        if not args.quiet:
            print_colored("Collecting system metrics...", 'cyan')
        
        # Collect metrics
        cpu_usage = get_cpu_usage()
        memory_usage = get_memory_usage()
        disks = get_disk_usage()
        
        # Get failed services
        failed_services = get_failed_services(args.ignore_services)
        if args.check_stopped:
            stopped_services = get_stopped_automatic_services(args.ignore_services)
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
        
        if not args.quiet:
            print_colored(f"\nPosting to API: {args.api_url}", 'cyan')
            print(f"Timeout: {args.timeout} seconds")
        
        # Post to API
        response = post_metrics(payload, args.api_url, args.timeout)
        
        if not args.quiet:
            print_colored("\n[SUCCESS] Metrics posted successfully.", 'green')
            print_colored("\nAPI Response:", 'cyan')
            print(json.dumps(response, indent=2))
        
        return response
    
    except urllib.error.URLError as e:
        print_colored("\n[NETWORK ERROR]", 'red')
        print_colored(f"Error: {e}", 'red')
        sys.exit(1)
    
    except Exception as e:
        print_colored("\n[ERROR]", 'red')
        print_colored(f"Error: {e}", 'red')
        sys.exit(1)


if __name__ == '__main__':
    main()
