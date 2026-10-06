# Occupier

Occupier is a centralized co-working space management system designed to manage desk and meeting-room bookings, real-time occupancy, and walk-in users across multiple co-working locations.

The system provides a single source of truth for branch occupancy and booking information, helping branch staff manage resources efficiently and giving central management reliable utilization data for operational and expansion decisions.

**Status:** In Development

---

## Problem Statement

A chain of co-working spaces currently manages desk and meeting-room bookings independently at each branch.

This creates several problems:

- The central team has no live view of occupancy across locations.
- High-demand desks and meeting rooms can be double-allocated during peak hours.
- Walk-in users are not consistently reflected in occupancy data.
- Branches operate with fragmented booking information.
- Historical utilization data is unreliable or difficult to aggregate.
- Expansion decisions are made without accurate occupancy data.

Occupier aims to solve these problems by providing a centralized, real-time platform for managing bookings and occupancy across all locations.

---

## Objectives

The main objectives of Occupier are to:

- Centralize booking information across multiple branches.
- Provide real-time visibility of branch occupancy.
- Prevent double bookings of desks and meeting rooms.
- Allow staff to manage walk-in users.
- Provide role-based access for administrators, branch staff, and members.
- Collect reliable utilization data.
- Support management in making data-driven expansion decisions.

---

## Key Features

### Authentication

- User registration and login.
- Secure authentication using Firebase Authentication.
- Role-based access control.
- User profile management.

### Desk Booking

- Browse available desks.
- Select a branch, date, and time.
- Reserve an available desk.
- View and manage personal bookings.
- Prevent overlapping bookings.

### Meeting Room Booking

- Browse available meeting rooms.
- View room capacity and amenities.
- Select date and time.
- Reserve meeting rooms.
- Prevent overlapping bookings.

### Real-Time Occupancy

- View current occupancy for each branch.
- Track occupied and available resources.
- Synchronize occupancy using Cloud Firestore.
- Distinguish between bookings and actual check-ins.

### Walk-In Management

- Allow branch staff to register walk-in users.
- Assign available desks or meeting rooms.
- Record check-in and check-out times.
- Include walk-ins in occupancy data.

### Admin Dashboard

- View occupancy across all branches.
- Manage branches.
- Manage desks and meeting rooms.
- View bookings.
- Monitor utilization.

### Utilization Analytics

- Track daily, weekly, and monthly occupancy.
- Compare branch utilization.
- Identify peak usage periods.
- Track desk and meeting-room utilization.
- Support data-driven expansion decisions.

---

## User Roles

Occupier supports three primary user roles.

### Central Administrator

Central administrators can:

- View all branches.
- Monitor network-wide occupancy.
- Manage branches.
- Manage resources.
- Manage branch staff.
- View utilization data.

### Branch Staff

Branch staff can:

- View their assigned branch.
- Monitor current occupancy.
- Manage bookings.
- Register walk-ins.
- Check users in and out.
- Manage resources within their branch.

### Member

Members can:

- Browse branches.
- View available desks and meeting rooms.
- Create bookings.
- View upcoming bookings.
- Cancel bookings.
- Check in and out.

---

## Technology Stack

| Component | Technology |
|---|---|
| Frontend | Flutter |
| Programming Language | Dart |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| File Storage | Firebase Storage |
| Authorization | Firestore Security Rules |
| Local Testing | Firebase Emulator Suite |
| Target Platform | Android / iOS |

---

## System Architecture

At a high level, the system follows this architecture:

```text
                    Occupier Flutter App
                           |
              +------------+------------+
              |                         |
       Firebase Auth              Cloud Firestore
              |                         |
              |              +----------+----------+
              |              |          |          |
              |          Branches   Bookings   Occupancy
              |              |          |          |
              |          Desks &    Resources   Check-ins
              |          Rooms
              |
       User Authentication

                    Firebase Storage
                           |
                    Images / Files