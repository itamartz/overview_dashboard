#!/usr/bin/env python3
"""
OpenShift Workload Monitoring Agent

Gathers resource statuses from OpenShift/Kubernetes and posts them to the Dashboard API.
Follows the Overview Dashboard Agent Development Guide standards.
"""

import argparse
import json
import os
import subprocess
import sys
import hashlib
import urllib.request
import urllib.error
import ssl

# Define terminal colors
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
    print_color(f"  Overview Dashboard - OpenShift Agent", 'cyan')
    print_color(f"  Mode:         {mode}", 'yellow')
    print_color(f"  System Name:  {config['systemName']}", 'cyan')
    print_color(f"  Project Name: {config['projectName']}", 'cyan')
    print_color(f"  API URL:      {config['apiUrl']}", 'cyan')
    print_color("==================================================", 'cyan')

def generate_md5_id(system_name: str, project_name: str, resource_name: str, namespace: str) -> str:
    """Generate deterministic MD5 Component ID."""
    unique_string = f"{system_name}-{project_name}-{namespace}-{resource_name}".encode('utf-8')
    return hashlib.md5(unique_string).hexdigest()

def get_mock_data(k8s_kind: str) -> dict:
    """Return mock payload for testing."""
    if k8s_kind == "deployments":
        return {
            "items": [
                {
                    "metadata": {"name": "mock-app", "namespace": "default", "creationTimestamp": "2025-01-01T00:00:00Z"},
                    "spec": {"replicas": 3},
                    "status": {"availableReplicas": 3}
                },
                {
                    "metadata": {"name": "mock-failing-app", "namespace": "default", "creationTimestamp": "2025-01-01T00:00:00Z"},
                    "spec": {"replicas": 2},
                    "status": {"availableReplicas": 1}
                }
            ]
        }
    return {"items": []}

def run_oc(command: str, mock: bool, k8s_kind: str) -> dict:
    """Run an oc command and return the JSON output."""
    if mock:
        return get_mock_data(k8s_kind)
        
    try:
        subprocess.run(["oc", "version", "--client"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print_color("Error: oc not found. Please ensure oc is installed and in your PATH.", 'red')
        return None
    except subprocess.CalledProcessError:
        pass

    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print_color(f"Error running command '{command}': {e.stderr}", 'red')
        return None
    except json.JSONDecodeError:
        print_color(f"Error decoding JSON from command '{command}'", 'red')
        return None

def calculate_status(kind: str, spec: dict, status: dict) -> tuple:
    """Determine the status string and severity based on resource kind and status."""
    desired = 0
    current = 0
    
    if kind == "deployments":
        desired = spec.get('replicas', 1)
        current = status.get('availableReplicas', 0)
    elif kind == "statefulsets":
        desired = spec.get('replicas', 1)
        current = status.get('readyReplicas', 0)
    elif kind == "daemonsets":
        desired = status.get('desiredNumberScheduled', 0)
        current = status.get('numberReady', 0)

    status_str = "Unknown"
    severity = "info"

    if desired > 0:
        if current >= desired:
            status_str = "Running"
            severity = "ok"
        elif current == 0:
            status_str = "Down"
            severity = "error"
        else:
            status_str = "Degraded"
            severity = "warning"
    else:
        status_str = "ScaledDown"
        severity = "warning"

    return status_str, severity, desired, current

def post_to_api(payload: dict, config: dict, args: argparse.Namespace):
    """POST component payload to the API."""
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
    parser = argparse.ArgumentParser(description='OpenShift Monitoring Agent')
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
        "projectName": "OpenShift Workloads",
        "systemName": "OpenShift",
        "defaultTTL": 300,
        "namespaces": []
    }
    
    if os.path.exists(args.config_path):
        try:
            with open(args.config_path, 'r') as f:
                file_config = json.load(f)
                config.update(file_config)
        except Exception as e:
            print_color(f"Error reading config {args.config_path}: {e}", 'red')
            sys.exit(1)

    # Apply overrides
    if args.api_url: config['apiUrl'] = args.api_url
    if args.project_name: config['projectName'] = args.project_name
    if args.system_name: config['systemName'] = args.system_name
    if args.ttl: config['defaultTTL'] = args.ttl

    print_banner(config, args)

    resources_to_check = {
        "Deployments": "deployments",
        "Statefulsets": "statefulsets",
        "Daemonsets": "daemonsets"
    }

    for res_name, k8s_kind in resources_to_check.items():
        print_color(f"\nCollecting {k8s_kind}...", 'cyan', args.quiet)
        data = run_oc(f"oc get {k8s_kind} --all-namespaces -o json", args.mock, k8s_kind)
        
        if not data:
            continue

        items = data.get('items', [])
        for item in items:
            metadata = item.get('metadata', {})
            status_obj = item.get('status', {})
            spec_obj = item.get('spec', {})
            
            name = metadata.get('name')
            namespace = metadata.get('namespace')
            created_at = metadata.get('creationTimestamp')
            
            # Filter namespaces if specified in config
            if config.get('namespaces') and namespace not in config['namespaces']:
                continue
            
            status_str, severity, desired, current = calculate_status(k8s_kind, spec_obj, status_obj)
            component_id = generate_md5_id(config['systemName'], config['projectName'], name, namespace)
            
            resource_entry = {
                "Id": component_id,
                "Name": name,
                "Namespace": namespace,
                "Status": status_str,
                "Severity": severity,
                "TTL": config['defaultTTL'],
                "ClusterCreatedAt": created_at,
                "Replicas": f"{current}/{desired}",
                "Kind": res_name
            }
            
            payload = {
                "systemName": config['systemName'],
                "projectName": config['projectName'],
                "payload": resource_entry
            }
            
            post_to_api(payload, config, args)

if __name__ == "__main__":
    main()
