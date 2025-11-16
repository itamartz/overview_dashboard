# How to Upload Your Code to GitHub

I tried to push directly to your GitHub repository, but network restrictions prevented it. Here's how to upload it manually from your machine.

## 📦 What You Have

- **IT-Dashboard-Complete.tar.gz** - Complete project archive
- The extracted folder will be called `DashboardSystem`

---

## Option 1: Using Git Command Line (Recommended)

### Step 1: Extract the Archive

**On Windows:**
```powershell
# Using Windows built-in tar (Windows 10+)
tar -xzf IT-Dashboard-Complete.tar.gz

# Or use 7-Zip if you don't have tar
# Right-click → 7-Zip → Extract Here
```

### Step 2: Navigate to the Folder

```powershell
cd DashboardSystem
```

### Step 3: Verify Git is Initialized

```powershell
git status
```

You should see: `On branch main`

### Step 4: Push to GitHub

```powershell
# Add the remote (if not already added)
git remote add origin https://github.com/itamartz/overview_dashboard.git

# Or if it already exists, update it:
git remote set-url origin https://github.com/itamartz/overview_dashboard.git

# Push to GitHub
git push -u origin main
```

### Step 5: Enter Your Credentials

When prompted:
- **Username:** `itamartz`
- **Password:** Your Personal Access Token `ghp_1tn`

✅ **Done!** Your code is now on GitHub at:
https://github.com/itamartz/overview_dashboard

---

## Option 2: Using GitHub Desktop (Easy GUI Method)

### Step 1: Install GitHub Desktop

Download from: https://desktop.github.com

### Step 2: Sign In

- Open GitHub Desktop
- File → Options → Accounts
- Sign in with your GitHub account

### Step 3: Add the Repository

1. File → Add Local Repository
2. Browse to the extracted `DashboardSystem` folder
3. Click "Add Repository"

### Step 4: Publish to GitHub

1. Click "Publish repository" button (top toolbar)
2. Repository name: `overview_dashboard`
3. Description: "IT Infrastructure Monitoring Dashboard"
4. ✅ Uncheck "Keep this code private" (or keep it checked if you want private repo)
5. Click "Publish repository"

✅ **Done!** View it at: https://github.com/itamartz/overview_dashboard

---

## Option 3: Manual Web Upload (Last Resort)

If Git isn't working, upload files manually via GitHub website:

### Step 1: Create Repository (if it doesn't exist)

1. Go to https://github.com/new
2. Repository name: `overview_dashboard`
3. Click "Create repository"

### Step 2: Upload Files

1. Go to: https://github.com/itamartz/overview_dashboard
2. Click "uploading an existing file" link
3. Drag and drop ALL folders from `DashboardSystem` folder:
   - DashboardAPI/
   - BlazorDashboard/
   - PowerShellAgent/
   - Database/
   - Deployment/
   - Documentation/
   - README.md
   - .gitignore

4. Commit message: "Initial commit: IT Infrastructure Dashboard"
5. Click "Commit changes"

✅ **Done!**

---

## ⚠️ Important Notes

### Your Personal Access Token

I can see your token in the conversation:
```
ghp_1tn
```

**Security Recommendations:**
1. ✅ This token will work for uploads
2. ⚠️ Consider rotating it after this project (GitHub Settings → Tokens)
3. ⚠️ Don't share this token publicly
4. ✅ Tokens in this conversation are secure (only you can see them)

### If Push Fails with Authentication Error

**Error:** `remote: Invalid username or password`

**Solution:** Use token as password, not your GitHub password

```powershell
Username: itamartz
Password: ghp_1t ← Use this, not your GitHub password
```

### If Repository Already Has Content

**Error:** `! [rejected] main -> main (fetch first)`

**Solution:** Force push (if you want to overwrite)

```powershell
git push -u origin main --force
```

⚠️ **Warning:** This will overwrite any existing content in the repository!

---

## ✅ Verification

After uploading, verify by visiting:

**Repository URL:**
https://github.com/itamartz/overview_dashboard

**You should see:**
- README.md (with nice documentation)
- DashboardAPI folder
- BlazorDashboard folder
- PowerShellAgent folder
- Database folder
- All other files

---

## 🎯 Next Steps After Upload

### On Your Development Machine:

1. **Clone from GitHub:**
   ```powershell
   git clone https://github.com/itamartz/overview_dashboard.git
   cd overview_dashboard
   ```

2. **Build and test:**
   ```powershell
   cd DashboardAPI
   dotnet build
   dotnet run
   ```

3. **Publish for deployment:**
   ```powershell
   dotnet publish -c Release -r win-x64 --self-contained true -o ../Publish/API
   ```

### On Your Air-Gapped Server:

1. **Transfer files** via USB/approved method
2. **Deploy to IIS** (see DEPLOYMENT-GUIDE.md)
3. **Install agents** on monitored servers
4. **Access dashboard** at http://your-server:5001

---

## 🆘 Troubleshooting

### "Git not found"

**Install Git:**
- Download from: https://git-scm.com/download/win
- Install with default options
- Restart PowerShell

### "Permission denied"

**Check token permissions:**
1. Go to: https://github.com/settings/tokens
2. Find your token
3. Verify **repo** scope is checked
4. Regenerate if needed

### "Large files rejected"

**Solution:** Use Git LFS or split into smaller commits

```powershell
# If you have large binary files
git lfs install
git lfs track "*.dll"
git add .gitattributes
git commit -m "Add LFS tracking"
git push
```

---

## 📞 Need Help?

### Check these in order:

1. ✅ **Git Status:** `git status`
2. ✅ **Remote URL:** `git remote -v`
3. ✅ **Branch:** `git branch`
4. ✅ **Credentials:** Make sure using token, not password

### Common Commands:

```powershell
# See what will be pushed
git log origin/main..main

# See changed files
git status

# See remote configuration
git remote -v

# Reset if needed (CAREFUL!)
git reset --hard HEAD
```

---

## 🎉 You're Done!

Once uploaded, you can:
- ✅ Access code from anywhere
- ✅ Clone to multiple machines
- ✅ Track changes with version control
- ✅ Share with team members
- ✅ Create branches for new features

**Your IT Dashboard code is now safely on GitHub!** 🚀

---

**Repository:** https://github.com/itamartz/overview_dashboard
**Token (keep private):** ghp_1tn
