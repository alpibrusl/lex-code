# code.lexlang.org

The lex-code landing page — static, no build step. `.github/workflows/pages.yml`
deploys this directory as-is via GitHub Pages on every push to `main` that
touches `site/`.

## One-time: point the domain

Until DNS is pointed, the site is live at `https://alpibrusl.github.io/lex-code/`
(the page's absolute canonical URL assumes the custom domain, so use that URL
for the real check once DNS is live).

1. In **Settings → Pages** (already enabled, source = GitHub Actions), confirm
   the custom domain shows `code.lexlang.org` (set by `site/CNAME`).
2. At the registrar, add a `CNAME` record: `code` → `alpibrusl.github.io`.
3. GitHub provisions TLS automatically once DNS resolves; then tick **Enforce
   HTTPS** in Settings → Pages.

Same pattern as `lexlang.org` itself — see
[lex-www's DEPLOYMENT.md](https://github.com/alpibrusl/lex-www/blob/main/DEPLOYMENT.md).
