# AI News Digest

`fetch-ai-news.sh` collects a small digest from Hugging Face Daily Papers, arXiv, and The Verge RSS, writing dated Markdown and logs under `BASE_DIR`.

## Safe usage

The default `BASE_DIR` is the directory containing the script. Override it when running from cron or another installation directory:

```bash
BASE_DIR=/var/lib/ai-news SEND_EMAIL=false ./fetch-ai-news.sh
```

Email delivery is **disabled by default**. To enable it, provide credentials and recipients at runtime; no secret is stored in the repository:

```bash
SEND_EMAIL=true \
AGENTMAIL_API_KEY='…' \
AGENTMAIL_INBOX_ID='…' \
AGENTMAIL_TO='recipient@example.com' \
./fetch-ai-news.sh
```

The script uses bounded `curl` timeouts and records failures in `logs/errors.log`. Feed failures produce an explanatory section in the digest rather than aborting the whole collection.

## Tests

The offline integration test mocks all three feeds, disables delivery, and verifies generated output without contacting external services:

```bash
bash -n fetch-ai-news.sh
bash -n tests/test_fetch_ai_news.sh
./tests/test_fetch_ai_news.sh
```
