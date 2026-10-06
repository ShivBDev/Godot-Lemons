# Secure Full-Stack Auth & State Sync Engine

An architectural proof-of-concept demonstrating a secure, decoupled full-stack loop between an independent **Godot Engine game client** and a containerized **ASP.NET Core Web API** cluster backed by an isolated **PostgreSQL 18** database instance.

## 🚀 Architectural Notes
* **Privacy-First Cryptography:** Includes a multi-layered cryptographic strategy to shield data records from database dumps and compliance leaks (Blind indexing, AES-256 with distinct IVs, and SHA-256 session signatures).
* **OAuth 2.0 Email Delivery:** Uses a Google Workspace OAuth 2.0 refresh token to obtain short-lived access tokens and dispatch OTP/monitoring messages through the Gmail REST API over HTTPS, avoiding traditional SMTP port dependencies.
* **Live Infrastructure Monitoring:** Integrates native ASP.NET Core Health Checks mapping diagnostic daemon route to `/health`. If underlying data channel or database socket is severed, node instantly signals structural health degradation.
* **Autonomous Outage Incident Alerting:** Features a background `IHealthCheckPublisher` engine that tracks system stability every few seconds. If a critical service drops offline, the system immediately dispatches detailed crash information to the administration team's Google Workspace inbox through the Gmail REST API.
* **Unified API Error Contract (RFC 7807):** API error payloads use standard `ProblemDetailsResponse` contract. Godot client uses a single, centralized parsing function to ingest and handle any server-side validation or security exception.
* **Automated Client UI Lockout State Machine:** Implements centralized, async network tracker within the Godot client. While HTTP data streams are active, input controls are frozen to eliminate double-click bugs or client-side value spam.
* **IP-Partitioned Rate Limiting:** Fixed-window gateway middleware protects the authentication endpoint from credential brute-forcing and automated OTP request spam.
* **Autonomous Database Sweeping:** An asynchronous `.NET Hosted Service` background thread automatically purges abandoned OTP tokens and inactive sessions every 24 hours.
* **Modern Container DevOps:** Configured for high-portability deployment leveraging multi-stage Docker builds and software-defined isolated sub-networks compliant with Postgres 18 data directory layouts, with the production stack deployed through Railway.

## 🛠️ Technology Stack
* **Client Frontend:** Godot Engine (GDScript)
* **Backend Gateway:** C# (.NET 10 Web API)
* **Storage Layer:** PostgreSQL 18 (Container Volume mapped)
* **Authentication Email:** Google Workspace Gmail API (OAuth 2.0, HTTPS / port 443)
* **Deployment System:** Docker / Docker Compose / Railway

---

## 🔒 Cryptographic Implementation Architecture

### 1. User Identity Obfuscation (Deterministic Hashing)
To eliminate plain text storage of player email identities, the backend normalizes and passes emails through an `HMAC-SHA256` hashing processor leveraging a secure server-side pepper key. This acts as a cryptographic "Blind Index," enabling fast, direct table lookups while completely masking user email addresses.

### 2. PII Data Privacy (Reversible AES-256 Encryption)
Sensitive non-numeric profile data—such as custom player profile names—are encrypted symmetrically before entering the PostgreSQL write loop using `AES-256` in Cipher Block Chaining (CBC) mode. A unique, random Initialization Vector (IV) is prefixed to each output block, ensuring identical data inputs yield completely different cipher strings across the database schema rows.

### 3. Verification & Session Credentials (One-Way Signatures)
Short-lived validation keys (including the randomly generated crypto 6-digit One-Time Passcodes and user session tokens) are encoded securely using `SHA-256`. The server never stores plain-text OTP or session tokens in the database; raw credentials exist only for the duration required by the active client request.

---

## 📦 Local Installation & Deployment Guide

Follow these steps to run the complete backend infrastructure cluster locally on your development machine:

### 1. Extract the Application
```bash
git clone https://github.com/ShivBDev/Godot-Lemons.git
cd Godot-Lemons
```

### 2. Configure Environment Parameters
Create a copy of the template composition manifest and name it `docker-compose.yml`:
```bash
cp docker-compose.example.yml docker-compose.yml
```
Open the new `docker-compose.yml` file and populate the required environment configurations, including the Google Workspace Gmail address and OAuth 2.0 client credentials/refresh token used by the backend email service. Keep the populated file outside source control.

### 3. Launch the Application Containers
```bash
docker compose up --build -d
```
Verify that your environment status indicators are green and running stably:
```bash
docker ps
```

### 4. Interface with the Godot Client
Open the `lemon_frontend/` project folder inside the Godot Editor. Boot up the main network scene interface. The system is now ready to process live email registration routing, securely dispatch OTP codes through the Gmail API over HTTPS, track background money totals, and execute automated saves every 15 seconds through `http://127.0.0.1:5212`! The same backend is configured for cloud deployment through Railway.
