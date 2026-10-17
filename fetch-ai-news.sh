#!/usr/bin/env bash
#
# fetch-ai-news.sh — Fetch the latest AI news, log everything.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-${SCRIPT_DIR}}"
LOG_DIR="${BASE_DIR}/logs"
SEND_EMAIL="${SEND_EMAIL:-false}"
AGENTMAIL_API_KEY="${AGENTMAIL_API_KEY:-}"
AGENTMAIL_INBOX_ID="${AGENTMAIL_INBOX_ID:-}"
AGENTMAIL_TO="${AGENTMAIL_TO:-}"
ERROR_LOG="${LOG_DIR}/errors.log"
RUN_LOG="${LOG_DIR}/runs.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

mkdir -p "${LOG_DIR}"

log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${RUN_LOG}"
}

err_log() {
    echo "[${TIMESTAMP}] ERROR: $*" | tee -a "${ERROR_LOG}" >&2
}

cleanup() {
    local ec=$?
    if [ $ec -ne 0 ]; then
        err_log "Script exited with code ${ec}"
    fi
    exit $ec
}
trap cleanup EXIT

log "=== AI News Update Started ==="

# -------------------------------------------------------------------
# Fetch news — using a few reliable, lightweight sources.
# We use curl with a short timeout so a hang doesn't stall cron forever.
# -------------------------------------------------------------------
NEWS_OUTPUT="${BASE_DIR}/latest-news-$(date +%Y%m%d).md"
export NEWS_OUTPUT AGENTMAIL_API_KEY AGENTMAIL_INBOX_ID AGENTMAIL_TO

{
    echo "# AI News — $(date '+%A, %d %B %Y')"
    echo ""
    echo "_Fetched at ${TIMESTAMP}_"
    echo ""
    echo "---"
    echo ""

    # Source 1: Hugging Face Daily Papers (AI/ML focused)
    log "Fetching Hugging Face daily papers..."
    HF_DATA=$(curl -sS --max-time 15 \
        "https://huggingface.co/api/daily_papers?limit=5" 2>/dev/null || true)
    if [ -n "${HF_DATA}" ] && echo "${HF_DATA}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null | grep -q '[1-9]'; then
        echo "## 🤗 Hugging Face Daily Papers"
        echo "${HF_DATA}" | python3 -c "
import sys, json
papers = json.load(sys.stdin)
for p in papers[:5]:
    title = p.get('title', 'Untitled')
    url = p.get('url', '') or f\"https://arxiv.org/abs/{p.get('paper', {}).get('id', '')}\"
    print(f'- [{title}]({url})')
" 2>/dev/null || echo "- (Could not parse HF papers)"
    else
        echo "## 🤗 Hugging Face Daily Papers"
        echo "- (Could not fetch papers — service may be unreachable)"
    fi
    echo ""

    # Source 2: ArXiv AI (cs.AI, cs.LG, cs.CL)
    log "Fetching ArXiv AI listings..."
    ARXIV_DATA=$(curl -sS --max-time 20 \
        "http://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.LG+OR+cat:cs.CL&sortBy=submittedDate&sortOrder=descending&max_results=5" 2>/dev/null || true)
    if [ -n "${ARXIV_DATA}" ] && echo "${ARXIV_DATA}" | grep -qi '<entry>'; then
        echo "## 📄 ArXiv — Recent AI/ML Papers"
        echo "${ARXIV_DATA}" | python3 -c "
import sys, xml.etree.ElementTree as ET
data = sys.stdin.read()
root = ET.fromstring(data)
ns = {'a': 'http://www.w3.org/2005/Atom'}
entries = root.findall('a:entry', ns)
for e in entries[:5]:
    title = e.find('a:title', ns).text.strip().replace('\n', ' ') if e.find('a:title', ns) is not None else 'Untitled'
    link = e.find('a:id', ns).text if e.find('a:id', ns) is not None else ''
    print(f'- [{title}]({link})')
" 2>/dev/null || echo "- (Could not parse ArXiv entries)"
    else
        echo "## 📄 ArXiv — Recent AI/ML Papers"
        echo "- (Could not fetch ArXiv — service may be unreachable)"
    fi
    echo ""

    # Source 3: Simple RSS grab — The Verge AI (lightweight)
    log "Fetching tech headlines (The Verge AI)..."
    VERGE_DATA=$(curl -sS --max-time 15 \
        "https://www.theverge.com/ai-artificial-intelligence/rss.xml" 2>/dev/null || true)
    if [ -n "${VERGE_DATA}" ] && echo "${VERGE_DATA}" | grep -qi '<item>'; then
        echo "## 📰 AI Headlines (The Verge)"
        echo "${VERGE_DATA}" | python3 -c "
import sys, xml.etree.ElementTree as ET
data = sys.stdin.read()
root = ET.fromstring(data)
items = root.findall('.//item')
for item in items[:5]:
    title = item.find('title').text.strip() if item.find('title') is not None else 'Untitled'
    link = item.find('link').text if item.find('link') is not None else ''
    pub = item.find('pubDate').text if item.find('pubDate') is not None else ''
    print(f'- [{title}]({link})  _{pub}_')
" 2>/dev/null || echo "- (Could not parse The Verge feed)"
    else
        echo "## 📰 AI Headlines (The Verge)"
        echo "- (Could not fetch feed — service may be unreachable)"
    fi
    echo ""
} > "${NEWS_OUTPUT}" 2>>"${ERROR_LOG}"

log "News saved to ${NEWS_OUTPUT}"

# Display a summary
echo "════════════════════════════════════════════════"
echo "  AI NEWS DIGEST  —  $(date '+%A, %d %B %Y')"
echo "════════════════════════════════════════════════"
head -60 "${NEWS_OUTPUT}"
echo ""
echo "... (full report at ${NEWS_OUTPUT})"
echo "════════════════════════════════════════════════"

# ===================================================================
# Optional AgentMail delivery. Disabled by default to prevent accidental
# external sends; credentials and recipients must be supplied at runtime.
# ===================================================================
if [[ "${SEND_EMAIL,,}" == "true" ]]; then
    if [[ -z "${AGENTMAIL_API_KEY}" || -z "${AGENTMAIL_INBOX_ID}" || -z "${AGENTMAIL_TO}" ]]; then
        err_log "SEND_EMAIL=true requires AGENTMAIL_API_KEY, AGENTMAIL_INBOX_ID, and AGENTMAIL_TO"
    elif python3 -I -c "
import os, sys
try:
    import agentmail
    client = agentmail.AgentMail(api_key=os.environ['AGENTMAIL_API_KEY'])
    with open(os.environ['NEWS_OUTPUT'], 'r', encoding='utf-8') as f:
        content = f.read()
    resp = client.inboxes.messages.send(
        inbox_id=os.environ['AGENTMAIL_INBOX_ID'],
        to=[os.environ['AGENTMAIL_TO']],
        subject='📰 AI News Digest',
        text=content,
    )
    print(f'Sent OK — Message ID: {resp.message_id}')
except Exception as e:
    print(f'FAILED: {e}')
    sys.exit(1)
" 2>>"${ERROR_LOG}"; then
        log "News digest emailed successfully"
    else
        err_log "Failed to email news digest"
    fi
else
    log "Email delivery disabled (set SEND_EMAIL=true to enable)"
fi

log "=== AI News Update Completed Successfully ==="
