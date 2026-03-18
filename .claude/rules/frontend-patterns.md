---
paths:
  - "**/*.js"
  - "**/*.ts"
  - "app/javascript/"
  - "package.json"
---

# Frontend conventions
- Stimulus + Turbo (Hotwire) preferred over SPAs
- JS lives in app/javascript/, keep it thin
- No npm package without a conversation first

# Zero cost during Rails-only sessions.
# Never loads when you're in .rb files.
# That's the whole point.