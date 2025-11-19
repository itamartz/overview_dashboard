# How to Work with GitHub

This guide explains how to use GitHub with the Overview Dashboard project.

## 📦 Current Repository

**Repository:** https://github.com/itamartz/overview_dashboard

The repository contains:
- Unified OverviewDashboard application (.NET 9.0)
- Docker deployment configuration
- GitHub Actions workflow for automated deployment
- Complete documentation

---

## 🚀 Cloning the Repository

### First Time Setup

```powershell
# Clone the repository
git clone https://github.com/itamartz/overview_dashboard.git
cd overview_dashboard

# Run the application
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

---

## 📤 Pushing Changes

### Standard Workflow

```powershell
# Check status
git status

# Add changes
git add .

# Commit with message
git commit -m "Your descriptive message"

# Push to GitHub
git push origin main
```

### Automated Deployment

When you push to the `main` branch, GitHub Actions automatically:
1. Builds a Docker image
2. Deploys to your GCP instance (if configured)
3. Restarts the container with new code

---

## 🔑 Authentication

### Using Personal Access Token

When Git prompts for credentials:
- **Username:** `itamartz`
- **Password:** Your Personal Access Token (starts with `ghp_`)

### Creating a New Token

1. Go to: https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Select scopes:
   - ✅ `repo` (full control of private repositories)
   - ✅ `workflow` (update GitHub Actions workflows)
4. Click "Generate token"
5. **Save the token** - you won't see it again!

---

## 🌿 Branching Strategy

### Create a Feature Branch

```powershell
# Create and switch to new branch
git checkout -b feature/your-feature-name

# Make changes, then commit
git add .
git commit -m "Add new feature"

# Push branch to GitHub
git push origin feature/your-feature-name
```

### Merge to Main

```powershell
# Switch to main
git checkout main

# Pull latest changes
git pull origin main

# Merge your feature
git merge feature/your-feature-name

# Push to main (triggers deployment)
git push origin main
```

---

## 🐳 Docker Deployment via GitHub Actions

### Setup (One-Time)

Configure GitHub Secrets in your repository:

1. Go to: https://github.com/itamartz/overview_dashboard/settings/secrets/actions
2. Add these secrets:
   - `GCP_HOST` - Your server IP address
   - `GCP_USERNAME` - SSH username
   - `GCP_SSH_KEY` - Your private SSH key

### Trigger Deployment

```powershell
# Any push to main triggers deployment
git push origin main
```

### Monitor Deployment

1. Go to: https://github.com/itamartz/overview_dashboard/actions
2. Click on the latest workflow run
3. Watch the progress of each step

---

## 🔧 Common Git Tasks

### View Commit History

```powershell
git log --oneline --graph --all
```

### Undo Last Commit (Keep Changes)

```powershell
git reset --soft HEAD~1
```

### Discard Local Changes

```powershell
# Discard changes in specific file
git checkout -- filename

# Discard all changes
git reset --hard HEAD
```

### Pull Latest Changes

```powershell
git pull origin main
```

### View Differences

```powershell
# See what changed
git diff

# See staged changes
git diff --staged
```

---

## 🆘 Troubleshooting

### "Permission denied"

**Problem:** Authentication failed

**Solution:**
```powershell
# Make sure you're using token, not password
# Username: itamartz
# Password: ghp_your_token_here
```

### "Rejected - fetch first"

**Problem:** Remote has changes you don't have locally

**Solution:**
```powershell
# Pull and merge
git pull origin main

# Or pull with rebase
git pull --rebase origin main

# Then push
git push origin main
```

### "Large files rejected"

**Problem:** File too large for GitHub (>100MB)

**Solution:**
```powershell
# Add to .gitignore
echo "large-file.bin" >> .gitignore
git add .gitignore
git commit -m "Ignore large files"
```

### "Merge conflicts"

**Problem:** Same file changed in different ways

**Solution:**
```powershell
# Edit conflicted files manually
# Look for <<<<<<< HEAD markers
# Choose which changes to keep

# After resolving
git add .
git commit -m "Resolve merge conflicts"
```

---

## 📋 .gitignore

The repository includes a `.gitignore` file that excludes:
- `bin/` and `obj/` directories
- `*.db` database files
- `*.user` files
- IDE-specific files

### Add More Exclusions

```powershell
# Edit .gitignore
echo "my-secret-file.txt" >> .gitignore
git add .gitignore
git commit -m "Update gitignore"
```

---

## 🎯 Best Practices

### Commit Messages

Use clear, descriptive messages:

```powershell
# Good
git commit -m "Add Docker deployment workflow"
git commit -m "Fix database path for Windows Service"
git commit -m "Update README with deployment instructions"

# Bad
git commit -m "fix"
git commit -m "changes"
git commit -m "update"
```

### Commit Frequency

- Commit often with small, logical changes
- Each commit should represent one complete change
- Don't commit broken code to main branch

### Before Pushing

```powershell
# Always check what you're pushing
git status
git diff

# Test locally
dotnet build
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

---

## 🔄 Syncing with GitHub

### Daily Workflow

```powershell
# Start of day - get latest
git pull origin main

# Work on changes
# ... make changes ...

# End of day - push changes
git add .
git commit -m "Describe your changes"
git push origin main
```

---

## 📞 Getting Help

### Useful Commands

```powershell
# See remote URL
git remote -v

# See current branch
git branch

# See what will be pushed
git log origin/main..main

# See file changes
git status
```

### Resources

- Git Documentation: https://git-scm.com/doc
- GitHub Guides: https://guides.github.com
- Git Cheat Sheet: https://education.github.com/git-cheat-sheet-education.pdf

---

## 🎉 You're All Set!

Now you can:
- ✅ Clone the repository
- ✅ Make changes locally
- ✅ Push to GitHub
- ✅ Trigger automated deployments
- ✅ Collaborate with team members

**Your code is version-controlled and automatically deployed!** 🚀

---

**Repository:** https://github.com/itamartz/overview_dashboard
