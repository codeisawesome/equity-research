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
ALL_HTML=$(ls *.html 2>/dev/null | grep -v '^index\.html$' || true)

if [ -z "$ALL_HTML" ]; then
    echo -e "${YELLOW}No dashboard HTML files found. Nothing to do.${NC}"
    exit 0
fi

# -- Detect which files are already linked in index.html ------
NEW_FILES=""
EXISTING_COUNT=0

for file in $ALL_HTML; do
    if grep -q "href=\"${file}\"" index.html 2>/dev/null; then
        EXISTING_COUNT=$((EXISTING_COUNT + 1))
    else
        NEW_FILES="$NEW_FILES $file"
    fi
done

NEW_FILES=$(echo "$NEW_FILES" | xargs)  # trim whitespace

if [ -z "$NEW_FILES" ]; then
    echo -e "${GREEN}All $EXISTING_COUNT dashboard(s) already on the landing page.${NC}"
    echo ""
    # Still check for any uncommitted changes to push
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

echo -e "${GREEN}Found ${EXISTING_COUNT} existing dashboard(s).${NC}"
echo -e "${YELLOW}Detected $(echo "$NEW_FILES" | wc -w | xargs) new file(s):${NC}"
for file in $NEW_FILES; do
    echo "  → $file"
done
echo ""

# ============================================================
#  PARSE each new HTML file and generate a card
# ============================================================

# Clean up any previous temp file
rm -f /tmp/equity_new_cards.txt

for file in $NEW_FILES; do
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
    if echo "$RATING_LOWER" | grep -q "buy"; then
        BADGE_CLASS="speculative-buy"
    elif echo "$RATING_LOWER" | grep -q "sell\|avoid"; then
        BADGE_CLASS="sell"
    elif echo "$RATING_LOWER" | grep -q "hold"; then
        BADGE_CLASS="hold"
    fi

    # -- Build a short description ----------------------------
    DESC="Equity research dashboard with financial analysis, valuation modeling, and risk assessment for ${COMPANY}."

    # -- Generate card HTML (store ticker/company/etc for Python) --
    # Append parsed data to a temp file for Python to process
    echo "${file}|||${TICKER}|||${COMPANY}|||${DESC}|||${BADGE_CLASS}|||${RATING}" >> /tmp/equity_new_cards.txt
    echo -e "${GREEN}  ✓ Card generated.${NC}"
    echo ""
done

# -- Insert new cards into index.html -------------------------
if [ -f /tmp/equity_new_cards.txt ]; then
    echo -e "${YELLOW}Updating index.html...${NC}"

    python3 << 'PYEOF'
import os

# Read the card data
cards_data = []
with open('/tmp/equity_new_cards.txt', 'r') as f:
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

if not cards_data:
    print("  No card data found.")
    exit(0)

# Build HTML for new cards
new_cards_html = ""
for card in cards_data:
    new_cards_html += f"""
  <a href="{card['file']}" class="report-card">
    <span class="card-arrow">&rarr;</span>
    <div class="card-ticker mono">{card['ticker']}</div>
    <div class="card-company">{card['company']}</div>
    <div class="card-desc">{card['desc']}</div>
    <span class="card-badge {card['badge_class']}">{card['rating']}</span>
  </a>
"""

# Read index.html and insert before the closing </div> of reports-grid
with open('index.html', 'r') as f:
    content = f.read()

insert_point = content.rfind('</a>')
if insert_point == -1:
    print("  Error: Could not find insertion point in index.html")
    exit(1)

insert_after = content.index('\n', insert_point) + 1
new_content = content[:insert_after] + new_cards_html + content[insert_after:]

with open('index.html', 'w') as f:
    f.write(new_content)

print(f"  index.html updated — added {len(cards_data)} new card(s).")

# Clean up
os.remove('/tmp/equity_new_cards.txt')
PYEOF

    echo ""
fi

# -- Git add, commit, and push --------------------------------
echo -e "${YELLOW}Committing and pushing to GitHub...${NC}"
git add -A

# Build a useful commit message
NEW_TICKERS=""
for file in $NEW_FILES; do
    T=$(grep -o '<title>[^<]*</title>' "$file" | head -1 | sed 's/<[^>]*>//g' | sed -n 's/^\(\$[A-Z]*\).*/\1/p')
    NEW_TICKERS="$NEW_TICKERS $T"
done
NEW_TICKERS=$(echo "$NEW_TICKERS" | xargs)

COMMIT_MSG="Add dashboard(s): ${NEW_TICKERS}"
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
