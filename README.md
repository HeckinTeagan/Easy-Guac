# 🥑 Easy Guac
**A streamlined, single-script Apache Guacamole installer for Linux labs.**

Easy Guac is a shell script designed to simplify the deployment of Apache Guacamole using Docker. It automates dependency management, database initialization, and container orchestration across multiple Linux distributions.

> [!WARNING]  
> **LAB USE ONLY:** This script is intended for development and testing in isolated lab environments. It serves Guacamole over HTTP (Port 8080). It is **not** intended for production use or exposure to the public internet without an external reverse proxy and additional security hardening.

## 🚀 Deployment
> [!NOTE]
> This script requires root privileges to install Docker dependencies and manage system services. Please ensure you have `sudo` access on your machine. Add `sudo` to the one-liner below between && and ./easy-guac.sh

To deploy the full stack (Guacamole, Guacd, and Postgres) with a single command, run:
```bash
wget -qO easy-guac.sh https://raw.githubusercontent.com/HeckinTeagan/Easy-Guac/main/easy-guac.sh && chmod +x easy-guac.sh && ./easy-guac.sh 
```


---

## ✨ Key Features
* **📦 Single-Script Design:** Deploys the entire environment from one file.
* **⚡ Multi-Distro Logic:** Automated package handling for **Alpine, Debian/Ubuntu, Fedora/RHEL, and Arch Linux.**
* **🛡️ Automated Setup:** Generates random database credentials and initializes the SQL schema on first run.
* **🚦 Health Monitoring:** Watches the Java process, DB sockets, and Tomcat status to ensure the stack is operational before finishing.

## 🛠 Usage
| Option | Description |
| :--- | :--- |
| `./easy-guac.sh` | Standard interactive setup. |
| `./easy-guac.sh -i` | **Install Mode:** Skips the welcome prompt. |
| `./easy-guac.sh -p` | **Purge:** Completely removes all containers, volumes, and local data. |

---

## 🌐 Network Troubleshooting
If the script finishes successfully but you cannot access the web interface at the provided URL, check the following:

### 1. Firewall Rules
Ensure your host OS allows traffic on **TCP Port 8080**.
* **Ubuntu (UFW):** `sudo ufw allow 8080/tcp`
* **Fedora/RHEL (Firewalld):** `sudo firewall-cmd --add-port=8080/tcp --permanent && sudo firewall-cmd --reload`

### 2. Virtual Machine Networking
* **NAT Mode:** If using VirtualBox or VMware in NAT mode, you must create a **Port Forwarding Rule** (Host Port 8080 ⮕ Guest Port 8080).
* **Bridged Mode:** Ensure the VM has a valid IP address on your local network.

### 3. Remote Headless Servers
If your lab server is remote and does not have a GUI, the easiest way to access the interface is via an **SSH Tunnel**:
* Connect using: `ssh -L 8080:localhost:8080 user@your-lab-ip`
* Once connected, access Guacamole at `http://localhost:8080/guacamole/` on your local machine.

---

## 🔑 Default Credentials
* **Username:** `guacadmin`
* **Password:** `guacadmin`
* *Note: The database password is randomly generated and stored in `/opt/stacks/guacamole/.env`.*