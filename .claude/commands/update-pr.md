# Update Pull Request

Update the title and description of the current branch's pull request using GitHub CLI.

## Instructions

1. First, check if there's an open pull request for the current branch using `gh pr list`
2. If a PR exists, update it using `gh pr edit` with:
   - A concise, descriptive title that summarizes the changes
   - A comprehensive description including:
     - Summary of changes (bullet points)
     - Test plan or verification steps
     - Any breaking changes or migration notes if applicable
3. Use the commit history and changed files to understand what was modified
4. Keep the title under 72 characters
5. Format the description using GitHub-flavored markdown

## Example Command

```bash
gh pr edit --title "Fix macOS build configuration and add App Sandbox entitlement" \
  --body "## Summary
- Added LSApplicationCategoryType to macOS Info.plist for App Store compliance
- Enabled App Sandbox entitlement required for Mac App Store distribution
- Fixed visionOS release_match lane to properly reference iOS provisioning profiles
- Converted release workflow to use matrix strategy for parallel platform builds

## Changes
- Updated Project.swift to include required Info.plist keys for all platforms
- Created macOS entitlements file with minimal sandbox permissions
- Refactored GitHub Actions workflow for more efficient parallel builds
- Fixed bundle ID consistency across all platforms (io.ngs.LiveClock)

## Test Plan
- [x] Verified Tuist project generation succeeds
- [x] Confirmed build number uses GitHub Actions Run ID
- [ ] Test App Store upload validation passes"
```

## Important Notes
- **DO NOT** add any AI/Claude signatures, co-author attributions, or "Updated with Claude" type messages
- **DO NOT** mention that changes were made with assistance from AI/Claude
- Keep the description professional and factual, focusing only on the technical changes
- Always check the PR number or URL first if updating a specific PR
- Do not include emoji unless consistent with the repository's established style