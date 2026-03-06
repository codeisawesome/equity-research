#!/bin/bash
# ============================================================
#  deploy.sh — Equity Research Hub auto-deploy script
# ============================================================
#  Detects new HTML dashboard files, adds cards to the landing
#  page (index.html), and pushes everything to GitHub Pages.
#
#  USAGE:
#    1. Drop your new dashboard .html file(s) into this folder
#    2. Open Terminal and run:
#         cd ~/equity-research
#         ./deploy.sh
#    3. Done — your site updates in ~30 seconds.
#
#  FIRST-TIME SETUP — see SETUP.md in this folder.
# ============================================================

set -e

# -- Navigate to the script's directory (the repo root) ------
cd "$(dirname "$0")"

# -- Colors for terminal output -------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Equity Research Hub — Deploy Script${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# -- Check: are we in a git repo? -----------------------------
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${RED}Error: This folder is not a git repository.${NC}"
    echo "See SETUP.md for first-time setup instructions."
    exit 1
fi

# -- Pull latest changes first --------------------------------
echo -e "${YELLOW}Pulling latest changes from GitHub...${NC}"
git pull --quiet origin main 2>/dev/null || true

# -- Find all HTML files that are NOT index.html --------------
ALL_HTML=$(find . -maxdepth 1 -name '*.html' -print | sed 's|^\./||' | grep -v '^index\.html$' | sort || true)
LINKED_FILES=$(grep -o 'href="[^"]*\.html"' index.html 2>/dev/null | sed 's/href="//;s/"$//' | grep -v '^index\.html$' || true)

NEW_FILES=""
REMOVED_FILES=""
EXISTING_COUNT=0

for file in $ALL_HTML; do
    if echo "$LINKED_FILES" | grep -qx "$file"; then
        EXISTING_COUNT=$((EXISTING_COUNT + 1))
    else
        NEW_FILES="$NEW_FILES $file"
    fi
done

for file in $LINKED_FILES; do
    if ! echo "$ALL_HTML" | grep -qx "$file"; then
        REMOVED_FILES="$REMOVED_FILES $file"
    fi
done

NEW_FILES=$(echo "$NEW_FILES" | xargs)
REMOVED_FILES=$(echo "$REMOVED_FILES" | xargs)

if [ -z "$NEW_FILES" ] && [ -z "$REMOVED_FILES" ]; then
    echo -e "${GREEN}Landing page is already aligned with current dashboard files.${NC}"
    echo ""
    if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
        echo -e "${GREEN}Everything is up to date. Nothing to deploy.${NC}"
        exit 0
    else
        echo -e "${YELLOW}Found uncommitted changes. Pushing to GitHub...${NC}"
        git add -A
        git commit -m "Update dashboards"
        git push origin main
        echo -e "${GREEN}Done! Site will update in ~30 seconds.${NC}"
        exit 0
    fi
fi

echo -e "${GREEN}Found ${EXISTING_COUNT} dashboard(s) already linked in index.html.${NC}"
if [ -n "$NEW_FILES" ]; then
    echo -e "${YELLOW}Detected $(echo "$NEW_FILES" | wc -w | xargs) new file(s):${NC}"
    for file in $NEW_FILES; do
        echo "  + $file"
    done
fi
if [ -n "$REMOVED_FILES" ]; then
    echo -e "${YELLOW}Detected $(echo "$REMOVED_FILES" | wc -w | xargs) removed file(s):${NC}"
    for file in $REMOVED_FILES; do
        echo "  - $file"
    done
fi
echo ""

# -- Preserve existing card order, remove missing files, append new files --
ORDERED_FILES=""
for file in $LINKED_FILES; do
    if echo "$ALL_HTML" | grep -qx "$file"; then
        ORDERED_FILES="$ORDERED_FILES $file"
    fi
done
for file in $ALL_HTML; do
    if ! echo " $ORDERED_FILES " | grep -q " $file "; then
        ORDERED_FILES="$ORDERED_FILES $file"
    fi
done
ORDERED_FILES=$(echo "$ORDERED_FILES" | xargs)

# ============================================================
#  PARSE each current HTML file and generate cards
# ============================================================

rm -f /tmp/equity_cards.txt

for file in $ORDERED_FILES; do
    echo -e "${CYAN}Parsing: ${file}${NC}"

    # -- Extract ticker and company from <title> tag ----------
    # Expected format: $TICKER — Company Name | Equity Research Dashboard
    TITLE_LINE=$(grep -o '<title>[^<]*</title>' "$file" | head -1 | sed 's/<[^>]*>//g')

    TICKER=$(echo "$TITLE_LINE" | sed -n 's/^\(\$[A-Z]*\).*/\1/p')
    COMPANY=$(echo "$TITLE_LINE" | sed -n 's/^[^—]*— \(.*\) |.*/\1/p')

    if [ -z "$TICKER" ]; then
        echo -e "${RED}  Warning: Could not parse ticker from $file — skipping.${NC}"
        continue
    fi
    if [ -z "$COMPANY" ]; then
        COMPANY="Unknown Company"
    fi

    echo "  Ticker:  $TICKER"
    echo "  Company: $COMPANY"

    # -- Extract rating from the header area ------------------
    # Strategy: look for the first badge text near "Rating" or
    # the first badge class in the header section.
    RATING=""

    # Method 1: FLY-style — header-badge with "Rating" label
    # Format: <div class="val" ...>HOLD</div><div class="lbl">Rating</div>
    RATING=$(grep 'Rating</div>' "$file" 2>/dev/null | head -1 | sed -n 's/.*class="val"[^>]*>\([^<]*\)<.*Rating.*/\1/p' | xargs)

    # Method 2: TEL-style — badge class in header-right
    if [ -z "$RATING" ]; then
        RATING=$(sed -n '/header-right/,/<\/div>/{ s/.*class="badge[^"]*"[^>]*>\([^<]*\)<.*/\1/p; }' "$file" | head -1 | xargs)
    fi

    # Method 3: Quick Rating line
    if [ -z "$RATING" ]; then
        RATING=$(grep 'Quick Rating' "$file" | sed -n 's/.*class="badge[^"]*"[^>]*>\([^<]*\)<.*/\1/p' | head -1 | xargs)
    fi

    # Default fallback
    if [ -z "$RATING" ]; then
        RATING="NEW"
    fi

    echo "  Rating:  $RATING"

    # -- Determine badge color class --------------------------
    RATING_LOWER=$(echo "$RATING" | tr '[:upper:]' '[:lower:]')
    BADGE_CLASS="hold"
    if echo "$RATING_LOWER" | grep -q "buy" && echo "$RATING_LOWER" | grep -q "hold"; then
        BADGE_CLASS="mix"
    elif echo "$RATING_LOWER" | grep -q "buy"; then
        BADGE_CLASS="buy"
    elif echo "$RATING_LOWER" | grep -q "hold"; then
        BADGE_CLASS="hold"
    fi

    # -- Build a short description ----------------------------
    DESC="Equity research dashboard with financial analysis, valuation modeling, and risk assessment for ${COMPANY}."

    # -- Generate card HTML (store ticker/company/etc for Python) --
    # Append parsed data to a temp file for Python to process
    echo "${file}|||${TICKER}|||${COMPANY}|||${DESC}|||${BADGE_CLASS}|||${RATING}" >> /tmp/equity_cards.txt
    echo -e "${GREEN}  ✓ Card generated.${NC}"
    echo ""
done

# -- Rebuild cards section in index.html ----------------------
echo -e "${YELLOW}Updating index.html...${NC}"

python3 << 'PYEOF'
import os
import re

# Read the card data
cards_data = []
if os.path.exists('/tmp/equity_cards.txt'):
    with open('/tmp/equity_cards.txt', 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('|||')
            if len(parts) == 6:
                cards_data.append({
                    'file': parts[0],
                    'ticker': parts[1],
                    'company': parts[2],
                    'desc': parts[3],
                    'badge_class': parts[4],
                    'rating': parts[5],
                })

# Helpers for rebuilding the current lineup rows
def strip_tags(value):
    value = re.sub(r'<[^>]+>', ' ', value)
    value = value.replace('&nbsp;', ' ').replace('&#160;', ' ')
    value = value.replace('&bull;', ' ').replace('•', ' ')
    value = value.replace('&amp;', '&')
    value = re.sub(r'\s+', ' ', value)
    return value.strip()

def parse_badge_pairs(content):
    pairs = []
    for val, lbl in re.findall(r'<div class="val"[^>]*>(.*?)</div>\s*<div class="lbl"[^>]*>(.*?)</div>', content, re.S):
        pairs.append((strip_tags(lbl).lower(), strip_tags(val)))
    return pairs

def first_match(patterns, content, default=""):
    for pattern in patterns:
        match = re.search(pattern, content, re.S | re.I)
        if match:
            value = strip_tags(match.group(1))
            if value:
                return value
    return default

def parse_currency(value):
    if not value:
        return None
    cleaned = value.replace(',', '').replace('~', '').replace('$', '').strip()
    match = re.search(r'-?\d+(?:\.\d+)?', cleaned)
    return float(match.group(0)) if match else None

def infer_move(current_price, target_price):
    current = parse_currency(current_price)
    target = parse_currency(target_price)
    if current in (None, 0) or target is None:
        return ""
    change = ((target / current) - 1) * 100
    sign = '+' if change > 0 else ''
    return f"{sign}{change:.1f}%"

def normalize_badge_class(rating):
    rating_lower = rating.lower()
    if 'buy' in rating_lower and 'hold' in rating_lower:
        return 'mix'
    if 'buy' in rating_lower:
        return 'buy'
    return 'hold'

def move_class(move_text):
    if not move_text:
        return 'neutral'
    if move_text.startswith('+'):
        return 'positive'
    if move_text.startswith('-') or move_text.startswith('−'):
        return 'negative'
    return 'neutral'

def escape_attr(value):
    return (
        value.replace('&', '&amp;')
        .replace('"', '&quot;')
        .replace('<', '&lt;')
        .replace('>', '&gt;')
    )

def escape_html_text(value):
    return (
        value.replace('&', '&amp;')
        .replace('<', '&lt;')
        .replace('>', '&gt;')
    )

rows_html = ""
for card in cards_data:
    with open(card['file'], 'r') as dashboard_file:
        dashboard_html = dashboard_file.read()

    badge_pairs = parse_badge_pairs(dashboard_html)
    badge_map = {label: value for label, value in badge_pairs}

    current_price = (
        badge_map.get('current price')
        or first_match([r'data-symbol="[^"]+">([^<]+)</div>'], dashboard_html)
        or "N/A"
    )

    target_label = ""
    target_value = ""
    for label, value in badge_pairs:
        if 'target' in label:
            target_label = label
            target_value = value
            break
    if not target_value:
        target_value = "N/A"
        target_label = "target"

    expected_move = badge_map.get('expected move') or infer_move(current_price, target_value) or "N/A"

    update_date = first_match(
        [
            r'Data as of\s*([^<|]+)',
            r'Last updated:\s*([^<]+)',
        ],
        dashboard_html,
        default="Unknown",
    )

    thesis_text = first_match(
        [
            r'<div class="thesis-box"[^>]*>\s*(?:<div[^>]*>.*?</div>\s*)?<p[^>]*>(.*?)</p>',
            r'<div class="analysis-prose"[^>]*>.*?<p[^>]*>(.*?)</p>',
            r'<div class="analysis-prose"[^>]*>.*?<li[^>]*>(.*?)</li>',
        ],
        dashboard_html,
        default=card['desc'],
    )

    thesis_text = re.sub(r'\s*<span class="source-badge[^"]*"[^>]*>.*?</span>', '', thesis_text, flags=re.S)
    thesis_text = strip_tags(thesis_text)
    thesis_text = re.sub(r'^\s*(Investment Thesis|Summary|Quick Rating(?: \(Swing\))?|Quick Rating(?: \(Position\))?|Value Strategy Validation|Execution vs\. Aspiration|Capital-light inflection)\s*:\s*', '', thesis_text, flags=re.I)
    if len(thesis_text) > 220:
        thesis_text = thesis_text[:217].rsplit(' ', 1)[0] + '...'

    symbol = card['ticker'].replace('$', '')
    rating = card['rating']
    badge_class = normalize_badge_class(rating)
    move_value_class = move_class(expected_move)
    target_subvalue = {
        'position target': 'Position target',
        'expected move target': 'Target',
        '12m target': '12M target',
        'target': 'Target',
    }.get(target_label, target_label.title() if target_label else 'Target')
    if target_subvalue == 'Target':
        target_subvalue = 'Base target'

    rows_html += f"""
      <a class="row" href="{escape_attr(card['file'])}" data-symbol="{escape_attr(symbol)}">
        <div class="ticker-block">
          <div class="ticker-line">
            <span class="ticker mono">{escape_html_text(card['ticker'])}</span>
            <span class="company">{escape_html_text(card['company'])}</span>
          </div>
          <div class="meta">Last updated: {escape_html_text(update_date)}</div>
        </div>
        <div><span class="pill {badge_class}">{escape_html_text(rating.title() if rating.isupper() else rating)}</span></div>
        <div class="metric-group">
          <div>
            <div class="value price-value" data-symbol="{escape_attr(symbol)}">{escape_html_text(current_price)}</div>
            <div class="subvalue live">Current via Yahoo</div>
          </div>
        </div>
        <div>
          <div class="value {move_class(infer_move(current_price, target_value) or expected_move)}">{escape_html_text(target_value)}</div>
          <div class="subvalue">{escape_html_text(target_subvalue)}</div>
        </div>
        <div>
          <div class="value {move_value_class}">{escape_html_text(expected_move)}</div>
          <div class="subvalue">Auto-generated</div>
        </div>
        <div class="thesis">{escape_html_text(thesis_text)}</div>
      </a>
"""

# Read index.html and replace the full dashboard list block
with open('index.html', 'r') as f:
    content = f.read()

list_block = f"""    <div class="list">
      <div class="list-head">
        <div>Name</div>
        <div>Rating</div>
        <div>Price</div>
        <div>Target</div>
        <div>Move</div>
        <div>Why It Exists</div>
      </div>{rows_html}
    </div>"""

pattern = re.compile(r'<div class="list">.*?</div>\s*</section>', re.S)
match = pattern.search(content)
if not match:
    print("  Error: Could not find dashboard list in index.html")
    exit(1)

new_content = pattern.sub(
    lambda m: f"{list_block}\n  </section>",
    content,
    count=1,
)

with open('index.html', 'w') as f:
    f.write(new_content)

print(f"  index.html updated — now contains {len(cards_data)} dashboard row(s).")

# Clean up
if os.path.exists('/tmp/equity_cards.txt'):
    os.remove('/tmp/equity_cards.txt')
PYEOF
echo ""

# -- Git add, commit, and push --------------------------------
echo -e "${YELLOW}Committing and pushing to GitHub...${NC}"
git add -A

# Build a useful commit message
COMMIT_MSG="Sync dashboard index"
if [ -n "$NEW_FILES" ] && [ -z "$REMOVED_FILES" ]; then
    NEW_TICKERS=""
    for file in $NEW_FILES; do
        T=$(grep -o '<title>[^<]*</title>' "$file" | head -1 | sed 's/<[^>]*>//g' | sed -n 's/^\(\$[A-Z]*\).*/\1/p')
        NEW_TICKERS="$NEW_TICKERS $T"
    done
    NEW_TICKERS=$(echo "$NEW_TICKERS" | xargs)
    COMMIT_MSG="Add dashboard(s): ${NEW_TICKERS}"
elif [ -z "$NEW_FILES" ] && [ -n "$REMOVED_FILES" ]; then
    COMMIT_MSG="Remove deleted dashboard(s) from index"
fi
git commit -m "$COMMIT_MSG"
git push origin main

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Deploy complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  Your site will update in ~30 seconds at:"
echo -e "  ${CYAN}https://codeisawesome.github.io/equity-research/${NC}"
echo ""
