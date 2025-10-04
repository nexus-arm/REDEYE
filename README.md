A comprehensive Nmap scanning tool with session management, reporting, and advanced scanning capabilities. Available in both Python and Bash implementations.

## Features

- **Automatic Dependency Management**: Auto-detects OS and installs required tools (nmap, ndiff, xsltproc)
- **Multi-Distribution Support**: Ubuntu, Debian, Arch Linux, Fedora/RHEL, and Termux
- **Session Management**: Save and organize scan results with timestamped outputs
- **Basic Scans**: Ping scan, intense scan, fast scan, default scripts, vulnerability scanning
- **Advanced Scans**: 20+ advanced scanning techniques including:
  - Firewall/IDS evasion (fragmentation, decoys, idle scans)
  - Service-specific vulnerability scans (SMB, FTP, MySQL, Web)
  - SSL/TLS vulnerability checks (Heartbleed)
  - WAF detection and DoS vulnerability testing
  - Full TCP/UDP comprehensive scans
- **Scan Comparison**: Compare two scan results using ndiff
- **HTML Reporting**: Generate professional HTML reports from XML scans
- **Interactive Helper**: Built-in Nmap command reference guide
- **Color-coded Interface**: Beautiful terminal UI with organized menus

## Supported Distributions

- **Debian/Ubuntu** - APT package manager
- **Arch Linux** - Pacman package manager
- **Fedora/RHEL/CentOS** - DNF/YUM package managers
- **Termux** - Android terminal environment
- **Others** - Automatic fallback detection

## Requirements

The script automatically checks and installs:
- `nmap` - Network exploration tool and security scanner
- `ndiff` - Nmap scan comparison tool
- `xsltproc` - XSLT processor for HTML report generation

## Installation

### Python Version

```bash
# Download the script
wget https://raw.githubusercontent.com/yourusername/redeye/main/redeye.py

# Make it executable
chmod +x redeye.py

# Run the scanner
python3 redeye.py
```

### Bash Version

```bash
# Download the script
wget https://raw.githubusercontent.com/yourusername/redeye/main/redeye.sh

# Make it executable
chmod +x redeye.sh

# Run the scanner
./redeye.sh
```

## Usage

### Quick Start

1. **Launch RedEye**
   ```bash
   # Python
   python3 redeye.py
   
   # Bash
   ./redeye.sh
   ```

2. **Set a Target** (Option 1)
   ```
   Enter target IP or domain: 192.168.1.1
   ```

3. **Create a Session** (Option 8)
   ```
   Enter session name: my_network_scan
   ```

4. **Run a Scan** (Options 3-7 or 11)
   - Choose from basic or advanced scan options
   - Results are automatically saved to your session

### Basic Scan Options

- **Ping Scan (3)**: Host discovery only, no port scanning
- **Intense Scan (4)**: Aggressive scan with OS detection (-A -T4)
- **Fast Scan (5)**: Quick scan of top 100 ports
- **Default Scripts (6)**: Safe, default NSE scripts
- **Vulnerability Scan (7)**: General vulnerability detection scripts

### Advanced Scan Options (Option 11)

#### Firewall/IDS Evasion
1. Aggressive Discovery (All ping types)
2. Full Port Scan (Skip host discovery)
3. Fragmented Packets (Evade packet filters)
4. Decoy Scan (Hide your IP among decoys)
5. Idle Scan (Zombie host stealth scanning)

#### Vulnerability & Service Scans
6. Comprehensive Web Server Scan
7. SMB Vulnerability Scan (EternalBlue, etc.)
8. FTP Vulnerability Scan
9. MySQL Vulnerability Scan
10. Heartbleed SSL Check
11. WAF Detection
12. Slowloris DoS Vulnerability

#### Deep Scans
13. Full TCP & UDP Scan (Very slow)
14. Safe Script Scan (Non-intrusive)
15. Exploit Scripts (Dangerous - use with caution)
16. Brute Force Scripts
17. Traceroute & Geolocation
18. Aggressive All Ports (-A -p-)
19. Network Sweep (Ping only)
20. All TCP Ports + OS Detection

### Session Management

All scans within a session are saved to `redeye_sessions/<session_name>/` with automatic timestamping:
- `scan_YYYY-MM-DD_HH-MM-SS.nmap` - Normal output
- `scan_YYYY-MM-DD_HH-MM-SS.xml` - XML output for reports

### Scan Comparison (Option 9)

Compare two XML scans to identify changes:
```
1. Select first scan file
2. Select second scan file
3. View differences using ndiff
```

### HTML Report Generation (Option 10)

Generate professional HTML reports:
```
1. Select XML scan file
2. Report generated at same location with .html extension
```

### Custom Ports

Set custom ports (Option 2) to focus scans:
```
Examples:
- Single port: 80
- Port range: 1-1000
- Multiple ports: 22,80,443
- Mixed: 22,80-100,443,8000-9000
```

### Custom Nmap Commands (Option 12)

Execute any nmap command while maintaining session saving:
```
Enter full nmap command: nmap -sV -O --script=vuln 192.168.1.1
```

## Command Helper (Option 13)

Interactive reference guide covering:
1. Host Discovery options
2. Scan Techniques
3. Port Specification
4. Service & OS Detection
5. Nmap Scripting Engine (NSE)
6. Timing and Performance
7. Output Formats

## Project Structure

```
redeye/
├── redeye.py              # Python implementation
├── redeye.sh              # Bash implementation
├── README.md              # This file
└── redeye_sessions/       # Created at runtime
    └── <session_name>/
        ├── scan_*.nmap    # Scan results (normal format)
        ├── scan_*.xml     # Scan results (XML format)
        └── scan_*.html    # Generated HTML reports
```

## Testing Dependency Installation

Test the automatic dependency installation without running the full scanner:

```bash
# Python
python3 redeye.py --test-deps

# Bash
./redeye.sh --test-deps
```

## Root Privileges

Many advanced scans require root privileges:
- SYN scans (-sS)
- OS detection (-O)
- UDP scans (-sU)
- Some stealth techniques

The script will automatically use `sudo` when needed.

## Safety Features

- **Dependency Verification**: Checks all tools before scanning
- **Session Isolation**: Each project gets its own directory
- **Automatic Backups**: All scans saved with timestamps
- **Warning Prompts**: Dangerous scans require confirmation
- **Error Handling**: Graceful handling of missing tools or permissions

## Examples

### Basic Network Discovery
```bash
1. Set target: 192.168.1.0/24
2. Create session: home_network
3. Run ping scan (Option 3)
4. Review results in redeye_sessions/home_network/
```

### Vulnerability Assessment
```bash
1. Set target: example.com
2. Create session: vulnerability_assessment
3. Run vulnerability scan (Option 7)
4. Generate HTML report (Option 10)
```

### Service Enumeration
```bash
1. Set target: 10.0.0.5
2. Set ports: 1-10000
3. Create session: service_enum
4. Run intense scan (Option 4)
5. Compare with previous scan (Option 9)
```

### Web Application Testing
```bash
1. Set target: webapp.example.com
2. Set ports: 80,443,8080,8443
3. Advanced menu (Option 11)
4. Web server scan (Option 6)
5. WAF detection (Option 11)
```

## Troubleshooting

### Tools Not Installing
- Ensure you have internet connectivity
- Check if your package manager is up to date
- Verify you have sudo privileges
- Try manual installation using suggested commands

### Permission Denied
- Use sudo for scans requiring root privileges
- Check firewall rules that might block scanning
- Verify target is reachable

### Scans Not Saving
- Ensure you've created a session (Option 8)
- Check write permissions in redeye_sessions/
- Verify disk space availability

## Legal Notice

**IMPORTANT**: This tool is for authorized security testing only.

- Only scan networks and systems you own or have explicit permission to test
- Unauthorized port scanning may be illegal in your jurisdiction
- Some scans can disrupt services or trigger security alerts
- The authors are not responsible for misuse of this tool

Always obtain proper authorization before conducting security assessments.

## Contributing

Contributions are welcome! Areas for improvement:
- Additional scan templates
- More OS/package manager support
- Enhanced reporting features
- Export formats (JSON, CSV)
- Scan scheduling and automation

## License

This project is provided as-is for educational and authorized security testing purposes.

## Credits

Built on top of the powerful Nmap security scanner by Gordon Lyon (Fyodor).

## Version

**RedEye Nmap Scanner v1.0 - Professional Edition**

---

*Scan responsibly. Test ethically. Secure thoroughly.*