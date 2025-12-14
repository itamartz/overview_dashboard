# Installation Instructions

1.  **Copy Files**
    Copy the python script and systemd files to the server:
    ```bash
    mkdir -p /opt/monitoring
    cp monitor_ocp.py /opt/monitoring/
    cp monitor-ocp.service /etc/systemd/system/
    cp monitor-ocp.timer /etc/systemd/system/
    ```

2.  **Permissions**
    Make sure the script is executable (optional for python, but good practice):
    ```bash
    chmod +x /opt/monitoring/monitor_ocp.py
    ```

3.  **Reload Daemon**
    Reload systemd to recognize the new files:
    ```bash
    systemctl daemon-reload
    ```

4.  **Enable and Start Timer**
    Start the timer immediately and enable it to persist on reboot:
    ```bash
    systemctl enable --now monitor-ocp.timer
    ```

5.  **Status Check**
    Verify the timer is active:
    ```bash
    systemctl list-timers --all | grep monitor
    ```
    
    Trigger a manual run to test:
    ```bash
    systemctl start monitor-ocp.service
    systemctl status monitor-ocp.service
    ```
