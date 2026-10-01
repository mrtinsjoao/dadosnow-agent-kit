# Demo app

A ten-line Python module with tests, used to try the kit end to end in a
throwaway repository. No dependencies beyond Python 3.

```bash
# 1. a throwaway repo with a local "remote"
cp -r examples/demo-app /tmp/dn-demo && cd /tmp/dn-demo
git init -q && git add . && git commit -qm "demo app"
git init -q --bare /tmp/dn-demo-remote.git && git remote add origin /tmp/dn-demo-remote.git
git push -q -u origin HEAD

# 2. install the kit
/path/to/dadosnow-agent-kit/install.sh .
git add . && git commit -qm "chore: DadosNow kit"

# 3. tests pass
python3 -m unittest -q

# 4. commit a fake secret and push: the gate blocks it
echo "PAYMENTS_API_SECRET = \"pk$(od -An -N10 -tx1 /dev/urandom | tr -d ' \n')\"" >> pricing.py
git commit -qam "config: add storage key"
git push            # dn-security-reviewer returns VERDICT: BLOCK

# 5. undo it and push again: PASS
git reset -q --hard HEAD~1 && git push
```

The value is random bytes generated on the spot; it is not a key for any service.
