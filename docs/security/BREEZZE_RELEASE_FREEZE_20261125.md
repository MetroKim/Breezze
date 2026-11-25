# BREEZZE — SOURCE SECURITY AND NO-RELEASE POLICY

**Effective immediately. This is an active development project, not a finished app.**

**No release, production deployment, store publishing, source archive upload, GitHub Release, installer or public build artifact is authorized until the full app has passed its defined acceptance gates and the owner explicitly lifts this freeze.**

## Verified exposure at discovery

The canonical GitHub repository `MetroKim/Breezze` reported `visibility: public`. The GitHub Releases API reported two **published, immutable** source-history releases containing 55,052,458-byte and 55,227,021-byte Git bundle assets, plus a metadata ZIP. The GitHub API reported one download per asset at the time of the audit. A download counter is not proof of who received the files. Public commit history may have been cloned already, and removing a release cannot retract external copies.

## Remediation

1. **Owner priority:** switch the canonical repository to **private** under GitHub Settings > General > Danger Zone; verify outside authenticated accounts cannot access the repository.
2. Delete both published releases and their related tags using the GitHub Releases controls. Releases marked **immutable** may first need the repository-level release immutability feature disabled in Settings. The `release-freeze-cleanup.yml` workflow attempts cleanup using a GitHub Actions `contents:write` token and **fails loudly** if not possible.
3. The one-time workflow that previously uploaded complete history bundles is deleted from the live main branch. Never recreate it.
4. Keep application secrets in Railway/Supabase/Cloudflare secret stores; never in source, artifacts or public logs. Review GitHub Actions artifacts, fork permissions, releases, and shared design attachments for inadvertent disclosure. If secrets were ever included in the old public history, rotate them and inspect access logs.
5. Keep PRs, design and unit tests, static builds and emulator acceptance as development verification only. No production redeploy, store release or app installer distribution from these checks.
6. Before lifting the freeze, require all milestones done, P0/P1 native Android/iOS acceptance, accessibility/visual review, Google OAuth and Apple verification, production rights/licensing and offline territory grants, documented release security review, and explicit owner approval.

**The code change that installs this policy does NOT by itself make the repository private or guarantee that immutable releases can be removed. Verify the actual GitHub visibility and release listing after it runs.**
