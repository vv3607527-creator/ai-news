#!/usr/bin/env bash
#
# fetch-ai-news.sh — Fetch the latest AI news, log everything.
#
set -euo pipefail

BASE_DIR="/root/ai-news"
LOG_DIR="${BASE_DIR}/logs"
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
# Send via AgentMail Email
# ===================================================================
log "Sending news digest via AgentMail..."
if python3 -I -c "
import sys
try:
    import agentmail
    api_key = 'am_us_1b883aa1de96b109b495a2ea8bbe87ec3197c6f284280c3477bac31b9c01001e'
    inbox_id = 'venky5789@agentmail.to'
    to_email = 'venky5789@agentmail.to'

    client = agentmail.AgentMail(api_key=api_key)

    # Read the news file
    with open('${NEWS_OUTPUT}', 'r') as f:
        content = f.read()

    # Send the email
    resp = client.inboxes.messages.send(
        inbox_id=inbox_id,
        to=[to_email],
        subject='📰 AI News Digest — $(date "+%A, %d %B %Y")',
        text=content,
    )
    print(f'Sent OK — Message ID: {resp.message_id}')
    sys.exit(0)
except Exception as e:
    print(f'FAILED: {e}')
    sys.exit(1)
" 2>>"${ERROR_LOG}"; then
    log "✅ News digest emailed successfully to venky5789@agentmail.to"
else
    err_log "Failed to email news digest"
fi

log "=== AI News Update Completed Successfully ==="
