#!/usr/bin/env python3
"""
Post Linux System Metrics to Monitoring API

Wrapper script for get_system_metrics.py to maintain backward compatibility.
"""

import sys
import subprocess
import os

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_script = os.path.join(script_dir, 'get_system_metrics.py')
    
    cmd = [sys.executable, target_script] + sys.argv[1:]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
    except Exception as e:
        print(f"Error calling {target_script}: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
