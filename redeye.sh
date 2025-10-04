#!/usr/bin/env bash

# =============================================================================
# REDEYE NMAP SCANNER - PROFESSIONAL EDITION (BASH VERSION)
# =============================================================================
# A comprehensive Nmap scanning tool with session management, reporting,
# and advanced scanning capabilities.
# =============================================================================

# =============================================================================
# CONSTANTS AND GLOBAL VARIABLES
# =============================================================================
REQUIRED_TOOLS=("nmap" "ndiff" "xsltproc")
SESSIONS_DIR="redeye_sessions"

# Current state variables
CURRENT_TARGET=""
CURRENT_PORTS=""
CURRENT_SESSION=""

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================
COLOR_HEADER='\033[95m'
COLOR_BLUE='\033[94m'
COLOR_CYAN='\033[96m'
COLOR_GREEN='\033[92m'
COLOR_YELLOW='\033[93m'
COLOR_RED='\033[91m'
COLOR_ENDC='\033[0m'
COLOR_BOLD='\033[1m'
COLOR_UNDERLINE='\033[4m'

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

is_root() {
    [[ $EUID -eq 0 ]]
}

command_exists() {
    command -v "$1" &> /dev/null
}

# =============================================================================
# DEPENDENCY MANAGEMENT FUNCTIONS
# =============================================================================

detect_os() {
    local os_id="unknown"
    local pkg_manager=""
    local install_cmd=""
    local update_cmd=""

    # Termux detection
    if [[ -n "${PREFIX}" && "${PREFIX}" == /data/data/com.termux* ]] || [[ -d "/data/data/com.termux/files/usr" ]]; then
        os_id="termux"
        pkg_manager="pkg"
        install_cmd="pkg install -y"
        update_cmd="pkg update -y"
        echo "$os_id|$pkg_manager|$install_cmd|$update_cmd"
        return
    fi

    # Read /etc/os-release if exists
    if [[ -f "/etc/os-release" ]]; then
        local os_data=$(cat /etc/os-release | tr '[:upper:]' '[:lower:]')
        
        if echo "$os_data" | grep -q "ubuntu"; then
            os_id="ubuntu"
            pkg_manager="apt"
            install_cmd="apt-get install -y"
            update_cmd="apt-get update -y"
        elif echo "$os_data" | grep -q "debian" && ! echo "$os_data" | grep -q "ubuntu"; then
            os_id="debian"
            pkg_manager="apt"
            install_cmd="apt-get install -y"
            update_cmd="apt-get update -y"
        elif echo "$os_data" | grep -q "arch"; then
            os_id="arch"
            pkg_manager="pacman"
            install_cmd="pacman -S --noconfirm"
            update_cmd="pacman -Sy --noconfirm"
        elif echo "$os_data" | grep -qE "(fedora|rhel|centos|red hat)"; then
            os_id="redhat"
            if command_exists dnf; then
                pkg_manager="dnf"
                install_cmd="dnf install -y"
                update_cmd="dnf makecache --refresh -y"
            else
                pkg_manager="yum"
                install_cmd="yum install -y"
                update_cmd="yum makecache -y"
            fi
        elif echo "$os_data" | grep -q "id_like=debian"; then
            os_id="debian-like"
            pkg_manager="apt"
            install_cmd="apt-get install -y"
            update_cmd="apt-get update -y"
        fi
    fi

    # Fallback: detect by package manager binaries
    if [[ -z "$pkg_manager" ]]; then
        if command_exists apt-get; then
            os_id="debian-like"
            pkg_manager="apt"
            install_cmd="apt-get install -y"
            update_cmd="apt-get update -y"
        elif command_exists pacman; then
            os_id="arch"
            pkg_manager="pacman"
            install_cmd="pacman -S --noconfirm"
            update_cmd="pacman -Sy --noconfirm"
        elif command_exists dnf; then
            os_id="redhat"
            pkg_manager="dnf"
            install_cmd="dnf install -y"
            update_cmd="dnf makecache --refresh -y"
        elif command_exists yum; then
            os_id="redhat"
            pkg_manager="yum"
            install_cmd="yum install -y"
            update_cmd="yum makecache -y"
        elif command_exists pkg && [[ -d "/data/data/com.termux" ]]; then
            os_id="termux"
            pkg_manager="pkg"
            install_cmd="pkg install -y"
            update_cmd="pkg update -y"
        fi
    fi

    echo "$os_id|$pkg_manager|$install_cmd|$update_cmd"
}

pkg_name_for_bin() {
    local bin_name="$1"
    local pkg_manager="$2"
    
    case "$pkg_manager" in
        apt|pkg)
            if [[ "$bin_name" == "ndiff" ]]; then
                echo "nmap"
            else
                echo "$bin_name"
            fi
            ;;
        pacman)
            if [[ "$bin_name" == "xsltproc" ]]; then
                echo "libxslt"
            elif [[ "$bin_name" == "ndiff" ]]; then
                echo "nmap"
            else
                echo "$bin_name"
            fi
            ;;
        dnf|yum)
            if [[ "$bin_name" == "xsltproc" ]]; then
                echo "libxslt"
            elif [[ "$bin_name" == "ndiff" ]]; then
                echo "nmap"
            else
                echo "$bin_name"
            fi
            ;;
        *)
            echo "$bin_name"
            ;;
    esac
}

check_tools() {
    local missing=()
    local found=()
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command_exists "$tool"; then
            found+=("$tool")
        else
            missing+=("$tool")
        fi
    done
    
    echo "${missing[*]}|${found[*]}"
}

attempt_install() {
    local missing_str="$1"
    local pkg_manager="$2"
    local install_cmd="$3"
    local update_cmd="$4"
    
    IFS=' ' read -ra missing <<< "$missing_str"
    
    if [[ -z "$pkg_manager" || -z "$install_cmd" ]]; then
        echo -e "${COLOR_RED}[ERROR] No supported package manager detected; cannot install automatically.${COLOR_ENDC}"
        return 1
    fi

    # Update package database
    if [[ -n "$update_cmd" ]]; then
        echo -e "${COLOR_YELLOW}[INFO] Running update: $update_cmd${COLOR_ENDC}"
        if is_root; then
            eval "$update_cmd" 2>&1
        else
            sudo $update_cmd 2>&1
        fi
    fi

    # Get package names
    local pkg_names=()
    local seen_pkgs=()
    for bin in "${missing[@]}"; do
        local pkg=$(pkg_name_for_bin "$bin" "$pkg_manager")
        if [[ ! " ${seen_pkgs[@]} " =~ " ${pkg} " ]]; then
            pkg_names+=("$pkg")
            seen_pkgs+=("$pkg")
        fi
    done

    # Try install without sudo first
    echo -e "${COLOR_YELLOW}[INFO] Trying install: $install_cmd ${pkg_names[*]} (without sudo)${COLOR_ENDC}"
    if is_root; then
        eval "$install_cmd ${pkg_names[*]}" 2>&1
    else
        $install_cmd ${pkg_names[*]} 2>&1
    fi

    # Re-check
    local check_result=$(check_tools)
    IFS='|' read -r still_missing found <<< "$check_result"
    
    if [[ -z "$still_missing" ]]; then
        echo -e "${COLOR_GREEN}[INFO] All tools installed successfully.${COLOR_ENDC}"
        return 0
    fi

    # Try with sudo if not root
    if ! is_root; then
        echo -e "${COLOR_YELLOW}[INFO] Retrying with sudo: sudo $install_cmd ${pkg_names[*]}${COLOR_ENDC}"
        sudo $install_cmd ${pkg_names[*]} 2>&1
        
        check_result=$(check_tools)
        IFS='|' read -r still_missing found <<< "$check_result"
        
        if [[ -z "$still_missing" ]]; then
            echo -e "${COLOR_GREEN}[INFO] All tools installed successfully (with sudo).${COLOR_ENDC}"
            return 0
        else
            echo -e "${COLOR_YELLOW}[WARN] Still missing after sudo install: $still_missing${COLOR_ENDC}"
        fi
    else
        echo -e "${COLOR_YELLOW}[INFO] Already running as root; attempted install above failed.${COLOR_ENDC}"
    fi

    return 1
}

print_manual_suggestions() {
    local pkg_manager="$1"
    
    echo ""
    echo "=== Manual installation suggestions ==="
    case "$pkg_manager" in
        apt)
            echo "Debian/Ubuntu (APT):"
            echo "  sudo apt-get update"
            echo "  sudo apt-get install -y nmap ndiff xsltproc"
            echo "  (ndiff usually included with nmap; if not, search 'apt-cache search ndiff')"
            ;;
        pkg)
            echo "Termux (pkg):"
            echo "  pkg update"
            echo "  pkg install nmap libxslt"
            echo "  (ndiff usually comes with nmap)"
            ;;
        pacman)
            echo "Arch (pacman):"
            echo "  sudo pacman -Sy"
            echo "  sudo pacman -S nmap libxslt"
            echo "  (ndiff usually part of nmap package)"
            ;;
        dnf|yum)
            echo "Fedora/RHEL ($pkg_manager):"
            echo "  sudo $pkg_manager makecache --refresh"
            echo "  sudo $pkg_manager install -y nmap libxslt"
            echo "  (ndiff usually comes with nmap)"
            ;;
        *)
            echo "Unknown package manager. Try installing: nmap, libxslt (xsltproc)."
            ;;
    esac
    echo "If you are inside a container or don't have privileges, consider contacting the sysadmin or using a container that has these tools."
}

ensure_tools() {
    echo -e "${COLOR_YELLOW}[INFO] Checking required tools: ${REQUIRED_TOOLS[*]}${COLOR_ENDC}"
    
    local check_result=$(check_tools)
    IFS='|' read -r missing found <<< "$check_result"
    
    if [[ -z "$missing" ]]; then
        echo -e "${COLOR_GREEN}[INFO] All required tools are present: $found${COLOR_ENDC}"
        return 0
    fi

    echo -e "${COLOR_YELLOW}[WARN] Missing tools: $missing${COLOR_ENDC}"
    
    local os_info=$(detect_os)
    IFS='|' read -r os_id pkg_manager install_cmd update_cmd <<< "$os_info"
    echo -e "${COLOR_YELLOW}[INFO] Detected OS: $os_id, package manager: $pkg_manager${COLOR_ENDC}"

    if attempt_install "$missing" "$pkg_manager" "$install_cmd" "$update_cmd"; then
        return 0
    fi

    # Final check & suggestions
    check_result=$(check_tools)
    IFS='|' read -r still_missing found <<< "$check_result"
    
    if [[ -n "$still_missing" ]]; then
        echo -e "${COLOR_RED}[ERROR] Could not install: $still_missing${COLOR_ENDC}"
        print_manual_suggestions "$pkg_manager"
        return 1
    fi
    
    return 0
}

# =============================================================================
# UI AND DISPLAY FUNCTIONS
# =============================================================================

show_banner() {
    local logo='
▒▓████████▓▒   ▓████████▓▒  ▓███████▓▒   ▓████████▓▒  ▓█▓▒   ▓█▓▒  ▓████████▓▒
▒▓█▓▒   ▓█▓▒  ▓█▓▒     ▒▓█▓▒   ▓█▓▒  ▓█▓▒     ▒▓█▓▒   ▓█▓▒  ▓█▓▒
▒▓█▓▒   ▓█▓▒  ▓█▓▒     ▒▓█▓▒   ▓█▓▒  ▓█▓▒     ▒▓█▓▒   ▓█▓▒  ▓█▓▒
▒▓███████▓▒   ▓██████▓▒  ▒▓█▓▒   ▓█▓▒  ▓██████▓▒   ▒▓██████▓▒  ▓██████▓▒
▒▓█▓▒   ▓█▓▒  ▓█▓▒     ▒▓█▓▒   ▓█▓▒  ▓█▓▒         ▒▓█▓▒   ▓█▓▒
▒▓█▓▒   ▓█▓▒  ▓█▓▒     ▒▓█▓▒   ▓█▓▒  ▓█▓▒         ▒▓█▓▒   ▓█▓▒
▒▓█▓▒   ▓█▓▒  ▓████████▓▒  ▓███████▓▒   ▓████████▓▒   ▒▓█▓▒   ▓████████▓▒
'
    echo -e "${COLOR_RED}${logo}${COLOR_ENDC}"
    echo -e "${COLOR_BOLD}            Welcome to the RedEye Nmap Scanner - Professional Edition${COLOR_ENDC}\n"
}

setup_environment() {
    echo -e "${COLOR_BOLD}--- Checking Dependencies ---${COLOR_ENDC}"
    
    local all_deps_met=true
    for tool in "${REQUIRED_TOOLS[@]}"; do
        echo -ne "${COLOR_YELLOW}Checking for ${tool} installation...${COLOR_ENDC} "
        if command_exists "$tool"; then
            echo -e "${COLOR_GREEN}Found at $(command -v $tool)${COLOR_ENDC}"
        else
            echo -e "${COLOR_RED}Not found.${COLOR_ENDC}"
            all_deps_met=false
        fi
    done

    if [[ "$all_deps_met" == false ]]; then
        if ! ensure_tools; then
            echo -e "\n${COLOR_RED}${COLOR_BOLD}One or more dependencies could not be installed. Please install them manually and restart the script.${COLOR_ENDC}"
            exit 1
        fi
    fi
    
    echo -e "${COLOR_GREEN}${COLOR_BOLD}All dependencies are met. Starting RedEye...${COLOR_ENDC}\n"
}

# =============================================================================
# SCANNING AND COMMAND EXECUTION FUNCTIONS
# =============================================================================

run_command() {
    local cmd=("$@")
    local session="$CURRENT_SESSION"
    
    # Check if this is an nmap scan (not ping or list scan)
    local is_nmap_scan=false
    if [[ "${cmd[0]}" == "nmap" || "${cmd[0]}" == "sudo" && "${cmd[1]}" == "nmap" ]]; then
        local has_sn=false
        local has_sl=false
        for arg in "${cmd[@]}"; do
            [[ "$arg" == "-sn" || "$arg" == "-sP" ]] && has_sn=true
            [[ "$arg" == "-sL" ]] && has_sl=true
        done
        [[ "$has_sn" == false && "$has_sl" == false ]] && is_nmap_scan=true
    fi

    if [[ -n "$session" && "$is_nmap_scan" == true ]]; then
        local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        local session_path="${SESSIONS_DIR}/${session}"
        local base_filename="${session_path}/scan_${timestamp}"
        
        cmd+=("-oN" "${base_filename}.nmap")
        cmd+=("-oX" "${base_filename}.xml")
    fi

    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}Executing: ${cmd[*]}${COLOR_ENDC}"
    echo "------------------------------------------------------------"
    
    "${cmd[@]}"
    local exit_code=$?
    
    echo "------------------------------------------------------------"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}Command finished.${COLOR_ENDC}"
    
    if [[ -n "$session" && "$is_nmap_scan" == true ]]; then
        echo -e "${COLOR_GREEN}Results saved in: ${base_filename}.nmap/.xml${COLOR_ENDC}\n"
    fi
    
    return $exit_code
}

# =============================================================================
# SESSION MANAGEMENT FUNCTIONS
# =============================================================================

set_session() {
    read -p "$(echo -e ${COLOR_YELLOW})Enter session name (e.g., 'project_x'): $(echo -e ${COLOR_ENDC})" session_name
    session_name=$(echo "$session_name" | xargs)  # trim whitespace
    
    if [[ -z "$session_name" ]]; then
        echo -e "${COLOR_RED}Session name cannot be empty.${COLOR_ENDC}"
        return 1
    fi
    
    local session_path="${SESSIONS_DIR}/${session_name}"
    mkdir -p "$session_path" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        CURRENT_SESSION="$session_name"
        echo -e "${COLOR_GREEN}Session '${session_name}' is active. Scans will be saved to '${session_path}'.${COLOR_ENDC}"
        return 0
    else
        echo -e "${COLOR_RED}Failed to create session directory.${COLOR_ENDC}"
        return 1
    fi
}

list_files_in_session() {
    local session="$1"
    local extension="$2"
    local session_path="${SESSIONS_DIR}/${session}"
    
    if [[ ! -d "$session_path" ]]; then
        echo -e "${COLOR_RED}Session directory not found.${COLOR_ENDC}"
        return 1
    fi
    
    local files=($(ls -1 "$session_path"/*"${extension}" 2>/dev/null | sort))
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${COLOR_YELLOW}No '${extension}' files found in session '${session}'.${COLOR_ENDC}"
        return 1
    fi
    
    echo -e "\n${COLOR_HEADER}Available '${extension}' files in '${session}':${COLOR_ENDC}"
    local i=1
    for file in "${files[@]}"; do
        echo "  ${i}. $(basename "$file")"
        ((i++))
    done
    
    return 0
}

# =============================================================================
# REPORTING AND ANALYSIS FUNCTIONS
# =============================================================================

compare_scans() {
    if [[ -z "$CURRENT_SESSION" ]]; then
        echo -e "\n${COLOR_RED}Please set a session first (Option 8).${COLOR_ENDC}"
        return
    fi

    local session_path="${SESSIONS_DIR}/${CURRENT_SESSION}"
    local files=($(ls -1 "$session_path"/*.xml 2>/dev/null | sort))
    
    if [[ ${#files[@]} -lt 2 ]]; then
        echo -e "${COLOR_YELLOW}You need at least two XML scans in this session to compare.${COLOR_ENDC}"
        return
    fi

    list_files_in_session "$CURRENT_SESSION" ".xml"
    
    read -p "$(echo -e ${COLOR_BOLD})Select the first file (number): $(echo -e ${COLOR_ENDC})" choice1
    read -p "$(echo -e ${COLOR_BOLD})Select the second file (number): $(echo -e ${COLOR_ENDC})" choice2
    
    if [[ ! "$choice1" =~ ^[0-9]+$ ]] || [[ ! "$choice2" =~ ^[0-9]+$ ]]; then
        echo -e "${COLOR_RED}Invalid selection.${COLOR_ENDC}"
        return
    fi
    
    local file1="${files[$((choice1-1))]}"
    local file2="${files[$((choice2-1))]}"
    
    if [[ -z "$file1" ]] || [[ -z "$file2" ]]; then
        echo -e "${COLOR_RED}Invalid selection.${COLOR_ENDC}"
        return
    fi
    
    run_command ndiff "$file1" "$file2"
}

generate_report() {
    if [[ -z "$CURRENT_SESSION" ]]; then
        echo -e "\n${COLOR_RED}Please set a session first (Option 8).${COLOR_ENDC}"
        return
    fi

    local session_path="${SESSIONS_DIR}/${CURRENT_SESSION}"
    local files=($(ls -1 "$session_path"/*.xml 2>/dev/null | sort))
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${COLOR_YELLOW}No XML files found in session '${CURRENT_SESSION}'.${COLOR_ENDC}"
        return
    fi

    list_files_in_session "$CURRENT_SESSION" ".xml"
    
    read -p "$(echo -e ${COLOR_BOLD})Select the XML file to generate a report from: $(echo -e ${COLOR_ENDC})" choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        echo -e "${COLOR_RED}Invalid selection.${COLOR_ENDC}"
        return
    fi
    
    local xml_file="${files[$((choice-1))]}"
    
    if [[ -z "$xml_file" ]]; then
        echo -e "${COLOR_RED}Invalid selection.${COLOR_ENDC}"
        return
    fi
    
    local html_file="${xml_file%.xml}.html"
    
    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}Generating HTML report...${COLOR_ENDC}"
    
    if xsltproc -o "$html_file" "$xml_file" 2>/dev/null; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}Successfully generated HTML report:${COLOR_ENDC} ${html_file}"
    else
        echo -e "${COLOR_RED}Error generating report.${COLOR_ENDC}"
        echo -e "${COLOR_YELLOW}Hint: Make sure 'xsltproc' is installed and Nmap's XSL file is in its search path.${COLOR_ENDC}"
    fi
}

# =============================================================================
# MENU AND INTERFACE FUNCTIONS
# =============================================================================

show_helper() {
    while true; do
        echo -e "\n${COLOR_HEADER}${COLOR_BOLD}--- Nmap Command Helper ---${COLOR_ENDC}"
        echo "1. Host Discovery"
        echo "2. Scan Techniques"
        echo "3. Port Specification"
        echo "4. Service & OS Detection"
        echo "5. Nmap Scripting Engine (NSE)"
        echo "6. Timing and Performance"
        echo "7. Output Formats"
        echo "0. Back to Main Menu"
        echo "----------------------------------"
        
        read -p "$(echo -e ${COLOR_BOLD})Select a category to learn more: $(echo -e ${COLOR_ENDC})" choice
        
        echo ""
        echo "============================================================"
        case "$choice" in
            1)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Host Discovery:${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-sn / -sP${COLOR_ENDC} : Ping Scan. Disables port scanning. Best for just discovering which hosts are online."
                echo -e "${COLOR_CYAN}-sL${COLOR_ENDC}      : List Scan. Simply lists targets without scanning them. Good for a quick target overview."
                echo -e "${COLOR_CYAN}-Pn${COLOR_ENDC}      : No Ping. Skips host discovery. Assumes all targets are online. Use if hosts block pings."
                ;;
            2)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Scan Techniques:${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-sS${COLOR_ENDC} : TCP SYN (Stealth) Scan. Fast, stealthy, and the most popular scan type. Requires root."
                echo -e "${COLOR_CYAN}-sT${COLOR_ENDC} : TCP Connect Scan. Slower and more detectable than SYN, but doesn't require root."
                echo -e "${COLOR_CYAN}-sU${COLOR_ENDC} : UDP Scan. Scans for open UDP ports. Very slow. Requires root."
                ;;
            3)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Port Specification:${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-p <range>${COLOR_ENDC} : Scan specific ports. Examples: -p 22, -p 1-1023, -p U:53,T:21-25,80."
                echo -e "${COLOR_CYAN}-F${COLOR_ENDC}         : Fast Scan. Scans the 100 most common ports."
                ;;
            4)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Service & OS Detection:${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-sV${COLOR_ENDC} : Service/Version Detection. Probes open ports to find out the exact service and version running."
                echo -e "${COLOR_CYAN}-O${COLOR_ENDC}  : OS Detection. Tries to determine the target's operating system. Requires root."
                echo -e "${COLOR_CYAN}-A${COLOR_ENDC}  : Aggressive Scan. A shortcut for -O -sV -sC --traceroute."
                ;;
            5)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Nmap Scripting Engine (NSE):${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-sC${COLOR_ENDC} : Default Scripts. Runs the default set of scripts. It's considered safe for the target."
                echo -e "${COLOR_CYAN}--script <name>${COLOR_ENDC} : Runs specific scripts, categories (e.g., 'vuln'), or all scripts."
                ;;
            6)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Timing and Performance:${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-T<0-5>${COLOR_ENDC} : Timing Template. T0 (paranoid) is very slow, T5 (insane) is very fast. T4 is recommended."
                ;;
            7)
                echo -e "${COLOR_BLUE}${COLOR_BOLD}Output Formats:${COLOR_ENDC}"
                echo -e "${COLOR_CYAN}-oN <file>${COLOR_ENDC} : Normal Output. Saves the output in a standard text file."
                echo -e "${COLOR_CYAN}-oX <file>${COLOR_ENDC} : XML Output. Saves in XML format, which can be parsed by other tools."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${COLOR_RED}Invalid choice. Please select from the menu.${COLOR_ENDC}"
                ;;
        esac
        echo "============================================================"
        echo ""
    done
}

# =============================================================================
# ADVANCED SCANNING FUNCTIONS
# =============================================================================

show_advanced_scans() {
    local target="$CURRENT_TARGET"
    local ports="$CURRENT_PORTS"
    
    while true; do
        echo -e "\n${COLOR_HEADER}${COLOR_BOLD}--- Advanced Scans Menu (Target: ${target}) ---${COLOR_ENDC}"
        if [[ -n "$ports" ]]; then
            echo -e "${COLOR_GREEN}${COLOR_BOLD}Using Custom Ports: ${ports}${COLOR_ENDC}"
        fi
        echo -e "${COLOR_YELLOW}--- Firewall/IDS Evasion & Discovery ---${COLOR_ENDC}"
        echo "1.  Aggressive Discovery (All Ping Types)"
        echo "2.  Full Port Scan (No Ping)"
        echo "3.  Firewall Evasion (Fragment Packets)"
        echo "4.  Firewall Evasion (Decoy Scan)"
        echo "5.  Idle Scan (Ultimate Stealth - requires zombie host)"
        echo -e "${COLOR_YELLOW}--- Vulnerability & Service Specific Scans ---${COLOR_ENDC}"
        echo "6.  Comprehensive Web Server Scan"
        echo "7.  SMB Vulnerability Scan (e.g., EternalBlue)"
        echo "8.  FTP Vulnerability Scan"
        echo "9.  MySQL Vulnerability Scan"
        echo "10. Heartbleed SSL Vulnerability Check"
        echo "11. Detect Web Application Firewall (WAF)"
        echo "12. Slowloris DoS Vulnerability Check"
        echo -e "${COLOR_YELLOW}--- Deep & Aggressive Scans ---${COLOR_ENDC}"
        echo "13. Full TCP & UDP Scan (Extremely Slow)"
        echo "14. Safe Script Scan (Non-intrusive)"
        echo -e "${COLOR_RED}15. Exploit Script Scan (Potentially Dangerous)${COLOR_ENDC}"
        echo "16. Brute Force Scripts (Auth Category)"
        echo "17. Traceroute & Geo-location"
        echo "18. Aggressive All Ports Scan (-A -p-)"
        echo "19. Full Network Sweep (Ping Only)"
        echo "20. Scan for ALL TCP ports with OS detection"
        echo "0.  Back to Main Menu"
        echo "--------------------------------------------------"

        read -p "$(echo -e ${COLOR_BOLD})Select an advanced scan: $(echo -e ${COLOR_ENDC})" choice
        
        local cmd=()
        
        case "$choice" in
            1)
                cmd=(sudo nmap -sn -PE -PS22,80,443 -PA80,443 -PU53 -T4 "$target")
                ;;
            2)
                if [[ -n "$ports" ]]; then
                    cmd=(sudo nmap -Pn -sS -T4 -p "$ports" "$target")
                else
                    cmd=(sudo nmap -Pn -sS -T4 -p- "$target")
                fi
                ;;
            3)
                cmd=(sudo nmap -f -sS -T4)
                [[ -n "$ports" ]] && cmd+=(-p "$ports")
                cmd+=("$target")
                ;;
            4)
                cmd=(sudo nmap -D RND:10 -sS -T4)
                [[ -n "$ports" ]] && cmd+=(-p "$ports")
                cmd+=("$target")
                ;;
            5)
                read -p "$(echo -e ${COLOR_YELLOW})Enter Zombie IP for Idle Scan: $(echo -e ${COLOR_ENDC})" zombie
                if [[ -n "$zombie" ]]; then
                    cmd=(sudo nmap -Pn -sI "$zombie")
                    [[ -n "$ports" ]] && cmd+=(-p "$ports")
                    cmd+=("$target")
                fi
                ;;
            6)
                cmd=(nmap --script http-enum,http-title,http-vuln* -sV -T4)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 80,443)
                fi
                cmd+=("$target")
                ;;
            7)
                cmd=(nmap --script smb-vuln* -sV -T4)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 139,445)
                fi
                cmd+=("$target")
                ;;
            8)
                cmd=(nmap --script ftp-anon,ftp-vuln* -sV -T4)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 21)
                fi
                cmd+=("$target")
                ;;
            9)
                cmd=(nmap --script mysql-empty-password,mysql-vuln* -sV -T4)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 3306)
                fi
                cmd+=("$target")
                ;;
            10)
                cmd=(nmap --script ssl-heartbleed -sV)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 443)
                fi
                cmd+=("$target")
                ;;
            11)
                cmd=(nmap --script http-waf-detect,http-waf-fingerprint -T4)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 80,443)
                fi
                cmd+=("$target")
                ;;
            12)
                cmd=(nmap --script http-slowloris-check -T4)
                [[ -n "$ports" ]] && cmd+=(-p "$ports")
                cmd+=("$target")
                ;;
            13)
                echo -e "${COLOR_RED}${COLOR_BOLD}WARNING: This scan is extremely slow and can take many hours.${COLOR_ENDC}"
                if [[ -n "$ports" ]]; then
                    cmd=(sudo nmap -sS -sU -T4 -p "$ports" "$target")
                else
                    cmd=(sudo nmap -sS -sU -T4 -p T:-,U:1-4000 "$target")
                fi
                ;;
            14)
                cmd=(nmap -sV -sC --script '"not intrusive"')
                [[ -n "$ports" ]] && cmd+=(-p "$ports")
                cmd+=("$target")
                ;;
            15)
                echo -e "${COLOR_RED}${COLOR_BOLD}WARNING: Running 'exploit' scripts is dangerous and may crash the target.${COLOR_ENDC}"
                read -p "Are you sure you want to continue? (yes/no): " confirm
                if [[ "$confirm" == "yes" ]]; then
                    cmd=(sudo nmap -sV --script exploit -T4)
                    [[ -n "$ports" ]] && cmd+=(-p "$ports")
                    cmd+=("$target")
                fi
                ;;
            16)
                cmd=(nmap -sV --script auth -T4)
                [[ -n "$ports" ]] && cmd+=(-p "$ports")
                cmd+=("$target")
                ;;
            17)
                cmd=(nmap --traceroute --script traceroute-geolocation -T4)
                if [[ -n "$ports" ]]; then
                    cmd+=(-p "$ports")
                else
                    cmd+=(-p 80)
                fi
                cmd+=("$target")
                ;;
            18)
                echo -e "${COLOR_RED}${COLOR_BOLD}WARNING: This is a very noisy and slow scan.${COLOR_ENDC}"
                cmd=(sudo nmap -A -p- -T4 "$target")
                ;;
            19)
                cmd=(nmap -sn -T4 "$target")
                ;;
            20)
                if [[ -n "$ports" ]]; then
                    cmd=(sudo nmap -O -T4 -p "$ports" "$target")
                else
                    cmd=(sudo nmap -O -T4 -p- "$target")
                fi
                ;;
            0)
                break
                ;;
            *)
                echo -e "${COLOR_RED}Invalid choice.${COLOR_ENDC}"
                ;;
        esac

        if [[ ${#cmd[@]} -gt 0 ]]; then
            run_command "${cmd[@]}"
        fi
    done
}

show_menu() {
    echo -e "\n${COLOR_HEADER}${COLOR_BOLD}--- RedEye Nmap Scanner Menu ---${COLOR_ENDC}"
    
    if [[ -n "$CURRENT_SESSION" ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}Active Session: ${CURRENT_SESSION}${COLOR_ENDC}"
    else
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}No Active Session (scans will not be saved)${COLOR_ENDC}"
    fi
    
    if [[ -n "$CURRENT_TARGET" ]]; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}Current Target: ${CURRENT_TARGET}${COLOR_ENDC}"
    else
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}No Target Set${COLOR_ENDC}"
    fi
    
    if [[ -n "$CURRENT_PORTS" ]]; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}Custom Ports: ${CURRENT_PORTS}${COLOR_ENDC}"
    else
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}Ports: Default${COLOR_ENDC}"
    fi
    
    echo "----------------------------------"
    echo "--- Target & Port Management ---"
    echo "1.  Set / Change Target"
    echo "2.  Set / Unset Custom Ports (Optional)"
    
    echo ""
    echo "--- Basic Scans ---"
    echo "3.  Ping Scan (Host Discovery only)"
    echo "4.  Intense Scan (-A -T4)"
    echo "5.  Fast Scan (Top 100 ports)"
    echo "6.  Default Scripts Scan (-sC)"
    echo "7.  Vulnerability Scan (General 'vuln' scripts)"

    echo ""
    echo "--- Session, Reporting & Advanced ---"
    echo -e "${COLOR_CYAN}8.  Set / Create Scan Session${COLOR_ENDC}"
    echo -e "${COLOR_CYAN}9.  Compare Two Scans (Diff)${COLOR_ENDC}"
    echo -e "${COLOR_CYAN}10. Generate HTML Report${COLOR_ENDC}"
    echo -e "${COLOR_CYAN}11. Advanced Scans Menu${COLOR_ENDC}"

    echo ""
    echo "--- Other Options ---"
    echo "12. Custom Nmap Command"
    echo -e "${COLOR_GREEN}13. Nmap Command Helper${COLOR_ENDC}"
    echo "0.  Exit"
    echo "----------------------------------"
}

# =============================================================================
# MAIN APPLICATION FUNCTION
# =============================================================================

main() {
    clear
    show_banner
    
    setup_environment
    
    mkdir -p "$SESSIONS_DIR" 2>/dev/null

    while true; do
        show_menu
        read -p "$(echo -e ${COLOR_BOLD})Enter your choice: $(echo -e ${COLOR_ENDC})" choice
        
        local scan_choices=("3" "4" "5" "6" "7" "11")
        
        case "$choice" in
            1)
                read -p "$(echo -e ${COLOR_YELLOW})Enter target IP or domain: $(echo -e ${COLOR_ENDC})" target
                target=$(echo "$target" | xargs)  # trim whitespace
                if [[ -z "$target" ]]; then
                    echo -e "${COLOR_RED}Target cannot be empty.${COLOR_ENDC}"
                    CURRENT_TARGET=""
                else
                    CURRENT_TARGET="$target"
                fi
                ;;
            2)
                read -p "$(echo -e ${COLOR_YELLOW})Enter custom ports (or blank to clear): $(echo -e ${COLOR_ENDC})" ports_in
                ports_in=$(echo "$ports_in" | xargs)  # trim whitespace
                if [[ -z "$ports_in" ]]; then
                    CURRENT_PORTS=""
                else
                    CURRENT_PORTS="$ports_in"
                fi
                ;;
            3|4|5|6|7|11)
                if [[ -z "$CURRENT_TARGET" ]]; then
                    echo -e "\n${COLOR_RED}${COLOR_BOLD}No target has been set. Please use option '1' first.${COLOR_ENDC}"
                    continue
                fi
                
                case "$choice" in
                    3)
                        run_command nmap -sn "$CURRENT_TARGET"
                        ;;
                    4)
                        local cmd=(nmap -A -T4)
                        [[ -n "$CURRENT_PORTS" ]] && cmd+=(-p "$CURRENT_PORTS")
                        cmd+=("$CURRENT_TARGET")
                        run_command "${cmd[@]}"
                        ;;
                    5)
                        local cmd=(nmap -F -T4)
                        [[ -n "$CURRENT_PORTS" ]] && cmd+=(-p "$CURRENT_PORTS")
                        cmd+=("$CURRENT_TARGET")
                        run_command "${cmd[@]}"
                        ;;
                    6)
                        local cmd=(nmap -sC)
                        [[ -n "$CURRENT_PORTS" ]] && cmd+=(-p "$CURRENT_PORTS")
                        cmd+=("$CURRENT_TARGET")
                        run_command "${cmd[@]}"
                        ;;
                    7)
                        local cmd=(nmap --script vuln -sV)
                        [[ -n "$CURRENT_PORTS" ]] && cmd+=(-p "$CURRENT_PORTS")
                        cmd+=("$CURRENT_TARGET")
                        run_command "${cmd[@]}"
                        ;;
                    11)
                        show_advanced_scans
                        ;;
                esac
                ;;
            8)
                set_session
                ;;
            9)
                compare_scans
                ;;
            10)
                generate_report
                ;;
            12)
                read -p "$(echo -e ${COLOR_YELLOW})Enter full nmap command: $(echo -e ${COLOR_ENDC})" custom_cmd
                custom_cmd=$(echo "$custom_cmd" | xargs)
                if [[ "$custom_cmd" == nmap* ]]; then
                    run_command $custom_cmd
                else
                    echo -e "${COLOR_RED}Invalid command. It must start with 'nmap '.${COLOR_ENDC}"
                fi
                ;;
            13)
                show_helper
                ;;
            0)
                echo -e "${COLOR_GREEN}Exiting RedEye. Goodbye!${COLOR_ENDC}"
                exit 0
                ;;
            *)
                echo -e "${COLOR_RED}Invalid choice. Please try again.${COLOR_ENDC}"
                ;;
        esac
    done
}

# =============================================================================
# SIGNAL HANDLING
# =============================================================================

trap 'echo -e "\n${COLOR_YELLOW}Operation cancelled by user. Exiting RedEye.${COLOR_ENDC}"; exit 130' INT TERM

# =============================================================================
# ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$1" == "--test-deps" ]]; then
        ensure_tools
        exit $?
    else
        main
    fi
fi