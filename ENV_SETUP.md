# Environment Variables Setup Guide

## Overview

The Zen Route Pricing Engine uses **environment variables** instead of Rails encrypted credentials for better deployment flexibility and security.

---

## Setup Instructions

### 1. Local Development

```bash
# Copy the example file
cp .env.example .env

# Edit with your actual values
nano .env
```

**Required variables:**
- `GOOGLE_MAPS_API_KEY` - Your Google Maps API key
- `DATABASE_URL` - Connection to shared CockroachDB
- `REDIS_URL` - Redis connection for caching
- `SECRET_KEY_BASE` - Generate with `rails secret`

### 2. Production Deployment

**DO NOT commit `.env` to Git!**

On your production server:

```bash
# Create .env file
nano .env

# Paste production values
GOOGLE_MAPS_API_KEY=prod_key_here
DATABASE_URL=postgresql://user:pass@prod-db:26257/swapzen_production
REDIS_URL=redis://prod-redis:6379/0
SECRET_KEY_BASE=long_random_string_here
ROUTE_PROVIDER_STRATEGY=google
RAILS_ENV=production
PORT=3001
```

**Secure the file:**
```bash
chmod 600 .env
chown app_user:app_user .env
```

### 3. Docker/Kamal Deployment

Add to `.kamal/secrets`:
```bash
GOOGLE_MAPS_API_KEY=xxx
DATABASE_URL=xxx
REDIS_URL=xxx
SECRET_KEY_BASE=xxx
```

---

## Required Environment Variables

### Critical (Must Set)

| Variable | Description | Example |
|----------|-------------|---------|
| `GOOGLE_MAPS_API_KEY` | Google Maps Distance Matrix API key | `AIzaSyC...` |
| `DATABASE_URL` | CockroachDB connection string | `postgresql://root@localhost:26257/swapzen_development` |
| `SECRET_KEY_BASE` | Rails session encryption key | `rails secret` |

### Important (Recommended)

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | (none) | Redis for route caching - **highly recommended** |
| `ROUTE_PROVIDER_STRATEGY` | `google` | Route provider: `google`, `local`, `haversine` |
| `RAILS_ENV` | `development` | Environment: `development`, `production`, `test` |
| `PORT` | `3000` | Server port (suggest `3001` for pricing engine) |

### Optional

| Variable | Description |
|----------|-------------|
| `RAILS_LOG_LEVEL` | Log verbosity: `debug`, `info`, `warn`, `error` |
| `RAILS_MAX_THREADS` | Puma thread count (affects DB pool) |
| `SENTRY_DSN` | Error tracking |
| `NEW_RELIC_LICENSE_KEY` | Performance monitoring |

---

## Generating Secrets

### SECRET_KEY_BASE
```bash
rails secret
```

### GOOGLE_MAPS_API_KEY
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Enable "Distance Matrix API"
3. Create credentials → API Key
4. Restrict to your server IPs

---

## Verification

Test your configuration:

```bash
# Check variables are loaded
rails runner 'puts ENV["GOOGLE_MAPS_API_KEY"].present? ? "✅ API key loaded" : "❌ Missing API key"'

# Test database connection
rails runner 'puts PricingConfig.count; puts "✅ Database connected"'

# Test Redis connection
rails runner 'Rails.cache.write("test", "ok"); puts Rails.cache.read("test") == "ok" ? "✅ Redis working" : "❌ Redis failed"'

# Run full test
rails runner test_pricing.rb
```

---

## Security Best Practices

1. **Never commit `.env`** - Already in `.gitignore` ✅
2. **Use different keys per environment** - Dev, staging, prod should have separate keys
3. **Rotate secrets regularly** - Especially `SECRET_KEY_BASE` and API keys
4. **Restrict API key** - Limit Google Maps key to production IPs only
5. **Use secret managers** - For production, consider AWS Secrets Manager or similar

---

## Troubleshooting

### "Config not found" error
```bash
# Check DATABASE_URL is set
echo $DATABASE_URL

# Run seeds
rails db:seed
```

### "Google Maps API" error
```bash
# Verify API key
echo $GOOGLE_MAPS_API_KEY

# Test with fallback
ROUTE_PROVIDER_STRATEGY=local rails runner test_pricing.rb
```

### Redis connection error
```bash
# Check Redis is running
redis-cli ping  # Should return "PONG"

# Or use memory store temporarily
unset REDIS_URL
```

---

## Migration from Rails Credentials

We moved from `config/credentials.yml.enc` to `.env` files for:
- ✅ Easier deployment (no master.key distribution)
- ✅ Better Docker/Kamal integration  
- ✅ Industry-standard approach
- ✅ No risk of committing secrets to Git

Old master.key is no longer needed.
