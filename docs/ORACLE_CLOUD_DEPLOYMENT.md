# Oracle Cloud Deployment Guide

This guide walks you through deploying the Service Mesh Benchmark application on Oracle Cloud Infrastructure (OCI).

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Oracle Cloud Infrastructure Setup](#oracle-cloud-infrastructure-setup)
3. [Server Preparation](#server-preparation)
4. [Application Deployment](#application-deployment)
5. [SSL/TLS Configuration (Optional)](#ssltls-configuration-optional)
6. [Monitoring and Maintenance](#monitoring-and-maintenance)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting, ensure you have:

- An Oracle Cloud account with credits or active subscription
- SSH client installed on your local machine
- Git installed on your local machine
- Basic knowledge of Linux command line
- Domain name (optional, for SSL/TLS)

## Oracle Cloud Infrastructure Setup

### 1. Create a Compute Instance

1. **Log in to Oracle Cloud Console**
   - Navigate to https://cloud.oracle.com/
   - Sign in with your credentials

2. **Create a New Compute Instance**
   - Go to **Compute** → **Instances**
   - Click **Create Instance**

3. **Instance Configuration**
   - **Name**: `service-mesh-benchmark`
   - **Compartment**: Select your compartment
   - **Availability Domain**: Choose any available domain

4. **Image and Shape**
   - **Image**: Ubuntu 22.04 Minimal (recommended)
   - **Shape**:
     - **Recommended**: VM.Standard.E4.Flex (4 OCPUs, 16 GB RAM)
     - **Minimum**: VM.Standard.E2.1.Micro (1 OCPU, 1 GB RAM) - Free tier eligible, but limited performance

5. **Networking**
   - **Virtual Cloud Network**: Create new or select existing
   - **Subnet**: Use public subnet
   - **Public IP**: Assign a public IPv4 address

6. **Add SSH Keys**
   - Upload your SSH public key or generate a new key pair
   - Download the private key if generating new

7. **Boot Volume**
   - Size: 50-100 GB (recommended)

8. **Click Create**

### 2. Configure Security List / Network Security Group

After instance creation, configure firewall rules:

1. **Navigate to VCN Details**
   - Go to **Networking** → **Virtual Cloud Networks**
   - Click on your VCN
   - Click on the subnet used by your instance

2. **Add Ingress Rules**
   - Click **Security Lists** → Your security list
   - Click **Add Ingress Rules**

   Add the following rules:

   | Source CIDR | Protocol | Source Port | Destination Port | Description |
   |------------|----------|-------------|------------------|-------------|
   | 0.0.0.0/0  | TCP      | All         | 22               | SSH |
   | 0.0.0.0/0  | TCP      | All         | 80               | HTTP |
   | 0.0.0.0/0  | TCP      | All         | 443              | HTTPS |
   | 0.0.0.0/0  | TCP      | All         | 3000             | Frontend |
   | 0.0.0.0/0  | TCP      | All         | 8000             | API |
   | 0.0.0.0/0  | TCP      | All         | 9090             | Prometheus |
   | 0.0.0.0/0  | TCP      | All         | 3001             | Grafana |

   **Note**: For production, restrict source CIDR to your specific IPs instead of 0.0.0.0/0

3. **Save Changes**

### 3. Note Your Instance Details

After instance is running, note:
- **Public IP Address**: e.g., `123.45.67.89`
- **SSH Connection**: `ssh ubuntu@123.45.67.89 -i /path/to/private-key`

## Server Preparation

### 1. Connect to Your Instance

```bash
# Replace with your actual IP and key path
ssh ubuntu@YOUR_INSTANCE_IP -i /path/to/your-private-key.pem

# If permission denied, set correct permissions
chmod 600 /path/to/your-private-key.pem
```

### 2. Run Server Setup Script

```bash
# Download the repository (or copy setup script)
cd /tmp
git clone <your-repository-url> repo-temp
cd repo-temp

# Run server setup as root
sudo bash scripts/setup-server.sh
```

This script will:
- Update system packages
- Install Docker and Docker Compose
- Install kubectl for Kubernetes
- Configure firewall rules
- Optimize system settings for networking
- Create application directory at `/opt/service-mesh-benchmark`

**Important**: After the script completes, **log out and log back in** for Docker group changes to take effect:

```bash
exit
# Then reconnect
ssh ubuntu@YOUR_INSTANCE_IP -i /path/to/your-private-key.pem
```

### 3. Clone Repository

```bash
# Navigate to application directory
cd /opt/service-mesh-benchmark

# Clone your repository
git clone <your-repository-url> .

# Verify files
ls -la
```

## Application Deployment

### 1. Configure Environment Variables

```bash
# Copy production environment template
cp .env.production.example .env.production

# Edit with your favorite editor
vim .env.production
# or
nano .env.production
```

**Required Configuration**:

```bash
# Database password - use a strong random password
POSTGRES_PASSWORD=your_secure_password_here

# Redis password - use a strong random password
REDIS_PASSWORD=another_secure_password_here

# API CORS origins - use your actual domain or IP
ALLOWED_ORIGINS=http://YOUR_INSTANCE_IP:3000,https://your-domain.com

# Frontend API URL
API_URL=http://YOUR_INSTANCE_IP:8000

# Grafana password
GRAFANA_PASSWORD=yet_another_secure_password

# Security key - IMPORTANT: Generate a secure key
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
```

**Generate Secure Passwords**:

```bash
# Generate random passwords
python3 -c "import secrets; print('POSTGRES_PASSWORD=' + secrets.token_urlsafe(24))"
python3 -c "import secrets; print('REDIS_PASSWORD=' + secrets.token_urlsafe(24))"
python3 -c "import secrets; print('SECRET_KEY=' + secrets.token_urlsafe(32))"
python3 -c "import secrets; print('GRAFANA_PASSWORD=' + secrets.token_urlsafe(16))"
```

### 2. Deploy Application

```bash
# Make deployment script executable
chmod +x scripts/deploy.sh

# Run deployment
./scripts/deploy.sh
```

The deployment script will:
1. Validate environment variables
2. Stop any existing containers
3. Pull base images
4. Build application images
5. Start all services
6. Wait for health checks
7. Display service URLs

### 3. Verify Deployment

After deployment completes, you should see:

```
╔════════════════════════════════════════════════════════════╗
║            Deployment Successful! 🎉                       ║
╔════════════════════════════════════════════════════════════╗

Services are now running at:
  Frontend:    http://localhost:3000
  API:         http://localhost:8000
  API Docs:    http://localhost:8000/docs
  Prometheus:  http://localhost:9090
  Grafana:     http://localhost:3001
```

### 4. Access Your Application

From your local machine, access:

- **Frontend**: `http://YOUR_INSTANCE_IP:3000`
- **API**: `http://YOUR_INSTANCE_IP:8000`
- **API Documentation**: `http://YOUR_INSTANCE_IP:8000/docs`
- **Prometheus**: `http://YOUR_INSTANCE_IP:9090`
- **Grafana**: `http://YOUR_INSTANCE_IP:3001`

**Grafana Login**:
- Username: `admin`
- Password: (from your `.env.production` file)

## SSL/TLS Configuration (Optional)

For production deployments, it's recommended to use SSL/TLS with a domain name.

### Prerequisites

1. Domain name pointing to your Oracle Cloud instance IP
2. Certbot installed on your instance

### Install Certbot

```bash
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx
```

### Option 1: Using Nginx Reverse Proxy

1. **Install Nginx**:

```bash
sudo apt-get install -y nginx
```

2. **Create Nginx Configuration**:

```bash
sudo vim /etc/nginx/sites-available/service-mesh-benchmark
```

Add the following configuration:

```nginx
# Frontend
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# API
server {
    listen 80;
    server_name api.your-domain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Grafana
server {
    listen 80;
    server_name grafana.your-domain.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

3. **Enable Site**:

```bash
sudo ln -s /etc/nginx/sites-available/service-mesh-benchmark /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

4. **Obtain SSL Certificates**:

```bash
sudo certbot --nginx -d your-domain.com -d www.your-domain.com -d api.your-domain.com -d grafana.your-domain.com
```

5. **Update .env.production**:

```bash
# Update ALLOWED_ORIGINS
ALLOWED_ORIGINS=https://your-domain.com,https://www.your-domain.com

# Update URLs
API_URL=https://api.your-domain.com
VITE_API_URL=https://api.your-domain.com
GRAFANA_URL=https://grafana.your-domain.com
```

6. **Redeploy**:

```bash
./scripts/deploy.sh
```

### Auto-renewal

Certbot automatically configures renewal. Test it:

```bash
sudo certbot renew --dry-run
```

## Monitoring and Maintenance

### View Logs

```bash
# All services
docker-compose -f docker-compose.prod.yml logs -f

# Specific service
docker-compose -f docker-compose.prod.yml logs -f api
docker-compose -f docker-compose.prod.yml logs -f frontend

# Last 100 lines
docker-compose -f docker-compose.prod.yml logs --tail=100 api
```

### Check Service Status

```bash
docker-compose -f docker-compose.prod.yml ps
```

### Restart Services

```bash
# Restart all
docker-compose -f docker-compose.prod.yml restart

# Restart specific service
docker-compose -f docker-compose.prod.yml restart api
```

### Stop Services

```bash
docker-compose -f docker-compose.prod.yml down
```

### Update Application

```bash
# Pull latest code
git pull

# Rebuild and redeploy
./scripts/deploy.sh
```

### Database Backup

```bash
# Create backup
docker exec benchmark-postgres pg_dump -U benchmark service_mesh_benchmark > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore from backup
cat backup_file.sql | docker exec -i benchmark-postgres psql -U benchmark service_mesh_benchmark
```

### Monitor Resources

```bash
# Docker stats
docker stats

# System resources
htop

# Disk usage
df -h

# Docker disk usage
docker system df
```

## Troubleshooting

### Services Won't Start

1. **Check logs**:
   ```bash
   docker-compose -f docker-compose.prod.yml logs
   ```

2. **Check disk space**:
   ```bash
   df -h
   ```

3. **Check Docker status**:
   ```bash
   sudo systemctl status docker
   ```

### Cannot Connect to Services

1. **Check Oracle Cloud Security List**:
   - Ensure ingress rules are configured correctly
   - Verify source CIDR is not too restrictive

2. **Check instance firewall**:
   ```bash
   sudo iptables -L -n
   ```

3. **Check service is listening**:
   ```bash
   sudo netstat -tlnp | grep -E '3000|8000|9090|3001'
   ```

### Database Connection Errors

1. **Check PostgreSQL is running**:
   ```bash
   docker logs benchmark-postgres
   ```

2. **Verify password matches** in `.env.production` and docker-compose.prod.yml

3. **Test connection**:
   ```bash
   docker exec -it benchmark-postgres psql -U benchmark -d service_mesh_benchmark
   ```

### Frontend Can't Reach API

1. **Check CORS settings**:
   - Verify `ALLOWED_ORIGINS` in `.env.production`
   - Check API logs for CORS errors

2. **Verify API_URL** in frontend environment:
   ```bash
   docker exec benchmark-frontend env | grep API
   ```

### Out of Memory

1. **Check memory usage**:
   ```bash
   free -h
   docker stats
   ```

2. **Increase instance memory** or reduce concurrent benchmarks

3. **Add swap space**:
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

### SSL Certificate Issues

1. **Check certificate expiry**:
   ```bash
   sudo certbot certificates
   ```

2. **Manually renew**:
   ```bash
   sudo certbot renew
   ```

3. **Check Nginx configuration**:
   ```bash
   sudo nginx -t
   ```

## Performance Optimization

### For Production Workloads

1. **Use a larger instance**: VM.Standard.E4.Flex with 8+ OCPUs
2. **Enable Docker BuildKit**:
   ```bash
   export DOCKER_BUILDKIT=1
   ```
3. **Configure Docker daemon** for production:
   ```json
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "3"
     },
     "storage-driver": "overlay2"
   }
   ```

### Database Optimization

Add to `docker-compose.prod.yml` under postgres service:

```yaml
command:
  - "postgres"
  - "-c"
  - "max_connections=200"
  - "-c"
  - "shared_buffers=256MB"
  - "-c"
  - "effective_cache_size=1GB"
  - "-c"
  - "work_mem=16MB"
```

## Security Best Practices

1. **Use strong passwords** for all services
2. **Restrict Security List** to specific IPs when possible
3. **Enable SSL/TLS** for production
4. **Regular updates**:
   ```bash
   sudo apt-get update && sudo apt-get upgrade -y
   ```
5. **Configure firewall** (UFW):
   ```bash
   sudo ufw enable
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```
6. **Monitor logs** regularly for suspicious activity
7. **Backup data** regularly

## Additional Resources

- [Oracle Cloud Documentation](https://docs.oracle.com/en-us/iaas/Content/home.htm)
- [Docker Documentation](https://docs.docker.com/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [SvelteKit Documentation](https://kit.svelte.dev/)

## Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review application logs
3. Check Oracle Cloud service status
4. Open an issue on the project repository

---

**Last Updated**: 2025-11-01
