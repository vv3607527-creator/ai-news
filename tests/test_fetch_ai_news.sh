#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *huggingface*) printf '[{"title":"Test paper","url":"https://example.test/paper"}]' ;;
  *arxiv*) printf '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Test arXiv</title><id>https://example.test/arxiv</id></entry></feed>' ;;
  *theverge*) printf '<rss><channel><item><title>Test headline</title><link>https://example.test/news</link><pubDate>today</pubDate></item></channel></rss>' ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$TMP/bin/curl"
BASE_DIR="$TMP/output" SEND_EMAIL=false PATH="$TMP/bin:$PATH" bash "$ROOT/fetch-ai-news.sh" >"$TMP/stdout" 2>"$TMP/stderr"
test -s "$TMP/output/latest-news-$(date +%Y%m%d).md"
grep -q 'Test paper' "$TMP/output/latest-news-$(date +%Y%m%d).md"
grep -q 'Test arXiv' "$TMP/output/latest-news-$(date +%Y%m%d).md"
grep -q 'Test headline' "$TMP/output/latest-news-$(date +%Y%m%d).md"
grep -q 'Email delivery disabled' "$TMP/output/logs/runs.log"
printf '%s\n' 'offline mocked-feed integration: PASS'
