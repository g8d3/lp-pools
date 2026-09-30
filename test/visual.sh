#!/bin/bash
# visual gate: drive the real page in a real browser, assert DOM + zero JS errors.
set -e
B=http://127.0.0.1:$(python3 -c "import json;print(json.load(open('needs.json'))['port'])")
echo "== visual $B"
agent-browser open $B >/dev/null 2>&1; sleep 3
fail=0
chk() { # chk <label> <eval-js> <expected-substring>
  got=$(agent-browser eval "$2" 2>&1 | tail -n 1)
  if [[ "$got" == *"$3"* ]]; then echo "ok: $1 ($got)"; else echo "FAIL: $1 (got $got, want *$3*)"; fail=1; fi
}
chk "table has rows" "document.querySelectorAll('#tb tr.trow').length+' rows'" "rows"
chk "header/body cols match" "document.querySelectorAll('#tb tr.trow')[0].children.length+'/'+document.querySelectorAll('thead tr:first-child th').length" "11/11"
chk "no js errors" "window.__errs.length+' errors'" "0 errors"
agent-browser eval "document.getElementById('f-q').value='HOOD';document.getElementById('f-q').dispatchEvent(new Event('input'));" >/dev/null 2>&1; sleep 6
chk "live rows chains in filter" "var r=[...document.querySelectorAll('#tb tr.trow td:nth-child(3)')].map(function(t){return t.textContent});var o=[...document.querySelectorAll('#ms-chain-o input')].map(function(i){return i.value});var m=r.filter(function(x){return o.indexOf(x)<0});m.length+' missing'+(m[0]||'')" "0 missing"
agent-browser eval "document.querySelector('th[data-k=tvl]').click()" >/dev/null 2>&1; sleep 2
chk "sort toggles" "document.querySelector('th[data-k=tvl]').textContent" "▲"
agent-browser eval "document.querySelector('#tb [data-dep]').click()" >/dev/null 2>&1; sleep 2
chk "deposit opens" "document.querySelectorAll('.xrow').length+' panels'" "1 panels"
agent-browser eval "document.getElementById('zgo').click()" >/dev/null 2>&1; sleep 2
chk "quote renders" "document.getElementById('zout').textContent.slice(0,6)" "Put in"
chk "no js errors after flow" "window.__errs.length+' errors: '+window.__errs.join(';')" "0 errors"
exit $fail
