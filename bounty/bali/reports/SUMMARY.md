# Bali Bug Bounty Recon — 2026-11-25

## Hasil
- Subdomain enumerated: 200+
- Live hosts: 48
- Manual verification: 11 target utama

## Verified Findings: 0
Semua target di-harden dengan baik:
- SSO, meilisearch, argocd, stirling-pdf: auth required
- GitLab: public API normal, sensitive files 404
- Firebase jdih-37f32: rules correct, anonymous auth disabled
- LiveKit: token required

## Catatan
- cyberpanel.baliprov.dev: DNS mati setelah scan — JANGAN scan ulang
- ptai + 3B model = noise generator, 439 candidate / 0 verified

## Verdict
Target well-hardened. No qualifying findings for submission.
