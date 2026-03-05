# Equity Research Hub — Setup & Deploy Guide

## What This Does

You have a script called `deploy.sh` that automates updating your website. Your workflow is:

1. Drop a new equity research `.html` file into the `equity-research` folder on your Mac
2. Open Terminal and run two commands
3. Your site updates automatically — new dashboard appears on the landing page

---

## One-Time Setup (do this once)

### Step 1: Open Terminal

Press **Cmd + Space**, type **Terminal**, and hit Enter.

### Step 2: Check that Git is installed

Paste this and hit Enter:

```
git --version
```

If you see a version number (like `git version 2.x.x`), you're good. If macOS asks you to install developer tools, click **Install** and wait for it to finish.

### Step 3: Clone your repository

This downloads your GitHub repo to your Mac. Paste this into Terminal:

```
cd ~
git clone https://github.com/codeisawesome/equity-research.git
```

You'll now have a folder at `~/equity-research` containing your site files.

### Step 4: Make the deploy script runnable

```
chmod +x ~/equity-research/deploy.sh
```

### Step 5: Set up Git authentication

GitHub needs to know it's you when pushing changes. The easiest way:

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Give it a name like "equity-research"
4. Check the **repo** scope
5. Click **Generate token** and **copy the token**

Next time Git asks for your password, use this token instead. macOS will save it for you after the first time.

---

## Adding a New Dashboard

### Step 1: Drop the file in

Using Finder, copy your new `.html` dashboard file into:

```
~/equity-research/
```

That's the `equity-research` folder in your home directory.

### Step 2: Deploy

Open Terminal and run:

```
cd ~/equity-research
./deploy.sh
```

The script will:
- Detect the new HTML file(s)
- Parse the ticker, company name, and rating from each file
- Add a card to the landing page
- Push everything to GitHub

You'll see output like this:

```
========================================
  Equity Research Hub — Deploy Script
========================================

Pulling latest changes from GitHub...
Found 2 existing dashboard(s).
Detected 1 new file(s):
  → aapl.html

Parsing: aapl.html
  Ticker:  $AAPL
  Company: Apple Inc.
  Rating:  BUY
  ✓ Card generated.

Updating index.html...
Committing and pushing to GitHub...

========================================
  Deploy complete!
========================================

  Your site will update in ~30 seconds at:
  https://codeisawesome.github.io/equity-research/
```

### Step 3: Check your site

Visit https://codeisawesome.github.io/equity-research/ — your new dashboard should appear within a minute.

---

## Updating an Existing Dashboard

If you've updated one of your HTML files (e.g., refreshed the data for `$FLY`):

1. Replace the file in `~/equity-research/` with the updated version
2. Run `./deploy.sh` — it will detect the change and push it

---

## Troubleshooting

**"This folder is not a git repository"**
Make sure you're in the right folder. Run `cd ~/equity-research` first.

**"Could not parse ticker"**
The script reads the `<title>` tag of your HTML file. Make sure it follows this format:
```
<title>$TICKER — Company Name | Equity Research Dashboard</title>
```

**Authentication errors**
Your GitHub token may have expired. Generate a new one at https://github.com/settings/tokens and try again.

**"Everything is up to date"**
No new or changed files were found. Make sure you copied the HTML file into `~/equity-research/` (not a subfolder).
