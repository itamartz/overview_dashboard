#!/usr/bin/env python3
"""
Post Checkpoint Firewall Metrics to Monitoring API

Wrapper script for backwards compatibility. Uses get_checkpoint_metrics.py internally.
"""

import sys
import os

# Import the metrics gathering module
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

import get_checkpoint_metrics

if __name__ == '__main__':
    get_checkpoint_metrics.main()
