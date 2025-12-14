import subprocess
import json
import requests
import datetime
import os
import sys

# Configuration
API_URL = os.getenv("DASHBOARD_API_URL", "https://overview/api/components")
SYSTEM_NAME = "OpenShift"

# Resource Mapping
RESOURCES = {
    "Deployments": "deployments",
    "Statefulsets": "statefulsets",
    "Daemonsets": "daemonsets"
}

def run_oc(command):
    """Run a oc command and return the JSON output."""
    try:
        # Check if oc is available
        subprocess.run(["oc", "version", "--client"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print("Error: oc not found. Please ensure oc is installed and in your PATH.")
        return None
    except subprocess.CalledProcessError:
        pass # oc exists, proceed to try the actual command

    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running command '{command}': {e.stderr}")
        return None
    except json.JSONDecodeError:
        print(f"Error decoding JSON from command '{command}'")
        return None

def calculate_status(kind, spec, status):
    """Determine the status string and severity based on resource kind and status."""
    desired = 0
    current = 0
    
    if kind == "deployments":
        desired = spec.get('replicas', 1) # Default to 1 if not specified? 
        current = status.get('availableReplicas', 0)
    elif kind == "statefulsets":
        desired = spec.get('replicas', 1)
        current = status.get('readyReplicas', 0)
    elif kind == "daemonsets":
        desired = status.get('desiredNumberScheduled', 0)
        current = status.get('numberReady', 0)

    # Status Logic
    status_str = "Unknown"
    severity = "info" # Default fallback, but logic covers cases below

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
        # Scaled down intentionally
        status_str = "ScaledDown"
        severity = "warning" # User requested warning/error for scaled down state

    # Debug output to troubleshoot logic
    #print(f"DEBUG [{kind}]: desired={desired}, current={current} -> status={status_str}, severity={severity}")

    return status_str, severity, desired, current

def collect_and_push():
    for project_name, k8s_kind in RESOURCES.items():
        print(f"Collecting {k8s_kind}...")
        data = run_oc(f"oc get {k8s_kind} --all-namespaces -o json")
        
        if not data:
            print(f"No data found for {k8s_kind}")
            continue

        resource_list = []
        
        items = data.get('items', [])
        for item in items:
            metadata = item.get('metadata', {})
            status_obj = item.get('status', {})
            spec_obj = item.get('spec', {})
            
            name = metadata.get('name')
            namespace = metadata.get('namespace')
            created_at = metadata.get('creationTimestamp')
            
            status_str, severity, desired, current = calculate_status(k8s_kind, spec_obj, status_obj)
            
            resource_entry = {
                "Id": name,  # Unique ID for Upsert logic
                "Name": name,
                "Namespace": namespace,
                "Status": status_str,
                "Severity": severity,
                "ClusterCreatedAt": created_at,
                "Replicas": f"{current}/{desired}"
            }
            resource_list.append(resource_entry)

        # Post each resource as a separate component
        print(f"Found {len(resource_list)} resources for {project_name}")
        
        for resource in resource_list:            
            body = {
                "systemName": SYSTEM_NAME,
                "projectName": project_name,
                "payload": json.dumps(resource)
            }
            
            try:
                resp = requests.post(API_URL, json=body)
                if resp.status_code < 200 or resp.status_code >= 300:
                     print(f"Failed to post {resource['name']}. Code: {resp.status_code}, Body: {resp.text}")
            except Exception as e:
                print(f"Exception posting {resource['name']}: {e}")
        
        print(f"Finished posting {project_name}")

if __name__ == "__main__":
    collect_and_push()
