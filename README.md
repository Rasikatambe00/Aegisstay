# 🏨 AegisStay - Hotel Crisis Management System

<div align="center">

![AegisStay](https://img.shields.io/badge/AegisStay-v1.0.0-FF6B4A?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?style=for-the-badge\&logo=flutter)
![Supabase](https://img.shields.io/badge/Supabase-Latest-3ECF8E?style=for-the-badge\&logo=supabase)
![Kotlin](https://img.shields.io/badge/Kotlin-1.9+-7F52FF?style=for-the-badge\&logo=kotlin)
![Node.js](https://img.shields.io/badge/Node.js-18+-339933?style=for-the-badge\&logo=node.js)
![License](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)

**Real-time emergency response platform for hotels with AI-driven fire detection, guest evacuation guidance, and staff coordination.**

</div>

---

## 📱 Overview

**AegisStay** is a real-time hotel safety and crisis management system designed to detect, report, and coordinate emergency responses (especially fire incidents).

It replaces slow manual coordination with **instant alerts, real-time tracking, and intelligent evacuation guidance**.

⚡ Key impact:

* <2 sec alert delivery
* Real-time staff coordination
* Smart evacuation routing
* AI-assisted decision support

---

## ✨ Key Features

### 🚨 Emergency Detection & Reporting

* Manual reporting (guest panic button)
* Staff-triggered incidents
* Sensor integration (MQTT / IoT ready)
* AI anomaly detection (optional)

---

### 📢 Real-Time Alert System

* Supabase Realtime subscriptions
* Role-based alerts (Guest / Staff / Admin)
* Priority notifications
* Offline queue + retry

---

### 🧭 Smart Evacuation Guidance

* A* pathfinding algorithm
* Live route updates
* Danger zone avoidance
* ETA to exit calculation
* “I’m Safe” confirmation tracking

---

### 👥 Staff Task Coordination

* Real-time task assignment
* Status updates (pending / in-progress / done)
* Staff location tracking
* Incident-linked task panel

---

### 📊 Admin Command Center

* Live incident dashboard
* Guest evacuation tracking
* Staff coordination overview
* Incident timeline & analytics

---

### 🤖 AI & Analytics

* Fire spread prediction (Digital Twin concept)
* Risk zone identification
* Post-incident analytics

---

## 🏗️ Architecture

### System Overview

```
Frontend (Flutter Apps)
   ↓
Supabase Backend
   ├─ PostgreSQL (Database)
   ├─ Realtime (WebSockets)
   ├─ Auth (JWT-based)
   ├─ Storage (media & reports)
   ↓
Custom Backend (Node.js - optional)
   ├─ AI services
   ├─ Pathfinding engine
   └─ External integrations (MQTT, APIs)
```

---

## 🛠️ Tech Stack

### Frontend

* Flutter
* Provider / Riverpod
* Supabase Flutter SDK

### Backend

* Supabase (Primary backend)

  * PostgreSQL
  * Realtime subscriptions
  * Auth
  * Storage

* Optional:

  * Node.js (AI + integrations)

### Realtime

* Supabase Channels (WebSocket-based)

### Database

* PostgreSQL (managed by Supabase)

### Local Storage

* Hive / SharedPreferences

---

## 🚀 Quick Start

### Prerequisites

* Flutter 3.0+
* Supabase account
* Android Studio / VS Code

---

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/aegisstay.git
cd aegisstay
```

---

### 2. Supabase Setup

1. Create a project at https://supabase.com
2. Get:

   * Project URL
   * Anon Key

---

### 3. Configure Environment

```dart
const supabaseUrl = 'YOUR_SUPABASE_URL';
const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

---

### 4. Run App

```bash
flutter pub get
flutter run
```

---

## 🧱 Database Design (Supabase)

### Tables

* users (guest / staff / admin)
* incidents
* tasks
* notifications
* locations
* activity_logs

---

## 🔄 Realtime Flow

```
1. Incident created → Supabase INSERT
2. Realtime event triggers
3. Clients subscribed to "incidents"
4. UI updates instantly
```

---

## 🔐 Authentication & Security

* Supabase Auth (JWT)
* Role-based access control (RBAC)
* Row Level Security (RLS)
* Secure API access policies

---

## 🧪 Testing

```bash
flutter test
```

---

## 🚢 Deployment

### Mobile

* Android APK / Play Store
* iOS (future)

### Backend

* Supabase (managed cloud)

---

## 📋 Roadmap

* 🔄 Push notifications (FCM/APNs integration)
* 🔄 Map-based indoor navigation
* 🔄 AI fire prediction improvements
* 🔄 Multi-language support

---

## ⚠️ Known Limitations

* Indoor GPS accuracy may vary
* Requires internet for realtime sync
* AI predictions depend on training data

---

## 🤝 Contributing

1. Fork repo
2. Create branch
3. Commit changes
4. Open PR

---

## 📄 License

MIT License

---

## 💡 About

Built for real-time emergency response and safety optimization in hotels.

**AegisStay — Turning chaos into coordinated response.**
