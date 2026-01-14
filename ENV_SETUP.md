# Environment Variables Setup

## Quick Start

```bash
# Copy template
cp .env.example .env

# Edit with your values
nano .env
```

---

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GOOGLE_MAPS_API_KEY` | Google Maps Distance Matrix API key | `AIzaSyC...` |
| `DATABASE_URL` | CockroachDB connection (shared with swapzen-api) | `postgresql://root@localhost:26257/swapzen_development` |
| `SECRET_KEY_BASE` | Rails session encryption (generate with `rails secret`) | Run: `rails secret` |

## Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | (none) | Redis for route caching - **recommended for production** |
| `ROUTE_PROVIDER_STRATEGY` | `google` | Route provider: `google`, `local`, or `haversine` |
| `RAILS_ENV` | `development` | Environment: `development`, `production`, `test` |
| `PORT` | `3000` | Server port (suggest `3001` for pricing engine) |
| `RAILS_MAX_THREADS` | `5` | Puma thread count (affects DB pool size) |

---

## Setup by Environment

### Local Development

```bash
cp .env.example .env
```

Edit `.env`:
```bash
GOOGLE_MAPS_API_KEY=your_dev_api_key
DATABASE_URL=postgresql://root@localhost:26257/swapzen_development
REDIS_URL=redis://localhost:6379/0
SECRET_KEY_BASE=$(rails secret)
ROUTE_PROVIDER_STRATEGY=local  # Use Haversine fallback
RAILS_ENV=development
PORT=3001
```

### Production Server

Create `/path/to/app/.env`:
```bash
GOOGLE_MAPS_API_KEY=prod_key_here
DATABASE_URL=postgresql://user:pass@prod-db:26257/swapzen_production?sslmode=require
REDIS_URL=redis://prod-redis:6379/0
SECRET_KEY_BASE=long_random_production_key_here
ROUTE_PROVIDER_STRATEGY=google
RAILS_ENV=production
PORT=3001
```

Secure the file:
```bash
chmod 600 .env
chown app_user:app_user .env
```

---

## Verification

Test your configuration:

```bash
# Check API key is loaded
rails runner 'puts ENV["GOOGLE_MAPS_API_KEY"] ? "✅ API key loaded" : "❌ Missing"'

# Test database
rails runner 'puts PricingConfig.count; puts "✅ Database OK"'

# Test Redis
rails runner 'Rails.cache.write("test", "ok"); puts Rails.cache.read("test") == "ok" ? "✅ Redis OK" : "⚠️ Using memory store"'
```

---

## Getting API Keys

### Google Maps API Key
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Enable "Distance Matrix API"
3. Create credentials → API Key
4. **Restrict key:** Limit to production server IPs only

### SECRET_KEY_BASE
```bash
rails secret
```

---

## Troubleshooting

**"Config not found" error:**
```bash
rails db:seed  # Load pricing configs
```

**Google Maps API error:**
```bash
# Use fallback temporarily
ROUTE_PROVIDER_STRATEGY=local rails runner test_pricing.rb
```

**Redis connection failed:**
```bash
# Check Redis is running
redis-cli ping  # Should return "PONG"

# Or run without Redis (uses memory store)
unset REDIS_URL
```

---

## Security

- ✅ `.env` is already in `.gitignore`
- ✅ Never commit `.env` to version control
- ✅ Use different keys for dev/staging/production  
- ✅ Rotate secrets regularly
- ✅ Restrict Google Maps API key to production IPs
