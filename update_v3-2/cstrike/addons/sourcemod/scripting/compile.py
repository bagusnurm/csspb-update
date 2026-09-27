import subprocess
import shutil
import sys
import os

SM_DIR = r"D:\Game\CSSPB\cstrike\addons\sourcemod"
COMPILER = os.path.join(SM_DIR, "scripting", "compile.exe")
COMPILED = os.path.join(SM_DIR, "scripting", "compiled")
PLUGINS = os.path.join(SM_DIR, "plugins")

print("=== Sourcemod Auto Compiler ===")

if len(sys.argv) < 2:
    print("[ERROR] Drag & drop file .sp ke script ini.")
    input("Press Enter to exit...")
    sys.exit(1)

sp_file = sys.argv[1]
print(f"[INFO] File SP: {sp_file}")
print(f"[INFO] Compiler : {COMPILER}")

# Jalankan compiler
try:
    proc = subprocess.run(
        [COMPILER, sp_file],
        capture_output=True,
        text=True,
        shell=True  # penting untuk path ada spasi
    )
except Exception as e:
    print(f"[FATAL] Gagal menjalankan compiler: {e}")
    input("Press Enter to exit...")
    sys.exit(1)

# Tampilkan output compile
print("----- COMPILER OUTPUT -----")
print(proc.stdout)
print(proc.stderr)
print("---------------------------")

if proc.returncode != 0:
    print("[ERROR] Compile gagal!")
    input("Press Enter to exit...")
    sys.exit(1)

# Copy hasil .smx ke plugins
name, _ = os.path.splitext(os.path.basename(sp_file))
src = os.path.join(COMPILED, f"{name}.smx")
dst = os.path.join(PLUGINS, f"{name}.smx")

try:
    shutil.copy2(src, dst)
    print(f"[SUCCESS] {name}.smx sudah ter-copy ke folder plugins.")
except Exception as e:
    print(f"[ERROR] Gagal copy file: {e}")

input("Press Enter to exit...")
