# =============================================================================
# REDEYE NMAP SCANNER - PROFESSIONAL EDITION
# =============================================================================
# A comprehensive Nmap scanning tool with session management, reporting,
# and advanced scanning capabilities.
# =============================================================================

# =============================================================================
# IMPORTS
# =============================================================================
import os
import shlex
import shutil
import subprocess
import sys
import textwrap
from datetime import datetime

# =============================================================================
# CONSTANTS AND GLOBAL VARIABLES
# =============================================================================
REQUIRED = ["nmap", "ndiff", "xsltproc"]
SESSIONS_DIR = "redeye_sessions"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def run_cmd(cmd, capture=False):
    """Run command (list or string). Return (returncode, stdout, stderr)."""
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    try:
        if capture:
            proc = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
        else:
            proc = subprocess.run(cmd, check=False)
            return proc.returncode, "", ""
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except Exception as e:
        return 1, "", str(e)

def shutil_which(name):
    """Simple wrapper for shutil.which but avoids import collision if needed."""
    return shutil.which(name)

def is_root():
    """Check if running as root user."""
    try:
        return os.geteuid() == 0
    except AttributeError:
        # Windows or other, assume not root
        return False

# =============================================================================
# DEPENDENCY MANAGEMENT FUNCTIONS
# =============================================================================

def detect_os():
    """Return tuple (os_id, pkg_manager, install_cmd_list, update_cmd_list)."""
    # default unknown
    os_id = "unknown"
    pkg = None
    install_cmd = None
    update_cmd = None

    # termux detection
    if os.environ.get("PREFIX", "").startswith("/data/data/com.termux/files/usr") or os.path.exists("/data/data/com.termux/files/usr"):
        os_id = "termux"
        pkg = "pkg"
        install_cmd = ["pkg", "install", "-y"]
        update_cmd = ["pkg", "update", "-y"]
        return os_id, pkg, install_cmd, update_cmd

    # read /etc/os-release if exists
    if os.path.exists("/etc/os-release"):
        try:
            with open("/etc/os-release", "r", encoding="utf-8") as f:
                data = f.read().lower()
            # simple matching
            if "ubuntu" in data:
                os_id = "ubuntu"
                pkg = "apt"
                install_cmd = ["apt-get", "install", "-y"]
                update_cmd = ["apt-get", "update", "-y"]
            elif "debian" in data and "ubuntu" not in data:
                os_id = "debian"
                pkg = "apt"
                install_cmd = ["apt-get", "install", "-y"]
                update_cmd = ["apt-get", "update", "-y"]
            elif "arch" in data:
                os_id = "arch"
                pkg = "pacman"
                install_cmd = ["pacman", "-S", "--noconfirm"]
                update_cmd = ["pacman", "-Sy", "--noconfirm"]
            elif any(x in data for x in ("fedora", "rhel", "centos", "red hat")):
                os_id = "redhat"
                # prefer dnf when available
                if shutil_which("dnf"):
                    pkg = "dnf"
                    install_cmd = ["dnf", "install", "-y"]
                    update_cmd = ["dnf", "makecache", "--refresh", "-y"]
                else:
                    pkg = "yum"
                    install_cmd = ["yum", "install", "-y"]
                    update_cmd = ["yum", "makecache", "-y"]
            else:
                # try ID_LIKE fallback
                if "id_like=debian" in data or "id_like=debian" in data.replace('"', ''):
                    os_id = "debian-like"
                    pkg = "apt"
                    install_cmd = ["apt-get", "install", "-y"]
                    update_cmd = ["apt-get", "update", "-y"]
        except Exception:
            pass

    # fallback: detect package manager binaries
    if pkg is None:
        if shutil_which("apt-get"):
            os_id = os_id if os_id != "unknown" else "debian-like"
            pkg = "apt"
            install_cmd = ["apt-get", "install", "-y"]
            update_cmd = ["apt-get", "update", "-y"]
        elif shutil_which("pacman"):
            os_id = "arch"
            pkg = "pacman"
            install_cmd = ["pacman", "-S", "--noconfirm"]
            update_cmd = ["pacman", "-Sy", "--noconfirm"]
        elif shutil_which("dnf"):
            os_id = "redhat"
            pkg = "dnf"
            install_cmd = ["dnf", "install", "-y"]
            update_cmd = ["dnf", "makecache", "--refresh", "-y"]
        elif shutil_which("yum"):
            os_id = "redhat"
            pkg = "yum"
            install_cmd = ["yum", "install", "-y"]
            update_cmd = ["yum", "makecache", "-y"]
        elif shutil_which("pkg"):
            os_id = "termux"
            pkg = "pkg"
            install_cmd = ["pkg", "install", "-y"]
            update_cmd = ["pkg", "update", "-y"]

    return os_id, pkg, install_cmd, update_cmd

def check_tools():
    """Check which required tools are available."""
    missing = []
    found = []
    for b in REQUIRED:
        if shutil_which(b):
            found.append(b)
        else:
            missing.append(b)
    return found, missing

def pkg_name_for_bin(bin_name, pkg_manager):
    """Map binary to package name per package manager."""
    # default identity
    if pkg_manager in ("apt", "pkg"):
        if bin_name == "ndiff":
            return "nmap"  # ndiff often included with nmap on Debian/Ubuntu
        return bin_name
    if pkg_manager == "pacman":
        if bin_name == "xsltproc":
            return "libxslt"
        if bin_name == "ndiff":
            return "nmap"
        return bin_name
    if pkg_manager in ("dnf", "yum"):
        if bin_name == "xsltproc":
            return "libxslt"
        if bin_name == "ndiff":
            return "nmap"
        return bin_name
    # fallback
    return bin_name

def attempt_install(missing, pkg_manager, install_cmd, update_cmd):
    """Try to update db and install missing packages. Return True if all installed."""
    if pkg_manager is None or install_cmd is None:
        print("[ERROR] No supported package manager detected; cannot install automatically.")
        return False

    # update if possible
    if update_cmd:
        print(f"[INFO] Running update: {' '.join(update_cmd)}")
        rc, out, err = run_cmd(update_cmd, capture=True)
        if rc != 0:
            print(f"[WARN] Update command returned {rc}. stdout: {out} stderr: {err}")

    pkg_names = []
    for b in missing:
        pkg_names.append(pkg_name_for_bin(b, pkg_manager))

    # dedupe while preserving order
    seen = set()
    uniq = []
    for p in pkg_names:
        if p not in seen:
            seen.add(p)
            uniq.append(p)

    cmd = install_cmd + uniq
    print(f"[INFO] Trying install: {' '.join(cmd)} (without sudo)")

    rc, out, err = run_cmd(cmd, capture=True)
    if rc == 0:
        print("[INFO] Install command finished, re-checking tools...")
    else:
        print(f"[WARN] Install without sudo returned {rc}. stderr: {err}")

    # re-check
    _, still_missing = check_tools()
    if not still_missing:
        print("[INFO] All tools installed successfully.")
        return True

    # try with sudo if not root
    if not is_root():
        sudo_cmd = ["sudo"] + cmd
        print(f"[INFO] Retrying with sudo: {' '.join(sudo_cmd)}")
        rc, out, err = run_cmd(sudo_cmd, capture=True)
        if rc == 0:
            _, still_missing = check_tools()
            if not still_missing:
                print("[INFO] All tools installed successfully (with sudo).")
                return True
            else:
                print(f"[WARN] Still missing after sudo install: {still_missing}")
        else:
            print(f"[ERROR] sudo install failed with rc={rc}. stderr: {err}")

    else:
        print("[INFO] Already running as root; attempted install above failed.")

    return False

def print_manual_suggestions(pkg_manager):
    """Print manual installation suggestions for different package managers."""
    print("\n=== Manual installation suggestions ===")
    if pkg_manager == "apt":
        print("Debian/Ubuntu (APT):")
        print("  sudo apt-get update")
        print("  sudo apt-get install -y nmap ndiff xsltproc")
        print("  (ndiff usually included with nmap; if not, search 'apt-cache search ndiff')")
    elif pkg_manager == "pkg":
        print("Termux (pkg):")
        print("  pkg update")
        print("  pkg install nmap libxslt")
        print("  (ndiff usually comes with nmap)")
    elif pkg_manager == "pacman":
        print("Arch (pacman):")
        print("  sudo pacman -Sy")
        print("  sudo pacman -S nmap libxslt")
        print("  (ndiff usually part of nmap package)")
    elif pkg_manager in ("dnf", "yum"):
        print("Fedora/RHEL (dnf/yum):")
        print("  sudo {} makecache --refresh".format(pkg_manager))
        print("  sudo {} install -y nmap libxslt".format(pkg_manager))
        print("  (ndiff usually comes with nmap)")
    else:
        print("Unknown package manager. Try installing: nmap, libxslt (xsltproc).")
    print("If you are inside a container or don't have privileges, consider contacting the sysadmin or using a container that has these tools.")

def ensure_tools():
    """Main entry: detect OS, check and attempt install, print suggestions on failure."""
    print("[INFO] Checking required tools:", ", ".join(REQUIRED))
    found, missing = check_tools()
    if not missing:
        print("[INFO] All required tools are present:", ", ".join(found))
        return True

    print("[WARN] Missing tools:", ", ".join(missing))
    os_id, pkg_manager, install_cmd, update_cmd = detect_os()
    print(f"[INFO] Detected OS: {os_id}, package manager: {pkg_manager}")

    ok = attempt_install(missing, pkg_manager, install_cmd, update_cmd)
    if ok:
        return True

    # final check & suggestions
    _, still_missing = check_tools()
    if still_missing:
        print("[ERROR] Could not install:", ", ".join(still_missing))
        print_manual_suggestions(pkg_manager)
        return False
    return True

# =============================================================================
# UI AND DISPLAY FUNCTIONS
# =============================================================================

class Colors:
    """Class for storing ANSI color codes for terminal output."""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def show_banner():
    """Displays the RedEye ASCII art banner."""
    logo = r"""
░▒▓███████▓▒░░▒▓████████▓▒░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
░▒▓███████▓▒░░▒▓██████▓▒░ ░▒▓█▓▒░░▒▓█▓▒░▒▓██████▓▒░  ░▒▓██████▓▒░░▒▓██████▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░   ░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░   ░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░▒▓███████▓▒░░▒▓████████▓▒░  ░▒▓█▓▒░   ░▒▓████████▓▒░
"""
    print(f"{Colors.RED}{logo}{Colors.ENDC}")
    print(f"{Colors.BOLD}            Welcome to the RedEye Nmap Scanner - Professional Edition{Colors.ENDC}\n")

def print_wrapped(text, indent=0):
    """Prints text with wrapping and indentation."""
    prefix = ' ' * indent
    wrapper = textwrap.TextWrapper(initial_indent=prefix, width=80, subsequent_indent=prefix)
    print(wrapper.fill(text))

def check_tool_installed(tool_name):
    """Checks if a given tool is installed and available in the PATH using shutil.which."""
    print(f"{Colors.YELLOW}Checking for {tool_name} installation...{Colors.ENDC}", end=' ')
    path = shutil.which(tool_name)
    if path:
        print(f"{Colors.GREEN}Found at {path}{Colors.ENDC}")
        return True
    else:
        print(f"{Colors.RED}Not found.{Colors.ENDC}")
        return False

def install_dependency(tool_name):
    """Attempts to install a missing dependency using the system's package manager."""
    manager = None
    install_cmd = []
    update_cmd = []
    
    if shutil.which("apt-get"):
        manager = "apt-get"
        # On Debian-based systems, ndiff is part of the nmap package.
        package_map = {'nmap': 'nmap', 'ndiff': 'ndiff', 'xsltproc': 'xsltproc'}
        package_name = package_map.get(tool_name)
        update_cmd = ['sudo', 'apt-get', 'update']
        install_cmd = ['sudo', 'apt-get', 'install', '-y', package_name]
    elif shutil.which("dnf") or shutil.which("yum"):
        manager = "dnf" if shutil.which("dnf") else "yum"
        # On RedHat-based systems, ndiff is also in the nmap package, but xsltproc is in libxslt.
        package_map = {'nmap': 'nmap', 'ndiff': 'ndiff', 'xsltproc': 'libxslt'}
        package_name = package_map.get(tool_name)
        install_cmd = ['sudo', manager, 'install', '-y', package_name]
    else:
        print(f"{Colors.RED}Unsupported package manager. Please install '{tool_name}' manually.{Colors.ENDC}")
        return False

    if not package_name:
        print(f"{Colors.RED}Could not determine package for '{tool_name}'. Please install manually.{Colors.ENDC}")
        return False
        
    choice = input(f"{Colors.YELLOW}Attempt to install '{package_name}' using {manager}? (y/n): {Colors.ENDC}").lower()
    if choice not in ['y', 'yes']:
        print(f"{Colors.RED}Installation skipped by user.{Colors.ENDC}")
        return False

    try:
        if update_cmd:
            print(f"\n{Colors.CYAN}Running package list update ({' '.join(update_cmd)})...{Colors.ENDC}")
            # Stream output directly to the user's terminal
            subprocess.run(update_cmd, check=True, stdout=sys.stdout, stderr=sys.stderr)

        print(f"\n{Colors.CYAN}Running installation ({' '.join(install_cmd)})...{Colors.ENDC}")
        subprocess.run(install_cmd, check=True, stdout=sys.stdout, stderr=sys.stderr)
        
        print(f"{Colors.GREEN}\nInstallation of {package_name} appears to be successful.{Colors.ENDC}")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"\n{Colors.RED}Installation failed for {package_name}.{Colors.ENDC}")
        print(f"{Colors.RED}Error: {e}{Colors.ENDC}")
        print(f"{Colors.YELLOW}Please try installing it manually.{Colors.ENDC}")
        return False

def setup_environment():
    """Checks for all dependencies and prompts to install them if missing."""
    print(f"{Colors.BOLD}--- Checking Dependencies ---{Colors.ENDC}")
    # ndiff is part of the nmap package, but we check for the executable to be sure.
    dependencies = ['nmap', 'ndiff', 'xsltproc']
    all_deps_met = True
    
    for tool in dependencies:
        if not check_tool_installed(tool):
            if not install_dependency(tool):
                all_deps_met = False
            # Re-check after install attempt to be certain
            elif not check_tool_installed(tool):
                print(f"{Colors.RED}Verification failed for {tool} after installation attempt.{Colors.ENDC}")
                all_deps_met = False
    
    if not all_deps_met:
        print(f"\n{Colors.RED}{Colors.BOLD}One or more dependencies could not be installed. Please install them manually and restart the script.{Colors.ENDC}")
        sys.exit(1)
    
    print(f"{Colors.GREEN}{Colors.BOLD}All dependencies are met. Starting RedEye...{Colors.ENDC}\n")

# =============================================================================
# SCANNING AND COMMAND EXECUTION FUNCTIONS
# =============================================================================

def run_command(command, session=None):
    """
    Executes a given shell command, saves output if a session is active,
    and streams its output to the console.
    """
    is_nmap_scan = command[0] == 'nmap' and '-sn' not in command and '-sL' not in command

    if session and is_nmap_scan:
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        session_path = os.path.join(SESSIONS_DIR, session)
        base_filename = os.path.join(session_path, f"scan_{timestamp}")
        
        command.extend(['-oN', f'{base_filename}.nmap'])
        command.extend(['-oX', f'{base_filename}.xml'])

    print(f"\n{Colors.CYAN}{Colors.BOLD}Executing: {' '.join(command)}{Colors.ENDC}")
    print("-" * 60)
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in iter(process.stdout.readline, ''):
            print(line, end='')
        process.stdout.close()
        process.wait()
        print("\n" + "-" * 60)
        print(f"{Colors.GREEN}{Colors.BOLD}Command finished.{Colors.ENDC}")
        if session and is_nmap_scan:
            print(f"{Colors.GREEN}Results saved in: {base_filename}.nmap/.xml{Colors.ENDC}\n")

    except Exception as e:
        print(f"{Colors.RED}An error occurred: {e}{Colors.ENDC}")

# =============================================================================
# SESSION MANAGEMENT FUNCTIONS
# =============================================================================

def set_session():
    """Creates a new session or sets an existing one."""
    session_name = input(f"{Colors.YELLOW}Enter session name (e.g., 'project_x'): {Colors.ENDC}").strip()
    if not session_name:
        print(f"{Colors.RED}Session name cannot be empty.{Colors.ENDC}")
        return None
    
    session_path = os.path.join(SESSIONS_DIR, session_name)
    try:
        os.makedirs(session_path, exist_ok=True)
        print(f"{Colors.GREEN}Session '{session_name}' is active. Scans will be saved to '{session_path}'.{Colors.ENDC}")
        return session_name
    except OSError as e:
        print(f"{Colors.RED}Failed to create session directory: {e}{Colors.ENDC}")
        return None

def list_files_in_session(session, extension):
    """Lists files with a specific extension in a session directory."""
    session_path = os.path.join(SESSIONS_DIR, session)
    if not os.path.isdir(session_path):
        print(f"{Colors.RED}Session directory not found.{Colors.ENDC}")
        return []
    
    files = sorted([f for f in os.listdir(session_path) if f.endswith(extension)])
    if not files:
        print(f"{Colors.YELLOW}No '{extension}' files found in session '{session}'.{Colors.ENDC}")
        return []
    
    print(f"\n{Colors.HEADER}Available '{extension}' files in '{session}':{Colors.ENDC}")
    for i, f in enumerate(files):
        print(f"  {i+1}. {f}")
    return files

# =============================================================================
# REPORTING AND ANALYSIS FUNCTIONS
# =============================================================================

def compare_scans(session):
    """Compares two XML scan files using ndiff."""
    if not session:
        print(f"\n{Colors.RED}Please set a session first (Option 8).{Colors.ENDC}")
        return

    xml_files = list_files_in_session(session, ".xml")
    if len(xml_files) < 2:
        print(f"{Colors.YELLOW}You need at least two XML scans in this session to compare.{Colors.ENDC}")
        return

    try:
        choice1 = int(input(f"{Colors.BOLD}Select the first file (number): {Colors.ENDC}")) - 1
        choice2 = int(input(f"{Colors.BOLD}Select the second file (number): {Colors.ENDC}")) - 1

        file1_path = os.path.join(SESSIONS_DIR, session, xml_files[choice1])
        file2_path = os.path.join(SESSIONS_DIR, session, xml_files[choice2])

        run_command(['ndiff', file1_path, file2_path])
    except (ValueError, IndexError):
        print(f"{Colors.RED}Invalid selection.{Colors.ENDC}")

def generate_report(session):
    """Generates an HTML report from an XML scan file."""
    if not session:
        print(f"\n{Colors.RED}Please set a session first (Option 8).{Colors.ENDC}")
        return

    xml_files = list_files_in_session(session, ".xml")
    if not xml_files:
        return
    
    try:
        choice = int(input(f"{Colors.BOLD}Select the XML file to generate a report from: {Colors.ENDC}")) - 1
        xml_file = xml_files[choice]
        xml_path = os.path.join(SESSIONS_DIR, session, xml_file)
        html_path = xml_path.replace('.xml', '.html')
        
        command = ['xsltproc', '-o', html_path, xml_path]
        
        print(f"\n{Colors.CYAN}{Colors.BOLD}Generating HTML report...{Colors.ENDC}")
        result = subprocess.run(command, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"{Colors.GREEN}{Colors.BOLD}Successfully generated HTML report:{Colors.ENDC} {html_path}")
        else:
            print(f"{Colors.RED}Error generating report:{Colors.ENDC}")
            print(result.stderr)
            print(f"{Colors.YELLOW}Hint: Make sure 'xsltproc' is installed and Nmap's XSL file is in its search path.{Colors.ENDC}")

    except (ValueError, IndexError):
        print(f"{Colors.RED}Invalid selection.{Colors.ENDC}")

# =============================================================================
# MENU AND INTERFACE FUNCTIONS
# =============================================================================

def show_helper():
    """Displays a detailed helper menu for Nmap commands."""
    while True:
        print(f"\n{Colors.HEADER}{Colors.BOLD}--- Nmap Command Helper ---{Colors.ENDC}")
        print("1. Host Discovery")
        print("2. Scan Techniques")
        print("3. Port Specification")
        print("4. Service & OS Detection")
        print("5. Nmap Scripting Engine (NSE)")
        print("6. Timing and Performance")
        print("7. Output Formats")
        print("0. Back to Main Menu")
        print("-" * 34)
        
        choice = input(f"{Colors.BOLD}Select a category to learn more: {Colors.ENDC}")

        print("\n" + "="*60)
        if choice == '1':
            print(f"{Colors.BLUE}{Colors.BOLD}Host Discovery:{Colors.ENDC}")
            print(f"{Colors.CYAN}-sn / -sP{Colors.ENDC} : Ping Scan. Disables port scanning. Best for just discovering which hosts are online.")
            print(f"{Colors.CYAN}-sL{Colors.ENDC}      : List Scan. Simply lists targets without scanning them. Good for a quick target overview.")
            print(f"{Colors.CYAN}-Pn{Colors.ENDC}      : No Ping. Skips host discovery. Assumes all targets are online. Use if hosts block pings.")
        elif choice == '2':
            print(f"{Colors.BLUE}{Colors.BOLD}Scan Techniques:{Colors.ENDC}")
            print(f"{Colors.CYAN}-sS{Colors.ENDC} : TCP SYN (Stealth) Scan. Fast, stealthy, and the most popular scan type. Requires root.")
            print(f"{Colors.CYAN}-sT{Colors.ENDC} : TCP Connect Scan. Slower and more detectable than SYN, but doesn't require root.")
            print(f"{Colors.CYAN}-sU{Colors.ENDC} : UDP Scan. Scans for open UDP ports. Very slow. Requires root.")
        elif choice == '3':
            print(f"{Colors.BLUE}{Colors.BOLD}Port Specification:{Colors.ENDC}")
            print(f"{Colors.CYAN}-p <range>{Colors.ENDC} : Scan specific ports. Examples: -p 22, -p 1-1023, -p U:53,T:21-25,80.")
            print(f"{Colors.CYAN}-F{Colors.ENDC}         : Fast Scan. Scans the 100 most common ports.")
        elif choice == '4':
            print(f"{Colors.BLUE}{Colors.BOLD}Service & OS Detection:{Colors.ENDC}")
            print(f"{Colors.CYAN}-sV{Colors.ENDC} : Service/Version Detection. Probes open ports to find out the exact service and version running.")
            print(f"{Colors.CYAN}-O{Colors.ENDC}  : OS Detection. Tries to determine the target's operating system. Requires root.")
            print(f"{Colors.CYAN}-A{Colors.ENDC}  : Aggressive Scan. A shortcut for -O -sV -sC --traceroute.")
        elif choice == '5':
            print(f"{Colors.BLUE}{Colors.BOLD}Nmap Scripting Engine (NSE):{Colors.ENDC}")
            print(f"{Colors.CYAN}-sC{Colors.ENDC} : Default Scripts. Runs the default set of scripts. It's considered safe for the target.")
            print(f"{Colors.CYAN}--script <name>{Colors.ENDC} : Runs specific scripts, categories (e.g., 'vuln'), or all scripts.")
        elif choice == '6':
            print(f"{Colors.BLUE}{Colors.BOLD}Timing and Performance:{Colors.ENDC}")
            print(f"{Colors.CYAN}-T<0-5>{Colors.ENDC} : Timing Template. T0 (paranoid) is very slow, T5 (insane) is very fast. T4 is recommended.")
        elif choice == '7':
            print(f"{Colors.BLUE}{Colors.BOLD}Output Formats:{Colors.ENDC}")
            print(f"{Colors.CYAN}-oN <file>{Colors.ENDC} : Normal Output. Saves the output in a standard text file.")
            print(f"{Colors.CYAN}-oX <file>{Colors.ENDC} : XML Output. Saves in XML format, which can be parsed by other tools.")
        elif choice == '0':
            break
        else:
            print(f"{Colors.RED}Invalid choice. Please select from the menu.{Colors.ENDC}")
        print("="*60 + "\n")

# =============================================================================
# ADVANCED SCANNING FUNCTIONS
# =============================================================================

def show_advanced_scans(target, ports, session):
    """Displays and handles the advanced scans menu for a given target."""
    while True:
        print(f"\n{Colors.HEADER}{Colors.BOLD}--- Advanced Scans Menu (Target: {target}) ---{Colors.ENDC}")
        if ports:
            print(f"{Colors.GREEN}{Colors.BOLD}Using Custom Ports: {ports}{Colors.ENDC}")
        print(f"{Colors.YELLOW}--- Firewall/IDS Evasion & Discovery ---{Colors.ENDC}")
        print("1.  Aggressive Discovery (All Ping Types)")
        print("2.  Full Port Scan (No Ping)")
        print("3.  Firewall Evasion (Fragment Packets)")
        print("4.  Firewall Evasion (Decoy Scan)")
        print("5.  Idle Scan (Ultimate Stealth - requires zombie host)")
        print(f"{Colors.YELLOW}--- Vulnerability & Service Specific Scans ---{Colors.ENDC}")
        print("6.  Comprehensive Web Server Scan")
        print("7.  SMB Vulnerability Scan (e.g., EternalBlue)")
        print("8.  FTP Vulnerability Scan")
        print("9.  MySQL Vulnerability Scan")
        print("10. Heartbleed SSL Vulnerability Check")
        print("11. Detect Web Application Firewall (WAF)")
        print("12. Slowloris DoS Vulnerability Check")
        print(f"{Colors.YELLOW}--- Deep & Aggressive Scans ---{Colors.ENDC}")
        print("13. Full TCP & UDP Scan (Extremely Slow)")
        print("14. Safe Script Scan (Non-intrusive)")
        print(f"{Colors.RED}15. Exploit Script Scan (Potentially Dangerous){Colors.ENDC}")
        print("16. Brute Force Scripts (Auth Category)")
        print("17. Traceroute & Geo-location")
        print("18. Aggressive All Ports Scan (-A -p-)")
        print("19. Full Network Sweep (Ping Only)")
        print("20. Scan for ALL TCP ports with OS detection")
        print("0.  Back to Main Menu")
        print("-" * 50)

        choice = input(f"{Colors.BOLD}Select an advanced scan: {Colors.ENDC}")
        command_list = None
        
        port_args = ['-p', ports] if ports else []

        if choice == '1':
            command_list = ['sudo', 'nmap', '-sn', '-PE', '-PS22,80,443', '-PA80,443', '-PU53', '-T4', target]
        elif choice == '2':
            command_list = ['sudo', 'nmap', '-Pn', '-sS', '-T4'] + (port_args if ports else ['-p-']) + [target]
        elif choice == '3':
            command_list = ['sudo', 'nmap', '-f', '-sS', '-T4'] + port_args + [target]
        elif choice == '4':
            command_list = ['sudo', 'nmap', '-D', 'RND:10', '-sS', '-T4'] + port_args + [target]
        elif choice == '5':
            zombie = input(f"{Colors.YELLOW}Enter Zombie IP for Idle Scan: {Colors.ENDC}")
            if zombie:
                command_list = ['sudo', 'nmap', '-Pn', '-sI', zombie] + port_args + [target]
        elif choice == '6':
            command_list = ['nmap', '--script', 'http-enum,http-title,http-vuln*', '-sV', '-T4'] + (port_args if ports else ['-p', '80,443']) + [target]
        elif choice == '7':
            command_list = ['nmap', '--script', 'smb-vuln*', '-sV', '-T4'] + (port_args if ports else ['-p', '139,445']) + [target]
        elif choice == '8':
            command_list = ['nmap', '--script', 'ftp-anon,ftp-vuln*', '-sV', '-T4'] + (port_args if ports else ['-p', '21']) + [target]
        elif choice == '9':
            command_list = ['nmap', '--script', 'mysql-empty-password,mysql-vuln*', '-sV', '-T4'] + (port_args if ports else ['-p', '3306']) + [target]
        elif choice == '10':
            command_list = ['nmap', '--script', 'ssl-heartbleed', '-sV'] + (port_args if ports else ['-p', '443']) + [target]
        elif choice == '11':
            command_list = ['nmap', '--script', 'http-waf-detect,http-waf-fingerprint', '-T4'] + (port_args if ports else ['-p', '80,443']) + [target]
        elif choice == '12':
            command_list = ['nmap', '--script', 'http-slowloris-check', '-T4'] + port_args + [target]
        elif choice == '13':
            print(f"{Colors.RED}{Colors.BOLD}WARNING: This scan is extremely slow and can take many hours.{Colors.ENDC}")
            command_list = ['sudo', 'nmap', '-sS', '-sU', '-T4'] + (port_args if ports else ['-p', 'T:-,U:1-4000']) + [target]
        elif choice == '14':
            command_list = ['nmap', '-sV', '-sC', '--script', '"not intrusive"'] + port_args + [target]
        elif choice == '15':
            print(f"{Colors.RED}{Colors.BOLD}WARNING: Running 'exploit' scripts is dangerous and may crash the target.{Colors.ENDC}")
            if input("Are you sure you want to continue? (yes/no): ").lower() == 'yes':
                command_list = ['sudo', 'nmap', '-sV', '--script', 'exploit', '-T4'] + port_args + [target]
        elif choice == '16':
            command_list = ['nmap', '-sV', '--script', 'auth', '-T4'] + port_args + [target]
        elif choice == '17':
            command_list = ['nmap', '--traceroute', '--script', 'traceroute-geolocation', '-T4'] + (port_args if ports else ['-p', '80']) + [target]
        elif choice == '18':
            print(f"{Colors.RED}{Colors.BOLD}WARNING: This is a very noisy and slow scan.{Colors.ENDC}")
            command_list = ['sudo', 'nmap', '-A', '-p-', '-T4'] + port_args + [target] # port_args is redundant but harmless
        elif choice == '19':
            command_list = ['nmap', '-sn', '-T4', target]
        elif choice == '20':
            command_list = ['sudo', 'nmap', '-O', '-T4'] + (port_args if ports else ['-p-']) + [target]
        elif choice == '0':
            break
        else:
            print(f"{Colors.RED}Invalid choice.{Colors.ENDC}")

        if command_list:
            run_command(command_list, session)

def show_menu(target, ports, session):
    """Displays the main menu of the scanner, showing the current state."""
    print(f"\n{Colors.HEADER}{Colors.BOLD}--- RedEye Nmap Scanner Menu ---{Colors.ENDC}")
    if session: print(f"{Colors.CYAN}{Colors.BOLD}Active Session: {session}{Colors.ENDC}")
    else: print(f"{Colors.YELLOW}{Colors.BOLD}No Active Session (scans will not be saved){Colors.ENDC}")
    if target: print(f"{Colors.GREEN}{Colors.BOLD}Current Target: {target}{Colors.ENDC}")
    else: print(f"{Colors.YELLOW}{Colors.BOLD}No Target Set{Colors.ENDC}")
    if ports: print(f"{Colors.GREEN}{Colors.BOLD}Custom Ports: {ports}{Colors.ENDC}")
    else: print(f"{Colors.YELLOW}{Colors.BOLD}Ports: Default{Colors.ENDC}")
    
    print("-" * 34)
    print("--- Target & Port Management ---")
    print("1.  Set / Change Target")
    print("2.  Set / Unset Custom Ports (Optional)")
    
    print("\n--- Basic Scans ---")
    print("3.  Ping Scan (Host Discovery only)")
    print("4.  Intense Scan (-A -T4)")
    print("5.  Fast Scan (Top 100 ports)")
    print("6.  Default Scripts Scan (-sC)")
    print("7.  Vulnerability Scan (General 'vuln' scripts)")

    print("\n--- Session, Reporting & Advanced ---")
    print(f"{Colors.CYAN}8.  Set / Create Scan Session{Colors.ENDC}")
    print(f"{Colors.CYAN}9.  Compare Two Scans (Diff){Colors.ENDC}")
    print(f"{Colors.CYAN}10. Generate HTML Report{Colors.ENDC}")
    print(f"{Colors.CYAN}11. Advanced Scans Menu{Colors.ENDC}")

    print("\n--- Other Options ---")
    print("12. Custom Nmap Command")
    print(f"{Colors.GREEN}13. Nmap Command Helper{Colors.ENDC}")
    print("0.  Exit")
    print("-" * 34)

# =============================================================================
# MAIN APPLICATION FUNCTION
# =============================================================================

def main():
    """Main function to run the script's menu loop."""
    os.system('cls' if os.name == 'nt' else 'clear')
    show_banner()
    
    setup_environment() # New dependency check and installation function
    
    os.makedirs(SESSIONS_DIR, exist_ok=True)

    current_target = None
    current_ports = None
    current_session = None

    while True:
        try:
            show_menu(current_target, current_ports, current_session)
            choice = input(f"{Colors.BOLD}Enter your choice: {Colors.ENDC} ").strip()

            scan_choices = ['3', '4', '5', '6', '7', '11']

            if choice == '1':
                current_target = input(f"{Colors.YELLOW}Enter target IP or domain: {Colors.ENDC}").strip()
                if not current_target:
                    print(f"{Colors.RED}Target cannot be empty.{Colors.ENDC}")
                    current_target = None
            elif choice == '2':
                ports_in = input(f"{Colors.YELLOW}Enter custom ports (or blank to clear): {Colors.ENDC}").strip()
                current_ports = ports_in if ports_in else None
            elif choice == '8':
                current_session = set_session()
            elif choice in scan_choices and not current_target:
                print(f"\n{Colors.RED}{Colors.BOLD}No target has been set. Please use option '1' first.{Colors.ENDC}")
            elif choice == '3':
                run_command(['nmap', '-sn', current_target], current_session)
            elif choice == '4':
                port_args = ['-p', current_ports] if current_ports else []
                run_command(['nmap', '-A', '-T4'] + port_args + [current_target], current_session)
            elif choice == '5':
                port_args = ['-p', current_ports] if current_ports else []
                run_command(['nmap', '-F', '-T4'] + port_args + [current_target], current_session)
            elif choice == '6':
                port_args = ['-p', current_ports] if current_ports else []
                run_command(['nmap', '-sC'] + port_args + [current_target], current_session)
            elif choice == '7':
                port_args = ['-p', current_ports] if current_ports else []
                run_command(['nmap', '--script', 'vuln', '-sV'] + port_args + [current_target], current_session)
            elif choice == '9':
                compare_scans(current_session)
            elif choice == '10':
                generate_report(current_session)
            elif choice == '11':
                show_advanced_scans(current_target, current_ports, current_session)
            elif choice == '12':
                 custom_cmd_str = input(f"{Colors.YELLOW}Enter full nmap command: {Colors.ENDC}")
                 if custom_cmd_str.lower().strip().startswith("nmap "):
                     run_command(custom_cmd_str.split(), current_session)
                 else:
                    print(f"{Colors.RED}Invalid command. It must start with 'nmap '.{Colors.ENDC}")
            elif choice == '13':
                show_helper()
            elif choice == '0':
                print(f"{Colors.GREEN}Exiting RedEye. Goodbye!{Colors.ENDC}")
                break
            else:
                print(f"{Colors.RED}Invalid choice. Please try again.{Colors.ENDC}")
        
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Operation cancelled by user. Exiting RedEye.{Colors.ENDC}")
            sys.exit(0)
        except Exception as e:
            print(f"{Colors.RED}An unexpected error occurred: {e}{Colors.ENDC}")

# =============================================================================
# ENTRY POINT
# =============================================================================

if __name__ == "__main__":
    # Check if running standalone for testing dependency helper
    if len(sys.argv) > 1 and sys.argv[1] == "--test-deps":
        success = ensure_tools()
        sys.exit(0 if success else 2)
    else:
        main()

