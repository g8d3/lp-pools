#!/bin/bash
# QA GATE — run before every delivery. Fails the delivery if anything is red.
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
echo "### 1. JS syntax"
python3 -c "
import re
h=open('public/index.html').read()
js=re.search(r'<script>(.*)</script>',h,re.S).group(1)
open('/tmp/lpcheck.js','w').write(js)"
node --check /tmp/lpcheck.js && echo "JS OK"
echo "### 2. API smoke"
bash test/check.sh
echo "### 3. visual + zero-error gate"
bash test/visual.sh
echo "### 4. pain digest"
bash bin/report.sh
echo "### GATE GREEN"
