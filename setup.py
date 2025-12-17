#!/usr/bin/env python3
"""
Verilator Installation Check and Auto-Install Script
For Ubuntu systems
"""

import subprocess
import sys
import os
import shutil
from pathlib import Path

def run_command(cmd, check=True, capture_output=True, text=True):
    """Execute shell command and return result"""
    try:
        result = subprocess.run(cmd, shell=True, check=check, 
                              capture_output=capture_output, text=text)
        return result
    except subprocess.CalledProcessError as e:
        print(f"Command execution failed: {cmd}")
        print(f"Error message: {e.stderr}")
        if check:
            sys.exit(1)
        return e

def check_verilator_installed():
    """Check if Verilator is already installed"""
    print("Checking if Verilator is installed...")
    
    # Method 1: Check if verilator command exists
    if shutil.which("verilator"):
        print("✓ Verilator command exists")
        
        # Check version
        result = run_command("verilator --version", check=False)
        if result.returncode == 0:
            version = result.stdout.strip()
            print(f"✓ Verilator version: {version}")
            return True
        else:
            print("✗ Verilator command exists but cannot get version info")
            return False
    else:
        print("✗ Verilator not installed")
        return False

def install_dependencies():
    """Install Verilator dependencies"""
    print("\nInstalling Verilator dependencies...")
    
    # Update package list
    print("Updating package list...")
    run_command("sudo apt-get update")
    
    # Install dependencies (according to Verilator official documentation)
    dependencies = [
        "git", "help2man", "perl", "python3", "make", "autoconf", "g++", "flex", "bison", "ccache",
        "numactl", "perl-doc",
        "libfl2",
        "libfl-dev",
        "zlib1g", "zlib1g-dev"
    ]

    # Additional packages for newer Ubuntu versions
    extra_deps = [
        "gtkwave",  # Optional: waveform viewer
    ]
    
    all_deps = dependencies + extra_deps

    print(f"Installing dependencies: {', '.join(dependencies)}")
    
    for v in dependencies:
        cmd = f"sudo apt-get install -y {v}"
        result = run_command(cmd)

    print("✓ Dependencies installed successfully")
    return True
    # if result.returncode == 0:
    #     print("✓ Dependencies installed successfully")
    #     return True
    # else:
    #     print("✗ Dependency installation failed")
    #     return False

def install_verilator_from_source():
    """Compile and install Verilator from source"""
    print("\nCompiling and installing Verilator from source...")
    
    # Create temporary directory
    temp_dir = Path("/tmp/verilator_install")
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True)
    
    try:
        # Change to temporary directory
        os.chdir(temp_dir)
        
        # Clone Verilator repository
        print("Cloning Verilator source code...")
        run_command("git clone https://github.com/verilator/verilator")
        
        run_command("unset VERILATOR_ROOT")
        os.chdir("verilator")

        # Switch to stable version (e.g., latest stable tag)
        print("Switching to stable version...")
        # Get latest stable tag
        result = run_command("git tag -l 'v[0-9]*' | sort -V | tail -1")
        latest_stable = result.stdout.strip()
        latest_stable = "v5.038"
        
        if latest_stable:
            run_command(f"git checkout {latest_stable}")
            print(f"Switched to version: {latest_stable}")
        else:
            print("Using latest main branch")
        
        # Configure and compile
        print("Running autoconf...")
        run_command("autoconf")
        
        print("Configuring build options...")
        # Install to system directory with --prefix=/usr/local
        run_command("./configure --prefix=/usr/local")
        
        print("Compiling Verilator...")
        # Use multi-core compilation for speed
        cpu_cores = os.cpu_count()
        run_command(f"make -j{cpu_cores}")
        
        print("Installing Verilator...")
        run_command("sudo make install")
        
        print("✓ Verilator installation completed")
        return True
        
    except Exception as e:
        print(f"✗ Verilator installation failed: {e}")
        return False
    finally:
        # Clean up temporary directory
        if temp_dir.exists():
            shutil.rmtree(temp_dir)

def install_verilator_from_ppa():
    """Attempt to install Verilator from PPA (Ubuntu specific)"""
    print("\nAttempting to install Verilator from PPA...")
    
    try:
        # Add PPA repository
        print("Adding Verilator PPA...")
        run_command("sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test")
        run_command("sudo apt-get update")
        
        # Install Verilator
        print("Installing Verilator...")
        run_command("sudo apt-get install -y verilator")
        
        # Verify installation
        result = run_command("verilator --version", check=False)
        if result.returncode == 0:
            print(f"✓ Verilator installed successfully: {result.stdout.strip()}")
            return True
        else:
            print("✗ PPA installation failed, attempting source installation")
            return False
            
    except Exception as e:
        print(f"✗ PPA installation failed: {e}")
        return False

def check_installation_success():
    """Verify if installation was successful"""
    print("\nVerifying installation result...")
    
    result = run_command("verilator --version", check=False)
    if result.returncode == 0:
        version = result.stdout.strip()
        print(f"✓ Verilator installed successfully! Version: {version}")
        
        # Simple functionality test
        print("Performing simple functionality test...")
        test_result = run_command("verilator --help | head -5", check=False)
        if test_result.returncode == 0:
            print("✓ Verilator functionality is normal")
        else:
            print("⚠ Verilator functionality test failed")
            
        return True
    else:
        print("✗ Verilator installation failed")
        return False

def check_software_toolchain_installed():
    """Check if Software toolchain is already installed"""
    print("Checking if Software toolchain is installed...")

    # Method 1: Check if verilator command exists
    if shutil.which("riscv32-unknown-elf-gcc"):
        print("✓ riscv32-unknown-elf-gcc command exists")

        # Check version
        result = run_command("riscv32-unknown-elf-gcc --version", check=False)
        if result.returncode == 0:
            version = result.stdout.strip()
            print(f"✓ {version}")
            return True
        else:
            print("✗ riscv32-unknown-elf-gcc command exists but cannot get version info")
            return False
    else:
        print("✗ riscv32-unknown-elf-gcc not installed")
        return False


def install_software_toolchain():
    """Install software toolchain from source"""
    print("\nInstalling software toolchain from source...")

    # Create temporary directory
    temp_dir = Path("/tmp/software_install")
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True)

    try:
        # Change to temporary directory
        os.chdir(temp_dir)
        
        # Clone Verilator repository
        print("Download RISCV GNU Toolchain ...")
        run_command("wget https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2025.05.01/riscv32-elf-ubuntu-22.04-gcc-nightly-2025.05.01-nightly.tar.xz")
        run_command("tar -xvf riscv32-elf-ubuntu-22.04-gcc-nightly-2025.05.01-nightly.tar.xz")
        run_command("sudo cp -rf riscv/bin/* /usr/local/bin")

        print("✓ software toolchain installation completed")
        return True
        
    except Exception as e:
        print(f"✗ software toolchain installation failed: {e}")
        return False
    finally:
        # Clean up temporary directory
        if temp_dir.exists():
            shutil.rmtree(temp_dir)

def main():
    """Main function"""
    print("=" * 60)
    print("Verilator Installation Check Script")
    print("=" * 60)

    project_path = os.getcwd()

    # Check current system
    if not sys.platform.startswith('linux'):
        print("Error: This script only works on Linux systems")
        sys.exit(1)

    # Check if Ubuntu/Debian
    try:
        with open('/etc/os-release', 'r') as f:
            os_info = f.read()
            if 'ubuntu' not in os_info.lower() and 'debian' not in os_info.lower():
                print("Warning: This script is primarily for Ubuntu/Debian systems")
    except FileNotFoundError:
        print("Warning: Unable to determine operating system type")

    # Check if already installed
    if check_verilator_installed():
        print("\n✓ Verilator is already installed, no action needed")
        sys.exit(0)

    # Ask user if they want to continue with installation
    # response = input("\nVerilator not installed, continue with installation? (y/N): ").strip().lower()
    # if response not in ['y', 'yes']:
    #     print("Installation cancelled")
    #     sys.exit(0)

    # Install dependencies
    if not install_dependencies():
        print("Dependency installation failed, exiting")
        sys.exit(1)

    # Choose installation method
    print("\nSelect installation method:")
    print("1. Compile from source (recommended, get latest version)")
    print("2. Install from PPA (may be older version, but more stable)")

    # choice = input("Enter choice (1 or 2, default 1): ").strip()
    choice = "1"

    success = False
    if choice == "2":
        print("\nAttempting PPA installation...")
        success = install_verilator_from_ppa()
        if not success:
            print("PPA installation failed, falling back to source installation")
            success = install_verilator_from_source()
    else:
        print("\nCompiling from source...")
        success = install_verilator_from_source()

    # Verify installation
    if success:
        check_installation_success()
        print("\n🎉 Verilator installation completed!")

        # Display usage tips
        print("\nUsage tips:")
        print("1. Verify installation: verilator --version")
        print("2. View help: verilator --help")
        print("3. Compile example: verilator --cc --exe example.v")
    else:
        print("\n❌ Verilator installation failed")
        print("Please refer to official documentation for manual installation: https://verilator.org/guide/latest/install.html")
        sys.exit(1)

    if check_software_toolchain_installed():
        print("\n✓ software toolchain is already installed, no action needed")
        sys.exit(0)

    if not install_software_toolchain():
        print("software toolchain installation failed, exiting")
        sys.exit(1)

    check_software_toolchain_installed()

    # TODO: git clone mpw
    os.chdir(project_path)
    run_command("git clone https://github.com/retroSoC/mini-ver-mpw.git rtl/mini/mpw")
    

if __name__ == "__main__":
    main()