#!/usr/bin/env bash
set -euo pipefail

# ===== 1. Base packages =====
sudo apt-get update -qq
sudo apt-get install -y -qq jq pipx python3-pip python3-venv git curl unzip \
  build-essential libpcap-dev chromium-browser 2>/dev/null || true

# ===== 2. Go environment =====
export GOPATH=$HOME/go
export GOTMPDIR=$HOME/go-tmp
export PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
mkdir -p "$GOPATH/bin" "$GOTMPDIR"

grep -q 'GOPATH=$HOME/go' ~/.bashrc || cat >> ~/.bashrc <<'EOF'
export GOPATH=$HOME/go
export GOTMPDIR=$HOME/go-tmp
export PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
EOF

# ===== 3. Go recon tools =====
GO_TOOLS=(
  github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  github.com/projectdiscovery/dnsx/cmd/dnsx@latest
  github.com/projectdiscovery/httpx/cmd/httpx@latest
  github.com/projectdiscovery/katana/cmd/katana@latest
  github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
  github.com/tomnomnom/waybackurls@latest
  github.com/lc/gau/v2/cmd/gau@latest
  github.com/ffuf/ffuf/v2@latest
)
for t in "${GO_TOOLS[@]}"; do
  echo "[+] go install $t"
  go install "$t" || echo "[!] failed: $t (lanjut)"
done

# ===== 4. ptai (Pentest-AI) =====
pipx ensurepath || true
pipx install ptai || pipx upgrade ptai

# ===== 5. Ollama + model kecil =====
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
# Jalankan ollama di background
nohup ollama serve >/tmp/ollama.log 2>&1 &
sleep 5
# Model 3B: muat di 8GB RAM Codespaces
ollama pull qwen2.5:3b-instruct || ollama pull llama3.2:3b || true

# ===== 6. Workspace =====
mkdir -p ~/bounty/{_templates,_scopes,_reports}
echo "[✓] Bootstrap selesai. Jalankan: source ~/.bashrc && ptai --help"
