# Docker Deployment to GCP Guide

This guide explains how to deploy the Overview Dashboard to a GCP instance using GitHub Actions and Docker.

## Prerequisites

- GCP instance with Docker installed
- SSH access to the GCP instance
- GitHub repository with the code

## Setup Steps

### 1. Create a Branch for Docker Changes

```bash
git checkout -b feature/docker-deployment
git add Dockerfile .dockerignore .github/
git commit -m "Add Docker deployment configuration"
git push origin feature/docker-deployment
```

### 2. Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

Add the following secrets:

#### `GCP_HOST`
- **Value**: Your GCP instance IP address or hostname
- **Example**: `34.123.45.67` or `my-instance.us-central1-a.c.my-project.internal`

#### `GCP_USERNAME`
- **Value**: SSH username for your GCP instance
- **Example**: `your-username` or `ubuntu` or `admin`

#### `GCP_SSH_KEY`
- **Value**: Your private SSH key for accessing the GCP instance
- **How to get it**:
  ```bash
  # On your local machine, display your private key
  cat ~/.ssh/id_rsa
  # Or if you use a different key
  cat ~/.ssh/your-gcp-key
  ```
- **Important**: Copy the ENTIRE key including:
  ```
  -----BEGIN OPENSSH PRIVATE KEY-----
  [key content]
  -----END OPENSSH PRIVATE KEY-----
  ```

### 3. Prepare Your GCP Instance

SSH into your GCP instance and run:

```bash
# Create directory for persistent data
sudo mkdir -p /var/overview-dashboard/data

# Set appropriate permissions
sudo chown -R $USER:$USER /var/overview-dashboard

# Verify Docker is installed
docker --version

# If Docker is not installed, install it:
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

### 4. Configure Firewall Rules (if needed)

Allow HTTP/HTTPS traffic to your GCP instance:

```bash
# Using gcloud CLI
gcloud compute firewall-rules create allow-http --allow tcp:80 --source-ranges 0.0.0.0/0
gcloud compute firewall-rules create allow-https --allow tcp:443 --source-ranges 0.0.0.0/0

# Or configure in GCP Console:
# VPC Network → Firewall → Create Firewall Rule
```

### 5. Test Locally (Optional)

Before pushing to GitHub, test the Docker build locally:

```bash
# Build the image
docker build -t overview-dashboard:test .

# Run the container
docker run -d \
  --name overview-dashboard-test \
  -p 8080:8080 \
  -v $(pwd)/Database:/app/Database \
  overview-dashboard:test

# Check logs
docker logs overview-dashboard-test

# Test the application
curl http://localhost:8080

# Clean up
docker stop overview-dashboard-test
docker rm overview-dashboard-test
```

### 6. Trigger Deployment

#### Option A: Push to Main Branch
```bash
git checkout main
git merge feature/docker-deployment
git push origin main
```

#### Option B: Manual Trigger
1. Go to GitHub → Actions → "Build and Deploy to GCP"
2. Click "Run workflow"
3. Select the branch
4. Click "Run workflow"

### 7. Monitor Deployment

1. Go to GitHub → Actions
2. Click on the running workflow
3. Watch the progress of each step
4. Check for any errors

## Workflow Explanation

The GitHub Actions workflow does the following:

1. **Checkout code**: Gets the latest code from the repository
2. **Build Docker image**: Creates a Docker image with your application
3. **Save image**: Exports the image to a tar file
4. **Copy to GCP**: Transfers the image to your GCP instance via SCP
5. **Deploy**: 
   - Loads the image on the GCP instance
   - Stops the old container
   - Starts a new container with the updated image
   - Cleans up old images
6. **Verify**: Checks container logs to ensure successful deployment

## Container Configuration

The deployed container:
- **Name**: `overview-dashboard`
- **Ports**: 
  - 80 → 8080 (HTTP)
  - 443 → 8081 (HTTPS)
- **Restart policy**: `unless-stopped` (auto-restart on failure)
- **Volume**: `/var/overview-dashboard/data` → `/app/Database` (persistent data)

## Accessing Your Application

After successful deployment, access your application at:
- `http://[YOUR_GCP_IP]`
- `https://[YOUR_GCP_IP]` (if HTTPS is configured)

## Troubleshooting

### Check container status
```bash
ssh [GCP_USERNAME]@[GCP_HOST]
docker ps -a | grep overview-dashboard
```

### View container logs
```bash
docker logs overview-dashboard
docker logs --tail 100 -f overview-dashboard  # Follow logs
```

### Restart container
```bash
docker restart overview-dashboard
```

### Manual deployment
```bash
# If GitHub Actions fails, you can deploy manually:
docker pull [your-image] # or build locally
docker stop overview-dashboard
docker rm overview-dashboard
docker run -d --name overview-dashboard --restart unless-stopped -p 80:8080 -v /var/overview-dashboard/data:/app/Database overview-dashboard:latest
```

### SSH connection issues
- Verify your SSH key is correct
- Ensure the GCP instance allows SSH (port 22)
- Check that the username is correct

### Docker permission issues
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

## Customization

### Change deployment branch
Edit `.github/workflows/deploy-to-gcp.yml`:
```yaml
on:
  push:
    branches:
      - main  # Change to your preferred branch
```

### Change ports
Edit the workflow file, modify the `docker run` command:
```bash
-p 8080:8080 \  # Change host port (left side)
```

### Add environment variables
```bash
docker run -d \
  --name overview-dashboard \
  -e ASPNETCORE_ENVIRONMENT=Production \
  -e ConnectionStrings__DefaultConnection="your-connection-string" \
  ...
```

### Use Docker Compose (Alternative)
Create `docker-compose.yml` for more complex setups with multiple services.

## Security Best Practices

1. **Use HTTPS**: Configure SSL/TLS certificates (Let's Encrypt)
2. **Restrict SSH**: Use firewall rules to limit SSH access
3. **Rotate secrets**: Regularly update SSH keys and credentials
4. **Use private registry**: For production, consider using GCP Container Registry
5. **Scan images**: Enable vulnerability scanning

## Next Steps

- [ ] Set up HTTPS with Let's Encrypt
- [ ] Configure automatic backups for the database
- [ ] Set up monitoring and alerting
- [ ] Implement rolling deployments for zero-downtime
- [ ] Use GCP Container Registry instead of transferring tar files
- [ ] Set up staging environment

## Alternative: Using GCP Container Registry

For a more robust solution, consider using GCP Container Registry:

1. Push images to GCR instead of transferring tar files
2. Pull images directly on the GCP instance
3. Benefits: versioning, security scanning, faster deployments

Let me know if you'd like a guide for this approach!
