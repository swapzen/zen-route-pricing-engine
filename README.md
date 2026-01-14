# Zen Route Pricing Engine

**Production-grade microservice for hyper-local delivery pricing.**

Calculates competitive delivery costs for SwapZen's marketplace, ensuring profitability through conservative buffers, dynamic surge pricing, and traffic-aware routing.

---

## 🚀 Quick Start

### Prerequisites
- Ruby 3.3.6+
- Rails 8.0+
- CockroachDB (Postgres-compatible)
- Redis (for route caching)
- Google Maps API Key (production)

### Setup

```bash
# 1. Install dependencies
bundle install

# 2. Configure environment variables
cp .env.example .env
nano .env  # Add your actual keys

# 3. Configure database (shared with swapzen-api)
# Edit .env: DATABASE_URL=postgresql://root@localhost:26257/swapzen_development

# 4. Run migrations (if not already run)
rails db:migrate

# 5. Seed pricing configs
rails db:seed

# 6. Start server
rails server -p 3001
```

**See [ENV_SETUP.md](ENV_SETUP.md) for detailed environment variable configuration.**

---

## 📡 API Endpoints

### Public Endpoints

#### **POST /route_pricing/create_quote**

Generate a delivery price quote.

**Request:**
```json
{
  "city_code": "hyd",
  "vehicle_type": "two_wheeler",
  "pickup_lat": "17.4470",
  "pickup_lng": "78.3771",
  "drop_lat": "17.3616",
  "drop_lng": "78.4747",
  "item_value_paise": 50000  // optional
}
```

**Parameters:**
- `city_code` (string, required): City code (e.g., `hyd`, `blr`, `del`)
- `vehicle_type` (string, required): Vehicle type
  - `two_wheeler` - Bike/scooter
  - `three_wheeler` - Auto/tuk-tuk
  - `four_wheeler` - Small truck (Tata Ace)
- `pickup_lat` (string, required): Pickup latitude (decimal degrees)
- `pickup_lng` (string, required): Pickup longitude (decimal degrees)
- `drop_lat` (string, required): Drop latitude (decimal degrees)
- `drop_lng` (string, required): Drop longitude (decimal degrees)
- `item_value_paise` (integer, optional): Item value in paise (for high-value surcharge)

**Response (200 OK):**
```json
{
  "success": true,
  "code": 200,
  "quote_id": "uuid-here",
  "price_paise": 19000,
  "price_inr": 190.0,
  "distance_m": 19671,
  "duration_s": 2736,
  "duration_in_traffic_s": 3142,
  "pricing_version": "v1",
  "confidence": "high",
  "provider": "google",
  "breakdown": {
    "base_fare": 2000,
    "distance_component": 13600,
    "surge_multiplier_applied": 1.0,
    "traffic_ratio": 1.15,
    "variance_buffer": 780,
    "margin_guardrail": 1000,
    "final_price": 19000
  }
}
```

**Response (422 Unprocessable Entity):**
```json
{
  "error": "Config not found for city/vehicle combination"
}
```

**cURL Example:**
```bash
curl -X POST http://localhost:3001/route_pricing/create_quote \
  -H "Content-Type: application/json" \
  -d '{
    "city_code": "hyd",
    "vehicle_type": "two_wheeler",
    "pickup_lat": "17.4470",
    "pickup_lng": "78.3771",
    "drop_lat": "17.3616",
    "drop_lng": "78.4747"
  }'
```

---

#### **POST /route_pricing/record_actual**

Record actual vendor price for feedback loop (used for tuning algorithm).

**Request:**
```json
{
  "pricing_quote_id": "uuid-from-create-quote",
  "vendor": "porter",
  "actual_price_paise": 19500,
  "vendor_booking_ref": "PORTER-12345",
  "notes": "9:05 AM IST, clear weather, moderate traffic"
}
```

**Parameters:**
- `pricing_quote_id` (string, required): Quote ID from create_quote
- `actual_price_paise` (integer, required): Actual vendor price in paise
- `vendor` (string, optional): Vendor name (default: `porter`)
- `vendor_booking_ref` (string, optional): Vendor's booking reference
- `notes` (string, optional): Context notes (time, weather, traffic)

**Response (201 Created):**
```json
{
  "success": true,
  "actual_id": "uuid-here",
  "variance_paise": 500,
  "variance_percentage": 2.56
}
```

---

### Admin Endpoints

#### **GET /route_pricing/admin/list_configs**

List all pricing configurations.

**Query Parameters:**
- `city_code` (optional): Filter by city
- `vehicle_type` (optional): Filter by vehicle type
- `active_only` (optional): `true` to show only active configs

**Response:**
```json
{
  "configs": [
    {
      "id": "uuid",
      "city_code": "hyd",
      "vehicle_type": "two_wheeler",
      "version": 1,
      "active": true,
      "effective_from": "2026-01-01T00:00:00+05:30",
      "effective_until": null,
      "surge_rules": [...]
    }
  ]
}
```

#### **PATCH /route_pricing/admin/update_config**

Create new version of pricing config.

#### **POST /route_pricing/admin/create_surge_rule**

Add dynamic surge rule.

#### **PATCH /route_pricing/admin/deactivate_surge_rule**

Deactivate a surge rule.

---

## ⚙️ Environment Variables

**All secrets are managed via `.env` file (not committed to Git).**

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
nano .env
```

### Required for Production
- `GOOGLE_MAPS_API_KEY` - Google Maps Distance Matrix API key
- `DATABASE_URL` - CockroachDB connection string
- `REDIS_URL` - Redis connection string (for caching)
- `SECRET_KEY_BASE` - Rails session encryption key

### Optional
- `ROUTE_PROVIDER_STRATEGY` - Provider selection: `google` (default), `local`, `haversine`
- `RAILS_ENV` - Environment: `development`, `production`, `test`
- `PORT` - Server port (default: 3000, suggest 3001)
- `RAILS_MAX_THREADS` - Puma thread pool size (default: 5)

**See [ENV_SETUP.md](ENV_SETUP.md) for complete documentation.**

---

## 🧪 Testing

### Basic Test (Haversine Fallback)
```bash
export ROUTE_PROVIDER_STRATEGY=local
rails runner test_pricing.rb
```

### Google Maps API Test
```bash
export GOOGLE_MAPS_API_KEY='your_key'
export ROUTE_PROVIDER_STRATEGY='google'
rails runner test_google_maps.rb
```

### Manual API Test
```bash
# Start server
rails server -p 3001

# In another terminal
curl -X POST http://localhost:3001/route_pricing/create_quote \
  -H "Content-Type: application/json" \
  -d '{
    "city_code": "hyd",
    "vehicle_type": "two_wheeler",
    "pickup_lat": "17.4470",
    "pickup_lng": "78.3771",
    "drop_lat": "17.3616",
    "drop_lng": "78.4747"
  }' | jq
```

---

## 🏗️ Architecture

### Pricing Algorithm (11 Steps)
1. **Base Fare** - Minimum charge
2. **Chargeable Distance** - Distance beyond base distance
3. **Distance Component** - Per-km charges
4. **Raw Subtotal** - Base + distance
5. **Dynamic Surge** - Time-of-day, traffic, events
6. **Multipliers** - Vehicle × City × Surge
7. **Variance Buffer** - 5-8% safety margin
8. **High-Value Buffer** - For expensive items
9. **Subtotal with Buffers**
10. **Margin Guardrail** - Minimum profit (3-4%)
11. **Rounding** - Up to nearest ₹10

### Fallback Mechanism
- **Primary:** Google Maps Distance Matrix API (traffic-aware)
- **Fallback:** Haversine formula × 1.4 tortuosity factor
- **Dev Mode:** Local calculation (no API calls)

### Caching
- Route data cached for 6 hours in Redis
- Cache key: `route:v1:{city}:{vehicle}:{norm_pickup}:{norm_drop}`
- Coordinates normalized to 4 decimals (~11m precision)

---

## 🔒 Security

This microservice contains proprietary pricing algorithms. Access is restricted to:
- SwapZen internal network only
- Admin endpoints require authentication (TODO: JWT)

---

## 📊 Database Schema

Shared database with `swapzen-api`:
- `pricing_configs` - Pricing parameters by city/vehicle
- `pricing_surge_rules` - Dynamic surge rules
- `pricing_quotes` - Quote history
- `pricing_actuals` - Vendor price feedback

---

## 🚢 Deployment

```bash
# Production
RAILS_ENV=production rails db:migrate
RAILS_ENV=production rails server -p 3001

# With Kamal (recommended)
kamal deploy
```

---

## 📝 Supported Cities & Vehicles

### Cities
- `hyd` - Hyderabad

### Vehicles
- `two_wheeler` - ₹20 base + ₹8/km
- `three_wheeler` - ₹100 base + ₹12/km
- `four_wheeler` - ₹200 base + ₹20/km

---

## 🐛 Troubleshooting

### Config not found
```bash
rails db:seed  # Load pricing configs
```

### Redis connection error
```bash
# Check Redis is running
redis-cli ping  # Should return "PONG"
```

### Google Maps API errors
```bash
# Verify API key
echo $GOOGLE_MAPS_API_KEY

# Switch to fallback
export ROUTE_PROVIDER_STRATEGY=local
```

---

## 📚 Documentation

- [Implementation Plan](../brain/implementation_plan.md)
- [Architectural Review](../brain/architectural_review.md)
- [API Spec](docs/openapi.json)
